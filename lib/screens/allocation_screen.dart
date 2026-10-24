// lib/screens/allocation_screen.dart
// ---------------------------------------------------------------------------
// Sample allocation across Equity, Hybrid and Debt, for a SIP or a lump sum.
//
//  * Up to 5 funds in each class, each with its own weight (category-wise:
//    Large Cap, Mid Cap, Small Cap, Corporate Bond ...).
//  * Any class percentage or fund weight can be 0.
//  * Auto: the split and the funds come from risk profile + years.
//  * Manual: you set the class split and pick the funds.
//  * Growth chart and a downloadable PDF.
//
// All numbers come from the API (/allocation/plan, /allocation/pdf).
// Illustration only, not investment advice.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../main.dart';
import '../services/allocation_service.dart';

const _classKeys = ['equity', 'hybrid', 'debt'];
const _classLabels = {'equity': 'Equity', 'hybrid': 'Hybrid', 'debt': 'Debt'};
const _classColors = {
  'equity': Brand.gold,
  'hybrid': Brand.teal,
  'debt': Brand.blue,
};
const _maxFunds = 5;

String _inrFull(num v) {
  final n = v.round();
  final s = n.abs().toString();
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return '${n < 0 ? '-' : ''}\u20b9$out';
}

String _inrShort(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e7) return '$sign\u20b9${(a / 1e7).toStringAsFixed(2)} Cr';
  if (a >= 1e5) return '$sign\u20b9${(a / 1e5).toStringAsFixed(2)} L';
  if (a >= 1e3) return '$sign\u20b9${(a / 1e3).toStringAsFixed(1)}K';
  return '$sign\u20b9${a.toStringAsFixed(0)}';
}

String _pct(double? v, {int dp = 1}) =>
    v == null ? '\u2014' : '${v.toStringAsFixed(dp)}%';

/// One editable fund row in Manual mode.
class _PickRow {
  String category;
  String fund;
  double weight;
  _PickRow(this.category, this.fund, this.weight);
}

class AllocationScreen extends StatefulWidget {
  const AllocationScreen({super.key});

  @override
  State<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends State<AllocationScreen> {
  String _mode = 'sip';
  final _amountCtrl = TextEditingController(text: '10000');
  int _years = 10;
  String _risk = 'balanced';
  bool _manual = false;

  // Manual settings
  double _eq = 45, _hy = 20; // debt is whatever is left
  final Map<String, List<_PickRow>> _rows = {
    'equity': <_PickRow>[],
    'hybrid': <_PickRow>[],
    'debt': <_PickRow>[],
  };

  AllocOptions? _options;
  AllocPlan? _plan;
  String? _error;
  String? _pdfError;
  bool _loading = true;
  bool _pdfBusy = false;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;

  double _classPct(String key) {
    if (key == 'equity') return _eq;
    if (key == 'hybrid') return _hy;
    return 100 - _eq - _hy;
  }

  AllocRequest _request() {
    if (!_manual) {
      return AllocRequest(
          mode: _mode, amount: _amount, years: _years, risk: _risk);
    }
    final picks = <String, List<MapEntry<String, double>>>{};
    for (final k in _classKeys) {
      if (_classPct(k) > 0 && _rows[k]!.isNotEmpty) {
        picks[k] = [for (final r in _rows[k]!) MapEntry(r.fund, r.weight)];
      }
    }
    return AllocRequest(
      mode: _mode,
      amount: _amount,
      years: _years,
      risk: _risk,
      classes: {for (final k in _classKeys) k: _classPct(k)},
      picks: picks,
    );
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _run);
  }

