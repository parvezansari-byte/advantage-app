// lib/screens/chart_options_screen.dart
// ---------------------------------------------------------------------------
// Live Chart + Option Chain, combined on one screen: pick an index once at
// the top, then switch between a price-chart view and an option-chain view
// for that same index without leaving the screen. Replaces having to go
// back to the menu to flip between the two separate screens.
//
// Reuses the exact same ApiService calls as the two original screens
// (getChart / getOptionExpiries / getOptionChain) — no backend changes
// needed. The chart and option-chain rendering widgets below are the same
// visuals as ChartScreen/OptionsScreen; they're duplicated here (as
// file-private classes) rather than imported, since those classes are
// private to their own files.
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _price(num? v) {
  if (v == null) return '—';
  final n = v.toDouble();
  final whole = n.truncate().abs().toString();
  final dec = (n.abs() - n.truncate().abs()).toStringAsFixed(2).substring(2);

  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final buf = <String>[];
    while (rest.length > 2) {
      buf.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) buf.insert(0, rest);
    grouped = '${buf.join(',')},$last3';
  }
  return '${n < 0 ? '-' : ''}$grouped.$dec';
}

String _signedPct(num? v) {
  if (v == null) return '—';
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
}

String _signed(num? v) {
  if (v == null) return '—';
  return '${v >= 0 ? '+' : '-'}₹${_price(v.abs())}';
}

