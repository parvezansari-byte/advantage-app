// lib/screens/allocation_screen.dart
// ---------------------------------------------------------------------------
// Sample equity / debt allocation for a SIP or a lump sum, with a growth chart.
// Auto: split from risk profile + years, funds picked by Sharpe ratio.
// Manual: you set the equity %, and can pick either fund from a dropdown.
// All numbers come from /allocation/plan. Illustration only, not advice.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/allocation_service.dart';

String _inrFull(double v) {
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

String _pct(double? v) => v == null ? '\u2014' : '${v.toStringAsFixed(1)}%';

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
  double _equityPct = 60;
  String? _equityFund, _debtFund;

  AllocOptions? _options;
  AllocPlan? _plan;
  String? _error;
  bool _loading = true;
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
      final plan = await AllocationService.plan(
        mode: _mode,
        amount: _amount,
        years: _years,
        risk: _risk,
        equityPct: _manual ? _equityPct.round() : null,
        equityFund: _manual ? _equityFund : null,
        debtFund: _manual ? _debtFund : null,
      );
      if (!mounted || id != _requestId) return;
      setState(() => _plan = plan);
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _setManual(bool on) async {
    if (on && _plan != null) {
      // Start from what Auto chose, so switching does not change the numbers.
      _equityPct = _plan!.equityPct.toDouble();
      _equityFund = _plan!.equity.fund?.name;
      _debtFund = _plan!.debt.fund?.name;
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _inputs(),
          const SizedBox(height: 14),
          if (_error != null)
            _box(Text(_error!, style: const TextStyle(color: Brand.red))),
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
        child: Padding(padding: padding ?? const EdgeInsets.all(14), child: child),
      );

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
            labelText: _mode == 'sip' ? 'Amount per month (\u20b9)' : 'Amount (\u20b9)',
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
        const SizedBox(height: 10),
        if (!_manual)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in const ['conservative', 'balanced', 'aggressive'])
              _chip(r[0].toUpperCase() + r.substring(1), _risk == r, () {
                setState(() => _risk = r);
                _run();
              }),
          ])
        else
          ..._manualControls(),
      ],
    ));
  }

  List<Widget> _manualControls() {
    return [
      Text(
          'Equity ${_equityPct.round()}%  \u00b7  Debt ${100 - _equityPct.round()}%',
          style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
      Slider(
        value: _equityPct,
        min: 0,
        max: 100,
        divisions: 20,
        activeColor: Brand.gold,
        label: '${_equityPct.round()}%',
        onChanged: (v) => setState(() => _equityPct = v),
        onChangeEnd: (_) => _run(),
      ),
      _dropdown('Equity fund', _options?.equity, _equityFund, _plan?.equity.fund,
          (v) {
        setState(() => _equityFund = v);
        _run();
      }),
      const SizedBox(height: 8),
      _dropdown('Debt fund', _options?.debt, _debtFund, _plan?.debt.fund, (v) {
        setState(() => _debtFund = v);
        _run();
      }),
    ];
  }

  Widget _dropdown(String label, List<AllocFund>? options, String? value,
      AllocFund? current, ValueChanged<String?> onChanged) {
    if (options == null) {
      return Text('Loading $label list\u2026',
          style: const TextStyle(color: Brand.mint, fontSize: 12));
    }
    // The fund Auto picked may not be in the short list; keep it selectable.
    final items = [...options];
    if (current != null && !items.any((f) => f.name == current.name)) {
      items.insert(0, current);
    }
    final selected = items.any((f) => f.name == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: selected,
      isExpanded: true,
      dropdownColor: Brand.vault,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Brand.mint),
      ),
      style: const TextStyle(color: Brand.paper, fontSize: 13),
      items: [
        for (final f in items)
          DropdownMenuItem<String>(
            value: f.name,
            child: Text('${f.shortName}  \u00b7  ${f.category}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  List<Widget> _results(AllocPlan p) {
    final sipWord = p.mode == 'sip' ? ' a month' : '';
    final gain = p.base - p.invested;
    return [
      if (p.hypothetical)
        _box(
          const Text(
              'Hypothetical: at least one fund has no usable track record, so a '
              'standard assumption (12% a year for equity, 7% for debt) is used for it.',
              style: TextStyle(color: Brand.gold, fontSize: 12.5)),
        ),
      _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('YOUR MIX',
                  style: TextStyle(
                      color: Brand.gold,
                      fontSize: 11.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
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
                if (p.equityPct > 0)
                  Expanded(flex: p.equityPct, child: Container(color: Brand.gold)),
                if (p.debtPct > 0)
                  Expanded(flex: p.debtPct, child: Container(color: Brand.blue)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(p.how,
              style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
          const SizedBox(height: 8),
          _bucketRow('Equity', Brand.gold, p.equity, sipWord),
          const Divider(height: 22),
          _bucketRow('Debt', Brand.blue, p.debt, sipWord),
        ],
      )),
      _box(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AFTER SOME YEARS',
              style: TextStyle(
                  color: Brand.gold,
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('${p.years} ${p.years == 1 ? 'year' : 'years'}',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
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
          Wrap(spacing: 12, runSpacing: 4, children: const [
            _Key('Invested', Colors.grey),
            _Key('Low', Brand.red),
            _Key('Expected', Brand.gold),
            _Key('High', Brand.green),
          ]),
        ],
      )),
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

  Widget _bucketRow(String title, Color color, AllocBucket b, String sipWord) {
    final f = b.fund;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$title ${b.pct}%',
              style: const TextStyle(
                  color: Brand.paper, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${_inrFull(b.amount)}$sipWord',
              style: const TextStyle(color: Brand.paper)),
        ]),
        if (b.pct > 0) ...[
          const SizedBox(height: 4),
          Text(f?.shortName ?? 'No fund found',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(
              b.ret.hypothetical
                  ? 'Hypothetical ${b.ret.cagr.toStringAsFixed(1)}% a year (no track record)'
                  : 'Past ${b.ret.basis} ${_pct(b.ret.historical)} a year \u00b7 expected ${b.ret.cagr.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: b.ret.hypothetical ? Brand.gold : Brand.mint,
                  fontSize: 11.5)),
        ],
      ],
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
    final names = ['Invested', 'Low', 'Expected', 'High'];
    final maxY = p.points.map((e) => e.high).fold<double>(0, (a, b) => a > b ? a : b);
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
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Brand.mint.withValues(alpha: 0.12), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
