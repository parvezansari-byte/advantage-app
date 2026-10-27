// lib/widgets/market_movers.dart
// Top gainers and losers for an index, on the Markets screen. Tap a row to open the stock.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../screens/stock_screen.dart';
import '../services/api_service.dart';

class MarketMovers extends StatefulWidget {
  const MarketMovers({super.key});

  @override
  State<MarketMovers> createState() => _MarketMoversState();
}

class _Mover {
  final String symbol, name;
  final double price, pct;
  _Mover(this.symbol, this.name, this.price, this.pct);
}

class _MarketMoversState extends State<MarketMovers> {
  static const _indices = {
    'Nifty 500': 'NIFTY 500',
    'Nifty 50': 'NIFTY 50',
    'Midcap': 'NIFTY MIDCAP 100',
    'Smallcap': 'NIFTY SMALLCAP 100',
  };

  String _label = 'Nifty 500';
  bool _gainers = true;
  List<_Mover> _up = [];
  List<_Mover> _down = [];
  String _asOf = '';
  bool _stale = false;
  bool _loading = true;
  bool _failed = false;
  int _requestId = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<_Mover> _rows(dynamic list) => [
        for (final r in (list as List? ?? const []))
          _Mover(
            '${(r as Map)['symbol']}',
            '${r['name'] ?? r['symbol']}',
            (r['price'] as num?)?.toDouble() ?? 0,
            (r['change_pct'] as num?)?.toDouble() ?? 0,
          ),
      ];

  Future<void> _load({bool silent = false}) async {
    final id = ++_requestId;
    if (!silent) setState(() => _loading = true);
    try {
      final idx = Uri.encodeQueryComponent(_indices[_label]!);
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/market/movers?index=$idx&n=10'))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted || id != _requestId) return;
      setState(() {
        _up = _rows(d['gainers']);
        _down = _rows(d['losers']);
        _asOf = '${d['as_of'] ?? ''}';
        _stale = d['stale'] == true;
        _failed = false;
      });
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() => _failed = _up.isEmpty && _down.isEmpty);
      }
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final rows = _gainers ? _up : _down;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOP MOVERS',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            Text(_stale ? 'delayed' : _asOf,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in _indices.keys)
            _chip(l, l == _label, () {
              if (l == _label) return;
              setState(() {
                _label = l;
                _up = [];
                _down = [];
              });
              _load();
            }),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _tab('Gainers', _gainers, Brand.green, () => setState(() => _gainers = true))),
          const SizedBox(width: 8),
          Expanded(child: _tab('Losers', !_gainers, Brand.red, () => setState(() => _gainers = false))),
        ]),
        const SizedBox(height: 8),
        if (_loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold))),
          )
        else if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nothing to show yet',
                style: TextStyle(color: Brand.mint, fontSize: 12)),
          )
        else
          ...rows.map(_row),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on
                ? Brand.gold.withValues(alpha: 0.18)
                : Brand.fern.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on ? Brand.gold : Colors.transparent, width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Brand.gold : Brand.mint,
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  Widget _tab(String label, bool on, Color color, VoidCallback tap) =>
      GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: on ? color : Brand.mint.withValues(alpha: 0.25)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? color : Brand.mint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      );

  Widget _row(_Mover m) {
    final up = m.pct >= 0;
    final color = up ? Brand.green : Brand.red;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockScreen(symbol: m.symbol)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.symbol,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold)),
                Text(m.name,
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
              Text('\u20b9${m.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Brand.paper, fontSize: 13)),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('${up ? '+' : ''}${m.pct.toStringAsFixed(2)}%',
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
