// lib/screens/chart_screen.dart
// ---------------------------------------------------------------------------
// Live chart: intraday and historical price series for any NSE symbol.
//
// On the 1D view the chart auto-refreshes every 30 seconds and the change is
// measured against the previous close — the same reference brokers quote.
// Longer timeframes measure from the start of the window instead.
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

// ===========================================================================
// SCREEN
// ===========================================================================

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, this.initialSymbol});

  /// Opens straight onto a symbol when launched from a stock page.
  final String? initialSymbol;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  static const _quickPicks = {
    'NIFTY 50': '^NSEI',
    'BANK NIFTY': '^NSEBANK',
    'SENSEX': '^BSESN',
    'RELIANCE': 'RELIANCE.NS',
    'HDFC BANK': 'HDFCBANK.NS',
    'TCS': 'TCS.NS',
    'INFOSYS': 'INFY.NS',
    'ICICI BANK': 'ICICIBANK.NS',
  };

  static const _timeframes = ['1D', '1W', '1M', '6M', '1Y', '5Y', 'ALL'];

  late String _symbol;
  String _timeframe = '1D';

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _symbol = widget.initialSymbol ?? '^NSEI';
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Only the 1D view refreshes — longer windows barely move, and polling
  /// them would waste the free tier's bandwidth for nothing.
  void _syncTimer() {
    _refreshTimer?.cancel();
    if (_timeframe == '1D') {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _load(silent: true),
      );
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await ApiService.getChart(_symbol, timeframe: _timeframe);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
      _syncTimer();
    } catch (e) {
      // A failed background refresh shouldn't wipe a good chart.
      if (mounted && !silent) setState(() => _error = '$e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _pick(String symbol) {
    setState(() => _symbol = symbol);
    _load();
  }

  void _submitSearch() {
    final raw = _searchCtrl.text.trim().toUpperCase();
    if (raw.isEmpty) return;
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    _pick(raw);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final up = ((d?['change'] as num?) ?? 0) >= 0;
    final accent = d == null ? Brand.gold : (up ? Brand.green : Brand.red);

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Live Chart',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: () => _load(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          // ---- Symbol search ----
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Brand.paper),
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9&^.\-]')),
            ],
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
              hintText: 'Any NSE symbol, e.g. ZOMATO or ^NSEI',
              hintStyle: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.5), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Brand.mint, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Brand.gold,
                    size: 20),
                onPressed: _submitSearch,
              ),
              filled: true,
              fillColor: Brand.fern.withValues(alpha: 0.32),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Brand.mint.withValues(alpha: 0.25)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Brand.gold),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ---- Quick picks ----
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in _quickPicks.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () => _pick(e.value),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: _symbol == e.value
                              ? Brand.gold.withValues(alpha: 0.18)
                              : Brand.fern.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _symbol == e.value
                                ? Brand.gold
                                : Brand.mint.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(e.key,
                            style: TextStyle(
                                color: _symbol == e.value
                                    ? Brand.gold
                                    : Brand.mint,
                                fontSize: 11.5,
                                fontWeight: _symbol == e.value
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ---- Timeframes ----
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in _timeframes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _timeframe = t);
                        _load();
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: _timeframe == t
                              ? accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _timeframe == t
                                ? accent.withValues(alpha: 0.7)
                                : Brand.mint.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(t,
                            style: TextStyle(
                                color: _timeframe == t ? accent : Brand.mint,
                                fontSize: 11.5,
                                fontWeight: _timeframe == t
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child:
                  Center(child: CircularProgressIndicator(color: Brand.gold)),
            )
          else if (_error != null)
            _ChartError(message: _error!, onRetry: () => _load())
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
      ),
    );
  }
}

// ===========================================================================
// PRICE HEADER
// ===========================================================================

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

// ===========================================================================
// CHART
// ===========================================================================

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
        // Tooltip for the touched point.
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
    // Keep the baseline on screen — a chart that hides it misleads.
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

    // Dashed baseline
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

    // Gradient fill under the line
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

    // Latest point marker
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = accent);
    canvas.drawCircle(
        last, 8, Paint()..color = accent.withValues(alpha: 0.25));

    // Crosshair
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

// ===========================================================================
// STATS
// ===========================================================================

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

// ===========================================================================
// ERROR
// ===========================================================================

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