  Future<void> _run() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await AllocationService.plan(_request());
      if (!mounted || id != _requestId) return;
      setState(() {
        _plan = plan;
        if (_manual) _fillEmptyRowsFrom(plan);
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  /// A class that has money but no rows yet shows what the server picked.
  void _fillEmptyRowsFrom(AllocPlan plan) {
    for (final k in _classKeys) {
      final c = plan.classOf(k);
      if (c == null || c.pct <= 0 || _rows[k]!.isNotEmpty) continue;
      _rows[k] = [
        for (final f in c.funds) _PickRow(f.category, f.name, f.weight),
      ];
    }
  }

  Future<void> _setManual(bool on) async {
    if (on && _plan != null) {
      // Start from what Auto chose, so switching does not change the numbers.
      final p = _plan!;
      _eq = p.classOf('equity')?.pct ?? 45;
      _hy = p.classOf('hybrid')?.pct ?? 20;
      for (final k in _classKeys) {
        final c = p.classOf(k);
        _rows[k] = [
          if (c != null)
            for (final f in c.funds) _PickRow(f.category, f.name, f.weight),
        ];
      }
    }
    setState(() => _manual = on);
    if (on && _options == null) {
      try {
        final o = await AllocationService.options();
        if (mounted) setState(() => _options = o);
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'Could not load the fund list. Try again.');
        }
      }
    }
    _run();
  }

