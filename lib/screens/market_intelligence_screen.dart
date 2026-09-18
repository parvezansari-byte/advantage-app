// lib/screens/market_intelligence_screen.dart
//
// Live snapshot across Global, India, Commodities, and Currency, with
// automatic event detection for notable moves and AI-generated "why it
// happened" context. Matches the website's Market Intelligence page.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class MarketIntelligenceScreen extends StatefulWidget {
  const MarketIntelligenceScreen({super.key});

  @override
  State<MarketIntelligenceScreen> createState() =>
      _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends State<MarketIntelligenceScreen> {
  List<dynamic> _instruments = [];
  String? _asOf;
  bool _loading = true;
  String? _error;

  final Map<String, String> _whyText = {};
  final Map<String, bool> _whyLoading = {};
  final Map<String, String> _whyError = {};

  static const _categoryOrder = ['Global', 'India', 'Commodities', 'Currency'];

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
      final d = await ApiService.getMarketIntelligenceSnapshot();
      if (mounted) {
        setState(() {
          _instruments = (d['instruments'] as List?) ?? [];
          _asOf = '${d['as_of'] ?? ''}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateWhy(Map ev) async {
    final key = '${ev['instrument']}';
    setState(() {
      _whyLoading[key] = true;
      _whyError.remove(key);
    });
    try {
      final text = await ApiService.getIntelligenceWhy(
        instrument: key,
        changePct: (ev['change_pct'] as num).toDouble(),
        threshold: (ev['threshold'] as num).toDouble(),
      );
      if (mounted) setState(() => _whyText[key] = text);
    } catch (e) {
      if (mounted) setState(() => _whyError[key] = 'Could not generate context: $e');
    } finally {
      if (mounted) setState(() => _whyLoading[key] = false);
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
        title: const Text('Market Intelligence',
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
                      if (_asOf != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('Last updated: $_asOf IST',
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.6),
                                  fontSize: 11)),
                        ),
                      for (final cat in _categoryOrder) ..._categorySection(cat),
                      const SizedBox(height: 8),
                      _whatMattersSection(),
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
            Text(_error ?? 'Could not load market snapshot',
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

  List<Widget> _categorySection(String category) {
    final items =
        _instruments.where((i) => (i as Map)['category'] == category).toList();
    if (items.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(category.toUpperCase(),
            style: const TextStyle(
                color: Brand.gold,
                fontSize: 12,
                letterSpacing: 1.1,
                fontWeight: FontWeight.bold)),
      ),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: items.map((i) => _instrumentCard(i as Map)).toList(),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _instrumentCard(Map i) {
    final changePct = (i['change_pct'] as num).toDouble();
    final up = changePct >= 0;
    final color = up ? Brand.green : Brand.red;
    final notable = i['notable'] == true;

    return Container(
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: notable ? 0.5 : 0.28),
        borderRadius: BorderRadius.circular(10),
        border: notable
            ? Border.all(color: Brand.gold.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtValue(i['value']),
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('${up ? '+' : ''}${changePct.toStringAsFixed(2)}%',
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${i['instrument']}',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.75), fontSize: 10.5),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _whatMattersSection() {
    final notable = _instruments
        .where((i) => (i as Map)['notable'] == true)
        .cast<Map>()
        .toList()
      ..sort((a, b) => (b['change_pct'] as num)
          .abs()
          .compareTo((a['change_pct'] as num).abs()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('WHAT MATTERS TODAY',
            style: TextStyle(
                color: Brand.gold,
                fontSize: 12,
                letterSpacing: 1.1,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (notable.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No instrument has moved beyond its notable-move threshold '
                'right now \u2014 a quiet session across Global, India, '
                'Commodities, and Currency.',
                style: TextStyle(color: Brand.mint.withValues(alpha: 0.8)),
              ),
            ),
          )
        else
          for (final ev in notable) _eventCard(ev),
      ],
    );
  }

  Widget _eventCard(Map ev) {
    final key = '${ev['instrument']}';
    final changePct = (ev['change_pct'] as num).toDouble();
    final direction = changePct >= 0 ? 'risen' : 'fallen';
    final magnitude = '${ev['magnitude'] ?? 'notably'}';
    final sectorImpact = (ev['sector_impact'] as List?) ?? [];
    final loading = _whyLoading[key] == true;
    final why = _whyText[key];
    final whyErr = _whyError[key];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.gold, width: 0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ev['instrument']} has $magnitude $direction '
              '(${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%)',
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Market impact: a ${changePct.abs().toStringAsFixed(2)}% move, '
              'above the ${(ev['threshold'] as num).toStringAsFixed(1)}% '
              'threshold used to flag this as notable.',
              style: TextStyle(color: Brand.mint.withValues(alpha: 0.8), fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text('Why it happened',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (why == null && !loading)
              OutlinedButton.icon(
                onPressed: () => _generateWhy(ev),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.gold,
                  side: const BorderSide(color: Brand.gold),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Generate context',
                    style: TextStyle(fontSize: 12.5)),
              )
            else if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold)),
              )
            else if (whyErr != null)
              Text(whyErr, style: const TextStyle(color: Brand.red, fontSize: 12))
            else if (why != null) ...[
              Text(why,
                  style: const TextStyle(
                      color: Brand.paper, fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI-inferred context \u2014 not confirmed news',
                    style: TextStyle(color: Brand.mint, fontSize: 10)),
              ),
            ],
            if (sectorImpact.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Sector impact',
                  style: TextStyle(
                      color: Brand.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final s in sectorImpact) _sectorImpactRow(s as Map),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'No sector-sensitivity mapping available for this '
                  'instrument yet \u2014 currently covers Crude Oil, USD/INR, '
                  'and Gold moves.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.6), fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectorImpactRow(Map s) {
    final dir = '${s['direction']}';
    final dirColor = dir == 'Positive'
        ? Brand.green
        : (dir == 'Negative' ? Brand.red : Brand.gold);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          _pill(dir, dirColor),
          _pill('${s['confidence']} confidence', Brand.mint),
          Text('${s['sector']}',
              style: const TextStyle(
                  color: Brand.paper, fontSize: 12.5, fontWeight: FontWeight.bold)),
          Text(' \u2014 ${s['why']}',
              style: TextStyle(color: Brand.mint.withValues(alpha: 0.75), fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _disclaimer() {
    return Text(
      '"Why it happened" is AI-generated general context, not verified news '
      'reporting \u2014 always check a live news source for confirmed events. '
      'Sector impact is a qualitative, rules-based estimate, not a computed '
      'regression or prediction. This is educational market commentary, not '
      'personalized investment advice.',
      style: TextStyle(color: Brand.mint.withValues(alpha: 0.55), fontSize: 11),
    );
  }

  String _fmtValue(dynamic v) {
    if (v is! num) return '$v';
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${buf.toString()}.${parts[1]}';
  }
}
