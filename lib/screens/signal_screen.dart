// lib/screens/signal_screen.dart
//
// Personal-use composite signal for NIFTY 50 / BANK NIFTY: combines price
// vs VWAP, RSI(14), SMA(9/20) crossover, option-chain PCR, and spot vs max
// pain into one "lean" with the real numbers shown underneath. This is
// explicitly NOT a win-rate predictor — no such thing exists for index F&O
// — it's a decision-support aggregate. The backend only serves this to one
// account email; the menu entry that opens this screen is already gated
// the same way in more_screen.dart.

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

const _signalIndices = ['NIFTY 50', 'BANK NIFTY'];

class SignalScreen extends StatefulWidget {
  const SignalScreen({super.key});

  @override
  State<SignalScreen> createState() => _SignalScreenState();
}

class _SignalScreenState extends State<SignalScreen> {
  String _index = 'NIFTY 50';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  Map<String, dynamic>? _bt;
  bool _btLoading = false;
  String? _btError;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) {
      setState(() {
        _error = 'Sign in to use signals';
        _loading = false;
      });
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await ApiService.getSignal(_index, email);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = '$e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _onIndexChanged(String i) {
    if (_index == i) return;
    setState(() {
      _index = i;
      _data = null;
      _bt = null;
      _btError = null;
    });
    _load();
  }

  Future<void> _runBacktest() async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    setState(() {
      _btLoading = true;
      _btError = null;
    });
    try {
      final r = await ApiService.getSignalBacktest(_index, email);
      if (mounted) setState(() => _bt = r);
    } catch (e) {
      if (mounted) setState(() => _btError = '$e');
    } finally {
      if (mounted) setState(() => _btLoading = false);
    }
  }

  Color _leanColor(String lean) {
    switch (lean) {
      case 'bullish':
        return Brand.green;
      case 'bearish':
        return Brand.red;
      default:
        return Brand.mint;
    }
  }

  IconData _leanIcon(String lean) {
    switch (lean) {
      case 'bullish':
        return Icons.trending_up;
      case 'bearish':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final score = (d?['score'] as num?)?.toInt() ?? 0;
    final signalColor = score >= 2
        ? Brand.green
        : (score <= -2 ? Brand.red : Brand.gold);

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Nifty Signals',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final i in _signalIndices)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: GestureDetector(
                        onTap: () => _onIndexChanged(i),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _index == i
                                ? Brand.gold.withValues(alpha: 0.18)
                                : Brand.fern.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _index == i
                                  ? Brand.gold
                                  : Brand.mint.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(i,
                              style: TextStyle(
                                  color: _index == i ? Brand.gold : Brand.mint,
                                  fontSize: 11.5,
                                  fontWeight: _index == i
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_error != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 30),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Brand.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off, color: Brand.red, size: 28),
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            height: 1.4)),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: Brand.gold, foregroundColor: Brand.vault),
                      onPressed: () => _load(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              )
            else if (d != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: signalColor.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                            score >= 2
                                ? Icons.trending_up
                                : (score <= -2 ? Icons.trending_down : Icons.trending_flat),
                            color: signalColor,
                            size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${d['signal']}',
                              style: TextStyle(
                                  color: signalColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        '${d['agree']} indicators agree  ·  updated ${d['updated']}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.75), fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final r in (d['readings'] as List? ?? []))
                _ReadingTile(
                  reading: (r as Map).cast<String, dynamic>(),
                  color: _leanColor('${r['lean']}'),
                  icon: _leanIcon('${r['lean']}'),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${d['disclaimer']}',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.65),
                        fontSize: 10.5,
                        height: 1.45)),
              ),
              const SizedBox(height: 14),
              _BacktestCard(
                data: _bt,
                loading: _btLoading,
                error: _btError,
                onRun: _runBacktest,
              ),
              const SizedBox(height: 8),
              Text(
                'Refreshes every 30 seconds while this screen is open.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.45), fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({required this.reading, required this.color, required this.icon});

  final Map<String, dynamic> reading;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${reading['label']}',
                    style: const TextStyle(
                        color: Brand.paper, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${reading['detail']}',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.75), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BacktestCard extends StatelessWidget {
  const _BacktestCard({
    required this.data,
    required this.loading,
    required this.error,
    required this.onRun,
  });

  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback onRun;

  String _pct(dynamic v, {int dp = 1}) =>
      v == null ? '—' : '${(v as num).toStringAsFixed(dp)}%';

  @override
  Widget build(BuildContext context) {
    final d = data;
    final trades = (d?['trades'] as num?)?.toInt() ?? 0;

    Widget stat(String label, String value, Color colour) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text(value,
                      style: TextStyle(
                          color: colour,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.mint.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: Brand.gold, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Backtest the rules',
                    style: TextStyle(
                        color: Brand.paper,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold)),
              ),
              if (loading)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold))
              else
                TextButton(
                  onPressed: onRun,
                  child: Text(d == null ? 'Run' : 'Re-run',
                      style: const TextStyle(color: Brand.gold)),
                ),
            ],
          ),
          if (d == null && error == null && !loading)
            Text(
              'Replays VWAP + RSI + SMA rules on the last ~60 days of '
              '15-minute bars to show how often they were actually right.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7),
                  fontSize: 11,
                  height: 1.4),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Brand.red, fontSize: 11.5)),
          if (d != null && trades == 0)
            Text('${d['note'] ?? 'No signals fired in this period.'}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 11.5)),
          if (d != null && trades > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              stat('TRADES', '$trades', Brand.paper),
              stat('WIN RATE', _pct(d['win_rate_pct']),
                  ((d['win_rate_pct'] as num?) ?? 0) >= 55 ? Brand.green : Brand.gold),
              stat('AVG / TRADE', _pct(d['avg_return_pct'], dp: 3),
                  ((d['avg_return_pct'] as num?) ?? 0) > 0 ? Brand.green : Brand.red),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              stat('MARKET ROSE', _pct(d['baseline_up_pct']), Brand.mint),
              stat('MAX DRAWDOWN', _pct(d['max_drawdown_pct'], dp: 2), Brand.red),
              stat('WORST STREAK', '${d['worst_losing_streak']} losses', Brand.red),
            ]),
            const SizedBox(height: 10),
            Text(
              'Longs: ${_pct(d['long_win_rate_pct'])} of ${d['long_trades']}  ·  '
              'Shorts: ${_pct(d['short_win_rate_pct'])} of ${d['short_trades']}  ·  '
              'held ${d['horizon_minutes']} min  ·  '
              '${d['period_start']} to ${d['period_end']}',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.75),
                  fontSize: 10.5,
                  height: 1.4),
            ),
            const SizedBox(height: 8),
            Text('${d['caveats']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.5),
                    fontSize: 10,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }
}
