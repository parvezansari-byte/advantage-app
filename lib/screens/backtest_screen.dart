// lib/screens/backtest_screen.dart
// ---------------------------------------------------------------------------
// Strategy backtesting on real historical prices.
//
// The simulation decides on day t's close and trades at day t+1's open, so no
// result depends on a price it couldn't have known. Every strategy is shown
// against Buy & Hold on identical data — most timing strategies lose to it,
// and the screen says so plainly rather than burying it.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _group(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return '${n < 0 ? '-' : ''}$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final buf = <String>[];
  while (rest.length > 2) {
    buf.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) buf.insert(0, rest);
  return '${n < 0 ? '-' : ''}${buf.join(',')},$last3';
}

String _money(num? v) => v == null ? '—' : '₹${_group(v.round())}';

String _moneyShort(num? v) {
  if (v == null) return '—';
  if (v.abs() >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  return _money(v);
}

String _pct(num? v, {bool sign = false}) {
  if (v == null) return '—';
  final s = sign && v > 0 ? '+' : '';
  return '$s${v.toStringAsFixed(2)}%';
}

Color _pnlColour(num? v) {
  if (v == null) return Brand.mint;
  if (v > 0) return Brand.green;
  if (v < 0) return Brand.red;
  return Brand.mint;
}

/// Exit reasons carry meaning worth colouring — a stop-loss exit is a
/// different outcome from a signal exit even at the same price.
Color _reasonColour(String reason) => switch (reason) {
      'Stop Loss' => Brand.red,
      'Take Profit' => Brand.green,
      'Open (marked)' => Brand.gold,
      _ => Brand.mint,
    };

// ===========================================================================
// SCREEN
// ===========================================================================

class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  static const _stocks = [
    'RELIANCE', 'HDFCBANK', 'ICICIBANK', 'SBIN', 'AXISBANK', 'KOTAKBANK',
    'TCS', 'INFY', 'HCLTECH', 'WIPRO', 'ITC', 'HINDUNILVR', 'NESTLEIND',
    'BHARTIARTL', 'LT', 'MARUTI', 'TATAMOTORS', 'M&M', 'BAJFINANCE',
    'SUNPHARMA', 'CIPLA', 'DRREDDY', 'TATASTEEL', 'JSWSTEEL', 'ADANIENT',
    'ADANIPORTS', 'NTPC', 'POWERGRID', 'ASIANPAINT', 'TITAN', 'ULTRACEMCO',
    'ONGC',
  ];

  static const _strategies = [
    'SMA Crossover',
    'RSI Mean Reversion',
    'Momentum (200-day trend)',
    'Buy & Hold',
  ];

  static const _periods = ['1 Year', '2 Years', '5 Years', '10 Years'];

  String _symbol = 'RELIANCE';
  String _strategy = 'SMA Crossover';
  String _period = '5 Years';
  double _capital = 100000;

  int _fast = 20;
  int _slow = 50;
  int _rsiWindow = 14;
  double _rsiBuy = 30;
  double _rsiSell = 60;

  bool _useSlTp = false;
  double _stopLoss = 10;
  double _takeProfit = 20;

  Map<String, dynamic>? _result;
  bool _running = false;
  String? _error;

  Future<void> _run() async {
    // The API rejects this too, but catching it here avoids a round trip.
    if (_strategy == 'SMA Crossover' && _fast >= _slow) {
      setState(() => _error = 'Fast SMA must be shorter than slow SMA');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await ApiService.runBacktest(
        symbol: _symbol,
        strategy: _strategy,
        period: _period,
        capital: _capital,
        fast: _fast,
        slow: _slow,
        rsiWindow: _rsiWindow,
        rsiBuy: _rsiBuy,
        rsiSell: _rsiSell,
        stopLoss: _stopLoss,
        takeProfit: _takeProfit,
        useSlTp: _useSlTp,
      );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Strategy Backtest',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          // ---- Stock ----
          const _Label('STOCK'),
          _ChipRow(
            options: _stocks,
            selected: _symbol,
            onSelect: (v) => setState(() => _symbol = v),
          ),

          const SizedBox(height: 16),
          const _Label('STRATEGY'),
          Column(
            children: [
              for (final s in _strategies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _strategy = s),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: _strategy == s
                            ? Brand.gold.withValues(alpha: 0.15)
                            : Brand.fern.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _strategy == s
                              ? Brand.gold
                              : Brand.mint.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _strategy == s
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: _strategy == s ? Brand.gold : Brand.mint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s,
                                    style: TextStyle(
                                        color: _strategy == s
                                            ? Brand.gold
                                            : Brand.paper,
                                        fontSize: 12.5,
                                        fontWeight: _strategy == s
                                            ? FontWeight.bold
                                            : FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(_describe(s),
                                    style: TextStyle(
                                        color:
                                            Brand.mint.withValues(alpha: 0.6),
                                        fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ---- Strategy parameters ----
          if (_strategy == 'SMA Crossover') ...[
            const SizedBox(height: 14),
            _IntSlider(
                label: 'Fast SMA',
                value: _fast,
                min: 5,
                max: 50,
                suffix: 'days',
                onChanged: (v) => setState(() => _fast = v)),
            _IntSlider(
                label: 'Slow SMA',
                value: _slow,
                min: 20,
                max: 200,
                suffix: 'days',
                onChanged: (v) => setState(() => _slow = v)),
          ],

          if (_strategy == 'RSI Mean Reversion') ...[
            const SizedBox(height: 14),
            _IntSlider(
                label: 'RSI window',
                value: _rsiWindow,
                min: 7,
                max: 21,
                suffix: 'days',
                onChanged: (v) => setState(() => _rsiWindow = v)),
            _IntSlider(
                label: 'Buy below RSI',
                value: _rsiBuy.round(),
                min: 15,
                max: 40,
                onChanged: (v) => setState(() => _rsiBuy = v.toDouble())),
            _IntSlider(
                label: 'Exit above RSI',
                value: _rsiSell.round(),
                min: 50,
                max: 80,
                onChanged: (v) => setState(() => _rsiSell = v.toDouble())),
          ],

          const SizedBox(height: 16),
          const _Label('PERIOD'),
          _ChipRow(
            options: _periods,
            selected: _period,
            onSelect: (v) => setState(() => _period = v),
          ),

          const SizedBox(height: 16),
          const _Label('CAPITAL'),
          _CapitalField(
            value: _capital,
            onChanged: (v) => setState(() => _capital = v),
          ),

          // ---- Risk controls ----
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _useSlTp = !_useSlTp),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: Brand.fern.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: _useSlTp
                      ? Brand.gold.withValues(alpha: 0.6)
                      : Brand.mint.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _useSlTp ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: _useSlTp ? Brand.gold : Brand.mint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Apply stop-loss and take-profit',
                        style: TextStyle(
                            color: _useSlTp ? Brand.gold : Brand.paper,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),

          if (_useSlTp) ...[
            const SizedBox(height: 10),
            _IntSlider(
                label: 'Stop loss',
                value: _stopLoss.round(),
                min: 3,
                max: 30,
                suffix: '%',
                onChanged: (v) => setState(() => _stopLoss = v.toDouble())),
            _IntSlider(
                label: 'Take profit',
                value: _takeProfit.round(),
                min: 5,
                max: 60,
                suffix: '%',
                onChanged: (v) => setState(() => _takeProfit = v.toDouble())),
          ],

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.vault),
                    )
                  : const Icon(Icons.play_arrow, size: 20),
              label: Text(_running ? 'Simulating…' : 'Run backtest',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Brand.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
              ),
              child: Text(_error!,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.9),
                      fontSize: 12,
                      height: 1.4)),
            ),
          ],

          if (_result != null) ...[
            const SizedBox(height: 24),
            _Results(data: _result!),
          ],
        ],
      ),
    );
  }

  String _describe(String s) => switch (s) {
        'SMA Crossover' =>
          'Hold while the fast average is above the slow one',
        'RSI Mean Reversion' => 'Buy when oversold, exit once recovered',
        'Momentum (200-day trend)' =>
          'Hold only while price is above its 200-day average',
        'Buy & Hold' => 'Buy on day one and never sell',
        _ => '',
      };
}

