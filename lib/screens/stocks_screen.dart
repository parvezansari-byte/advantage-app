// lib/screens/stocks_screen.dart
//
// Dedicated "Stocks" tab: sector/cap filters, a search box, and a
// scrollable list of the filtered universe below - same pattern as
// FundsScreen, so Stocks and Funds feel like siblings in the nav bar.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'stock_screen.dart';

class StocksScreen extends StatefulWidget {
  const StocksScreen({super.key});

  @override
  State<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends State<StocksScreen> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allStocksDetailed = [];
  List<String> _sectors = [];
  String _sectorFilter = 'All Sectors';
  String _capFilter = 'All Caps';

  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  Future<void> _loadStocks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getStockListDetailed();
      final stocks = (d['stocks'] as List? ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final sectors = (d['sectors'] as List? ?? []).map((e) => '$e').toList();
      if (mounted) {
        setState(() {
          _allStocksDetailed = stocks;
          _sectors = sectors;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toUpperCase();
    return _allStocksDetailed.where((s) {
      final matchesSector =
          _sectorFilter == 'All Sectors' || s['sector'] == _sectorFilter;
      final matchesCap = _capFilter == 'All Caps' || s['cap'] == _capFilter;
      final matchesQuery =
          q.isEmpty || '${s['symbol']}'.toUpperCase().contains(q);
      return matchesSector && matchesCap && matchesQuery;
    }).toList();
  }

  void _openStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockScreen(symbol: s)),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final caps = ['All Caps', 'LARGECAP', 'MIDCAP', 'SMALLCAP', 'ALLEQUITIES'];

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Stocks',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : (_error != null && _allStocksDetailed.isEmpty)
              ? _StocksErrorState(message: _error!, onRetry: _loadStocks)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _Dropdown(
                              value: _sectorFilter,
                              options: ['All Sectors', ..._sectors],
                              onChanged: (v) =>
                                  setState(() => _sectorFilter = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Dropdown(
                              value: _capFilter,
                              options: caps,
                              onChanged: (v) => setState(() => _capFilter = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Brand.paper),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _openStock,
                        decoration: InputDecoration(
                          hintText:
                              'Search ${_allStocksDetailed.length} stocks — e.g. RELIANCE',
                          prefixIcon:
                              const Icon(Icons.search, color: Brand.mint),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Showing ${filtered.length} of ${_allStocksDetailed.length}',
                          style: const TextStyle(
                              color: Brand.mint, fontSize: 12.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No stocks match these filters.',
                                  style: TextStyle(color: Brand.mint)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final s = filtered[i];
                                return Card(
                                  color: Brand.fern.withValues(alpha: 0.35),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text('${s['symbol']}',
                                        style: const TextStyle(
                                            color: Brand.paper,
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        '${s['sector'] ?? 'Other'} · ${s['cap'] ?? ''}',
                                        style: const TextStyle(
                                            color: Brand.mint, fontSize: 12)),
                                    trailing: const Icon(Icons.chevron_right,
                                        color: Brand.mint),
                                    onTap: () => _openStock('${s['symbol']}'),
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

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Brand.fern,
          icon: const Icon(Icons.expand_more, color: Brand.mint, size: 18),
          style: const TextStyle(color: Brand.paper, fontSize: 13.5),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _StocksErrorState extends StatelessWidget {
  const _StocksErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Brand.mint, size: 40),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.paper)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
