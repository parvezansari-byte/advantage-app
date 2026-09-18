// lib/screens/market_mood_screen.dart
//
// Composite Fear/Greed gauge for the Indian market, built from 5 signals
// (India VIX, momentum vs 125-day avg, sector breadth, gold safe-haven
// demand, 52-week positioning). Matches the website's Market Mood page.

import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class MarketMoodScreen extends StatefulWidget {
  const MarketMoodScreen({super.key});

  @override
  State<MarketMoodScreen> createState() => _MarketMoodScreenState();
}

class _MarketMoodScreenState extends State<MarketMoodScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  List<dynamic> _vixPoints = [];
  String _vixPeriod = '6mo';
  bool _loadingVix = false;

  String? _aiAnalysis;
  bool _loadingAi = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getMarketMood();
      if (mounted) setState(() => _data = d);
      _loadVix();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVix([String? period]) async {
    final p = period ?? _vixPeriod;
    setState(() {
      _vixPeriod = p;
      _loadingVix = true;
    });
    try {
      final points = await ApiService.getVixHistory(period: p);
      if (mounted) setState(() => _vixPoints = points);
    } catch (_) {
      // chart just stays empty; not critical to the page
    } finally {
      if (mounted) setState(() => _loadingVix = false);
    }
  }

  Future<void> _generateAiAnalysis() async {
    if (_data == null) return;
    setState(() {
      _loadingAi = true;
      _aiError = null;
    });
    try {
      final text = await ApiService.getMoodAiAnalysis(_data!);
      if (mounted) setState(() => _aiAnalysis = text);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Could not generate analysis: $e');
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  Color _hexColor(String? hex) {
    if (hex == null || hex.isEmpty) return Brand.mint;
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Market Mood',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : _error != null
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Brand.gold,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _gaugeCard(),
                      const SizedBox(height: 16),
                      _signalsCard(),
                      const SizedBox(height: 16),
                      _vixChartCard(),
                      const SizedBox(height: 16),
                      _aiCard(),
                      const SizedBox(height: 16),
                      _disclaimer(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Brand.mint, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'Could not load market mood',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.paper)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold, foregroundColor: Brand.vault),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gaugeCard() {
    final composite = (_data!['composite'] as num).toDouble();
    final zone = '${_data!['zone']}';
    final color = _hexColor(_data!['zone_color'] as String?);
    final asOf = '${_data!['as_of'] ?? ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            _MoodGauge(value: composite, zone: zone, color: color),
            const SizedBox(height: 8),
            Text('As of $asOf IST',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _signalsCard() {
    final scores = (_data!['scores'] as Map).cast<String, dynamic>();
    final details = (_data!['details'] as Map).cast<String, dynamic>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SIGNAL BREAKDOWN',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            for (final entry in scores.entries)
              _signalRow(
                entry.key,
                (entry.value as num).toDouble(),
                '${details[entry.key] ?? ''}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _signalRow(String name, double score, String detail) {
    final color =
        score >= 55 ? Brand.green : (score <= 45 ? Brand.red : Brand.gold);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Text(score.toStringAsFixed(0),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: Brand.fern.withValues(alpha: 0.3),
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(detail,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _vixChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('INDIA VIX TREND',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in ['1mo', '3mo', '6mo', '1y'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.toUpperCase()),
                        selected: p == _vixPeriod,
                        onSelected: (_) => _loadVix(p),
                        selectedColor: Brand.gold,
                        backgroundColor: Brand.fern.withValues(alpha: 0.35),
                        labelStyle: TextStyle(
                          color: p == _vixPeriod ? Brand.vault : Brand.mint,
                          fontWeight: p == _vixPeriod
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: _loadingVix
                  ? const Center(
                      child: CircularProgressIndicator(color: Brand.gold))
                  : _VixLineChart(points: _vixPoints),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI ANALYSIS',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_aiAnalysis == null && !_loadingAi)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _generateAiAnalysis,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.gold,
                    side: const BorderSide(color: Brand.gold),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate AI Analysis'),
                ),
              )
            else if (_loadingAi)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(color: Brand.gold),
              ))
            else if (_aiError != null)
              Text(_aiError!, style: const TextStyle(color: Brand.red))
            else ...[
              _MarkdownBoldText(text: _aiAnalysis ?? ''),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI-generated \u2014 not financial advice',
                    style: TextStyle(color: Brand.mint, fontSize: 10.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'This is a simplified, rules-based composite of 5 signals \u2014 not an '
        'official index. Sentiment can stay in an extreme zone for a long '
        'time; this is educational market context, not investment advice.',
        style: TextStyle(color: Brand.mint.withValues(alpha: 0.55), fontSize: 11),
      ),
    );
  }
}

class _MoodGauge extends StatelessWidget {
  const _MoodGauge(
      {required this.value, required this.zone, required this.color});

  final double value;
  final String zone;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 150,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: const Size(260, 150),
            painter: _GaugePainter(value.clamp(0, 100), color),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value.toStringAsFixed(0),
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 38,
                        fontWeight: FontWeight.bold)),
                Text(zone,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color);

  final double value;
  final Color color;

  static const _bandColors = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFFBBF24),
    Color(0xFF84CC16),
    Color(0xFF10B981),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 14;
    const startAngle = pi;
    const sweepPerBand = pi / 5;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;
    for (int i = 0; i < 5; i++) {
      bgPaint.color = _bandColors[i].withValues(alpha: 0.30);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + i * sweepPerBand,
        sweepPerBand,
        false,
        bgPaint,
      );
    }

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = color;
    final valueSweep = (value / 100) * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweep,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class _VixLineChart extends StatelessWidget {
  const _VixLineChart({required this.points});

  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(
          child: Text('No VIX data for this range.',
              style: TextStyle(color: Brand.mint)));
    }
    final values = points
        .map((p) => ((p as Map)['vix'] as num).toDouble())
        .toList(growable: false);
    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    final pad = ((maxV - minV) * 0.12).clamp(0.2, double.infinity);

    return CustomPaint(
      size: Size.infinite,
      painter: _SimpleLinePainter(values, minV - pad, maxV + pad),
    );
  }
}

// Lightweight hand-rolled line chart (no extra dependency) - VIX is a
// single series, so a full charting package isn't needed here.
class _SimpleLinePainter extends CustomPainter {
  _SimpleLinePainter(this.values, this.minY, this.maxY);

  final List<double> values;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final range = (maxY - minY).abs() < 0.001 ? 1.0 : (maxY - minY);
    final dx = size.width / (values.length - 1);

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - ((values[i] - minY) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Brand.gold.withValues(alpha: 0.25),
            Brand.gold.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Brand.gold,
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleLinePainter oldDelegate) => true;
}

// Renders **bold** markers from the AI's markdown-ish response as actual
// bold text, since there's no full markdown renderer wired in here.
class _MarkdownBoldText extends StatelessWidget {
  const _MarkdownBoldText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          color: Brand.paper,
          fontSize: 13,
          height: 1.5,
          fontWeight: i.isOdd ? FontWeight.bold : FontWeight.normal,
        ),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }
}