// ===========================================================================
// CONFIG WIDGETS
// ===========================================================================

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.8),
              fontSize: 9.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        itemBuilder: (context, i) {
          final o = options[i];
          final active = o == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: active
                      ? Brand.gold.withValues(alpha: 0.18)
                      : Brand.fern.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? Brand.gold
                        : Brand.mint.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(o,
                    style: TextStyle(
                        color: active ? Brand.gold : Brand.mint,
                        fontSize: 11.5,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IntSlider extends StatelessWidget {
  const _IntSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.85),
                      fontSize: 11.5)),
              const Spacer(),
              Text('$value${suffix.isEmpty ? '' : ' $suffix'}',
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Brand.gold,
              inactiveTrackColor: Brand.fern.withValues(alpha: 0.5),
              thumbColor: Brand.gold,
              overlayColor: Brand.gold.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalField extends StatefulWidget {
  const _CapitalField({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_CapitalField> createState() => _CapitalFieldState();
}

class _CapitalFieldState extends State<_CapitalField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value.round().toString());

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: Brand.paper, fontSize: 14),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null && parsed > 0) widget.onChanged(parsed);
      },
      decoration: InputDecoration(
        prefixText: '₹ ',
        prefixStyle: const TextStyle(color: Brand.gold, fontSize: 14),
        filled: true,
        fillColor: Brand.fern.withValues(alpha: 0.3),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Brand.mint.withValues(alpha: 0.2)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Brand.gold),
        ),
      ),
    );
  }
}

