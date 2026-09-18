// lib/screens/funds_screen.dart
// ---------------------------------------------------------------------------
// Mutual fund research, built on a monthly research snapshot with daily NAV
// refreshed from AMFI.
//
// These are REGULAR plan figures. Direct plans of the same schemes carry a
// lower expense ratio and correspondingly higher returns, so don't compare a
// number here against a Direct-plan quote.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

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

/// AUM arrives in crore; large funds read better in lakh crore.
String _aum(num? v) {
  if (v == null) return '—';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L Cr';
  if (v >= 1000) return '₹${_group((v).round())} Cr';
  return '₹${v.toStringAsFixed(1)} Cr';
}

String _pct(num? v, {bool sign = false}) {
  if (v == null) return '—';
  final s = sign && v > 0 ? '+' : '';
  return '$s${v.toStringAsFixed(2)}%';
}

String _plain(num? v, {int dp = 2}) =>
    v == null ? '—' : v.toStringAsFixed(dp);

Color _returnColour(num? v) {
  if (v == null) return Brand.mint;
  if (v >= 15) return Brand.green;
  if (v >= 8) return Brand.gold;
  if (v >= 0) return Brand.paper;
  return Brand.red;
}

/// Sharpe below zero means the fund trailed the risk-free rate.
Color _sharpeColour(num? v) {
  if (v == null) return Brand.mint;
  if (v >= 1) return Brand.green;
  if (v >= 0.5) return Brand.gold;
  if (v >= 0) return Brand.paper;
  return Brand.red;
}

/// Strips the plan suffix the snapshot carries on every name.
String _shortName(String raw) => raw
    .replaceAll(RegExp(r'-Reg\(G\)|\(G\)|-Reg', caseSensitive: false), '')
    .trim();

// ===========================================================================
// SCREEN
// ===========================================================================

class FundsScreen extends StatefulWidget {
  const FundsScreen({super.key});

  @override
  State<FundsScreen> createState() => _FundsScreenState();
}

class _FundsScreenState extends State<FundsScreen> {
  List<dynamic> _groups = [];
  String _group = '';
  String _category = '';
  String _sort = 'aum';

  Map<String, dynamic>? _list;
  bool _loadingCats = true;
  bool _loadingList = false;
  String? _error;

