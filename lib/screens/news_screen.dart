// lib/screens/news_screen.dart
// ---------------------------------------------------------------------------
// Market terminal: institutional flows (FII/DII) and a live news feed.
//
// Sentiment and impact tags are keyword heuristics computed server-side, not
// real NLP. They exist to help you scan a long feed quickly — the badges are
// labelled as such rather than presented as analysis.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _crore(num? v) {
  if (v == null) return '—';
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 100000) return '$sign₹${(a / 100000).toStringAsFixed(2)} L Cr';
  if (a >= 1000) return '$sign₹${(a / 1000).toStringAsFixed(2)}k Cr';
  return '$sign₹${a.toStringAsFixed(0)} Cr';
}

Color _sentimentColour(String s) => switch (s) {
      'Positive' => Brand.green,
      'Negative' => Brand.red,
      _ => Brand.mint,
    };

// ===========================================================================
// SCREEN
// ===========================================================================

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  Map<String, dynamic>? _news;
  Map<String, dynamic>? _flows;
  Map<String, dynamic>? _history;

  bool _loadingNews = true;
  bool _loadingFlows = true;
  bool _loadingHistory = true;
  String? _newsError;
  String? _flowsError;
  String? _historyError;

  String _filter = '';   // '', 'Positive', 'Negative', 'High'

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    // Each section is independent — one failing shouldn't blank the others.
    _loadFlows();
    _loadHistory();
    _loadNews();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final h = await ApiService.getFiiDiiHistory(days: 30);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) setState(() => _historyError = '$e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadNews() async {
    setState(() {
      _loadingNews = true;
      _newsError = null;
    });
    try {
      final sentiment =
          (_filter == 'Positive' || _filter == 'Negative') ? _filter : '';
      final impact = _filter == 'High' ? 'High' : '';
      final n = await ApiService.getNews(
          limit: 60, sentiment: sentiment, impact: impact);
      if (mounted) setState(() => _news = n);
    } catch (e) {
      if (mounted) setState(() => _newsError = '$e');
    } finally {
      if (mounted) setState(() => _loadingNews = false);
    }
  }

  Future<void> _loadFlows() async {
    setState(() {
      _loadingFlows = true;
      _flowsError = null;
    });
    try {
      final f = await ApiService.getFiiDii();
      if (mounted) setState(() => _flows = f);
    } catch (e) {
      if (mounted) setState(() => _flowsError = '$e');
    } finally {
      if (mounted) setState(() => _loadingFlows = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final articles = (_news?['articles'] as List?) ?? [];

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Market Terminal',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Brand.gold,
        backgroundColor: Brand.fern,
        onRefresh: () async {
          await Future.wait([_loadNews(), _loadFlows(), _loadHistory()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            // ---- Institutional flows ----
            const _SectionHeader('INSTITUTIONAL FLOWS'),
            if (_loadingFlows)
              const _FlowsSkeleton()
            else if (_flowsError != null)
              _InlineError(message: _flowsError!, onRetry: _loadFlows)
            else
              _FlowsPanel(data: _flows!),

            const SizedBox(height: 20),

            // ---- 30-day history ----
            const _SectionHeader('LAST 30 DAYS'),
            if (_loadingHistory)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_historyError != null)
              _InlineError(message: _historyError!, onRetry: _loadHistory)
            else
              _FlowHistoryPanel(data: _history!),

            const SizedBox(height: 22),

            // ---- News ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionHeader('MARKET NEWS'),
                if (_news != null)
                  Text('${_news!['count']} stories',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.6),
                          fontSize: 11)),
              ],
            ),
            const SizedBox(height: 4),

            _FilterStrip(
              active: _filter,
              summary: (_news?['summary'] as Map?)?.cast<String, dynamic>(),
              onChanged: (f) {
                setState(() => _filter = f);
                _loadNews();
              },
            ),

            const SizedBox(height: 10),

            if (_loadingNews)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_newsError != null)
              _InlineError(message: _newsError!, onRetry: _loadNews)
            else if (articles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('No stories match this filter',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.7),
                          fontSize: 13)),
                ),
              )
            else
              for (final a in articles)
                _NewsCard(article: (a as Map).cast<String, dynamic>()),

            if (articles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Sentiment and impact tags are keyword heuristics, not '
                'analysis. Always read the source before acting.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.5),
                    fontSize: 10.5,
                    height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// FII / DII PANEL
// ===========================================================================

class _FlowsPanel extends StatelessWidget {
  const _FlowsPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final flows = (data['flows'] as List?) ?? [];
    Map<String, dynamic>? find(String who) {
      for (final f in flows) {
        if ('${(f as Map)['who']}'.toUpperCase() == who) {
          return f.cast<String, dynamic>();
        }
      }
      return null;
    }

    final fii = find('FII');
    final dii = find('DII');

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _FlowCard(label: 'FII', data: fii)),
            const SizedBox(width: 10),
            Expanded(child: _FlowCard(label: 'DII', data: dii)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Source: ${data['source'] ?? '—'}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            if (fii?['date'] != null && '${fii!['date']}'.isNotEmpty)
              Text('${fii['date']}',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.label, required this.data});

  final String label;
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final net = data?['net'] as num?;
    final buy = data?['buy'] as num?;
    final sell = data?['sell'] as num?;
    final positive = (net ?? 0) >= 0;
    final colour = net == null
        ? Brand.mint
        : (positive ? Brand.green : Brand.red);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.9),
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (net != null)
                Icon(positive ? Icons.arrow_upward : Icons.arrow_downward,
                    color: colour, size: 16),
              const SizedBox(width: 2),
              Flexible(
                child: FittedBox(
                  child: Text(_crore(net),
                      style: TextStyle(
                          color: colour,
                          fontSize: 21,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(net == null
                  ? 'unavailable'
                  : (positive ? 'NET BUYING' : 'NET SELLING'),
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7),
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Divider(color: Brand.mint.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(_crore(buy),
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  Text('BOUGHT',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.65),
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              Column(
                children: [
                  Text(_crore(sell),
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  Text('SOLD',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.65),
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowsSkeleton extends StatelessWidget {
  const _FlowsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box() => Expanded(
          child: Container(
            height: 148,
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
                child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Brand.gold),
            )),
          ),
        );
    return Row(children: [box(), const SizedBox(width: 10), box()]);
  }
}

// ===========================================================================
// NEWS
// ===========================================================================

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.active,
    required this.summary,
    required this.onChanged,
  });

  final String active;
  final Map<String, dynamic>? summary;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String, int?)>[
      ('', 'All', null),
      ('Positive', 'Positive', summary?['positive'] as int?),
      ('Negative', 'Negative', summary?['negative'] as int?),
      ('High', 'High impact', summary?['high_impact'] as int?),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (key, label, count) in options)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: active == key
                        ? Brand.gold.withValues(alpha: 0.18)
                        : Brand.fern.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active == key
                          ? Brand.gold
                          : Brand.mint.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    count == null ? label : '$label · $count',
                    style: TextStyle(
                      color: active == key ? Brand.gold : Brand.mint,
                      fontSize: 11.5,
                      fontWeight:
                          active == key ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.article});

  final Map<String, dynamic> article;

  Future<void> _open(BuildContext context) async {
    final link = '${article['link'] ?? ''}';
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the article')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentiment = '${article['sentiment'] ?? 'Neutral'}';
    final impact = '${article['impact'] ?? 'Low'}';
    final image = '${article['image'] ?? ''}';

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (image.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        image,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                        // A broken image shouldn't leave a gap or an error box.
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    width: 68,
                                    height: 68,
                                    color:
                                        Brand.fern.withValues(alpha: 0.4),
                                  ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${article['title']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Text('${article['source']}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color:
                                          Brand.mint.withValues(alpha: 0.75),
                                      fontSize: 10.5)),
                            ),
                            if ('${article['age']}'.isNotEmpty) ...[
                              Text('  ·  ',
                                  style: TextStyle(
                                      color:
                                          Brand.mint.withValues(alpha: 0.5),
                                      fontSize: 10.5)),
                              Text('${article['age']}',
                                  style: TextStyle(
                                      color:
                                          Brand.mint.withValues(alpha: 0.6),
                                      fontSize: 10.5)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ('${article['summary']}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('${article['summary']}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.8),
                        fontSize: 12,
                        height: 1.45)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _Badge(
                      text: sentiment,
                      colour: _sentimentColour(sentiment)),
                  if (impact == 'High') ...[
                    const SizedBox(width: 6),
                    const _Badge(text: 'High impact', colour: Brand.gold),
                  ],
                  const Spacer(),
                  Icon(Icons.open_in_new,
                      size: 13, color: Brand.mint.withValues(alpha: 0.55)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              color: colour, fontSize: 9.5, fontWeight: FontWeight.bold)),
    );
  }
}