// ===========================================================================
// RESULTS
// ===========================================================================

class _Results extends StatelessWidget {
  const _Results({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final m = (data['metrics'] as Map).cast<String, dynamic>();
    final b = (data['benchmark'] as Map).cast<String, dynamic>();
    final trades = (data['trades'] as Map).cast<String, dynamic>();
    final beat = data['beat_benchmark'] == true;
    final edge = (data['edge_pp'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${data['symbol']} · ${data['strategy']}',
          style: const TextStyle(
              color: Brand.gold, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Text(
          '${data['from']} to ${data['to']}  ·  ${data['sessions']} sessions',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.65), fontSize: 10.5),
        ),

        const SizedBox(height: 14),

        // ---- Headline ----
        Row(
          children: [
            _ResultTile(
                label: 'FINAL VALUE',
                value: _moneyShort(m['final'] as num?),
                colour: Brand.gold),
            _ResultTile(
                label: 'TOTAL RETURN',
                value: _pct(m['total'] as num?, sign: true),
                colour: _pnlColour(m['total'] as num?)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _ResultTile(
                label: 'CAGR',
                value: _pct(m['cagr'] as num?, sign: true),
                colour: _pnlColour(m['cagr'] as num?)),
            _ResultTile(
                label: 'MAX DRAWDOWN',
                value: _pct(m['max_drawdown'] as num?),
                colour: Brand.red),
            _ResultTile(
                label: 'SHARPE',
                value: '${m['sharpe'] ?? '—'}',
                colour: ((m['sharpe'] as num?) ?? 0) >= 1
                    ? Brand.green
                    : Brand.paper),
          ],
        ),

        const SizedBox(height: 14),

        // ---- Benchmark verdict ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (beat ? Brand.green : Brand.gold).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: (beat ? Brand.green : Brand.gold)
                    .withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(beat ? Icons.trending_up : Icons.info_outline,
                      size: 16, color: beat ? Brand.green : Brand.gold),
                  const SizedBox(width: 7),
                  Text(
                    beat
                        ? 'Beat Buy & Hold by ${edge.toStringAsFixed(1)}pp'
                        : 'Buy & Hold did better by '
                            '${edge.abs().toStringAsFixed(1)}pp',
                    style: TextStyle(
                        color: beat ? Brand.green : Brand.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Strategy ${_pct(m['total'] as num?, sign: true)}',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.85),
                          fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Buy & Hold ${_pct(b['total'] as num?, sign: true)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.85),
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
              if (!beat) ...[
                const SizedBox(height: 8),
                Text(
                  'Most timing strategies underperform simply holding a '
                  'strong stock. This is a real result, not a bug.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.6),
                      fontSize: 10,
                      height: 1.4),
                ),
              ],
            ],
          ),
        ),

        // ---- Equity curve ----
        const SizedBox(height: 20),
        const _Label('EQUITY CURVE vs BUY & HOLD'),
        _EquityChart(
            curve: (data['curve'] as List?) ?? [],
            capital: (data['capital'] as num?)?.toDouble() ?? 0),

        // ---- Trade stats ----
        if ((trades['total'] as int? ?? 0) > 0) ...[
          const SizedBox(height: 20),
          const _Label('TRADE STATISTICS'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              children: [
                _StatRow(
                    label: 'Trades taken', value: '${trades['total']}'),
                _StatRow(
                    label: 'Win rate',
                    value: _pct(trades['win_rate'] as num?, sign: false),
                    colour: ((trades['win_rate'] as num?) ?? 0) >= 50
                        ? Brand.green
                        : Brand.red),
                _StatRow(
                    label: 'Wins / losses',
                    value: '${trades['wins']} / ${trades['losses']}'),
                _StatRow(
                    label: 'Average win',
                    value: _pct(trades['avg_win'] as num?, sign: true),
                    colour: Brand.green),
                _StatRow(
                    label: 'Average loss',
                    value: _pct(trades['avg_loss'] as num?, sign: true),
                    colour: Brand.red),
                _StatRow(
                    label: 'Best trade',
                    value: _pct(trades['best'] as num?, sign: true),
                    colour: Brand.green),
                _StatRow(
                    label: 'Worst trade',
                    value: _pct(trades['worst'] as num?, sign: true),
                    colour: Brand.red),
                if (trades['profit_factor'] != null)
                  _StatRow(
                      label: 'Profit factor',
                      value: '${trades['profit_factor']}',
                      colour: ((trades['profit_factor'] as num?) ?? 0) >= 1
                          ? Brand.green
                          : Brand.red),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Profit factor is gross profit divided by gross loss — above 1 '
            'means winners outweighed losers.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10,
                height: 1.35),
          ),

          // ---- Recent trades ----
          const SizedBox(height: 18),
          _TradeList(trades: (trades['recent'] as List?) ?? []),
        ] else ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              'This strategy never entered a position over the period — the '
              'entry condition was not met.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  height: 1.4),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Text(
          'Signals are decided on the close and traded at the next open, so no '
          'result uses a price it could not have known. Brokerage, slippage '
          'and taxes are not modelled — real returns would be lower. Past '
          'performance does not predict future results.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.5),
              fontSize: 10,
              height: 1.45),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.label,
    required this.value,
    required this.colour,
  });

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7),
                    fontSize: 8.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(value,
                  style: TextStyle(
                      color: colour,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    this.colour,
  });

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.85), fontSize: 11.5)),
          Text(value,
              style: TextStyle(
                  color: colour ?? Brand.paper,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ===========================================================================
// EQUITY CURVE
// ===========================================================================

class _EquityChart extends StatelessWidget {
  const _EquityChart({required this.curve, required this.capital});

  final List<dynamic> curve;
  final double capital;

  @override
  Widget build(BuildContext context) {
    if (curve.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 12, height: 3, color: Brand.gold),
            const SizedBox(width: 5),
            Text('Strategy',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
            const SizedBox(width: 16),
            Container(width: 12, height: 3, color: Brand.mint),
            const SizedBox(width: 5),
            Text('Buy & Hold',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 210,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _EquityPainter(curve: curve, capital: capital),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(curve.first as Map)['date']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 9.5)),
            Text('${(curve.last as Map)['date']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 9.5)),
          ],
        ),
      ],
    );
  }
}

