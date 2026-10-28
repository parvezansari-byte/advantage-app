// lib/screens/portfolio_review_screen.dart
// ---------------------------------------------------------------------------
// Mutual fund portfolio review. Add holdings by hand (fund name, invested,
// current value, date) or upload an Excel / CSV. The server matches each fund
// to our database and compares your return with its category and benchmark.
// Illustration only, not investment advice.
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/portfolio_review_service.dart';

String _inr(num v) {
  final n = v.round();
  final s = n.abs().toString();
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},${s.substring(s.length - 3)}';
  }
  return '${n < 0 ? '-' : ''}₹$out';
}

String _pct(num? v, {bool sign = true}) =>
    v == null ? '-' : '${sign && v > 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

String _dmy(String? iso) {
  if (iso == null || iso.length < 10) return 'no date';
  return '${iso.substring(8, 10)}-${iso.substring(5, 7)}-${iso.substring(0, 4)}';
}

Color _verdictColor(String v) {
  switch (v) {
    case 'Ahead':
      return Brand.green;
    case 'Behind':
      return Brand.red;
    case 'In line':
      return Brand.gold;
    default:
      return Brand.mint;
  }
}

class PortfolioReviewScreen extends StatefulWidget {
  const PortfolioReviewScreen({super.key});
  @override
  State<PortfolioReviewScreen> createState() => _PortfolioReviewScreenState();
}

