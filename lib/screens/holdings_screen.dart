// lib/screens/holdings_screen.dart
// ---------------------------------------------------------------------------
// Holdings Explorer: what funds actually own.
//
// Three views — which funds hold a given stock, one fund's full portfolio,
// and the overlap between two funds. Data is from AMC monthly disclosures,
// which cover only the fund houses that publish machine-readable factsheets,
// so the coverage line is shown wherever it matters.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../utils/holdings_pdf.dart';

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

String _pct(num? v, {int dp = 2}) =>
    v == null ? '—' : '${v.toStringAsFixed(dp)}%';

/// Disclosures are in lakh; crore reads better above a point.
String _lakhToMoney(num? lakh) {
  if (lakh == null) return '—';
  final cr = lakh / 100;
  if (cr >= 1000) return '₹${_group((cr / 1000).round())}k Cr';
  if (cr >= 1) return '₹${cr.toStringAsFixed(1)} Cr';
  return '₹${lakh.toStringAsFixed(1)} L';
}

String _qty(num? v) => v == null ? '—' : _group(v.round());

/// Bands mirror the API's own verdict so colour and words agree.
Color _overlapColour(String band) => switch (band) {
      'very_high' => Brand.red,
      'high' => Brand.gold,
      'moderate' => Brand.gold,
      _ => Brand.green,
    };

const _sectorPalette = [
  Brand.gold,
  Brand.green,
  Brand.mint,
  Color(0xFF8B9F7E),
  Color(0xFFD4A574),
  Color(0xFF7FA88B),
  Color(0xFFB8956A),
  Color(0xFF6B8E7F),
  Color(0xFFC9B47E),
];

// ===========================================================================
// SCREEN
// ===========================================================================