String _num(num? v) {
  if (v == null) return '—';
  final n = v.round();
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

/// Open interest reads better in lakhs — raw contract counts are unwieldy.
String _lakh(num? v) {
  if (v == null) return '—';
  final n = v.toDouble();
  if (n.abs() >= 10000000) return '${(n / 10000000).toStringAsFixed(2)} Cr';
  if (n.abs() >= 100000) return '${(n / 100000).toStringAsFixed(1)} L';
  if (n.abs() >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}

// ===========================================================================
// SCREEN
// ===========================================================================

/// The four indices the option-chain endpoint supports. Kept in the same
/// order/spelling OptionsScreen used, since the backend expects these exact
/// display strings.
const _indices = ['NIFTY 50', 'BANK NIFTY', 'FIN NIFTY', 'MIDCAP NIFTY'];

/// Yahoo-style tickers for the chart side. Only indices with a verified,
/// working ticker are listed here — FIN NIFTY and MIDCAP NIFTY have no
/// reliable Yahoo symbol, so the chart tab shows a plain notice for those
/// instead of risking wrong/empty data.
const _chartTickers = {
  'NIFTY 50': '^NSEI',
  'BANK NIFTY': '^NSEBANK',
};

class ChartOptionsScreen extends StatefulWidget {
  const ChartOptionsScreen({super.key, this.initialIndex});

  final String? initialIndex;

  @override
  State<ChartOptionsScreen> createState() => _ChartOptionsScreenState();
}

class _ChartOptionsScreenState extends State<ChartOptionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late String _index;

  // ---- Chart tab state ----
  static const _timeframes = ['1D', '1W', '1M', '6M', '1Y', '5Y', 'ALL'];
  String _timeframe = '1D';
  Map<String, dynamic>? _chartData;
  bool _chartLoading = true;
  String? _chartError;
  Timer? _refreshTimer;
  bool _candleMode = false;
  // Indicators switched on: sma, vwap, bb, rsi, macd.
  final Set<String> _indicators = {};

  // ---- Option chain tab state ----
  String _expiry = '';
  int _strikes = 10;
  List<String> _expiries = [];
  Map<String, dynamic>? _chain;
  bool _loadingExpiries = true;
  bool _loadingChain = false;
  String? _optError;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex ?? 'NIFTY 50';
    _tab = TabController(length: 2, vsync: this);
    if (_chartTickers.containsKey(_index)) {
      _loadChart();
    } else {
      _chartLoading = false;
      _tab.index = 1; // no chart for this index — open on the chain view
    }
    _loadExpiries();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tab.dispose();
    super.dispose();
  }

  void _onIndexChanged(String i) {
    if (_index == i) return;
    setState(() {
      _index = i;
      _chartData = null;
      _chartError = null;
    });
    if (_chartTickers.containsKey(_index)) {
      _loadChart();
    } else {
      _refreshTimer?.cancel();
      setState(() => _chartLoading = false);
    }
    _loadExpiries();
  }

  // ---- Chart loading ----

  void _syncTimer() {
    _refreshTimer?.cancel();
    if (_timeframe == '1D') {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _loadChart(silent: true),
      );
    }
  }

  Future<void> _loadChart({bool silent = false}) async {
    final ticker = _chartTickers[_index];
    if (ticker == null) return;
    if (!silent) {
      setState(() {
        _chartLoading = true;
        _chartError = null;
      });
    }
    try {
      final d = await ApiService.getChart(ticker, timeframe: _timeframe);
      if (!mounted) return;
      setState(() {
        _chartData = d;
        _chartError = null;
      });
      _syncTimer();
    } catch (e) {
      if (mounted && !silent) setState(() => _chartError = '$e');
    } finally {
      if (mounted && !silent) setState(() => _chartLoading = false);
    }
  }

  // ---- Option chain loading ----

  Future<void> _loadExpiries() async {
    setState(() {
      _loadingExpiries = true;
      _optError = null;
      _expiries = [];
      _chain = null;
    });
    try {
      final e = await ApiService.getOptionExpiries(_index);
      if (!mounted) return;
      setState(() {
        _expiries = e;
        _expiry = e.isNotEmpty ? e.first : '';
      });
      if (_expiry.isNotEmpty) await _loadChain();
    } catch (e) {
      if (mounted) setState(() => _optError = '$e');
    } finally {
      if (mounted) setState(() => _loadingExpiries = false);
    }
  }

  Future<void> _loadChain() async {
    setState(() {
      _loadingChain = true;
      _optError = null;
    });
    try {
      final c = await ApiService.getOptionChain(_index,
          expiry: _expiry, strikes: _strikes);
      if (mounted) setState(() => _chain = c);
    } catch (e) {
      if (mounted) setState(() => _optError = '$e');
    } finally {
      if (mounted) setState(() => _loadingChain = false);
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
        title: const Text('Chart & Options',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: () {
              if (_tab.index == 0) {
                _loadChart();
              } else {
                _expiry.isEmpty ? _loadExpiries() : _loadChain();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Brand.gold,
          labelColor: Brand.gold,
          unselectedLabelColor: Brand.mint,
          tabs: const [
            Tab(text: 'Chart'),
            Tab(text: 'Option Chain'),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          // ---- Shared index chips — same index drives both tabs ----
          SizedBox(
            height: 34,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              children: [
                for (final i in _indices)
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
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ChartTab(
                  index: _index,
                  timeframe: _timeframe,
                  timeframes: _timeframes,
                  data: _chartData,
                  loading: _chartLoading,
                  error: _chartError,
                  hasTicker: _chartTickers.containsKey(_index),
                  candleMode: _candleMode,
                  indicators: _indicators,
                  onTimeframe: (t) {
                    setState(() => _timeframe = t);
                    _loadChart();
                  },
                  onCandleModeChanged: (v) => setState(() => _candleMode = v),
                  onToggleIndicator: (k) => setState(() {
                    if (!_indicators.remove(k)) _indicators.add(k);
                  }),
                  onRetry: () => _loadChart(),
                ),
                _OptionsTab(
                  expiry: _expiry,
                  expiries: _expiries,
                  strikes: _strikes,
                  chain: _chain,
                  loadingExpiries: _loadingExpiries,
                  loadingChain: _loadingChain,
                  error: _optError,
                  onExpiry: (e) {
                    setState(() => _expiry = e);
                    _loadChain();
                  },
                  onStrikesChanged: (v) => setState(() => _strikes = v),
                  onStrikesCommitted: () => _loadChain(),
                  onRetry: _expiry.isEmpty ? _loadExpiries : _loadChain,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// CHART TAB
// ===========================================================================

class _ChartTab extends StatelessWidget {
  const _ChartTab({
    required this.index,
    required this.timeframe,
    required this.timeframes,
    required this.data,
    required this.loading,
    required this.error,
    required this.hasTicker,
    required this.candleMode,
    required this.indicators,
    required this.onTimeframe,
    required this.onCandleModeChanged,
    required this.onToggleIndicator,
    required this.onRetry,
  });

  final String index;
  final String timeframe;
  final List<String> timeframes;
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final bool hasTicker;
  final bool candleMode;
  final Set<String> indicators;
  final ValueChanged<String> onTimeframe;
  final ValueChanged<bool> onCandleModeChanged;
  final ValueChanged<String> onToggleIndicator;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!hasTicker) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.show_chart, color: Brand.mint, size: 28),
                const SizedBox(height: 10),
                Text(
                  'A live price chart isn\'t available for $index yet — '
                  'switch to the Option Chain tab for this index, or pick '
                  'NIFTY 50 or BANK NIFTY above for the chart view.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final d = data;
    final up = ((d?['change'] as num?) ?? 0) >= 0;
    final accent = d == null ? Brand.gold : (up ? Brand.green : Brand.red);

    Widget ind(String label, String key, Color colour) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Center(
            child: _StyleChip(
              label: label,
              selected: indicators.contains(key),
              accent: colour,
              onTap: () => onToggleIndicator(key),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        // ---- Timeframes ----
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in timeframes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onTimeframe(t),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: timeframe == t
                            ? accent.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: timeframe == t
                              ? accent.withValues(alpha: 0.7)
                              : Brand.mint.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              color: timeframe == t ? accent : Brand.mint,
                              fontSize: 11.5,
                              fontWeight: timeframe == t
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ---- Chart style: line vs. candlesticks ----
        Row(
          children: [
            _StyleChip(
              label: 'Line',
              selected: !candleMode,
              accent: accent,
              onTap: () => onCandleModeChanged(false),
            ),
            const SizedBox(width: 6),
            _StyleChip(
              label: 'Candles',
              selected: candleMode,
              accent: accent,
              onTap: () => onCandleModeChanged(true),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ---- Indicators (overlays on the price, and RSI / MACD panels) ----
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (d?['has_vwap'] == true)
                ind(d?['vwap_uses_volume'] == false ? 'Session avg' : 'VWAP',
                    'vwap', Brand.blue),
              ind('SMA 20', 'sma', Brand.gold),
              ind('Bollinger', 'bb', Brand.purple),
              ind('RSI 14', 'rsi', Brand.teal),
              ind('MACD', 'macd', Brand.green),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator(color: Brand.gold)),
          )
        else if (error != null)
          _ChartError(message: error!, onRetry: onRetry)
        else if (d != null) ...[
          _PriceHeader(data: d, accent: accent),
          const SizedBox(height: 16),
          _ChartCanvas(
              data: d,
              accent: accent,
              candleMode: candleMode,
              indicators: indicators),
          const SizedBox(height: 16),
          _StatsRow(data: d),
          const SizedBox(height: 14),
          Text(
            d['live'] == true
                ? 'Refreshes every 30 seconds while on 1D. Intraday prices '
                    'come from Yahoo and can lag the exchange by up to 15 '
                    'minutes.'
                : 'Interval: ${d['interval']} · ${d['points']} data points.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10.5,
                height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.7) : Brand.mint.withValues(alpha: 0.18),
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? accent : Brand.mint,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

class _PriceHeader extends StatelessWidget {
  const _PriceHeader({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final live = data['live'] == true;
    final up = ((data['change'] as num?) ?? 0) >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (live) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Brand.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text('${data['display']}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
            if (live)
              Text('  ·  LIVE',
                  style: TextStyle(
                      color: Brand.green.withValues(alpha: 0.9),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('₹${_price(data['last'] as num?)}',
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: accent, size: 20),
                  Text(
                    '${_signed(data['change'] as num?)} '
                    '(${_signedPct(data['change_pct'] as num?)})',
                    style: TextStyle(
                        color: accent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text('vs ${data['baseline_label']}',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
      ],
    );
  }
}

/// Draws one overlay line (VWAP etc). Gaps (null values) break the line.
void _drawOverlay(
  Canvas canvas,
  List<double?> vals,
  Color colour,
  double Function(int) x,
  double Function(double) y, {
  double width = 1.6,
}) {
  final paint = Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round;
  Path? path;
  for (var i = 0; i < vals.length; i++) {
    final v = vals[i];
    if (v == null) {
      if (path != null) canvas.drawPath(path, paint);
      path = null;
      continue;
    }
    final px = x(i), py = y(v);
    if (path == null) {
      path = Path()..moveTo(px, py);
    } else {
      path.lineTo(px, py);
    }
  }
  if (path != null) canvas.drawPath(path, paint);
}

/// Shaded band between two lines (Bollinger Bands), plus a thin outline.
void _drawBand(
  Canvas canvas,
  List<double?> upper,
  List<double?> lower,
  Color colour,
  double Function(int) x,
  double Function(double) y,
) {
  final idx = <int>[];
  for (var i = 0; i < upper.length; i++) {
    if (upper[i] != null && lower[i] != null) idx.add(i);
  }
  if (idx.length < 2) return;
  final fill = Path()..moveTo(x(idx.first), y(upper[idx.first]!));
  for (final i in idx) {
    fill.lineTo(x(i), y(upper[i]!));
  }
  for (final i in idx.reversed) {
    fill.lineTo(x(i), y(lower[i]!));
  }
  fill.close();
  canvas.drawPath(fill, Paint()..color = colour.withValues(alpha: 0.10));
  _drawOverlay(canvas, upper, colour.withValues(alpha: 0.75), x, y, width: 1.0);
  _drawOverlay(canvas, lower, colour.withValues(alpha: 0.75), x, y, width: 1.0);
}

/// Simple moving average over the closes, same length as the series
/// (leading entries before there are [period] points are null).
List<double?> _sma(List<double> closes, int period) {
  final out = List<double?>.filled(closes.length, null);
  double sum = 0;
  for (var i = 0; i < closes.length; i++) {
    sum += closes[i];
    if (i >= period) sum -= closes[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average, seeded with the first value (the same
/// convention as pandas ewm(span: period, adjust: false)).
List<double> _ema(List<double> v, int period) {
  final out = List<double>.filled(v.length, 0);
  if (v.isEmpty) return out;
  final k = 2 / (period + 1);
  out[0] = v[0];
  for (var i = 1; i < v.length; i++) {
    out[i] = v[i] * k + out[i - 1] * (1 - k);
  }
  return out;
}

/// Wilder's RSI. Entries before there are [period] price changes are null.
List<double?> _rsiSeries(List<double> c, int period) {
  final out = List<double?>.filled(c.length, null);
  if (c.length <= period) return out;
  double rsiOf(double avgGain, double avgLoss) {
    if (avgLoss == 0) return avgGain == 0 ? 50.0 : 100.0;
    return 100 - 100 / (1 + avgGain / avgLoss);
  }

  double gain = 0, loss = 0;
  for (var i = 1; i <= period; i++) {
    final d = c[i] - c[i - 1];
    if (d >= 0) {
      gain += d;
    } else {
      loss -= d;
    }
  }
  var avgGain = gain / period;
  var avgLoss = loss / period;
  out[period] = rsiOf(avgGain, avgLoss);
  for (var i = period + 1; i < c.length; i++) {
    final d = c[i] - c[i - 1];
    final g = d > 0 ? d : 0.0;
    final l = d < 0 ? -d : 0.0;
    avgGain = (avgGain * (period - 1) + g) / period;
    avgLoss = (avgLoss * (period - 1) + l) / period;
    out[i] = rsiOf(avgGain, avgLoss);
  }
  return out;
}

/// MACD(12, 26, 9): the line, its signal line and the histogram between them.
class _MacdSeries {
  _MacdSeries(this.macd, this.signal, this.hist);
  final List<double?> macd;
  final List<double?> signal;
  final List<double?> hist;
}

_MacdSeries _macdSeries(List<double> c) {
  final n = c.length;
  final macd = List<double?>.filled(n, null);
  final signal = List<double?>.filled(n, null);
  final hist = List<double?>.filled(n, null);
  if (n < 27) return _MacdSeries(macd, signal, hist);
  final fast = _ema(c, 12);
  final slow = _ema(c, 26);
  final line = <double>[for (var i = 0; i < n; i++) fast[i] - slow[i]];
  for (var i = 25; i < n; i++) {
    macd[i] = line[i];
  }
  final tail = line.sublist(25);
  final sig = _ema(tail, 9);
  for (var i = 8; i < tail.length; i++) {
    signal[25 + i] = sig[i];
    hist[25 + i] = tail[i] - sig[i];
  }
  return _MacdSeries(macd, signal, hist);
}

/// Bollinger Bands: SMA(period) +/- mult standard deviations (population).
(List<double?>, List<double?>) _bollinger(
    List<double> c, int period, double mult) {
  final upper = List<double?>.filled(c.length, null);
  final lower = List<double?>.filled(c.length, null);
  for (var i = period - 1; i < c.length; i++) {
    var sum = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      sum += c[j];
    }
    final mean = sum / period;
    var sq = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      sq += (c[j] - mean) * (c[j] - mean);
    }
    final sd = math.sqrt(sq / period);
    upper[i] = mean + mult * sd;
    lower[i] = mean - mult * sd;
  }
  return (upper, lower);
}

double _clampD(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

class _ChartCanvas extends StatefulWidget {
  const _ChartCanvas({
    required this.data,
    required this.accent,
    required this.indicators,
    this.candleMode = false,
  });

  final Map<String, dynamic> data;
  final Color accent;
  final Set<String> indicators;
  final bool candleMode;

  @override
  State<_ChartCanvas> createState() => _ChartCanvasState();
}

class _ChartCanvasState extends State<_ChartCanvas> {
  int? _touchIndex; // index inside the visible window

  // Visible window over the full series: first bar, and how many bars.
  double _start = 0;
  double _count = 0;
  int _seriesLen = 0;

  // Snapshot taken when a pinch begins.
  double _pinchStart = 0, _pinchCount = 0, _pinchFocal = 0;

  /// Keeps the window valid when the data length changes (a new timeframe,
  /// or a new bar arriving while on 1D).
  void _syncWindow(int n) {
    if (_seriesLen == 0 || _count <= 0) {
      _start = 0;
      _count = n.toDouble();
    } else if (n != _seriesLen) {
      final wasFull = _count >= _seriesLen - 0.5;
      final atEnd = _start + _count >= _seriesLen - 0.5;
      if (wasFull) {
        _start = 0;
        _count = n.toDouble();
      } else if (atEnd) {
        _start = n - _count;
      }
    }
    _seriesLen = n;
    _clampWindow(n);
  }

  void _clampWindow(int n) {
    final minCount = math.min(10, n).toDouble();
    _count = _count.clamp(minCount, n.toDouble()).toDouble();
    _start = _start.clamp(0.0, n - _count).toDouble();
  }

  double _width() {
    final box = context.findRenderObject() as RenderBox?;
    return (box == null || !box.hasSize) ? 0.0 : box.size.width;
  }

  int _indexAt(double dx, double width, int visible) {
    final ratio = (dx / width).clamp(0.0, 1.0).toDouble();
    final i = widget.candleMode
        ? (ratio * visible).floor()
        : (ratio * (visible - 1)).round();
    return i < 0 ? 0 : (i > visible - 1 ? visible - 1 : i);
  }

  @override
  Widget build(BuildContext context) {
    final series = [
      for (final p in (widget.data['series'] as List? ?? []))
        (p as Map).cast<String, dynamic>()
    ];
    if (series.length < 2) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Text('Not enough data to draw a chart',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
        ),
      );
    }
    final n = series.length;
    _syncWindow(n);

    final values = [
      for (final p in series) ((p['close'] as num?) ?? 0).toDouble()
    ];
    final opens = [
      for (final p in series)
        ((p['open'] as num?) ?? p['close'] as num? ?? 0).toDouble()
    ];
    final highs = [
      for (final p in series)
        ((p['high'] as num?) ?? p['close'] as num? ?? 0).toDouble()
    ];
    final lows = [
      for (final p in series)
        ((p['low'] as num?) ?? p['close'] as num? ?? 0).toDouble()
    ];
    final baseline = (widget.data['baseline'] as num?)?.toDouble();

    // Indicators are computed on the FULL series (so they are warmed up),
    // then cut down to the visible window below.
    final ind = widget.indicators;
    final smaFull = ind.contains('sma') ? _sma(values, 20) : null;
    final vwapFull = ind.contains('vwap')
        ? <double?>[for (final p in series) (p['vwap'] as num?)?.toDouble()]
        : null;
    final bbFull = ind.contains('bb') ? _bollinger(values, 20, 2.0) : null;
    final rsiFull = ind.contains('rsi') ? _rsiSeries(values, 14) : null;
    final macdFull = ind.contains('macd') ? _macdSeries(values) : null;

    // Visible window [a, b).
    var a = _start.round();
    var b = a + _count.round();
    if (b > n) b = n;
    if (a > b - 2) a = b - 2;
    if (a < 0) a = 0;
    final visN = b - a;
    final zoomed = visN < n;
    List<T> sl<T>(List<T> l) => l.sublist(a, b);

    final vValues = sl(values);
    final vOpens = sl(opens);
    final vHighs = sl(highs);
    final vLows = sl(lows);
    final vSma = smaFull == null ? null : sl(smaFull);
    final vVwap = vwapFull == null ? null : sl(vwapFull);
    final vBbU = bbFull == null ? null : sl(bbFull.$1);
    final vBbL = bbFull == null ? null : sl(bbFull.$2);

    final t = (_touchIndex != null && _touchIndex! < visN) ? _touchIndex : null;
    final ti = a + (t ?? visN - 1); // absolute index shown in panel readouts

    String touchLabel = '';
    if (t != null) {
      final k = a + t;
      touchLabel = widget.candleMode
          ? '${series[k]['label']}   '
              'O ${_price(opens[k])}  H ${_price(highs[k])}  '
              'L ${_price(lows[k])}  C ${_price(values[k])}'
          : '${series[k]['label']}   ₹${_price(values[k])}';
    }

    String fmt1(double? v) => v == null ? '—' : v.toStringAsFixed(1);
    String fmt2(double? v) => v == null ? '—' : v.toStringAsFixed(2);

    return Column(
      children: [
        SizedBox(
          height: 22,
          child: t != null
              ? Center(
                  child: Text(
                    touchLabel,
                    style: const TextStyle(
                        color: Brand.gold,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        zoomed
                            ? 'Drag to pan · tap a bar for values'
                            : 'Pinch to zoom',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.45),
                            fontSize: 10),
                      ),
                    ),
                    if (zoomed)
                      GestureDetector(
                        onTap: () => setState(() {
                          _start = 0;
                          _count = n.toDouble();
                        }),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Text('Reset zoom',
                              style: TextStyle(
                                  color: Brand.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
        ),
        GestureDetector(
          // One finger: crosshair when the whole chart is showing, pan when
          // zoomed in. (Horizontal-only, so vertical page scrolling still
          // works.) Two fingers: pinch to zoom.
          onHorizontalDragUpdate: (d) {
            final w = _width();
            if (w <= 0) return;
            if (zoomed) {
              setState(() {
                _touchIndex = null;
                _start -= d.delta.dx / w * _count;
                _clampWindow(n);
              });
            } else {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(d.globalPosition);
              setState(() => _touchIndex = _indexAt(local.dx, w, visN));
            }
          },
          onHorizontalDragEnd: (_) => setState(() => _touchIndex = null),
          onTapDown: (d) {
            final box = context.findRenderObject() as RenderBox?;
            final w = _width();
            if (box == null || w <= 0) return;
            final local = box.globalToLocal(d.globalPosition);
            setState(() => _touchIndex = _indexAt(local.dx, w, visN));
          },
          onTapUp: (_) => setState(() => _touchIndex = null),
          onTapCancel: () => setState(() => _touchIndex = null),
          onScaleStart: (d) {
            final w = _width();
            if (w <= 0) return;
            _pinchStart = _start;
            _pinchCount = _count;
            _pinchFocal = (d.localFocalPoint.dx / w).clamp(0.0, 1.0).toDouble();
          },
          onScaleUpdate: (d) {
            if (d.pointerCount < 2) return;
            final w = _width();
            if (w <= 0) return;
            final fx = (d.localFocalPoint.dx / w).clamp(0.0, 1.0).toDouble();
            setState(() {
              _touchIndex = null;
              _count = _pinchCount / d.scale;
              _clampWindow(n);
              // Keep the bar that was under the fingers when the pinch began
              // under the fingers now.
              _start = _pinchStart + _pinchFocal * _pinchCount - fx * _count;
              _clampWindow(n);
            });
          },
          child: Container(
            height: 240,
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: widget.candleMode
                  ? _CandlePainter(
                      opens: vOpens,
                      highs: vHighs,
                      lows: vLows,
                      closes: vValues,
                      sma: vSma,
                      vwap: vVwap,
                      bbUpper: vBbU,
                      bbLower: vBbL,
                      baseline: baseline,
                      touchIndex: t,
                    )
                  : _LinePainter(
                      values: vValues,
                      accent: widget.accent,
                      baseline: baseline,
                      sma: vSma,
                      vwap: vVwap,
                      bbUpper: vBbU,
                      bbLower: vBbL,
                      touchIndex: t,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${series[a]['label']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            Text('${series[b - 1]['label']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
        if (rsiFull != null) ...[
          const SizedBox(height: 12),
          _PanelBox(
            title: 'RSI (14)',
            value: fmt1(rsiFull[ti]),
            height: 90,
            painter: _RsiPainter(
              values: sl(rsiFull),
              slotMode: widget.candleMode,
              touchIndex: t,
            ),
          ),
        ],
        if (macdFull != null) ...[
          const SizedBox(height: 12),
          _PanelBox(
            title: 'MACD (12, 26, 9)',
            value: 'MACD ${fmt2(macdFull.macd[ti])}  '
                'Signal ${fmt2(macdFull.signal[ti])}  '
                'Hist ${fmt2(macdFull.hist[ti])}',
            height: 100,
            painter: _MacdPainter(
              macd: sl(macdFull.macd),
              signal: sl(macdFull.signal),
              hist: sl(macdFull.hist),
              slotMode: widget.candleMode,
              touchIndex: t,
            ),
          ),
        ],
      ],
    );
  }
}

/// Title + live readout above a small indicator chart. Uses the same
/// horizontal padding as the main chart so the bars line up underneath it.
class _PanelBox extends StatelessWidget {
  const _PanelBox({
    required this.title,
    required this.value,
    required this.height,
    required this.painter,
  });

  final String title;
  final String value;
  final double height;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(size: Size.infinite, painter: painter),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.accent,
    this.baseline,
    this.sma,
    this.vwap,
    this.bbUpper,
    this.bbLower,
    this.touchIndex,
  });

  final List<double> values;
  final Color accent;
  final double? baseline;
  final List<double?>? sma;
  final List<double?>? vwap;
  final List<double?>? bbUpper;
  final List<double?>? bbLower;
  final int? touchIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (baseline != null) {
      lo = math.min(lo, baseline!);
      hi = math.max(hi, baseline!);
    }
    final smaVals = sma;
    if (smaVals != null) {
      for (final v in smaVals) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final vwapVals = vwap;
    if (vwapVals != null) {
      for (final v in vwapVals) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final bbU = bbUpper;
    final bbL = bbLower;
    if (bbU != null && bbL != null) {
      for (final v in bbU) {
        if (v == null) continue;
        hi = math.max(hi, v);
      }
      for (final v in bbL) {
        if (v == null) continue;
        lo = math.min(lo, v);
      }
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad == 0 ? hi * 0.002 : pad;
    hi += pad == 0 ? hi * 0.002 : pad;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    Offset at(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height - ((values[i] - lo) / span) * size.height,
        );

    if (baseline != null) {
      final y = size.height - ((baseline! - lo) / span) * size.height;
      final paint = Paint()
        ..color = Brand.mint.withValues(alpha: 0.4)
        ..strokeWidth = 1;
      const dash = 5.0, gap = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dash, size.width), y), paint);
        x += dash + gap;
      }
    }

    if (bbU != null && bbL != null) {
      _drawBand(
        canvas,
        bbU,
        bbL,
        Brand.purple,
        (i) => size.width * i / (values.length - 1),
        (v) => size.height - ((v - lo) / span) * size.height,
      );
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final last = at(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = accent);
    canvas.drawCircle(
        last, 8, Paint()..color = accent.withValues(alpha: 0.25));

    if (smaVals != null) {
      Path? smaPath;
      for (var i = 0; i < smaVals.length; i++) {
        final v = smaVals[i];
        if (v == null) continue;
        final p = Offset(
            size.width * i / (values.length - 1),
            size.height - ((v - lo) / span) * size.height);
        if (smaPath == null) {
          smaPath = Path()..moveTo(p.dx, p.dy);
        } else {
          smaPath.lineTo(p.dx, p.dy);
        }
      }
      if (smaPath != null) {
        canvas.drawPath(
          smaPath,
          Paint()
            ..color = Brand.gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    if (vwapVals != null) {
      _drawOverlay(
        canvas,
        vwapVals,
        Brand.blue,
        (i) => size.width * i / (values.length - 1),
        (v) => size.height - ((v - lo) / span) * size.height,
      );
    }

    if (touchIndex != null &&
        touchIndex! >= 0 &&
        touchIndex! < values.length) {
      final p = at(touchIndex!);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = Brand.gold.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 4.5, Paint()..color = Brand.gold);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values ||
      old.touchIndex != touchIndex ||
      old.accent != accent ||
      old.sma != sma ||
      old.vwap != vwap;
}

// ===========================================================================
// CANDLESTICK PAINTER
// ===========================================================================
//
// Each bar from the API becomes one candle: a thin "wick" line spanning the
// bar's high→low, and a filled "body" rectangle spanning open→close. Green
// body = close finished above open (bullish bar); red body = close finished
// below open (bearish bar). This is the standard way traders read price
// action bar-by-bar, as opposed to a line chart which only shows the close.
class _CandlePainter extends CustomPainter {
  _CandlePainter({
    required this.opens,
    required this.highs,
    required this.lows,
    required this.closes,
    this.sma,
    this.vwap,
    this.bbUpper,
    this.bbLower,
    this.baseline,
    this.touchIndex,
  });

  final List<double> opens;
  final List<double> highs;
  final List<double> lows;
  final List<double> closes;
  final List<double?>? sma;
  final List<double?>? vwap;
  final List<double?>? bbUpper;
  final List<double?>? bbLower;
  final double? baseline;
  final int? touchIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final n = closes.length;
    if (n < 2) return;

    var lo = lows.reduce(math.min);
    var hi = highs.reduce(math.max);
    if (baseline != null) {
      lo = math.min(lo, baseline!);
      hi = math.max(hi, baseline!);
    }
    final smaVals = sma;
    if (smaVals != null) {
      for (final v in smaVals) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final vwapVals = vwap;
    if (vwapVals != null) {
      for (final v in vwapVals) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final bbU = bbUpper;
    final bbL = bbLower;
    if (bbU != null && bbL != null) {
      for (final v in bbU) {
        if (v == null) continue;
        hi = math.max(hi, v);
      }
      for (final v in bbL) {
        if (v == null) continue;
        lo = math.min(lo, v);
      }
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad == 0 ? hi * 0.002 : pad;
    hi += pad == 0 ? hi * 0.002 : pad;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double y(double v) => size.height - ((v - lo) / span) * size.height;
    final slot = size.width / n;
    final bodyW = math.max(slot * 0.55, 1.5);

    if (baseline != null) {
      final by = y(baseline!);
      final paint = Paint()
        ..color = Brand.mint.withValues(alpha: 0.4)
        ..strokeWidth = 1;
      const dash = 5.0, gap = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, by), Offset(math.min(x + dash, size.width), by), paint);
        x += dash + gap;
      }
    }

    if (bbU != null && bbL != null) {
      _drawBand(canvas, bbU, bbL, Brand.purple, (i) => slot * i + slot / 2, y);
    }

    for (var i = 0; i < n; i++) {
      final centre = slot * i + slot / 2;
      final up = closes[i] >= opens[i];
      final colour = up ? Brand.green : Brand.red;
      final wickPaint = Paint()
        ..color = colour
        ..strokeWidth = 1.2;

      canvas.drawLine(
          Offset(centre, y(highs[i])), Offset(centre, y(lows[i])), wickPaint);

      final bodyTop = y(math.max(opens[i], closes[i]));
      final bodyBottom = y(math.min(opens[i], closes[i]));
      final rect = Rect.fromLTRB(
          centre - bodyW / 2, bodyTop, centre + bodyW / 2,
          math.max(bodyBottom, bodyTop + 1));
      canvas.drawRect(rect, Paint()..color = colour);
    }

    if (smaVals != null) {
      Path? smaPath;
      for (var i = 0; i < smaVals.length; i++) {
        final v = smaVals[i];
        if (v == null) continue;
        final p = Offset(slot * i + slot / 2, y(v));
        if (smaPath == null) {
          smaPath = Path()..moveTo(p.dx, p.dy);
        } else {
          smaPath.lineTo(p.dx, p.dy);
        }
      }
      if (smaPath != null) {
        canvas.drawPath(
          smaPath,
          Paint()
            ..color = Brand.gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    if (vwapVals != null) {
      _drawOverlay(
        canvas,
        vwapVals,
        Brand.blue,
        (i) => slot * i + slot / 2,
        y,
      );
    }

    final t = touchIndex;
    if (t != null && t >= 0 && t < n) {
      final x = slot * t + slot / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Brand.gold.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.closes != closes ||
      old.touchIndex != touchIndex ||
      old.sma != sma ||
      old.vwap != vwap;
}

// ===========================================================================
// RSI / MACD PANEL PAINTERS
// ===========================================================================
// Same x-mapping as the main chart: candle slots when [slotMode] is true
// (candles centred in equal-width slots), edge-to-edge for the line chart.

double _panelX(int i, int n, double width, bool slotMode) =>
    slotMode ? width / n * (i + 0.5) : (n < 2 ? 0.0 : width * i / (n - 1));

void _dashedH(Canvas canvas, double y, double width, Paint paint) {
  var x = 0.0;
  while (x < width) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, width), y), paint);
    x += 8;
  }
}

void _panelCrosshair(
    Canvas canvas, Size size, int? touchIndex, int n, bool slotMode) {
  if (touchIndex == null || touchIndex < 0 || touchIndex >= n) return;
  final x = _panelX(touchIndex, n, size.width, slotMode);
  canvas.drawLine(
    Offset(x, 0),
    Offset(x, size.height),
    Paint()
      ..color = Brand.gold.withValues(alpha: 0.5)
      ..strokeWidth = 1,
  );
}

class _RsiPainter extends CustomPainter {
  _RsiPainter({
    required this.values,
    required this.slotMode,
    this.touchIndex,
  });

  final List<double?> values;
  final bool slotMode;
  final int? touchIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    double y(double v) =>
        size.height - (_clampD(v, 0.0, 100.0) / 100.0) * size.height;
    double x(int i) => _panelX(i, n, size.width, slotMode);

    // Overbought / oversold zones.
    canvas.drawRect(
      Rect.fromLTRB(0, y(100), size.width, y(70)),
      Paint()..color = Brand.red.withValues(alpha: 0.07),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, y(30), size.width, y(0)),
      Paint()..color = Brand.green.withValues(alpha: 0.07),
    );
    final guide = Paint()
      ..color = Brand.mint.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    _dashedH(canvas, y(70), size.width, guide);
    _dashedH(canvas, y(50), size.width, guide);
    _dashedH(canvas, y(30), size.width, guide);

    _drawOverlay(canvas, values, Brand.teal, x, y, width: 1.8);
    _panelCrosshair(canvas, size, touchIndex, n, slotMode);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, double yy) {
      tp.text = TextSpan(
          text: t,
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.5), fontSize: 8.5));
      tp.layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, yy - tp.height - 1));
    }

    label('70', y(70));
    label('30', y(30));
  }

  @override
  bool shouldRepaint(covariant _RsiPainter old) =>
      old.values != values ||
      old.touchIndex != touchIndex ||
      old.slotMode != slotMode;
}

class _MacdPainter extends CustomPainter {
  _MacdPainter({
    required this.macd,
    required this.signal,
    required this.hist,
    required this.slotMode,
    this.touchIndex,
  });

  final List<double?> macd;
  final List<double?> signal;
  final List<double?> hist;
  final bool slotMode;
  final int? touchIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final n = macd.length;
    if (n < 2) return;

    var lo = 0.0, hi = 0.0;
    for (final list in [macd, signal, hist]) {
      for (final v in list) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (hi - lo < 1e-9) {
      // Nothing to draw yet (not enough bars for MACD in this window).
      final tp = TextPainter(
        text: TextSpan(
            text: 'Needs about 35 bars of history',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final span = hi - lo;
    double y(double v) => size.height - ((v - lo) / span) * size.height;
    double x(int i) => _panelX(i, n, size.width, slotMode);

    final zeroY = y(0);
    _dashedH(
        canvas,
        zeroY,
        size.width,
        Paint()
          ..color = Brand.mint.withValues(alpha: 0.3)
          ..strokeWidth = 1);

    final barW = math.max(
        (slotMode ? size.width / n : size.width / (n - 1)) * 0.6, 1.0);
    for (var i = 0; i < n; i++) {
      final h = hist[i];
      if (h == null) continue;
      final top = y(math.max(h, 0.0));
      final bottom = y(math.min(h, 0.0));
      canvas.drawRect(
        Rect.fromLTRB(x(i) - barW / 2, top, x(i) + barW / 2,
            math.max(bottom, top + 0.5)),
        Paint()
          ..color = (h >= 0 ? Brand.green : Brand.red).withValues(alpha: 0.65),
      );
    }

    _drawOverlay(canvas, macd, Brand.blue, x, y, width: 1.5);
    _drawOverlay(canvas, signal, Brand.gold, x, y, width: 1.5);
    _panelCrosshair(canvas, size, touchIndex, n, slotMode);
  }

  @override
  bool shouldRepaint(covariant _MacdPainter old) =>
      old.macd != macd ||
      old.touchIndex != touchIndex ||
      old.slotMode != slotMode;
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, String sub, Color colour) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7),
                      fontSize: 9,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(value,
                    style: TextStyle(
                        color: colour,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.5), fontSize: 8.5)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('HIGH', '₹${_price(data['high'] as num?)}', 'period high',
            Brand.green),
        cell('LOW', '₹${_price(data['low'] as num?)}', 'period low', Brand.red),
        cell(
            'RANGE',
            data['range_pct'] == null
                ? '—'
                : '${(data['range_pct'] as num).toStringAsFixed(2)}%',
            'high to low',
            Brand.gold),
        cell('UPDATED', '${data['updated']}', 'IST', Brand.paper),
      ],
    );
  }
}

class _ChartError extends StatelessWidget {
  const _ChartError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 40),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          const Icon(Icons.show_chart, color: Brand.red, size: 28),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.4)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.gold,
              foregroundColor: Brand.vault,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// OPTION CHAIN TAB
// ===========================================================================

class _OptionsTab extends StatelessWidget {
  const _OptionsTab({
    required this.expiry,
    required this.expiries,
    required this.strikes,
    required this.chain,
    required this.loadingExpiries,
    required this.loadingChain,
    required this.error,
    required this.onExpiry,
    required this.onStrikesChanged,
    required this.onStrikesCommitted,
    required this.onRetry,
  });

  final String expiry;
  final List<String> expiries;
  final int strikes;
  final Map<String, dynamic>? chain;
  final bool loadingExpiries;
  final bool loadingChain;
  final String? error;
  final ValueChanged<String> onExpiry;
  final ValueChanged<int> onStrikesChanged;
  final VoidCallback onStrikesCommitted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        if (expiries.isNotEmpty) ...[
          Text('EXPIRY',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7),
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in expiries.take(8))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        if (expiry == e) return;
                        onExpiry(e);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: expiry == e
                              ? Brand.green.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: expiry == e
                                ? Brand.green.withValues(alpha: 0.7)
                                : Brand.mint.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(e,
                            style: TextStyle(
                                color:
                                    expiry == e ? Brand.green : Brand.mint,
                                fontSize: 10.5,
                                fontWeight: expiry == e
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (loadingExpiries || loadingChain)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 70),
            child: Center(child: CircularProgressIndicator(color: Brand.gold)),
          )
        else if (error != null)
          _OptionsError(message: error!, onRetry: onRetry)
        else if (chain != null) ...[
          _MetricsPanel(chain: chain!),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('Strikes around ATM',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.8),
                      fontSize: 11.5)),
              const Spacer(),
              Text('±$strikes',
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
            ),
            child: Slider(
              value: strikes.toDouble(),
              min: 5,
              max: 20,
              divisions: 15,
              onChanged: (v) => onStrikesChanged(v.round()),
              onChangeEnd: (_) => onStrikesCommitted(),
            ),
          ),
          const SizedBox(height: 6),
          _OiChart(chain: chain!),
          const SizedBox(height: 18),
          _ChainTable(chain: chain!),
          const SizedBox(height: 14),
          Text(
            'PCR is total put OI divided by total call OI. Above 1 means '
            'put writers dominate (often support); below 0.7 means call '
            'writers dominate (often resistance). Max pain is the strike '
            'where option writers would pay out least.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10.5,
                height: 1.45),
          ),
        ],
      ],
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final pcr = (chain['pcr'] as num?)?.toDouble() ?? 0;
    final pcrColour =
        pcr > 1.0 ? Brand.green : (pcr > 0.7 ? Brand.gold : Brand.red);

    Widget tile(String label, String value, Color colour) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colour.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.75),
                        fontSize: 8.5,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                FittedBox(
                  child: Text(value,
                      style: TextStyle(
                          color: colour,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tile('SPOT', _num(chain['spot'] as num?), Brand.paper),
            tile('PCR (OI)', pcr.toStringAsFixed(2), pcrColour),
            tile('MAX PAIN', _num(chain['max_pain'] as num?), Brand.gold),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            tile('PUT OI', _lakh(chain['total_pe_oi'] as num?), Brand.green),
            tile('CALL OI', _lakh(chain['total_ce_oi'] as num?), Brand.red),
            tile('ATM', _num(chain['atm'] as num?), Brand.mint),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: pcrColour.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: pcrColour.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${chain['signal']}',
                  style: TextStyle(
                      color: pcrColour,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text('Support ${_num(chain['support'] as num?)}',
                        style: const TextStyle(
                            color: Brand.green, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: Text(
                        'Resistance ${_num(chain['resistance'] as num?)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Brand.red, fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OiChart extends StatelessWidget {
  const _OiChart({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final r in (chain['rows'] as List? ?? []))
        (r as Map).cast<String, dynamic>()
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, color: Brand.green),
            const SizedBox(width: 5),
            Text('Put OI',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
            const SizedBox(width: 14),
            Container(width: 10, height: 10, color: Brand.red),
            const SizedBox(width: 5),
            Text('Call OI',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 230,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _OiPainter(
              rows: rows,
              spot: (chain['spot'] as num?)?.toDouble(),
              maxPain: (chain['max_pain'] as num?)?.toDouble(),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_num(rows.first['strike'] as num?),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            Text('strike',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.4), fontSize: 9.5)),
            Text(_num(rows.last['strike'] as num?),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _OiPainter extends CustomPainter {
  _OiPainter({required this.rows, this.spot, this.maxPain});

  final List<Map<String, dynamic>> rows;
  final double? spot;
  final double? maxPain;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;

    final ce = [for (final r in rows) ((r['ce_oi'] as num?) ?? 0).toDouble()];
    final pe = [for (final r in rows) ((r['pe_oi'] as num?) ?? 0).toDouble()];
    final peak = math.max(
      ce.isEmpty ? 0 : ce.reduce(math.max),
      pe.isEmpty ? 0 : pe.reduce(math.max),
    );
    if (peak <= 0) return;

    final slot = size.width / rows.length;
    final barW = math.max(slot * 0.36, 1.5);

    for (var i = 0; i < rows.length; i++) {
      final centre = slot * i + slot / 2;

      final peH = (pe[i] / peak) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(centre - barW - 0.5, size.height - peH, barW, peH),
        Paint()..color = Brand.green.withValues(alpha: 0.85),
      );

      final ceH = (ce[i] / peak) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(centre + 0.5, size.height - ceH, barW, ceH),
        Paint()..color = Brand.red.withValues(alpha: 0.85),
      );
    }

    void marker(double? value, Color colour, bool dotted) {
      if (value == null) return;
      final first = ((rows.first['strike'] as num?) ?? 0).toDouble();
      final last = ((rows.last['strike'] as num?) ?? 0).toDouble();
      if (last <= first) return;
      final ratio = ((value - first) / (last - first)).clamp(0.0, 1.0);
      final x = ratio * size.width;
      final paint = Paint()
        ..color = colour
        ..strokeWidth = 1.4;
      if (dotted) {
        var y = 0.0;
        while (y < size.height) {
          canvas.drawLine(
              Offset(x, y), Offset(x, math.min(y + 4, size.height)), paint);
          y += 8;
        }
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }

    marker(spot, Brand.gold, false);
    marker(maxPain, Brand.mint.withValues(alpha: 0.7), true);
  }

  @override
  bool shouldRepaint(covariant _OiPainter old) =>
      old.rows != rows || old.spot != spot || old.maxPain != maxPain;
}

class _ChainTable extends StatelessWidget {
  const _ChainTable({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final r in (chain['rows'] as List? ?? []))
        (r as Map).cast<String, dynamic>()
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final atm = (chain['atm'] as num?)?.toDouble();

    Widget head(String t, TextAlign align) => Expanded(
          child: Text(t,
              textAlign: align,
              style: const TextStyle(
                  color: Brand.gold,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold)),
        );

    return Card(
      color: Brand.fern.withValues(alpha: 0.25),
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: Brand.fern.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                head('CALL OI', TextAlign.left),
                head('LTP', TextAlign.right),
                head('STRIKE', TextAlign.center),
                head('LTP', TextAlign.left),
                head('PUT OI', TextAlign.right),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final strike = (r['strike'] as num?)?.toDouble();
                final isAtm = atm != null && strike == atm;

                return Container(
                  color: isAtm
                      ? Brand.gold.withValues(alpha: 0.14)
                      : (i.isEven
                          ? Colors.transparent
                          : Brand.fern.withValues(alpha: 0.12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_lakh(r['ce_oi'] as num?),
                            style: TextStyle(
                                color: Brand.red.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_num(r['ce_ltp'] as num?),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_num(strike),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: isAtm ? Brand.gold : Brand.mint,
                                fontSize: 11,
                                fontWeight: isAtm
                                    ? FontWeight.bold
                                    : FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(_num(r['pe_ltp'] as num?),
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_lakh(r['pe_oi'] as num?),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: Brand.green.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionsError extends StatelessWidget {
  const _OptionsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final needsAction = message.toLowerCase().contains('token') ||
        message.toLowerCase().contains('subscription') ||
        message.toLowerCase().contains('expired');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 30),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(needsAction ? Icons.key_off : Icons.cloud_off,
              color: Brand.red, size: 28),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.45)),
          if (!needsAction) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