  void _setMode(String m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _amountCtrl.text = m == 'sip' ? '10000' : '500000';
    });
    _run();
  }

  Future<void> _downloadPdf() async {
    setState(() {
      _pdfBusy = true;
      _pdfError = null;
    });
    try {
      final bytes = await AllocationService.pdf(_request());
      await Printing.sharePdf(bytes: bytes, filename: 'advantage_allocation.pdf');
    } catch (e) {
      if (mounted) {
        setState(() => _pdfError = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Auto allocation',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            icon: _pdfBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold))
                : const Icon(Icons.picture_as_pdf, color: Brand.gold),
            onPressed: (_plan == null || _pdfBusy) ? null : _downloadPdf,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _inputs(),
          if (_manual) _manualEditor(),
          if (_error != null)
            _box(Text(_error!, style: const TextStyle(color: Brand.red))),
          if (_pdfError != null)
            _box(Text(_pdfError!, style: const TextStyle(color: Brand.red))),
          if (_plan != null) ..._results(_plan!),
          if (_loading && _plan == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child:
                  Center(child: CircularProgressIndicator(color: Brand.gold)),
            ),
        ],
      ),
    );
  }

  Widget _box(Widget child, {EdgeInsets? padding}) => Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child:
            Padding(padding: padding ?? const EdgeInsets.all(14), child: child),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Brand.gold,
          fontSize: 11.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600));

  Widget _chip(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on
                ? Brand.gold.withValues(alpha: 0.18)
                : Brand.fern.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on ? Brand.gold : Colors.transparent, width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Brand.gold : Brand.mint,
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  Widget _inputs() {
    final quick = _mode == 'sip'
        ? const [5000, 10000, 25000, 50000]
        : const [100000, 500000, 1000000, 2500000];
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _chip('Monthly SIP', _mode == 'sip', () => _setMode('sip')),
          const SizedBox(width: 8),
          _chip('Lump sum', _mode == 'lumpsum', () => _setMode('lumpsum')),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Brand.paper, fontSize: 20),
          decoration: InputDecoration(
            labelText:
                _mode == 'sip' ? 'Amount per month (\u20b9)' : 'Amount (\u20b9)',
            labelStyle: const TextStyle(color: Brand.mint),
            prefixText: '\u20b9 ',
            prefixStyle: const TextStyle(color: Brand.gold, fontSize: 20),
          ),
          onChanged: (_) => _schedule(),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in quick)
            _chip(_inrShort(q.toDouble()), false, () {
              _amountCtrl.text = '$q';
              _run();
            }),
        ]),
        const SizedBox(height: 14),
        Text('For $_years ${_years == 1 ? 'year' : 'years'}',
            style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
        Slider(
          value: _years.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          activeColor: Brand.gold,
          label: '$_years',
          onChanged: (v) => setState(() => _years = v.round()),
          onChangeEnd: (_) => _run(),
        ),
        Row(children: [
          _chip('Auto', !_manual, () => _setManual(false)),
          const SizedBox(width: 8),
          _chip('Manual', _manual, () => _setManual(true)),
        ]),
        if (!_manual) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in const ['conservative', 'balanced', 'aggressive'])
              _chip(r[0].toUpperCase() + r.substring(1), _risk == r, () {
                setState(() => _risk = r);
                _run();
              }),
          ]),
        ],
      ],
    ));
  }

  // ------------------------------------------------------------ manual
  Widget _manualEditor() {
    final debt = 100 - _eq - _hy;
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('YOUR OWN MIX'),
        const SizedBox(height: 6),
        Text(
            'Equity ${_eq.round()}%  \u00b7  Hybrid ${_hy.round()}%  \u00b7  Debt ${debt.round()}%',
            style: const TextStyle(color: Brand.paper, fontSize: 13)),
        const Text('Any of them can be 0.',
            style: TextStyle(color: Brand.mint, fontSize: 11.5)),
        const SizedBox(height: 4),
        _slider('Equity', _eq, 100, _classColors['equity']!, (v) {
          setState(() {
            _eq = v;
            if (_eq + _hy > 100) _hy = 100 - _eq;
          });
        }),
        _slider('Hybrid', _hy, 100 - _eq, _classColors['hybrid']!, (v) {
          setState(() => _hy = v);
        }),
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 2),
          child: Text('Debt is the rest: ${debt.round()}%',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
        ),
        for (final k in _classKeys) ..._classEditor(k),
      ],
    ));
  }

  Widget _slider(String name, double value, double max, Color color,
      ValueChanged<double> onChanged) {
    final divisions = (max / 5).floor();
    return Row(children: [
      SizedBox(
          width: 56,
          child: Text(name,
              style: TextStyle(color: color, fontSize: 12.5))),
      Expanded(
        child: Slider(
          value: value.clamp(0, max <= 0 ? 0.0001 : max).toDouble(),
          min: 0,
          max: max <= 0 ? 0.0001 : max,
          divisions: divisions < 1 ? null : divisions,
          activeColor: color,
          label: '${value.round()}%',
          onChanged: max <= 0 ? null : onChanged,
          onChangeEnd: (_) => _run(),
        ),
      ),
      SizedBox(
          width: 40,
          child: Text('${value.round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Brand.paper, fontSize: 12.5))),
    ]);
  }

  List<Widget> _classEditor(String k) {
    final pct = _classPct(k);
    final rows = _rows[k]!;
    final color = _classColors[k]!;
    final total = rows.fold<double>(0, (s, r) => s + r.weight);
    return [
      const Divider(height: 26),
      Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('${_classLabels[k]} funds',
            style: const TextStyle(
                color: Brand.paper, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${rows.length} of $_maxFunds',
            style: const TextStyle(color: Brand.mint, fontSize: 12)),
      ]),
      if (pct <= 0)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('0% allocated, so none of these are used.',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
        )
      else if (_options == null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Loading the fund list\u2026',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
        )
      else ...[
        for (var i = 0; i < rows.length; i++) _pickRow(k, i),
        if (rows.isNotEmpty && (total - 100).abs() > 0.01)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                total <= 0
                    ? 'Give at least one fund a weight above 0.'
                    : 'Weights add up to ${total.round()}%. They are scaled to 100%.',
                style: const TextStyle(color: Brand.gold, fontSize: 12)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: rows.length >= _maxFunds ? null : () => _addRow(k),
            icon: const Icon(Icons.add, size: 18, color: Brand.gold),
            label: Text(
                rows.length >= _maxFunds ? 'Maximum 5 funds' : 'Add fund',
                style: const TextStyle(color: Brand.gold, fontSize: 12.5)),
          ),
        ),
      ],
    ];
  }

  void _addRow(String k) {
    final o = _options;
    if (o == null) return;
    final used = _rows[k]!.map((r) => r.fund).toSet();
    for (final cat in o.categories(k)) {
      for (final f in o.funds(k, cat)) {
        if (!used.contains(f.name)) {
          setState(() => _rows[k]!.add(_PickRow(cat, f.name, 10)));
          _schedule();
          return;
        }
      }
    }
  }

  Widget _pickRow(String k, int i) {
    final o = _options!;
    final row = _rows[k]![i];
    final cats = [...o.categories(k)];
    if (!cats.contains(row.category)) cats.insert(0, row.category);
    final taken = {
      for (var j = 0; j < _rows[k]!.length; j++)
        if (j != i) _rows[k]![j].fund,
    };
    final funds = [
      ...o.funds(k, row.category).where((f) => !taken.contains(f.name)),
    ];
    if (!funds.any((f) => f.name == row.fund)) {
      funds.insert(0, AllocFund(name: row.fund, category: row.category));
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 2),
      decoration: BoxDecoration(
        color: Brand.vault.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _dropdown<String>(
              'Category',
              row.category,
              [
                for (final c in cats)
                  DropdownMenuItem<String>(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis)),
              ],
              (v) {
                if (v == null || v == row.category) return;
                final list = o.funds(k, v).where((f) => !taken.contains(f.name));
                setState(() {
                  row.category = v;
                  if (list.isNotEmpty) row.fund = list.first.name;
                });
                _schedule();
              },
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18, color: Brand.mint),
            onPressed: () {
              setState(() => _rows[k]!.removeAt(i));
              _schedule();
            },
          ),
        ]),
        _dropdown<String>(
          'Fund',
          row.fund,
          [
            for (final f in funds)
              DropdownMenuItem<String>(
                value: f.name,
                child: Text(
                    '${f.shortName}${f.hasHistory ? '' : '  (new, hypothetical)'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          (v) {
            if (v == null) return;
            setState(() => row.fund = v);
            _schedule();
          },
        ),
        Row(children: [
          const Text('Weight',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          Expanded(
            child: Slider(
              value: row.weight.clamp(0, 100).toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: _classColors[k],
              label: '${row.weight.round()}%',
              onChanged: (v) => setState(() => row.weight = v),
              onChangeEnd: (_) => _run(),
            ),
          ),
          SizedBox(
              width: 38,
              child: Text('${row.weight.round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Brand.paper, fontSize: 12.5))),
          const SizedBox(width: 6),
        ]),
      ]),
    );
  }

  Widget _dropdown<T>(String label, T value, List<DropdownMenuItem<T>> items,
      ValueChanged<T?> onChanged) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: Brand.vault,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Brand.mint, fontSize: 12),
        isDense: true,
      ),
      style: const TextStyle(color: Brand.paper, fontSize: 13),
      items: items,
      onChanged: onChanged,
    );
  }

  // ----------------------------------------------------------- results
  List<Widget> _results(AllocPlan p) {
    final sipWord = p.mode == 'sip' ? ' a month' : '';
    final gain = p.base - p.invested;
    return [
      if (p.hypothetical)
        _box(const Text(
            'Hypothetical: at least one fund has no usable track record, so a '
            'standard assumption (12% a year for equity, 10% for hybrid, 7% for debt) is used for it.',
            style: TextStyle(color: Brand.gold, fontSize: 12.5))),
      _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('YOUR MIX'),
              if (_loading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                for (final c in p.classes)
                  if (c.pct > 0)
                    Expanded(
                      flex: (c.pct * 10).round().clamp(1, 1000),
                      child: Container(color: _classColors[c.key]),
                    ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(p.how,
              style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
          for (final c in p.classes) ..._classBlock(c, sipWord),
        ],
      )),
      if (p.byCategory.isNotEmpty)
        _box(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('CATEGORY-WISE'),
            const SizedBox(height: 8),
            for (final c in p.byCategory) _categoryRow(c, sipWord),
          ],
        )),
      _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('AFTER ${p.years} ${p.years == 1 ? 'YEAR' : 'YEARS'}'),
          const SizedBox(height: 8),
          Text(_inrShort(p.base),
              style: const TextStyle(
                  color: Brand.paper, fontSize: 30, fontWeight: FontWeight.bold)),
          Text(
              'expected, on ${_inrShort(p.invested)} invested (${gain >= 0 ? '+' : ''}${_inrShort(gain)})',
              style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(
              'Likely range ${_inrShort(p.low)} to ${_inrShort(p.high)}  \u00b7  '
              '${p.portBase.toStringAsFixed(1)}% a year '
              '(${p.portLow.toStringAsFixed(1)}% to ${p.portHigh.toStringAsFixed(1)}%)',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
          const SizedBox(height: 14),
          _chart(p),
          const SizedBox(height: 8),
          const Wrap(spacing: 12, runSpacing: 4, children: [
            _Key('Invested', Colors.grey),
            _Key('Low', Brand.red),
            _Key('Expected', Brand.gold),
            _Key('High', Brand.green),
          ]),
        ],
      )),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _pdfBusy ? null : _downloadPdf,
          style: ElevatedButton.styleFrom(
            backgroundColor: Brand.gold,
            foregroundColor: Brand.vault,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _pdfBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.vault))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_pdfBusy ? 'Creating PDF\u2026' : 'Download PDF'),
        ),
      ),
      _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in p.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('\u2022 $n',
                  style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
                'Expected return is half the fund\u2019s own record and half a long-run assumption.',
                style: TextStyle(color: Brand.mint, fontSize: 11.5)),
          ),
        ],
      )),
    ];
  }

  List<Widget> _classBlock(AllocClass c, String sipWord) {
    final color = _classColors[c.key]!;
    if (c.pct <= 0) {
      return [
        const Divider(height: 22),
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.35),
                  shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${c.label} 0%  \u00b7  not included',
              style: const TextStyle(color: Brand.mint, fontSize: 13)),
        ]),
      ];
    }
    return [
      const Divider(height: 22),
      Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text('${c.label} ${c.pct.toStringAsFixed(c.pct % 1 == 0 ? 0 : 1)}%',
            style: const TextStyle(
                color: Brand.paper, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${_inrFull(c.amount)}$sipWord',
            style: const TextStyle(color: Brand.paper)),
      ]),
      if (c.expected != null)
        Padding(
          padding: const EdgeInsets.only(left: 18, top: 2),
          child: Text('Expected ${_pct(c.expected)} a year',
              style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
        ),
      for (final f in c.funds) _fundRow(f, color),
    ];
  }

  Widget _fundRow(AllocFund f, Color color) {
    final zero = f.weight <= 0;
    final detail = f.hypothetical
        ? 'Hypothetical ${f.expected.toStringAsFixed(1)}% a year (no track record)'
        : 'Past ${f.basis} ${_pct(f.historical)} a year \u00b7 expected ${f.expected.toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 8),
      child: Opacity(
        opacity: zero ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.category.toUpperCase(),
                style: TextStyle(
                    color: color, fontSize: 10, letterSpacing: 0.8)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(f.shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Brand.paper, fontSize: 12.5, height: 1.25)),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_pct(f.weight, dp: f.weight % 1 == 0 ? 0 : 1),
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    Text(zero ? '\u2014' : _inrFull(f.amount),
                        style: const TextStyle(
                            color: Brand.mint, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
            Text(detail,
                style: TextStyle(
                    color: f.hypothetical ? Brand.gold : Brand.mint,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _categoryRow(AllocCategory c, String sipWord) {
    final color = _classColors[c.cls] ?? Brand.mint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(c.category,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.paper, fontSize: 12.5)),
            ),
            Text('${_pct(c.share)}  \u00b7  ${_inrFull(c.amount)}$sipWord',
                style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (c.share / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
              color: color,
              backgroundColor: Brand.fern.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chart(AllocPlan p) {
    List<FlSpot> spots(double Function(AllocPoint) pick) =>
        [for (final pt in p.points) FlSpot(pt.year.toDouble(), pick(pt))];
    LineChartBarData line(List<FlSpot> s, Color c,
            {double width = 2, List<int>? dash}) =>
        LineChartBarData(
          spots: s,
          isCurved: false,
          color: c,
          barWidth: width,
          dashArray: dash,
          dotData: const FlDotData(show: false),
        );
    const names = ['Invested', 'Low', 'Expected', 'High'];
    final maxY =
        p.points.map((e) => e.high).fold<double>(0, (a, b) => a > b ? a : b);
    final step = (p.years / 5).ceil().clamp(1, 10).toDouble();

    return SizedBox(
      height: 230,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: p.years.toDouble(),
          minY: 0,
          maxY: maxY * 1.05,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: Brand.mint.withValues(alpha: 0.12), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step,
                reservedSize: 24,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text('${v.round()}y',
                      style: const TextStyle(color: Brand.mint, fontSize: 10)),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(_inrShort(v),
                      style: const TextStyle(color: Brand.mint, fontSize: 10)),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched
                  .map((s) => LineTooltipItem(
                        '${names[s.barIndex]} ${_inrShort(s.y)}',
                        const TextStyle(
                            color: Brand.paper,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            line(spots((e) => e.invested), Colors.grey, dash: [6, 4]),
            line(spots((e) => e.low), Brand.red),
            line(spots((e) => e.base), Brand.gold, width: 3),
            line(spots((e) => e.high), Brand.green),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final Color color;
  const _Key(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: color),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Brand.mint, fontSize: 11)),
        ],
      );
}
