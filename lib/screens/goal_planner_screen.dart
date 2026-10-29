// lib/screens/goal_planner_screen.dart
//
// Goal planner: the monthly SIP needed to reach a goal, allowing for inflation,
// savings already set aside and a yearly step-up. Calls POST /planner/goal.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class GoalPlannerScreen extends StatefulWidget {
  const GoalPlannerScreen({super.key});

  @override
  State<GoalPlannerScreen> createState() => _GoalPlannerScreenState();
}

class _GoalPlannerScreenState extends State<GoalPlannerScreen> {
  final _target = TextEditingController(text: '5000000');
  final _existing = TextEditingController(text: '0');
  final _sip = TextEditingController();
  double _years = 10;
  double _inflation = 6;
  double _ret = 12;
  double _step = 0;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _r;

  @override
  void dispose() {
    _target.dispose();
    _existing.dispose();
    _sip.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _calc() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'target_today': _num(_target),
        'years': _years.round(),
        'inflation_pct': _inflation,
        'return_pct': _ret,
        'existing': _num(_existing),
        'step_up_pct': _step,
      };
      if (_sip.text.trim().isNotEmpty) body['monthly_sip'] = _num(_sip);
      final res = await http
          .post(Uri.parse('${ApiService.baseUrl}/planner/goal'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _r = Map<String, dynamic>.from(j as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _inr(num v) {
    final neg = v < 0;
    final s = v.abs().round().toString();
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
    return '${neg ? '-' : ''}₹$out';
  }

  String _short(num v) {
    final a = v.abs();
    if (a >= 1e7) return '₹${(v / 1e7).toStringAsFixed(2)} Cr';
    if (a >= 1e5) return '₹${(v / 1e5).toStringAsFixed(2)} L';
    return _inr(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Goal planner',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _field(_target, 'Goal in today\'s money (₹)'),
            _slider('Years to goal', _years, 1, 40, 39, '${_years.round()} yr',
                (v) => setState(() => _years = v)),
            _slider('Inflation', _inflation, 0, 12, 24,
                '${_inflation.toStringAsFixed(1)}%',
                (v) => setState(() => _inflation = v)),
            _slider('Expected return', _ret, 4, 20, 32,
                '${_ret.toStringAsFixed(1)}%', (v) => setState(() => _ret = v)),
            _slider('Yearly SIP step-up', _step, 0, 20, 20,
                '${_step.round()}%', (v) => setState(() => _step = v)),
            _field(_existing, 'Already saved for this goal (₹)'),
            _field(_sip, 'Test your own monthly SIP (₹, optional)'),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold, foregroundColor: Brand.vault),
              onPressed: _loading ? null : _calc,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Calculate'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Brand.red)),
              ),
            if (_r != null) ..._result(_r!),
          ],
        ),
      ),
    );
  }

  List<Widget> _result(Map<String, dynamic> r) {
    final solved = r['solved'] == true;
    final onTrack = r['on_track'] == true;
    final scenarios = ((r['scenarios'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return [
      const SizedBox(height: 16),
      _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(solved ? 'Invest every month' : 'Your SIP of',
            style: const TextStyle(color: Brand.mint, fontSize: 12)),
        Text(_inr((r['monthly_sip'] ?? 0) as num),
            style: const TextStyle(
                color: Brand.gold, fontSize: 30, fontWeight: FontWeight.bold)),
        if (_step > 0)
          Text('rising to ${_inr((r['last_year_sip'] ?? 0) as num)} a month in the last year',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
        const SizedBox(height: 8),
        _kv('Goal after inflation', _short((r['future_target'] ?? 0) as num)),
        _kv('Projected corpus', _short((r['projected_corpus'] ?? 0) as num)),
        _kv('You invest', _short((r['total_invested'] ?? 0) as num)),
        _kv('Growth', _short((r['growth'] ?? 0) as num)),
        const SizedBox(height: 6),
        Text(
          onTrack ? 'On track for the goal.' : 'Falls short of the goal at this SIP.',
          style: TextStyle(
              color: onTrack ? Brand.green : Brand.red,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
      ])),
      const Padding(
        padding: EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text('If returns differ',
            style: TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      _box(Column(children: [
        for (final s in scenarios)
          _kv('${(s['return_pct'] as num).toStringAsFixed(1)}% a year',
              '${_short((s['corpus'] ?? 0) as num)}  ·  ${s['vs_goal_pct']}% of goal'),
      ])),
      const SizedBox(height: 10),
      Text('${r['note'] ?? ''}',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
    ];
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Brand.paper),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Brand.mint, fontSize: 13),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Brand.mint.withValues(alpha: 0.4))),
            focusedBorder:
                const OutlineInputBorder(borderSide: BorderSide(color: Brand.gold)),
          ),
        ),
      );

  Widget _slider(String label, double v, double min, double max, int div,
          String shown, ValueChanged<double> on) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Brand.mint, fontSize: 13))),
          Text(shown,
              style: const TextStyle(
                  color: Brand.gold, fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: v,
          min: min,
          max: max,
          divisions: div,
          activeColor: Brand.gold,
          onChanged: on,
        ),
      ]);

  Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: Brand.mint, fontSize: 13))),
          Text(v, style: const TextStyle(color: Brand.paper, fontSize: 13)),
        ]),
      );
}