  /// category|sort -> response. Switching back shouldn't refetch.
  final Map<String, Map<String, dynamic>> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCats = true;
      _error = null;
    });
    try {
      final g = await ApiService.getFundDbCategories();
      if (!mounted) return;

      // Open on the first equity category, which is what most people want.
      String group = '', category = '';
      if (g.isNotEmpty) {
        final equity = g.firstWhere(
          (x) => '${(x as Map)['group']}'.toLowerCase() == 'equity',
          orElse: () => g.first,
        ) as Map;
        group = '${equity['group']}';
        final cats = (equity['categories'] as List?) ?? [];
        if (cats.isNotEmpty) category = '${(cats.first as Map)['name']}';
      }

      setState(() {
        _groups = g;
        _group = group;
        _category = category;
      });
      if (_category.isNotEmpty) await _loadList();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  Future<void> _loadList({bool force = false}) async {
    final key = '$_category|$_sort';
    if (!force && _cache.containsKey(key)) {
      setState(() => _list = _cache[key]);
      return;
    }
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final d = await ApiService.getFundDbList(_category, sort: _sort);
      if (!mounted) return;
      setState(() {
        _list = d;
        _cache[key] = d;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  List<dynamic> get _categoriesForGroup {
    for (final g in _groups) {
      if ('${(g as Map)['group']}' == _group) {
        return (g['categories'] as List?) ?? [];
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final funds = (_list?['funds'] as List?) ?? [];

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Mutual Funds',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Brand.mint),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _FundSearchSheet(),
            ),
          ),
        ],
      ),
      body: _loadingCats
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : (_error != null && _groups.isEmpty)
              ? _ErrorState(message: _error!, onRetry: _loadCategories)
              : Column(
                  children: [
                    _AssetClassTabs(
                      groups: _groups,
                      selected: _group,
                      onSelect: (g) {
                        setState(() {
                          _group = g;
                          final cats = _categoriesForGroup;
                          if (cats.isNotEmpty) {
                            _category = '${(cats.first as Map)['name']}';
                          }
                        });
                        _loadList();
                      },
                    ),
                    _CategoryChips(
                      categories: _categoriesForGroup,
                      selected: _category,
                      onSelect: (c) {
                        setState(() => _category = c);
                        _loadList();
                      },
                    ),
                    _SortBar(
                      sort: _sort,
                      isEquity: _group.toLowerCase() == 'equity',
                      onChanged: (s) {
                        setState(() => _sort = s);
                        _loadList();
                      },
                    ),
                    if (_list != null && !_loadingList)
                      _NavStatusLine(data: _list!),
                    Expanded(
                      child: _loadingList
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Brand.gold))
                          : _error != null
                              ? _ErrorState(
                                  message: _error!,
                                  onRetry: () => _loadList(force: true))
                              : RefreshIndicator(
                                  color: Brand.gold,
                                  backgroundColor: Brand.fern,
                                  onRefresh: () => _loadList(force: true),
                                  child: ListView.builder(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 4, 12, 24),
                                    itemCount: funds.length,
                                    itemBuilder: (context, i) => _FundCard(
                                      fund: (funds[i] as Map)
                                          .cast<String, dynamic>(),
                                      rank: i + 1,
                                      sort: _sort,
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}

// ===========================================================================
// NAVIGATION BARS
// ===========================================================================

class _AssetClassTabs extends StatelessWidget {
  const _AssetClassTabs({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<dynamic> groups;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Brand.mint.withValues(alpha: 0.12)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final g in groups)
            () {
              final name = '${(g as Map)['group']}';
              final active = name == selected;
              final total = g['total'];
              final label = (total == null) ? name : '$name  $total';
              return GestureDetector(
                onTap: () => onSelect(name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: active ? Brand.gold : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active ? Brand.gold : Brand.mint,
                        fontSize: 12.5,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<dynamic> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  /// "Equity : Large Cap" reads as just "Large Cap" once the tab shows Equity.
  String _label(String full) {
    final parts = full.split(' : ');
    return parts.length > 1 ? parts[1] : full;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final c = categories[i] as Map;
          final name = '${c['name']}';
          final active = name == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            child: GestureDetector(
              onTap: () => onSelect(name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? Brand.gold.withValues(alpha: 0.18)
                      : Brand.fern.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active
                        ? Brand.gold
                        : Brand.mint.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '${_label(name)} · ${c['count']}',
                  style: TextStyle(
                    color: active ? Brand.gold : Brand.mint,
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sort,
    required this.isEquity,
    required this.onChanged,
  });

  final String sort;
  final bool isEquity;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[
      ('aum', 'AUM'),
      ('r_1y', '1Y'),
      ('r_3y', '3Y'),
      ('r_5y', '5Y'),
      if (isEquity) ('sharpe', 'Sharpe'),
      ('expense_ratio', 'Low cost'),
    ];

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          Center(
            child: Text('Rank by',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.65), fontSize: 10.5)),
          ),
          const SizedBox(width: 8),
          for (final (key, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sort == key
                        ? Brand.gold.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: sort == key
                          ? Brand.gold.withValues(alpha: 0.6)
                          : Brand.mint.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: sort == key ? Brand.gold : Brand.mint,
                          fontSize: 10.5,
                          fontWeight: sort == key
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tells the user how fresh the NAVs are — the snapshot is monthly, the NAV
/// daily, and only matched funds get the live figure.
class _NavStatusLine extends StatelessWidget {
  const _NavStatusLine({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final matched = (data['nav_matched'] as int?) ?? 0;
    final shown = (data['count'] as int?) ?? 0;
    final total = (data['total_in_category'] as int?) ?? shown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 6,
              color: matched > 0 ? Brand.green : Brand.mint.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing $shown of $total  ·  $matched with live NAV  ·  '
              'Regular plan',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.6), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// FUND CARD
// ===========================================================================

class _AmcLogo extends StatelessWidget {
  const _AmcLogo({required this.domain, required this.name, this.size = 32});

  final String? domain;
  final String name;
  final double size;

  static const _fallbackColors = [
    Brand.gold,
    Brand.blue,
    Brand.purple,
    Brand.teal,
    Brand.green,
  ];

  Color _colorFor(String s) {
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash + c) % _fallbackColors.length;
    }
    return _fallbackColors[hash];
  }

  Widget _letterAvatar() {
    final trimmed = name.trim();
    final letter = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _colorFor(name),
      child: Text(
        letter,
        style: TextStyle(
          color: Brand.vault,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (domain == null || domain!.isEmpty) return _letterAvatar();

    // Google's public favicon service - keyless, no signup (Clearbit's
    // free logo API shut down in Dec 2025). Quality is favicon-grade, not
    // a hi-res brand logo, but reliable and free. Any failure (network,
    // no favicon) falls back to the colored initial above.
    final url =
        'https://www.google.com/s2/favicons?domain=$domain&sz=128';

    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _letterAvatar(),
      ),
    );
  }
}

class _FundCard extends StatelessWidget {
  const _FundCard({
    required this.fund,
    required this.rank,
    required this.sort,
  });

  final Map<String, dynamic> fund;
  final int rank;
  final String sort;

  @override
  Widget build(BuildContext context) {
    final live = fund['nav_live'] == true;

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _FundDetailSheet(name: '${fund['name']}'),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Name + rank ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? Brand.gold.withValues(alpha: 0.2)
                          : Brand.fern.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$rank',
                        style: TextStyle(
                            color: rank <= 3 ? Brand.gold : Brand.mint,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 9),
                  _AmcLogo(
                    domain: fund['amc_domain'] as String?,
                    name: '${fund['name']}',
                    size: 28,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_shortName('${fund['name']}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (live) ...[
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                    color: Brand.green,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text('NAV ₹${_plain(fund['nav'] as num?)}',
                                style: TextStyle(
                                    color: Brand.gold.withValues(alpha: 0.9),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600)),
                            if (fund['manager'] != null) ...[
                              Text('  ·  ',
                                  style: TextStyle(
                                      color:
                                          Brand.mint.withValues(alpha: 0.4),
                                      fontSize: 10)),
                              Flexible(
                                child: Text('${fund['manager']}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: Brand.mint
                                            .withValues(alpha: 0.65),
                                        fontSize: 10)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 11),

              // ---- Returns ----
              Row(
                children: [
                  _Metric(label: '1Y', value: _pct(fund['r_1y'] as num?),
                      colour: _returnColour(fund['r_1y'] as num?)),
                  _Metric(label: '3Y', value: _pct(fund['r_3y'] as num?),
                      colour: _returnColour(fund['r_3y'] as num?)),
                  _Metric(label: '5Y', value: _pct(fund['r_5y'] as num?),
                      colour: _returnColour(fund['r_5y'] as num?)),
                  _Metric(
                      label: 'AUM',
                      value: _aum(fund['aum'] as num?),
                      colour: Brand.paper),
                ],
              ),

              const SizedBox(height: 9),
              Divider(color: Brand.mint.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 8),

              // ---- Cost and risk ----
              Row(
                children: [
                  _Chip(
                      label: 'ER',
                      value: _pct(fund['expense_ratio'] as num?),
                      colour: (fund['expense_ratio'] as num?) != null &&
                              (fund['expense_ratio'] as num) < 1
                          ? Brand.green
                          : Brand.mint),
                  if (fund['sharpe'] != null)
                    _Chip(
                        label: 'Sharpe',
                        value: _plain(fund['sharpe'] as num?),
                        colour: _sharpeColour(fund['sharpe'] as num?)),
                  if (fund['alpha'] != null)
                    _Chip(
                        label: 'Alpha',
                        value: _plain(fund['alpha'] as num?),
                        colour: (fund['alpha'] as num) >= 0
                            ? Brand.green
                            : Brand.red),
                  if (fund['beta'] != null)
                    _Chip(
                        label: 'Beta',
                        value: _plain(fund['beta'] as num?),
                        colour: Brand.mint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
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
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.6),
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          FittedBox(
            child: Text(value,
                style: TextStyle(
                    color: colour,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.value,
    required this.colour,
  });

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label ',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6), fontSize: 9)),
            Text(value,
                style: TextStyle(
                    color: colour,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// FUND DETAIL
// ===========================================================================

class _FundDetailSheet extends StatefulWidget {
  const _FundDetailSheet({required this.name});

  final String name;

  @override
  State<_FundDetailSheet> createState() => _FundDetailSheetState();
}

class _FundDetailSheetState extends State<_FundDetailSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String? _aiAnalysis;
  bool _loadingAi = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService.getFundDbDetail(widget.name);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateAiAnalysis() async {
    if (_data == null) return;
    setState(() {
      _loadingAi = true;
      _aiError = null;
    });
    try {
      final text = await ApiService.getAiAnalysis(_data!, kind: 'fund');
      if (mounted) setState(() => _aiAnalysis = text);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Could not generate analysis: $e');
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
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
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Brand.gold))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _body(controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController controller) {
    if (_data == null || _data!['name'] == null) {
      return _ErrorState(
        message: 'Fund details not found for "${widget.name}".',
        onRetry: _load,
      );
    }
    final f = _data!;
    final ranks = (_data!['ranks'] as Map?)?.cast<String, dynamic>() ?? {};
    final peers = (_data!['peers'] as List?) ?? [];
    final live = f['nav_live'] == true;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AmcLogo(
              domain: f['amc_domain'] as String?,
              name: '${f['name']}',
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_shortName('${f['name']}'),
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('${f['classification'] ?? ''}',
                      style: TextStyle(
                          color: Brand.gold.withValues(alpha: 0.9),
                          fontSize: 11.5)),
                  if (f['manager'] != null) ...[
                    const SizedBox(height: 3),
                    Text('Managed by ${f['manager']}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7),
                            fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ---- NAV ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (live) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Brand.green, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(live ? 'LIVE NAV' : 'NAV (snapshot)',
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.8),
                              fontSize: 9.5,
                              letterSpacing: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('₹${_plain(f['nav'] as num?)}',
                      style: const TextStyle(
                          color: Brand.gold,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (f['nav_date'] != null)
                    Text('${f['nav_date']}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7),
                            fontSize: 10.5)),
                  if (f['nav_change_pct'] != null) ...[
                    const SizedBox(height: 3),
                    Text(
                        '${_pct(f['nav_change_pct'] as num?, sign: true)} '
                        'since snapshot',
                        style: TextStyle(
                            color: (f['nav_change_pct'] as num) >= 0
                                ? Brand.green
                                : Brand.red,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // ---- Returns ----
        const _SectionLabel('RETURNS'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(children: [
                _Metric(label: '1M', value: _pct(f['r_1m'] as num?),
                    colour: _returnColour(f['r_1m'] as num?)),
                _Metric(label: '3M', value: _pct(f['r_3m'] as num?),
                    colour: _returnColour(f['r_3m'] as num?)),
                _Metric(label: '6M', value: _pct(f['r_6m'] as num?),
                    colour: _returnColour(f['r_6m'] as num?)),
                _Metric(label: '1Y', value: _pct(f['r_1y'] as num?),
                    colour: _returnColour(f['r_1y'] as num?)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _Metric(label: '2Y', value: _pct(f['r_2y'] as num?),
                    colour: _returnColour(f['r_2y'] as num?)),
                _Metric(label: '3Y', value: _pct(f['r_3y'] as num?),
                    colour: _returnColour(f['r_3y'] as num?)),
                _Metric(label: '5Y', value: _pct(f['r_5y'] as num?),
                    colour: _returnColour(f['r_5y'] as num?)),
                _Metric(label: '10Y', value: _pct(f['r_10y'] as num?),
                    colour: _returnColour(f['r_10y'] as num?)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('Returns beyond 1 year are annualised (CAGR).',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 10)),

        const SizedBox(height: 18),

        // ---- Fund facts ----
        const _SectionLabel('FUND FACTS'),
        _FactBox(rows: [
          ('AUM', _aum(f['aum'] as num?), _rankText(ranks['aum'])),
          ('Expense ratio', _pct(f['expense_ratio'] as num?),
              _rankText(ranks['expense_ratio'])),
          ('Benchmark', '${f['benchmark'] ?? '—'}', null),
          ('Inception', '${f['inception'] ?? '—'}', null),
          ('Fund type', '${f['fund_type'] ?? '—'}', null),
          ('52-week range',
              f['nav_52w_low'] == null
                  ? '—'
                  : '₹${_plain(f['nav_52w_low'] as num?)} – '
                      '₹${_plain(f['nav_52w_high'] as num?)}',
              null),
        ]),

        // ---- Risk ----
        if (f['sharpe'] != null || f['std_dev'] != null) ...[
          const SizedBox(height: 18),
          const _SectionLabel('RISK & RATIOS'),
          _FactBox(rows: [
            ('Sharpe', _plain(f['sharpe'] as num?), _rankText(ranks['sharpe'])),
            ('Sortino', _plain(f['sortino'] as num?), null),
            ('Alpha', _plain(f['alpha'] as num?), null),
            ('Beta', _plain(f['beta'] as num?), null),
            ('Std deviation', _pct(f['std_dev'] as num?), null),
          ]),
          const SizedBox(height: 6),
          Text(
            'Sharpe measures return per unit of risk — higher is better. Beta '
            'above 1 means the fund swings more than its benchmark.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5),
                fontSize: 10,
                height: 1.4),
          ),
        ],

        // ---- Portfolio ----
        if (f['pct_large'] != null ||
            f['pe'] != null ||
            f['stocks'] != null) ...[
          const SizedBox(height: 18),
          const _SectionLabel('PORTFOLIO'),
          if (f['pct_large'] != null) _MarketCapBar(fund: f),
          _FactBox(rows: [
            ('Holdings',
                f['stocks'] == null
                    ? '—'
                    : '${(f['stocks'] as num).round()} stocks',
                null),
            ('PE ratio', _plain(f['pe'] as num?), null),
            ('PB ratio', _plain(f['pb'] as num?), null),
            ('Turnover', _pct(f['turnover'] as num?), null),
            ('Avg market cap', _aum(f['avg_mcap'] as num?), null),
            ('Top sector', '${f['top_sector'] ?? '—'}', null),
          ]),
        ],

        // ---- Debt-specific ----
        if (f['ytm'] != null || f['avg_maturity'] != null) ...[
          const SizedBox(height: 18),
          const _SectionLabel('DEBT PROFILE'),
          _FactBox(rows: [
            ('Yield to maturity', _pct(f['ytm'] as num?), null),
            ('Average maturity',
                f['avg_maturity'] == null
                    ? '—'
                    : '${_plain(f['avg_maturity'] as num?, dp: 1)} yrs',
                null),
            ('Modified duration',
                f['mod_duration'] == null
                    ? '—'
                    : '${_plain(f['mod_duration'] as num?, dp: 1)} yrs',
                null),
          ]),
        ],

        // ---- Exit load ----
        if (f['exit_load'] != null) ...[
          const SizedBox(height: 18),
          const _SectionLabel('EXIT LOAD'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${f['exit_load']}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.4)),
          ),
        ],

        // ---- Peers ----
        if (peers.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SectionLabel('OTHERS IN THIS CATEGORY'),
          for (final p in peers.take(6))
            () {
              final peer = (p as Map).cast<String, dynamic>();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(_shortName('${peer['name']}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.85),
                              fontSize: 11)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(_pct(peer['r_3y'] as num?),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: _returnColour(peer['r_3y'] as num?),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(_aum(peer['aum'] as num?),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.7),
                              fontSize: 10.5)),
                    ),
                  ],
                ),
              );
            }(),
        ],

        const SizedBox(height: 16),
        _aiAnalysisCard(),
        const SizedBox(height: 16),
        Text(
          'Regular plan figures. Direct plans of the same scheme have a lower '
          'expense ratio and higher returns. Metrics are from a monthly '
          'research snapshot; NAV refreshes daily from AMFI where the scheme '
          'could be matched.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.5),
              fontSize: 10,
              height: 1.45),
        ),
      ],
    );
  }

  Widget _aiAnalysisCard() {
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

  String? _rankText(dynamic rank) {
    if (rank is! Map) return null;
    return '#${rank['rank']} of ${rank['of']}';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(text,
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.8),
              fontSize: 9.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _FactBox extends StatelessWidget {
  const _FactBox({required this.rows});

  /// (label, value, optional rank badge)
  final List<(String, String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (label, value, rank) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(label,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.8),
                            fontSize: 11.5)),
                  ),
                  if (rank != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Brand.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(rank,
                          style: const TextStyle(
                              color: Brand.gold,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  Expanded(
                    flex: 4,
                    child: Text(value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Large/mid/small split as a single proportional bar.
class _MarketCapBar extends StatelessWidget {
  const _MarketCapBar({required this.fund});

  final Map<String, dynamic> fund;

  @override
  Widget build(BuildContext context) {
    final large = ((fund['pct_large'] as num?) ?? 0).toDouble();
    final mid = ((fund['pct_mid'] as num?) ?? 0).toDouble();
    final small = ((fund['pct_small'] as num?) ?? 0).toDouble();
    final total = large + mid + small;
    if (total <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (large > 0)
                    Expanded(
                        flex: (large * 10).round(),
                        child: Container(color: Brand.gold)),
                  if (mid > 0)
                    Expanded(
                        flex: (mid * 10).round(),
                        child: Container(color: Brand.green)),
                  if (small > 0)
                    Expanded(
                        flex: (small * 10).round(),
                        child: Container(color: Brand.mint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _CapLegend(colour: Brand.gold, label: 'Large', pct: large),
              const SizedBox(width: 14),
              _CapLegend(colour: Brand.green, label: 'Mid', pct: mid),
              const SizedBox(width: 14),
              _CapLegend(colour: Brand.mint, label: 'Small', pct: small),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapLegend extends StatelessWidget {
  const _CapLegend({
    required this.colour,
    required this.label,
    required this.pct,
  });

  final Color colour;
  final String label;
  final double pct;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration:
              BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text('$label ${pct.toStringAsFixed(0)}%',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.75), fontSize: 10)),
      ],
    );
  }
}

// ===========================================================================
// SEARCH
// ===========================================================================

class _FundSearchSheet extends StatefulWidget {
  const _FundSearchSheet();

  @override
  State<_FundSearchSheet> createState() => _FundSearchSheetState();
}

class _FundSearchSheetState extends State<_FundSearchSheet> {
  final _ctrl = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() => _error = 'Type at least 2 characters');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await ApiService.searchFundDb(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _error = 'No funds matched "$q"';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: Brand.paper),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search 2,000+ funds by name',
                  hintStyle:
                      TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.search, color: Brand.mint),
                  suffixIcon: _searching
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
                              color: Brand.gold),
                          onPressed: _search,
                        ),
                  filled: true,
                  fillColor: Brand.fern.withValues(alpha: 0.35),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Brand.mint.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Brand.gold),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 12)),
              ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final f = (_results[i] as Map).cast<String, dynamic>();
                  return _FundCard(fund: f, rank: i + 1, sort: 'aum');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// ERROR
// ===========================================================================

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
            Icon(Icons.cloud_off,
                size: 38, color: Brand.mint.withValues(alpha: 0.5)),
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
