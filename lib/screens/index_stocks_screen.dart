// lib/screens/index_stocks_screen.dart
// Every stock in an index with price and day change. Opens from the market breadth card.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../services/api_service.dart';
import 'stock_screen.dart';

class IndexStocksScreen extends StatefulWidget {
  final String index; // e.g. NIFTY 50
  final String initialFilter; // all | up | down
  const IndexStocksScreen(
      {super.key, required this.index, this.initialFilter = 'all'});

  @override
  State<IndexStocksScreen> createState() => _IndexStocksScreenState();
}

class _Stock {
  final String symbol, name;
  final double price, pct;
  _Stock(this.symbol, this.name, this.price, this.pct);
}

class _IndexStocksScreenState extends State<IndexStocksScreen> {
  List<_Stock> _all = [];
  late String _filter = widget.initialFilter;
  String _sort = 'best'; // best | worst | name
  String _query = '';
  int _rising = 0, _falling = 0, _flat = 0;
  String _asOf = '';
  bool _stale = false;
  String _note = '';
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
      final q = Uri.encodeQueryComponent(widget.index);
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/market/index-stocks?index=$q'))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) {
        var why = 'Could not load the stocks (${r.statusCode}).';
        try {
          why = '${(jsonDecode(r.body) as Map)['detail'] ?? why}';
        } catch (_) {}
        throw Exception(why);
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final rows = <_Stock>[
        for (final s in (d['stocks'] as List? ?? const []))
          _Stock(
            '${(s as Map)['symbol']}',
            '${s['name'] ?? s['symbol']}',
            (s['price'] as num?)?.toDouble() ?? 0,
            (s['change_pct'] as num?)?.toDouble() ?? 0,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _all = rows;
        _rising = (d['rising'] as num?)?.toInt() ?? 0;
        _falling = (d['falling'] as num?)?.toInt() ?? 0;
        _flat = (d['unchanged'] as num?)?.toInt() ?? 0;
        _asOf = '${d['as_of'] ?? ''}';
        _stale = d['stale'] == true;
        _note = '${d['note'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Stock> get _shown {
    var rows = _all.where((s) {
      if (_filter == 'up' && s.pct <= 0) return false;
      if (_filter == 'down' && s.pct >= 0) return false;
      if (_query.isNotEmpty) {
        final q = _query.toUpperCase();
        if (!s.symbol.contains(q) && !s.name.toUpperCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    if (_sort == 'best') rows.sort((a, b) => b.pct.compareTo(a.pct));
    if (_sort == 'worst') rows.sort((a, b) => a.pct.compareTo(b.pct));
    if (_sort == 'name') rows.sort((a, b) => a.symbol.compareTo(b.symbol));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: Text(widget.index,
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: _loading && _all.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : (_error != null && _all.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Brand.mint)),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Brand.gold,
                              foregroundColor: Brand.vault),
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Brand.gold,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [
                      Text(
                          '${_stale ? 'Delayed \u00b7 ' : ''}$_asOf \u00b7 ${_all.length} stocks',
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.7),
                              fontSize: 11)),
                      if (_note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_note,
                              style: const TextStyle(
                                  color: Brand.gold, fontSize: 10.5)),
                        ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        _chip('All ${_all.length}', _filter == 'all', Brand.gold,
                            () => setState(() => _filter = 'all')),
                        _chip('Rising $_rising', _filter == 'up', Brand.green,
                            () => setState(() => _filter = 'up')),
                        _chip('Falling $_falling', _filter == 'down', Brand.red,
                            () => setState(() => _filter = 'down')),
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                        style: const TextStyle(color: Brand.paper),
                        decoration: const InputDecoration(
                          hintText: 'Search in this index',
                          hintStyle: TextStyle(color: Brand.mint),
                          prefixIcon: Icon(Icons.search, color: Brand.mint),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Text('Sort',
                            style: TextStyle(color: Brand.mint, fontSize: 11.5)),
                        const SizedBox(width: 8),
                        _chip('Best', _sort == 'best', Brand.gold,
                            () => setState(() => _sort = 'best')),
                        const SizedBox(width: 6),
                        _chip('Worst', _sort == 'worst', Brand.gold,
                            () => setState(() => _sort = 'worst')),
                        const SizedBox(width: 6),
                        _chip('A\u2013Z', _sort == 'name', Brand.gold,
                            () => setState(() => _sort = 'name')),
                      ]),
                      const SizedBox(height: 8),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                              child: Text('No stocks match',
                                  style: TextStyle(color: Brand.mint))),
                        )
                      else
                        ...rows.map(_row),
                      if (_flat > 0 && _filter == 'all')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('$_flat unchanged',
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.6),
                                  fontSize: 11)),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _chip(String label, bool on, Color color, VoidCallback tap) =>
      GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on
                ? color.withValues(alpha: 0.18)
                : Brand.fern.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? color : Colors.transparent),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? color : Brand.mint,
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  Widget _row(_Stock s) {
    final up = s.pct >= 0;
    final color = s.pct == 0 ? Brand.mint : (up ? Brand.green : Brand.red);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => StockScreen(symbol: s.symbol))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.symbol,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold)),
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\u20b9${s.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Brand.paper, fontSize: 13)),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('${up ? '+' : ''}${s.pct.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
