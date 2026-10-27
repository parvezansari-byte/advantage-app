// lib/widgets/watchlist_card.dart
// Your watchlist on the Markets screen: stocks you pick, with live price and day change.
// The list is saved on this phone. Prices refresh every 20 seconds while the screen is open.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../screens/stock_screen.dart';
import '../services/api_service.dart';

class WatchlistCard extends StatefulWidget {
  const WatchlistCard({super.key});

  @override
  State<WatchlistCard> createState() => _WatchlistCardState();
}

class _Quote {
  final String symbol;
  final double price;
  final double? change, pct;
  final bool realtime;
  _Quote(this.symbol, this.price, this.change, this.pct, this.realtime);
}

class _WatchlistCardState extends State<WatchlistCard> {
  static const _key = 'watchlist_symbols';
  static const _max = 25;
  static List<String>? _universe; // all NSE symbols, loaded once for the search box

  List<String> _symbols = [];
  final Map<String, _Quote> _quotes = {};
  bool _ready = false;
  bool _loading = false;
  bool _marketOpen = false;
  String _asOf = '';
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _symbols = prefs.getStringList(_key) ?? [];
    } catch (_) {}
    if (!mounted) return;
    setState(() => _ready = true);
    await _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh(silent: true));
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _symbols);
    } catch (_) {}
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_symbols.isEmpty) return;
    if (!silent) setState(() => _loading = true);
    try {
      final r = await http
          .get(Uri.parse(
              '${ApiService.baseUrl}/market/quotes?symbols=${Uri.encodeQueryComponent(_symbols.join(','))}'))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final fresh = <String, _Quote>{};
      for (final q in (d['quotes'] as List? ?? const [])) {
        final m = q as Map<String, dynamic>;
        fresh['${m['symbol']}'] = _Quote(
          '${m['symbol']}',
          (m['price'] as num).toDouble(),
          (m['change'] as num?)?.toDouble(),
          (m['change_pct'] as num?)?.toDouble(),
          m['realtime'] == true,
        );
      }
      if (!mounted) return;
      setState(() {
        _quotes
          ..clear()
          ..addAll(fresh);
        _marketOpen = d['market_open'] == true;
        _asOf = '${d['as_of'] ?? ''}';
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = _quotes.isEmpty
            ? 'Could not load prices. Pull down to retry.'
            : 'Showing the last prices received');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    _universe ??= await ApiService.getStockList().catchError((_) => <String>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.vault,
      builder: (_) => _AddSheet(universe: _universe ?? const [], have: _symbols),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    if (_symbols.length >= _max) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watchlist is full (25 stocks)')));
      return;
    }
    setState(() => _symbols = [..._symbols, picked]);
    await _save();
    _refresh();
  }

  Future<void> _remove(String s) async {
    setState(() {
      _symbols = _symbols.where((x) => x != s).toList();
      _quotes.remove(s);
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('WATCHLIST',
                  style: TextStyle(
                      color: Brand.gold,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.bold)),
              Row(children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.gold)),
                  ),
                InkWell(
                  onTap: _add,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(children: [
                      Icon(Icons.add, size: 16, color: Brand.gold),
                      SizedBox(width: 2),
                      Text('Add',
                          style: TextStyle(color: Brand.gold, fontSize: 12)),
                    ]),
                  ),
                ),
              ]),
            ],
          ),
          if (_symbols.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                  'Add the stocks you follow to see their price and day change here.',
                  style: TextStyle(color: Brand.mint, fontSize: 12.5)),
            )
          else ...[
            if (_asOf.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                    _marketOpen
                        ? 'Market open \u00b7 updated $_asOf'
                        : 'Market closed \u00b7 last close \u00b7 $_asOf',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.65),
                        fontSize: 10.5)),
              ),
            for (final s in _symbols) _row(s),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!,
                    style: const TextStyle(color: Brand.gold, fontSize: 11.5)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(String s) {
    final q = _quotes[s];
    final pct = q?.pct;
    final up = (pct ?? 0) >= 0;
    final color = pct == null ? Brand.mint : (up ? Brand.green : Brand.red);
    return Dismissible(
      key: ValueKey('wl_$s'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Brand.red.withValues(alpha: 0.25),
        child: const Icon(Icons.delete_outline, color: Brand.red),
      ),
      onDismissed: (_) => _remove(s),
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => StockScreen(symbol: s))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Text(s,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold)),
                if (q?.realtime == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Brand.green, shape: BoxShape.circle)),
                  ),
              ]),
            ),
            if (q == null)
              const Text('\u2014', style: TextStyle(color: Brand.mint))
            else ...[
              Text('\u20b9${q.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Brand.paper, fontSize: 13)),
              const SizedBox(width: 10),
              Container(
                width: 70,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                    pct == null
                        ? '\u2014'
                        : '${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  final List<String> universe;
  final List<String> have;
  const _AddSheet({required this.universe, required this.have});

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toUpperCase();
    final matches = q.isEmpty
        ? <String>[]
        : widget.universe
            .where((s) => s.contains(q) && !widget.have.contains(s))
            .take(30)
            .toList()
          ..sort((a, b) {
            final aw = a.startsWith(q) ? 0 : 1;
            final bw = b.startsWith(q) ? 0 : 1;
            return aw != bw ? aw - bw : a.compareTo(b);
          });
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add to watchlist',
              style: TextStyle(
                  color: Brand.gold, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Brand.paper),
            decoration: const InputDecoration(
              hintText: 'Search a symbol, e.g. RELIANCE',
              hintStyle: TextStyle(color: Brand.mint),
              prefixIcon: Icon(Icons.search, color: Brand.mint),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (widget.universe.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Could not load the stock list. Type a symbol and tap Add.',
                  style: TextStyle(color: Brand.mint.withValues(alpha: 0.8), fontSize: 12)),
            ),
          if (widget.universe.isEmpty && q.isNotEmpty)
            ListTile(
              dense: true,
              title: Text('Add $q', style: const TextStyle(color: Brand.paper)),
              onTap: () => Navigator.pop(context, q),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in matches)
                  ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(color: Brand.paper)),
                    onTap: () => Navigator.pop(context, s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