class _PortfolioReviewScreenState extends State<PortfolioReviewScreen> {
  static const _prefKey = 'pf_review_rows_v1';
  final List<PfRow> _rows = [];
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_prefKey);
      if (s != null) {
        final l = jsonDecode(s) as List;
        if (mounted) setState(() => _rows.addAll(l.map((e) => PfRow.fromJson(e as Map<String, dynamic>))));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, jsonEncode(_rows.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _changed() {
    _result = null;
    _save();
    setState(() {});
  }

  Future<void> _addOrEdit([int? index]) async {
    final row = await showModalBottomSheet<PfRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.vault,
      builder: (_) => _RowSheet(initial: index == null ? null : _rows[index]),
    );
    if (row == null) return;
    if (index == null) {
      _rows.add(row);
    } else {
      _rows[index] = row;
    }
    _changed();
  }

  Future<void> _upload() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      if (f.bytes == null) {
        setState(() => _error = 'Could not read that file.');
        return;
      }
      setState(() => _busy = true);
      final res = await PortfolioReviewService.parse(f.name, f.bytes!);
      final rows = (res['rows'] as List).map((e) => PfRow.fromJson(e as Map<String, dynamic>)).toList();
      _rows.addAll(rows);
      final warn = (res['warnings'] as List).map((e) => '$e').toList();
      _info = 'Added ${rows.length} funds from ${f.name}.'
          '${warn.isEmpty ? '' : '\n${warn.take(4).join('\n')}'}';
      _changed();
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await PortfolioReviewService.review(_rows);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear all holdings?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      _rows.clear();
      _info = null;
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Portfolio review'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(tooltip: 'Clear all', icon: const Icon(Icons.delete_outline), onPressed: _clear),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Add your funds by hand or upload an Excel / CSV with columns: Fund name, Invested value, '
            'Current value, Date. We compare each fund with its category and benchmark.',
            style: TextStyle(color: Brand.mint, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _addOrEdit(),
                icon: const Icon(Icons.add, color: Brand.gold),
                label: const Text('Add fund', style: TextStyle(color: Brand.gold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file, color: Brand.gold),
                label: const Text('Upload Excel', style: TextStyle(color: Brand.gold)),
              ),
            ),
          ]),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_info!, style: const TextStyle(color: Brand.mint, fontSize: 12)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('No holdings yet', style: TextStyle(color: Brand.mint))),
            ),
          for (var i = 0; i < _rows.length; i++) _rowTile(i),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.vault),
              onPressed: _busy ? null : _review,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Review ${_rows.length} fund${_rows.length == 1 ? '' : 's'}'),
            ),
          ],
          if (_result != null) ..._resultWidgets(_result!),
        ],
      ),
    );
  }

  Widget _rowTile(int i) {
    final r = _rows[i];
    final gain = r.current - r.invested;
    return Card(
      color: Brand.fern.withOpacity(0.5),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _addOrEdit(i),
        title: Text(r.name,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.paper, fontSize: 13.5)),
        subtitle: Text(
            'Invested ${_inr(r.invested)}  •  Now ${_inr(r.current)}  •  ${_dmy(r.date)}',
            style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_pct(r.invested > 0 ? gain / r.invested * 100 : null),
              style: TextStyle(color: gain >= 0 ? Brand.green : Brand.red, fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Brand.mint),
            onPressed: () {
              _rows.removeAt(i);
              _changed();
            },
          ),
        ]),
      ),
    );
  }

  // ----------------------------------------------------------------- results
  List<Widget> _resultWidgets(Map<String, dynamic> r) {
    final t = r['totals'] as Map<String, dynamic>;
    final holdings = (r['holdings'] as List).cast<Map<String, dynamic>>();
    final alloc = r['allocation'] as Map<String, dynamic>;
    final obs = (r['observations'] as List).map((e) => '$e').toList();
    final notes = (r['notes'] as List).map((e) => '$e').toList();
    final gain = (t['gain'] as num).toDouble();
    final gc = gain >= 0 ? Brand.green : Brand.red;

    return [
      const SizedBox(height: 22),
      Text('Review as on ${r['as_of']}',
          style: const TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.fern.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _stat('Invested', _inr(t['invested'] as num)),
            _stat('Current', _inr(t['current'] as num)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _stat('Gain', '${_inr(gain)} (${_pct(t['abs_pct'] as num)})', color: gc),
            _stat('XIRR (a year)', _pct(t['xirr_pct'] as num?, sign: false)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _chip('${t['ahead']} ahead', Brand.green),
            _chip('${t['in_line']} in line', Brand.gold),
            _chip('${t['behind']} behind', Brand.red),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      const Text('ALLOCATION', style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)),
      const SizedBox(height: 6),
      for (final a in (alloc['by_asset'] as List).cast<Map<String, dynamic>>()) _bar(a),
      const SizedBox(height: 6),
      for (final a in (alloc['by_category'] as List).cast<Map<String, dynamic>>()) _bar(a, small: true),
      const SizedBox(height: 16),
      const Text('FUND BY FUND', style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)),
      const SizedBox(height: 6),
      for (final h in holdings) _holdingCard(h),
      if (obs.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('THINGS TO NOTICE',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)),
        const SizedBox(height: 6),
        for (final o in obs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $o', style: const TextStyle(color: Brand.paper, fontSize: 13)),
          ),
      ],
      const SizedBox(height: 14),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(n, style: const TextStyle(color: Brand.mint, fontSize: 11)),
        ),
    ];
  }

  Widget _stat(String label, String value, {Color color = Brand.paper}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Brand.mint, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
      );

  Widget _bar(Map<String, dynamic> a, {bool small = false}) {
    final pct = (a['pct'] as num).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        SizedBox(
          width: 118,
          child: Text('${a['name']}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: small ? Brand.mint : Brand.paper, fontSize: small ? 11.5 : 12.5)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: small ? 6 : 9,
              backgroundColor: Brand.fern.withOpacity(0.4),
              color: small ? Brand.teal : Brand.gold,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text('${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right, style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
        ),
      ]),
    );
  }

  Widget _holdingCard(Map<String, dynamic> h) {
    final v = '${h['verdict']}';
    final vc = _verdictColor(v);
    final matched = h['matched'] == true;
    final flags = (h['flags'] as List).map((e) => '$e').toList();
    final bench = h['benchmark_pct'] as num?;
    final cat = h['category_pct'] as num?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.fern.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: vc, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('${h['name']}',
                style: const TextStyle(color: Brand.paper, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          _chip(v, vc),
        ]),
        if (matched && h['matched_name'] != h['name'])
          Text('Matched to: ${h['matched_name']}', style: const TextStyle(color: Brand.mint, fontSize: 10.5)),
        const SizedBox(height: 6),
        Text(
            '${_inr(h['invested'] as num)} → ${_inr(h['current'] as num)}   '
            '${_pct(h['abs_pct'] as num)} total'
            '${h['cagr_pct'] != null ? '  •  ${_pct(h['cagr_pct'] as num)} a year' : ''}',
            style: const TextStyle(color: Brand.paper, fontSize: 12)),
        if (matched && (bench != null || cat != null)) ...[
          const SizedBox(height: 4),
          Text(
              '${h['horizon'] ?? ''} typical:  '
              '${bench != null ? 'benchmark ${_pct(bench)}' : ''}'
              '${bench != null && cat != null ? '  •  ' : ''}'
              '${cat != null ? '${h['category'] ?? 'category'} ${_pct(cat)}' : ''}',
              style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
        ],
        if ('${h['verdict_why']}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${h['verdict_why']}', style: TextStyle(color: vc, fontSize: 11.5)),
          ),
        if (h['benchmark'] != null)
          Text('Benchmark: ${h['benchmark']} (via index funds)',
              style: const TextStyle(color: Brand.mint, fontSize: 10.5)),
        if (h['plan_note'] != null)
          Text('${h['plan_note']}', style: const TextStyle(color: Brand.mint, fontSize: 10.5)),
        for (final f in flags)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('⚠ $f', style: const TextStyle(color: Brand.gold, fontSize: 11)),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet: fund name (with search), invested, current value, date
// ---------------------------------------------------------------------------
class _RowSheet extends StatefulWidget {
  final PfRow? initial;
  const _RowSheet({this.initial});
  @override
  State<_RowSheet> createState() => _RowSheetState();
}

class _RowSheetState extends State<_RowSheet> {
  final _name = TextEditingController();
  final _inv = TextEditingController();
  final _cur = TextEditingController();
  DateTime? _date;
  List<String> _hits = [];
  Timer? _deb;
  String? _err;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _name.text = i.name;
      _inv.text = i.invested.toStringAsFixed(0);
      _cur.text = i.current.toStringAsFixed(0);
      _date = i.date == null ? null : DateTime.tryParse(i.date!);
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    _name.dispose();
    _inv.dispose();
    _cur.dispose();
    super.dispose();
  }

  void _onName(String q) {
    _deb?.cancel();
    if (q.trim().length < 3) {
      setState(() => _hits = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await PortfolioReviewService.searchFunds(q);
        if (mounted) setState(() => _hits = r);
      } catch (_) {}
    });
  }

  double? _num(String s) => double.tryParse(s.replaceAll(RegExp(r'[,\s₹]'), ''));

  void _submit() {
    final inv = _num(_inv.text), cur = _num(_cur.text);
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Enter the fund name');
    if (inv == null || inv <= 0) return setState(() => _err = 'Invested value must be above 0');
    if (cur == null || cur < 0) return setState(() => _err = 'Enter the current value');
    final d = _date;
    Navigator.pop(
      context,
      PfRow(
        name: _name.text.trim(),
        invested: inv,
        current: cur,
        date: d == null
            ? null
            : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Brand.mint),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Brand.fern)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Brand.gold)),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.initial == null ? 'Add a fund' : 'Edit fund',
              style: const TextStyle(color: Brand.paper, fontSize: 16, fontWeight: FontWeight.w700)),
          TextField(
            controller: _name,
            style: const TextStyle(color: Brand.paper),
            decoration: _dec('Fund name (type to search)'),
            onChanged: _onName,
          ),
          for (final h in _hits.take(6))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(h, style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
              onTap: () => setState(() {
                _name.text = h;
                _hits = [];
              }),
            ),
          TextField(
            controller: _inv,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Brand.paper),
            decoration: _dec('Invested value (₹)'),
          ),
          TextField(
            controller: _cur,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Brand.paper),
            decoration: _dec('Current value (₹)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, color: Brand.gold),
            label: Text(
                _date == null
                    ? 'Investment date'
                    : '${_date!.day.toString().padLeft(2, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.year}',
                style: const TextStyle(color: Brand.gold)),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _date ?? DateTime(now.year - 1, now.month, now.day),
                firstDate: DateTime(2000),
                lastDate: now,
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Date of purchase (for SIPs, add each instalment as its own row).',
                style: TextStyle(color: Brand.mint, fontSize: 11)),
          ),
          if (_err != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: Brand.red))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.vault),
              onPressed: _submit,
              child: const Text('Save'),
            ),
          ),
        ]),
      ),
    );
  }
}