// ===========================================================================
// SHARED
// ===========================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: const TextStyle(
              color: Brand.gold,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_off, color: Brand.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Brand.gold,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 30-DAY FLOW HISTORY
// ===========================================================================

/// Combined bar-and-line chart: FII net as bars, DII net as a line.
///
/// Both series share one scale so the visual comparison is honest — a tall
/// DII line against short FII bars means DII really did buy more.
class _FlowHistoryChart extends StatelessWidget {
  const _FlowHistoryChart({required this.history});

  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: Brand.green,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Text('FII net',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
            const SizedBox(width: 14),
            Container(width: 14, height: 2, color: Brand.gold),
            const SizedBox(width: 5),
            Text('DII net',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 170,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _FlowChartPainter(history: history),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_shortDate(history.first['date']),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            Text(_shortDate(history.last['date']),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

String _shortDate(dynamic raw) {
  final s = '$raw';
  if (s.length < 10) return s;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final m = int.tryParse(s.substring(5, 7));
  final d = int.tryParse(s.substring(8, 10));
  if (m == null || d == null || m < 1 || m > 12) return s;
  return '${months[m - 1]} $d';
}

class _FlowChartPainter extends CustomPainter {
  _FlowChartPainter({required this.history});

  final List<Map<String, dynamic>> history;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    final fii = [
      for (final h in history) ((h['fii_net'] as num?) ?? 0).toDouble()
    ];
    final dii = [
      for (final h in history) ((h['dii_net'] as num?) ?? 0).toDouble()
    ];

    // One shared scale, padded so nothing touches the frame edge.
    final all = [...fii, ...dii];
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if (lo > 0) lo = 0;
    if (hi < 0) hi = 0;
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double yOf(double v) => size.height - ((v - lo) / span) * size.height;
    final zeroY = yOf(0);

    // Zero line
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = Brand.mint.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );

    // FII bars
    final slot = size.width / history.length;
    final barW = math.max(slot * 0.55, 2.0);
    for (var i = 0; i < fii.length; i++) {
      final cx = slot * i + slot / 2;
      final v = fii[i];
      final top = v >= 0 ? yOf(v) : zeroY;
      final bottom = v >= 0 ? zeroY : yOf(v);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - barW / 2, top, cx + barW / 2,
              math.max(bottom, top + 1)),
          const Radius.circular(2),
        ),
        Paint()
          ..color = (v >= 0 ? Brand.green : Brand.red)
              .withValues(alpha: 0.85),
      );
    }