class _EquityPainter extends CustomPainter {
  _EquityPainter({required this.curve, required this.capital});

  final List<dynamic> curve;
  final double capital;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.length < 2) return;

    final strat = [
      for (final p in curve) (((p as Map)['strategy'] as num?) ?? 0).toDouble()
    ];
    final hold = [
      for (final p in curve) (((p as Map)['buy_hold'] as num?) ?? 0).toDouble()
    ];

    var lo = math.min(strat.reduce(math.min), hold.reduce(math.min));
    var hi = math.max(strat.reduce(math.max), hold.reduce(math.max));
    // Keep the starting capital visible so gains and losses read honestly.
    if (capital > 0) {
      lo = math.min(lo, capital);
      hi = math.max(hi, capital);
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    Offset at(List<double> series, int i) => Offset(
          size.width * i / (series.length - 1),
          size.height - ((series[i] - lo) / span) * size.height,
        );

    // Break-even line
    if (capital > 0) {
      final y = size.height - ((capital - lo) / span) * size.height;
      final paint = Paint()
        ..color = Brand.mint.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 4, size.width), y), paint);
        x += 8;
      }
    }

    void draw(List<double> series, Color colour, double width) {
      final path = Path()..moveTo(at(series, 0).dx, at(series, 0).dy);
      for (var i = 1; i < series.length; i++) {
        final p = at(series, i);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    draw(hold, Brand.mint.withValues(alpha: 0.75), 1.5);
    draw(strat, Brand.gold, 2.2);

    final last = at(strat, strat.length - 1);
    canvas.drawCircle(last, 3.5, Paint()..color = Brand.gold);
  }

  @override
  bool shouldRepaint(covariant _EquityPainter old) =>
      old.curve != curve || old.capital != capital;
}

