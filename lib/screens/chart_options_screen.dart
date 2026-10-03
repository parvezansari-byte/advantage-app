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
                  onTimeframe: (t) {
                    setState(() => _timeframe = t);
                    _loadChart();
                  },
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
    required this.onTimeframe,
    required this.onRetry,
  });

  final String index;
  final String timeframe;
  final List<String> timeframes;
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final bool hasTicker;
  final ValueChanged<String> onTimeframe;
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
        const SizedBox(height: 16),

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
          _ChartCanvas(data: d, accent: accent),
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

class _ChartCanvas extends StatefulWidget {
  const _ChartCanvas({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  State<_ChartCanvas> createState() => _ChartCanvasState();
}

class _ChartCanvasState extends State<_ChartCanvas> {
  int? _touchIndex;

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

    final values = [
      for (final p in series) ((p['close'] as num?) ?? 0).toDouble()
    ];
    final baseline = (widget.data['baseline'] as num?)?.toDouble();

    return Column(
      children: [
        SizedBox(
          height: 22,
          child: _touchIndex == null
              ? const SizedBox.shrink()
              : Center(
                  child: Text(
                    '${series[_touchIndex!]['label']}   '
                    '₹${_price(series[_touchIndex!]['close'] as num?)}',
                    style: const TextStyle(
                        color: Brand.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
        ),
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.globalPosition);
            final ratio = (local.dx / box.size.width).clamp(0.0, 1.0);
            setState(() =>
                _touchIndex = (ratio * (values.length - 1)).round());
          },
          onHorizontalDragEnd: (_) => setState(() => _touchIndex = null),
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.globalPosition);
            final ratio = (local.dx / box.size.width).clamp(0.0, 1.0);
            setState(() =>
                _touchIndex = (ratio * (values.length - 1)).round());
          },
          onTapUp: (_) => setState(() => _touchIndex = null),
          onTapCancel: () => setState(() => _touchIndex = null),
          child: Container(
            height: 240,
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(
                values: values,
                accent: widget.accent,
                baseline: baseline,
                touchIndex: _touchIndex,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${series.first['label']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            Text('${series.last['label']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
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
    this.touchIndex,
  });

  final List<double> values;
  final Color accent;
  final double? baseline;
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
      old.accent != accent;
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