    // DII line
    final path = Path();
    for (var i = 0; i < dii.length; i++) {
      final cx = slot * i + slot / 2;
      final p = Offset(cx, yOf(dii[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Brand.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots only when there's room for them.
    if (history.length <= 40) {
      for (var i = 0; i < dii.length; i++) {
        canvas.drawCircle(
          Offset(slot * i + slot / 2, yOf(dii[i])),
          2.2,
          Paint()..color = Brand.gold,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowChartPainter old) =>
      old.history != history;
}

/// Compact stat tile for the 30-day summary row.
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 3),
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
  }
}

/// The whole 30-day block: summary tiles, chart and an expandable table.
class _FlowHistoryPanel extends StatelessWidget {
  const _FlowHistoryPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final history = [
      for (final h in (data['history'] as List? ?? []))
        (h as Map).cast<String, dynamic>()
    ];
    final summary =
        (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No history collected yet. The external table source blocks cloud '
          'servers, but each day\'s snapshot is saved automatically — so this '
          'will fill in over the coming sessions.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.8),
              fontSize: 12,
              height: 1.45),
        ),
      );
    }

    final fiiTotal = (summary['fii_net_total'] as num?) ?? 0;
    final diiTotal = (summary['dii_net_total'] as num?) ?? 0;
    final combined = (summary['combined_net'] as num?) ?? 0;
    final buyDays = summary['fii_buying_days'] ?? 0;
    final totalDays = summary['total_days'] ?? history.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (history.length < 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'History building: ${history.length} session(s) so far.',
              style: TextStyle(
                  color: Brand.gold.withValues(alpha: 0.9), fontSize: 11),
            ),
          ),
        Row(
          children: [
            _SummaryTile(
                label: 'FII NET',
                value: _crore(fiiTotal),
                colour: fiiTotal >= 0 ? Brand.green : Brand.red),
            _SummaryTile(
                label: 'DII NET',
                value: _crore(diiTotal),
                colour: diiTotal >= 0 ? Brand.green : Brand.red),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _SummaryTile(
                label: 'COMBINED',
                value: _crore(combined),
                colour: combined >= 0 ? Brand.green : Brand.red),
            _SummaryTile(
                label: 'FII BUY DAYS',
                value: '$buyDays/$totalDays',
                colour: Brand.gold),
          ],
        ),
        const SizedBox(height: 16),
        _FlowHistoryChart(history: history),
        const SizedBox(height: 10),
        _FlowHistoryTable(history: history),
        const SizedBox(height: 6),
        Text('Source: ${(data['sources'] as List?)?.join(', ') ?? '—'}',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 10)),
      ],
    );
  }
}

class _FlowHistoryTable extends StatelessWidget {
  const _FlowHistoryTable({required this.history});

  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) {
    // Newest first reads more naturally in a table.
    final rows = history.reversed.toList();

    return Card(
      color: Brand.fern.withValues(alpha: 0.25),
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Brand.gold,
          collapsedIconColor: Brand.mint,
          title: Text('Day-by-day (₹ crore)',
              style: TextStyle(
                  color: Brand.paper.withValues(alpha: 0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.45),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Date',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('FII net',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('DII net',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final fii = (r['fii_net'] as num?) ?? 0;
                  final dii = (r['dii_net'] as num?) ?? 0;
                  return Container(
                    color: i.isEven
                        ? Colors.transparent
                        : Brand.fern.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: Text(_shortDate(r['date']),
                                style: const TextStyle(
                                    color: Brand.mint, fontSize: 11))),
                        Expanded(
                          flex: 3,
                          child: Text(_crore(fii),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: fii >= 0 ? Brand.green : Brand.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(_crore(dii),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: dii >= 0 ? Brand.green : Brand.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
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