class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({super.key});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  Map<String, dynamic>? _summary;
  List<dynamic> _funds = [];
  bool _loading = true;
  String? _error;

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
      final s = await ApiService.getHoldingsSummary();
      final f = await ApiService.getHoldingsFunds();
      if (!mounted) return;
      setState(() {
        _summary = s;
        _funds = f;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          elevation: 0,
          title: const Text('Holdings Explorer',
              style:
                  TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: Brand.gold,
            unselectedLabelColor: Brand.mint,
            indicatorColor: Brand.gold,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: 'Who holds it'),
              Tab(text: 'Portfolio'),
              Tab(text: 'Overlap'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Brand.gold))
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      _CoverageBar(summary: _summary!),
                      Expanded(
                        child: TabBarView(
                          children: [
                            const _StockSearchTab(),
                            _PortfolioTab(funds: _funds),
                            _OverlapTab(funds: _funds),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// States plainly what the snapshot covers — partial coverage misread as
/// complete would make "no fund holds this" look like a fact.
class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Brand.fern,
          title: const Text('Coverage',
              style: TextStyle(color: Brand.paper, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Portfolio disclosures as on ${summary['as_on']}, covering '
                '${summary['funds']} funds from ${summary['amcs']} AMCs.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.45),
              ),
              const SizedBox(height: 10),
              Text(
                ((summary['amc_names'] as List?) ?? []).join(' · '),
                style: TextStyle(
                    color: Brand.gold.withValues(alpha: 0.85),
                    fontSize: 11,
                    height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Funds from other AMCs are not in this dataset, so an absent '
                'fund does not mean it holds nothing.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6),
                    fontSize: 10.5,
                    height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: Brand.gold)),
            ),
          ],
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Brand.fern.withValues(alpha: 0.25),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 12, color: Brand.mint.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${summary['funds']} funds · ${summary['amcs']} AMCs · '
                'as on ${summary['as_on']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.75), fontSize: 10.5),
              ),
            ),
            Text('Details',
                style: TextStyle(
                    color: Brand.gold.withValues(alpha: 0.8), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// SHARED WIDGETS
// ===========================================================================

/// Horizontal weight bar used by every list in this screen.
class _WeightBar extends StatelessWidget {
  const _WeightBar({
    required this.label,
    required this.pct,
    required this.maxPct,
    this.sub,
    this.colour = Brand.gold,
  });

  final String label;
  final num? pct;
  final double maxPct;
  final String? sub;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final value = (pct ?? 0).toDouble();
    final ratio = maxPct > 0 ? (value / maxPct).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Brand.paper, fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              Text(_pct(pct),
                  style: TextStyle(
                      color: colour,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Row(
                      children: [
                        Expanded(
                          flex: math.max((ratio * 1000).round(), 1),
                          child: Container(color: colour),
                        ),
                        Expanded(
                          flex: math.max(((1 - ratio) * 1000).round(), 1),
                          child: Container(
                              color: Brand.fern.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (sub != null) ...[
                const SizedBox(width: 8),
                Text(sub!,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.6),
                        fontSize: 9.5)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.colour = Brand.gold,
  });

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
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

/// Picks one fund via a searchable bottom sheet — 226 funds is too many for
/// a dropdown.
class _FundPicker extends StatelessWidget {
  const _FundPicker({
    required this.funds,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final List<dynamic> funds;
  final String label;
  final String? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _FundPickerSheet(funds: funds, onSelect: onSelect),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Brand.mint.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.7),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(selected ?? 'Tap to choose',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected == null
                              ? Brand.mint.withValues(alpha: 0.5)
                              : Brand.paper,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.expand_more,
                color: Brand.mint.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }
}

class _FundPickerSheet extends StatefulWidget {
  const _FundPickerSheet({required this.funds, required this.onSelect});

  final List<dynamic> funds;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  State<_FundPickerSheet> createState() => _FundPickerSheetState();
}

class _FundPickerSheetState extends State<_FundPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final filtered = needle.isEmpty
        ? widget.funds
        : widget.funds.where((f) {
            final m = f as Map;
            return '${m['fund']} ${m['amc']}'.toLowerCase().contains(needle);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: Brand.paper, fontSize: 13),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Filter ${widget.funds.length} funds',
                  hintStyle:
                      TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
                  prefixIcon:
                      const Icon(Icons.search, color: Brand.mint, size: 20),
                  filled: true,
                  fillColor: Brand.fern.withValues(alpha: 0.35),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Brand.mint.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Brand.gold),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final f = (filtered[i] as Map).cast<String, dynamic>();
                  return ListTile(
                    dense: true,
                    title: Text('${f['fund']}',
                        style: const TextStyle(
                            color: Brand.paper, fontSize: 12.5, height: 1.3)),
                    subtitle: Text(
                        '${f['amc']}  ·  ${f['holdings']} holdings',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.65),
                            fontSize: 10.5)),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSelect(f);
                    },
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 36, color: Brand.mint.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    height: 1.4)),
            const SizedBox(height: 16),
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
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — WHO HOLDS THIS STOCK
// ===========================================================================

class _StockSearchTab extends StatefulWidget {
  const _StockSearchTab();

  @override
  State<_StockSearchTab> createState() => _StockSearchTabState();
}

class _StockSearchTabState extends State<_StockSearchTab> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _data;
  int _picked = 0;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 3) {
      setState(() => _error = 'Type at least 3 characters');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
      _picked = 0;
    });
    try {
      final d = await ApiService.getStockHolders(q);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final securities = (_data?['securities'] as List?) ?? [];
    final current = securities.isEmpty
        ? null
        : (securities[_picked.clamp(0, securities.length - 1)] as Map)
            .cast<String, dynamic>();
    final holders = (current?['holders'] as List?) ?? [];
    final maxWeight = holders.isEmpty
        ? 1.0
        : ((holders.first as Map)['pct_nav'] as num? ?? 1).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        TextField(
          controller: _ctrl,
          style: const TextStyle(color: Brand.paper, fontSize: 13),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Stock name — e.g. HDFC Bank, Infosys, Zomato',
            hintStyle: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 12.5),
            prefixIcon: const Icon(Icons.search, color: Brand.mint, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.gold),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward,
                        color: Brand.gold, size: 20),
                    onPressed: _search,
                  ),
            filled: true,
            fillColor: Brand.fern.withValues(alpha: 0.35),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Brand.mint.withValues(alpha: 0.25)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Brand.gold),
            ),
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ),

        if (_data == null && _error == null && !_loading) ...[
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.travel_explore,
                    size: 42, color: Brand.mint.withValues(alpha: 0.35)),
                const SizedBox(height: 14),
                Text('Search a stock to see which funds own it',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 12.5)),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Weights come from each AMC\'s own monthly disclosure.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.5),
                        fontSize: 10.5,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ---- Multiple matching securities ----
        if (securities.length > 1) ...[
          const SizedBox(height: 14),
          Text('${securities.length} matching securities',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 10.5)),
          const SizedBox(height: 7),
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: securities.length,
              itemBuilder: (context, i) {
                final s = (securities[i] as Map).cast<String, dynamic>();
                final active = i == _picked;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _picked = i),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
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
                      child: Text(
                        '${s['instrument']}'.length > 26
                            ? '${'${s['instrument']}'.substring(0, 26)}…'
                            : '${s['instrument']}',
                        style: TextStyle(
                            color: active ? Brand.gold : Brand.mint,
                            fontSize: 10.5,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // ---- Selected security ----
        if (current != null) ...[
          const SizedBox(height: 16),
          Text('${current['instrument']}',
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text('${current['industry']}',
              style: TextStyle(
                  color: Brand.gold.withValues(alpha: 0.85), fontSize: 11)),

          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(
                  label: 'FUNDS HOLDING',
                  value: '${current['fund_count']}'),
              _StatTile(
                  label: 'COMBINED VALUE',
                  value: '₹${_group((current['total_value_cr'] as num? ?? 0).round())} Cr',
                  colour: Brand.green),
              _StatTile(
                  label: 'TOP WEIGHT',
                  value: _pct(current['max_weight'] as num?),
                  colour: Brand.paper),
            ],
          ),

          const SizedBox(height: 18),
          Text('BY WEIGHT IN EACH FUND',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.75),
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final h in holders)
                  () {
                    final row = (h as Map).cast<String, dynamic>();
                    return _WeightBar(
                      label: '${row['fund']}',
                      pct: row['pct_nav'] as num?,
                      maxPct: maxWeight,
                      sub: _lakhToMoney(row['value_lakh'] as num?),
                    );
                  }(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// TAB 2 — FUND PORTFOLIO
// ===========================================================================

class _PortfolioTab extends StatefulWidget {
  const _PortfolioTab({required this.funds});

  final List<dynamic> funds;

  @override
  State<_PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends State<_PortfolioTab> {
  String? _key;
  String? _label;
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;
  bool _showAll = false;

  Future<void> _load(String key) async {
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
      _showAll = false;
    });
    try {
      final d = await ApiService.getFundHoldings(key);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final holdings = (_data?['holdings'] as List?) ?? [];
    final sectors = (_data?['sectors'] as List?) ?? [];
    final shown = _showAll ? holdings : holdings.take(15).toList();
    final maxWeight = holdings.isEmpty
        ? 1.0
        : ((holdings.first as Map)['pct_nav'] as num? ?? 1).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _FundPicker(
          funds: widget.funds,
          label: 'FUND',
          selected: _label,
          onSelect: (f) {
            setState(() {
              _key = '${f['key']}';
              _label = '${f['fund']}';
            });
            _load('${f['key']}');
          },
        ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: Brand.gold)),
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ),

        if (_key == null && !_loading) ...[
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(Icons.pie_chart_outline,
                    size: 42, color: Brand.mint.withValues(alpha: 0.35)),
                const SizedBox(height: 14),
                Text('Choose a fund to see everything it owns',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 12.5)),
              ],
            ),
          ),
        ],

        if (_data != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(label: 'HOLDINGS', value: '${_data!['count']}'),
              _StatTile(
                  label: 'DISCLOSED',
                  value: _pct(_data!['disclosed_pct'] as num?, dp: 1),
                  colour: Brand.green),
              _StatTile(
                  label: 'TOP 10',
                  value: _pct(_data!['top10_pct'] as num?, dp: 1),
                  colour: Brand.paper),
            ],
          ),

          // ---- Sector allocation ----
          if (sectors.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('SECTOR ALLOCATION',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.75),
                    fontSize: 9.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _SectorBar(sectors: sectors),
          ],

          // ---- Holdings ----
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_showAll
                      ? 'ALL ${holdings.length} HOLDINGS'
                      : 'TOP 15 HOLDINGS',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.75),
                      fontSize: 9.5,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
              if (holdings.length > 15)
                GestureDetector(
                  onTap: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Show less' : 'Show all',
                      style: const TextStyle(
                          color: Brand.gold,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final h in shown)
                  () {
                    final row = (h as Map).cast<String, dynamic>();
                    return _WeightBar(
                      label: '${row['instrument']}',
                      pct: row['pct_nav'] as num?,
                      maxPct: maxWeight,
                      sub: _lakhToMoney(row['value_lakh'] as num?),
                    );
                  }(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Disclosed weight is the share of NAV these holdings account for. '
            'The remainder is cash, derivatives, or instruments outside this '
            'disclosure.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10,
                height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Download PDF Report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.gold,
                side: const BorderSide(color: Brand.gold),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final bytes = await buildFundPortfolioPdf(
                  fundName: _label ?? 'Fund',
                  data: _data!,
                );
                await Printing.sharePdf(
                    bytes: bytes, filename: '${(_label ?? 'fund').replaceAll(' ', '_')}_report.pdf');
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Stacked sector bar plus a legend — a pie chart in a phone-width column
/// makes small slices unreadable.
class _SectorBar extends StatelessWidget {
  const _SectorBar({required this.sectors});

  final List<dynamic> sectors;

  @override
  Widget build(BuildContext context) {
    final top = sectors.take(9).toList();
    final rest = sectors.skip(9).fold<double>(
        0, (sum, s) => sum + (((s as Map)['pct_nav'] as num?) ?? 0));

    final segments = <(String, double, Color)>[
      for (var i = 0; i < top.length; i++)
        (
          '${(top[i] as Map)['industry']}',
          (((top[i] as Map)['pct_nav'] as num?) ?? 0).toDouble(),
          _sectorPalette[i % _sectorPalette.length],
        ),
      if (rest > 0.01) ('Others', rest, Brand.fern),
    ];

    final total = segments.fold<double>(0, (s, seg) => s + seg.$2);
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final (_, pct, colour) in segments)
                  Expanded(
                    flex: math.max((pct * 100).round(), 1),
                    child: Container(color: colour),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final (name, pct, colour) in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: colour,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$name ${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.8),
                        fontSize: 10),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ===========================================================================
// TAB 3 — OVERLAP
// ===========================================================================

class _OverlapTab extends StatefulWidget {
  const _OverlapTab({required this.funds});

  final List<dynamic> funds;

  @override
  State<_OverlapTab> createState() => _OverlapTabState();
}

class _OverlapTabState extends State<_OverlapTab> {
  // Up to 4 funds (A-D). Only the first _activeCount slots are shown/used.
  final List<String?> _keys = List.filled(4, null);
  final List<String?> _labels = List.filled(4, null);
  int _activeCount = 2;

  List<List<double>>? _matrix;
  List<Map<String, dynamic>>? _heldByAll;
  bool _loading = false;
  String? _error;

  static const _slotLabels = ['FUND A', 'FUND B', 'FUND C', 'FUND D'];

  bool get _readyToCompare {
    final active = _keys.take(_activeCount).toList();
    if (active.any((k) => k == null)) return false;
    return active.toSet().length == active.length; // all distinct
  }

  Future<void> _compare() async {
    if (!_readyToCompare) return;
    setState(() {
      _loading = true;
      _error = null;
      _matrix = null;
      _heldByAll = null;
    });
    try {
      final n = _activeCount;
      final matrix = List.generate(n, (_) => List.filled(n, 0.0));
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final d = await ApiService.getFundOverlap(_keys[i]!, _keys[j]!);
          final pct = (d['overlap_pct'] as num?)?.toDouble() ?? 0.0;
          matrix[i][j] = pct;
          matrix[j][i] = pct;
        }
      }

      // Held-by-all: fetch each fund's full holdings, intersect by
      // instrument name across all active funds.
      final holdingSets = <Set<String>>[];
      final holdingRows = <String, Map<String, dynamic>>{};
      for (int i = 0; i < n; i++) {
        final d = await ApiService.getFundHoldings(_keys[i]!);
        final holdings = (d['holdings'] as List? ?? []).cast<Map>();
        final names = <String>{};
        for (final h in holdings) {
          final name = '${h['instrument']}';
          names.add(name);
          holdingRows.putIfAbsent(name, () => {'instrument': name});
        }
        holdingSets.add(names);
      }
      var common = holdingSets.first;
      for (final s in holdingSets.skip(1)) {
        common = common.intersection(s);
      }
      final heldByAll = common.map((name) => holdingRows[name]!).toList();

      if (mounted) {
        setState(() {
          _matrix = matrix;
          _heldByAll = heldByAll;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _cellColor(double pct) {
    if (pct >= 60) return Brand.red;
    if (pct >= 40) return const Color(0xFFD97706);
    if (pct >= 20) return const Color(0xFFEAB308);
    return Brand.green;
  }

  @override
  Widget build(BuildContext context) {
    final activeLabels = _labels.take(_activeCount).map((l) => l ?? '—').toList();
    double avgOverlap = 0;
    if (_matrix != null) {
      final pairs = <double>[];
      for (int i = 0; i < _activeCount; i++) {
        for (int j = i + 1; j < _activeCount; j++) {
          pairs.add(_matrix![i][j]);
        }
      }
      if (pairs.isNotEmpty) avgOverlap = pairs.reduce((a, b) => a + b) / pairs.length;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        // ---- fund count selector ----
        Row(
          children: [
            Text('COMPARE',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(width: 10),
            for (int n = 2; n <= 4; n++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$n funds'),
                  selected: _activeCount == n,
                  onSelected: (_) => setState(() {
                    _activeCount = n;
                    _matrix = null;
                    _heldByAll = null;
                  }),
                  selectedColor: Brand.gold.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                      color: _activeCount == n ? Brand.gold : Brand.mint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                  backgroundColor: Brand.fern.withValues(alpha: 0.3),
                  side: BorderSide(
                      color: _activeCount == n
                          ? Brand.gold
                          : Brand.mint.withValues(alpha: 0.2)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        for (int i = 0; i < _activeCount; i++) ...[
          _FundPicker(
            funds: widget.funds,
            label: _slotLabels[i],
            selected: _labels[i],
            onSelect: (f) {
              setState(() {
                _keys[i] = '${f['key']}';
                _labels[i] = '${f['fund']}';
              });
              if (_readyToCompare) _compare();
            },
          ),
          const SizedBox(height: 9),
        ],

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 50),
            child: Center(child: CircularProgressIndicator(color: Brand.gold)),
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ),

        if (_matrix == null && !_loading && _error == null) ...[
          const SizedBox(height: 50),
          Center(
            child: Column(
              children: [
                Icon(Icons.join_inner,
                    size: 42, color: Brand.mint.withValues(alpha: 0.35)),
                const SizedBox(height: 14),
                Text('Pick $_activeCount funds to compare',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 12.5)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Text(
                    'High overlap means funds hold much the same stocks — '
                    'owning several may add less diversification than it appears.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.5),
                        fontSize: 10.5,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_matrix != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              _StatTile(label: 'FUNDS COMPARED', value: '$_activeCount'),
              _StatTile(
                  label: 'AVG OVERLAP',
                  value: '${avgOverlap.toStringAsFixed(1)}%',
                  colour: _cellColor(avgOverlap)),
              _StatTile(
                  label: 'HELD BY ALL',
                  value: '${_heldByAll?.length ?? 0}',
                  colour: Brand.paper),
            ],
          ),

          const SizedBox(height: 20),
          Text('PAIRWISE OVERLAP MATRIX',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.75),
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _OverlapMatrix(labels: activeLabels, matrix: _matrix!, colorFor: _cellColor),

          const SizedBox(height: 20),
          Text('PAIRWISE OVERLAP SUMMARY',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.75),
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final pairs = <(String, String, double)>[];
            for (int i = 0; i < _activeCount; i++) {
              for (int j = i + 1; j < _activeCount; j++) {
                pairs.add((activeLabels[i], activeLabels[j], _matrix![i][j]));
              }
            }
            pairs.sort((a, b) => b.$3.compareTo(a.$3));
            return Column(
              children: [
                for (final p in pairs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Brand.fern.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${p.$1} vs ${p.$2}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.85),
                                  fontSize: 11.5)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _cellColor(p.$3).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${p.$3.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: _cellColor(p.$3),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),

          if (_heldByAll != null && _heldByAll!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('STOCKS HELD BY ALL $_activeCount FUNDS (${_heldByAll!.length})',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.75),
                    fontSize: 9.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: Brand.fern.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in _heldByAll!.take(30))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${h['instrument']}',
                          style: TextStyle(
                              color: Brand.paper.withValues(alpha: 0.9), fontSize: 11.5)),
                    ),
                ],
              ),
            ),
          ] else if (_heldByAll != null) ...[
            const SizedBox(height: 16),
            Text('No single stock is held by all $_activeCount selected funds.',
                style: TextStyle(color: Brand.mint.withValues(alpha: 0.6), fontSize: 11.5)),
          ],

          const SizedBox(height: 16),
          Text(
            'Overlap is the sum of the smaller weight of each shared holding. '
            'If both funds hold 5% of the same stock they overlap 5% there; '
            'if one holds 5% and the other 2%, they overlap 2%.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10,
                height: 1.45),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Download PDF Report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.gold,
                side: const BorderSide(color: Brand.gold),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final bytes = await buildOverlapPdf(
                  fundLabels: activeLabels,
                  matrix: _matrix!,
                  heldByAll: _heldByAll ?? [],
                );
                await Printing.sharePdf(bytes: bytes, filename: 'fund_overlap_report.pdf');
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Colour-coded NxN overlap matrix - the same heatmap concept as the web
/// app's PDF/Streamlit version, rendered as a Flutter Table.
class _OverlapMatrix extends StatelessWidget {
  const _OverlapMatrix({required this.labels, required this.matrix, required this.colorFor});

  final List<String> labels;
  final List<List<double>> matrix;
  final Color Function(double) colorFor;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    String short(String s) => s.length > 10 ? '${s.substring(0, 10)}…' : s;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: Brand.mint.withValues(alpha: 0.15)),
        defaultColumnWidth: const FixedColumnWidth(64),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Brand.vault),
            children: [
              const SizedBox(width: 70, height: 40),
              for (final l in labels)
                Container(
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(short(l),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Brand.gold, fontSize: 8.5, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          for (int i = 0; i < n; i++)
            TableRow(
              children: [
                Container(
                  width: 70,
                  height: 44,
                  alignment: Alignment.center,
                  color: Brand.vault,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(short(labels[i]),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Brand.gold, fontSize: 8.5, fontWeight: FontWeight.bold)),
                ),
                for (int j = 0; j < n; j++)
                  Container(
                    height: 44,
                    alignment: Alignment.center,
                    color: i == j ? Brand.vault : colorFor(matrix[i][j]),
                    child: Text(
                      i == j ? '—' : '${matrix[i][j].toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: i == j ? Brand.gold : Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OverlapRow extends StatelessWidget {
  const _OverlapRow({
    required this.instrument,
    required this.pctA,
    required this.pctB,
  });

  final String instrument;
  final double pctA;
  final double pctB;

  @override
  Widget build(BuildContext context) {
    final scale = math.max(math.max(pctA, pctB), 0.01);

    Widget bar(double pct, Color colour) => Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Row(
                    children: [
                      Expanded(
                        flex: math.max((pct / scale * 1000).round(), 1),
                        child: Container(color: colour),
                      ),
                      Expanded(
                        flex: math.max(
                            ((1 - pct / scale) * 1000).round(), 1),
                        child: Container(
                            color: Brand.fern.withValues(alpha: 0.45)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 40,
              child: Text('${pct.toStringAsFixed(2)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: colour,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(instrument,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Brand.paper, fontSize: 11.5)),
          const SizedBox(height: 5),
          bar(pctA, Brand.gold),
          const SizedBox(height: 3),
          bar(pctB, Brand.green),
        ],
      ),
    );
  }
}
