// lib/screens/rebalance_screen.dart
// ---------------------------------------------------------------------------
// Compares the equity / hybrid / debt split of a portfolio with a model mix
// (by risk profile and horizon) or your own target, shows the gap, how to close
// it with fresh money, and which categories lag. Illustration only.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

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

Color _statusColor(String s) =>
    s == 'On target' ? Brand.green : (s == 'Above target' ? Brand.gold : Brand.blue);

class RebalanceScreen extends StatefulWidget {
  final List<PfRow> rows;
  const RebalanceScreen({super.key, required this.rows});
  @override
  State<RebalanceScreen> createState() => _RebalanceScreenState();
}

class _RebalanceScreenState extends State<RebalanceScreen> {
  String _risk = 'balanced';
  int _years = 10;
  final _fresh = TextEditingController();
  final _eq = TextEditingController();
  final _hy = TextEditingController();
  final _dt = TextEditingController();
  bool _custom = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _fresh.dispose();
    _eq.dispose();
    _hy.dispose();
    _dt.dispose();
    super.dispose();
  }

  double _v(TextEditingController c) => double.tryParse(c.text.replaceAll(RegExp(r'[,\s₹]'), '')) ?? 0;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await PortfolioReviewService.rebalance(
        widget.rows,
        risk: _risk,
        years: _years,
        newMoney: _v(_fresh),
        target: _custom ? {'equity': _v(_eq), 'hybrid': _v(_hy), 'debt': _v(_dt)} : null,
      );
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Target mix check'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 8, children: [
            for (final r in const ['conservative', 'balanced', 'aggressive'])
              ChoiceChip(
                label: Text(r[0].toUpperCase() + r.substring(1)),
                selected: !_custom && _risk == r,
                selectedColor: Brand.gold,
                backgroundColor: Brand.fern,
                labelStyle: TextStyle(color: (!_custom && _risk == r) ? Brand.vault : Brand.paper, fontSize: 12),
                onSelected: (_) {
                  setState(() {
                    _risk = r;
                    _custom = false;
                  });
                  _run();
                },
              ),
            ChoiceChip(
              label: const Text('My own'),
              selected: _custom,
              selectedColor: Brand.gold,
              backgroundColor: Brand.fern,
              labelStyle: TextStyle(color: _custom ? Brand.vault : Brand.paper, fontSize: 12),
              onSelected: (_) => setState(() => _custom = true),
            ),
          ]),
          const SizedBox(height: 8),
          if (!_custom)
            Row(children: [
              const Text('Years to goal', style: TextStyle(color: Brand.mint, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _years.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  activeColor: Brand.gold,
                  label: '$_years',
                  onChanged: (v) => setState(() => _years = v.round()),
                  onChangeEnd: (_) => _run(),
                ),
              ),
              Text('$_years', style: const TextStyle(color: Brand.paper)),
            ]),
          if (_custom) ...[
            Row(children: [
              for (final p in [('Equity %', _eq), ('Hybrid %', _hy), ('Debt %', _dt)])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextField(
                      controller: p.$2,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Brand.paper),
                      decoration: InputDecoration(
                          labelText: p.$1, labelStyle: const TextStyle(color: Brand.mint, fontSize: 12)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            const Text('The three must add up to 100.', style: TextStyle(color: Brand.mint, fontSize: 11)),
          ],
          TextField(
            controller: _fresh,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Brand.paper),
            decoration: const InputDecoration(
              labelText: 'New money you could add (₹, optional)',
              labelStyle: TextStyle(color: Brand.mint, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.vault),
            onPressed: _busy ? null : _run,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Check'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Brand.red)),
            ),
          if (_data != null) ..._content(_data!),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final classes = (d['classes'] as List).cast<Map<String, dynamic>>();
    final cats = (d['categories'] as List).cast<Map<String, dynamic>>();
    final summary = (d['summary'] as List).map((e) => '$e').toList();
    final notes = (d['notes'] as List).map((e) => '$e').toList();
    final fm = d['fresh_money'] as Map<String, dynamic>?;
    final out = <Widget>[
      const SizedBox(height: 16),
      Text('${d['source']}', style: const TextStyle(color: Brand.mint, fontSize: 12)),
      const SizedBox(height: 10),
    ];
    for (final c in classes) {
      final cur = (c['current_pct'] as num).toDouble();
      final tgt = (c['target_pct'] as num).toDouble();
      final col = _statusColor('${c['status']}');
      final move = (c['move'] as num).toDouble();
      out.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.fern.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: col, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${c['label']}',
                  style: const TextStyle(color: Brand.paper, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Text('${c['status']}', style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          _bar('Now', cur, Brand.gold),
          const SizedBox(height: 4),
          _bar('Target', tgt, Brand.teal),
          const SizedBox(height: 6),
          Text(
              move.abs() < 500
                  ? 'Within range'
                  : (move > 0
                      ? 'About ${_inr(move)} short of target'
                      : 'About ${_inr(-move)} above target'),
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
        ]),
      ));
    }
    if (fm != null) {
      out.add(const SizedBox(height: 4));
      out.add(const Text('WHERE NEW MONEY WOULD GO',
          style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)));
      out.add(const SizedBox(height: 6));
      for (final s in (fm['split'] as List).cast<Map<String, dynamic>>()) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
              '${s['label']}: ${_inr(s['put'] as num)}  →  ${(s['after_pct'] as num).toStringAsFixed(1)}% of the portfolio',
              style: const TextStyle(color: Brand.paper, fontSize: 13)),
        ));
      }
    }
    out.add(const SizedBox(height: 14));
    out.add(const Text('CATEGORY GAPS',
        style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)));
    out.add(const SizedBox(height: 6));
    String? lastClass;
    for (final c in cats) {
      if ('${c['class']}' != lastClass) {
        lastClass = '${c['class']}';
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(lastClass, style: const TextStyle(color: Brand.paper, fontWeight: FontWeight.w600)),
        ));
      }
      final col = _statusColor('${c['status']}');
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${c['category']}', style: const TextStyle(color: Brand.mint, fontSize: 12.5))),
            Text('${(c['current_pct'] as num).toStringAsFixed(0)}% now • ${(c['target_pct'] as num).toStringAsFixed(0)}% model',
                style: TextStyle(color: col, fontSize: 11.5)),
          ]),
          if (c['candidate'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('For reference: ${'${c['candidate']['name']}'.split(' - ').first} (best risk-adjusted record in this category)',
                  style: const TextStyle(color: Brand.mint, fontSize: 10.5)),
            ),
        ]),
      ));
    }
    out.add(const SizedBox(height: 14));
    for (final s in summary) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('• $s', style: const TextStyle(color: Brand.paper, fontSize: 12.5)),
      ));
    }
    out.add(const SizedBox(height: 8));
    for (final n in notes) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(n, style: const TextStyle(color: Brand.mint, fontSize: 11)),
      ));
    }
    return out;
  }

  Widget _bar(String label, double pct, Color c) => Row(children: [
        SizedBox(width: 48, child: Text(label, style: const TextStyle(color: Brand.mint, fontSize: 11))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Brand.vault,
              color: c,
            ),
          ),
        ),
        SizedBox(
            width: 46,
            child: Text('${pct.toStringAsFixed(1)}%',
                textAlign: TextAlign.right, style: const TextStyle(color: Brand.paper, fontSize: 11.5))),
      ]);
}
