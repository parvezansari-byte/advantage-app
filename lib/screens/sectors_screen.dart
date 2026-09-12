// lib/screens/sectors_screen.dart
// ---------------------------------------------------------------------------
// Sector performance: NSE sector indices with 1-day and 1-month returns
// always visible, plus a switchable long window (1Y / 2Y / 3Y / 5Y).
//
// Every return is computed server-side from close prices, so all windows share
// one basis. A sector too young for a window shows "—" rather than a guess.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _level(num? v) {
  if (v == null) return '—';
  final n = v.round();
  final s = n.abs().toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final buf = <String>[];
  while (rest.length > 2) {
    buf.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) buf.insert(0, rest);
  return '${buf.join(',')},$last3';
}

String _pct(num? v) {
  if (v == null) return '—';
  final sign = v >= 0 ? '+' : '';
  return '$sign${v.toStringAsFixed(2)}%';
}

Color _pctColour(num? v) {
  if (v == null) return Brand.mint;
  if (v > 0) return Brand.green;
  if (v < 0) return Brand.red;
  return Brand.mint;
}

// ===========================================================================
// SCREEN
// ===========================================================================

class SectorsScreen extends StatefulWidget {
  const SectorsScreen({super.key});

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends State<SectorsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _compare = '1y';

  /// Cached per comparison period — switching back and forth shouldn't refetch.
  final Map<String, Map<String, dynamic>> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && _cache.containsKey(_compare)) {
      setState(() => _data = _cache[_compare]);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getSectors(compare: _compare);
      if (!mounted) return;
      setState(() {
        _data = d;
        _cache[_compare] = d;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectors = [
      for (final s in (_data?['sectors'] as List? ?? []))
        (s as Map).cast<String, dynamic>()
    ];
    final summary =
        (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Sector Performance',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: () => _load(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Brand.gold,
        backgroundColor: Brand.fern,
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
          children: [
            Text('NSE sector indices, ranked by 1-month return',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5)),
            const SizedBox(height: 14),

            // ---- Compare period ----
            Row(
              children: [
                Text('Compare',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.75),
                        fontSize: 11.5)),
                const SizedBox(width: 10),
                for (final p in ['1y', '2y', '3y', '5y'])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _compare = p);
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _compare == p
                              ? Brand.gold.withValues(alpha: 0.18)
                              : Brand.fern.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _compare == p
                                ? Brand.gold
                                : Brand.mint.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(p.toUpperCase(),
                            style: TextStyle(
                                color:
                                    _compare == p ? Brand.gold : Brand.mint,
                                fontSize: 11.5,
                                fontWeight: _compare == p
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_error != null)
              _SectorError(message: _error!, onRetry: () => _load(force: true))
            else ...[
              // ---- Breadth ----
              if (summary.isNotEmpty) _BreadthBar(summary: summary),
              const SizedBox(height: 14),

              // ---- Cards ----
              for (var i = 0; i < sectors.length; i++)
                _SectorCard(
                  sector: sectors[i],
                  rank: i + 1,
                  comparePeriod: '${_data?['compare_period'] ?? ''}',
                ),

              const SizedBox(height: 14),
              Text(
                'Returns are computed from index close prices. 1M is roughly '
                '22 trading sessions; longer windows use the nearest close at '
                'or before each anniversary.',
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
// BREADTH
// ===========================================================================

class _BreadthBar extends StatelessWidget {
  const _BreadthBar({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final up = (summary['advancing'] as int?) ?? 0;
    final down = (summary['declining'] as int?) ?? 0;
    final total = up + down;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$up advancing',
                  style: const TextStyle(
                      color: Brand.green,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
              Text('$down declining',
                  style: const TextStyle(
                      color: Brand.red,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (up > 0)
                    Expanded(flex: up, child: Container(color: Brand.green)),
                  if (down > 0)
                    Expanded(flex: down, child: Container(color: Brand.red)),
                ],
              ),
            ),
          ),
          if (summary['best'] != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text('Leading: ${summary['best']}',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.8),
                          fontSize: 11)),
                ),
                Expanded(
                  child: Text('Lagging: ${summary['worst']}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.8),
                          fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// SECTOR CARD
// ===========================================================================

class _SectorCard extends StatelessWidget {
  const _SectorCard({
    required this.sector,
    required this.rank,
    required this.comparePeriod,
  });

  final Map<String, dynamic> sector;
  final int rank;
  final String comparePeriod;

  @override
  Widget build(BuildContext context) {
    final oneMonth = sector['return_1m'] as num?;
    final accent = _pctColour(oneMonth);

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            // Rank + accent stripe
            Container(
              width: 3,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${sector['name']}',
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(_level(sector['level'] as num?),
                      style: const TextStyle(
                          color: Brand.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ReturnCell(label: '1D', value: sector['return_1d'] as num?),
                  _ReturnCell(label: '1M', value: oneMonth),
                  _ReturnCell(
                      label: comparePeriod.isEmpty ? '—' : comparePeriod,
                      value: sector['return_compare'] as num?),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnCell extends StatelessWidget {
  const _ReturnCell({required this.label, required this.value});

  final String label;
  final num? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.65),
                fontSize: 9.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(_pct(value),
            style: TextStyle(
                color: _pctColour(value),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ===========================================================================
// ERROR
// ===========================================================================

class _SectorError extends StatelessWidget {
  const _SectorError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.cloud_off, color: Brand.red, size: 28),
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