// ===========================================================================
// TRADE LIST
// ===========================================================================

class _TradeList extends StatelessWidget {
  const _TradeList({required this.trades});

  final List<dynamic> trades;

  @override
  Widget build(BuildContext context) {
    if (trades.isEmpty) return const SizedBox.shrink();

    // Newest first reads better than the API's chronological order.
    final rows = trades.reversed.toList();

    return Card(
      color: Brand.fern.withValues(alpha: 0.25),
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Brand.gold,
          collapsedIconColor: Brand.mint,
          title: Text('Trade log (${rows.length})',
              style: TextStyle(
                  color: Brand.paper.withValues(alpha: 0.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.45),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: const Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text('Entry',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 4,
                      child: Text('Exit',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('Return',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final t = (rows[i] as Map).cast<String, dynamic>();
                  final ret = t['return_pct'] as num?;
                  return Container(
                    color: i.isEven
                        ? Colors.transparent
                        : Brand.fern.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${t['entry_date']}',
                                  style: const TextStyle(
                                      color: Brand.mint, fontSize: 10)),
                              Text('₹${(t['entry'] as num).toStringAsFixed(1)}',
                                  style: TextStyle(
                                      color:
                                          Brand.paper.withValues(alpha: 0.8),
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${t['exit_date']}',
                                  style: const TextStyle(
                                      color: Brand.mint, fontSize: 10)),
                              Text(
                                '₹${(t['exit'] as num).toStringAsFixed(1)}'
                                '  ·  ${t['reason']}',
                                style: TextStyle(
                                    color: _reasonColour('${t['reason']}')
                                        .withValues(alpha: 0.9),
                                    fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(_pct(ret, sign: true),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: _pnlColour(ret),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
