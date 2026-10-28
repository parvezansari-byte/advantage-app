// lib/widgets/market_pulse.dart
// FII / DII flows and market breadth (advances vs declines) for the Markets screen.
// Each half loads on its own, so one failing never hides the other.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../screens/index_stocks_screen.dart';
import '../services/api_service.dart';

class MarketPulse extends StatefulWidget {
  const MarketPulse({super.key});

  @override
  State<MarketPulse> createState() => _MarketPulseState();
}

class _Flow {
  final String who;
  final double? buy, sell, net;
  _Flow(this.who, this.buy, this.sell, this.net);
}

class _Breadth {
  final String name;
  final int up, down, flat;
  _Breadth(this.name, this.up, this.down, this.flat);
  int get total => up + down + flat;
}

class _MarketPulseState extends State<MarketPulse> {
  List<_Flow> _flows = [];
  String _flowDate = '';
  String? _flowError;
  bool _flowLoading = true;

  List<_Breadth> _breadth = [];
  String _asOf = '';
  bool _stale = false;
  bool _breadthLoading = true;
  bool _breadthFailed = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    _loadFlows();
    _loadBreadth();
  }

  double? _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

  Future<void> _loadFlows() async {
    try {
      final d = await ApiService.getFiiDii();
      final rows = <_Flow>[];
      for (final r in (d['flows'] as List? ?? const [])) {
        final m = r as Map<String, dynamic>;
        rows.add(_Flow('${m['who']}', _n(m['buy']), _n(m['sell']), _n(m['net'])));
      }
      if (!mounted) return;
      setState(() {
        _flows = rows;
        _flowDate = '${d['date'] ?? ''}';
        _flowError = rows.isEmpty ? 'No flow data yet' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _flowError = '$e'.replaceFirst('ApiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _flowLoading = false);
    }
  }

  Future<void> _loadBreadth() async {
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/market/breadth'))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) throw Exception('status ${r.statusCode}');
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final rows = <_Breadth>[
        for (final i in (d['indices'] as List? ?? const []))
          _Breadth(
            '${(i as Map)['name']}',
            (i['advances'] as num?)?.toInt() ?? 0,
            (i['declines'] as num?)?.toInt() ?? 0,
            (i['unchanged'] as num?)?.toInt() ?? 0,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _breadth = rows;
        _asOf = '${d['as_of'] ?? ''}';
        _stale = d['stale'] == true;
        _breadthFailed = rows.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _breadthFailed = _breadth.isEmpty);
    } finally {
      if (mounted) setState(() => _breadthLoading = false);
    }
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _flowCard(),
        if (!_breadthFailed) ...[
          const SizedBox(height: 10),
          _breadthCard(),
        ],
      ],
    );
  }

  Widget _head(String title, String right) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Brand.gold,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold)),
          if (right.isNotEmpty)
            Text(right,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
        ],
      );

  Widget _shell(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _flowCard() {
    if (_flowLoading && _flows.isEmpty) {
      return _shell(const SizedBox(
          height: 60,
          child: Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.gold)))));
    }
    if (_flows.isEmpty) {
      return _shell(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('FII / DII FLOWS', ''),
          const SizedBox(height: 8),
          Text(_flowError ?? 'Not available right now',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
        ],
      ));
    }
    return _shell(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('FII / DII FLOWS', _flowDate),
        const SizedBox(height: 12),
        Row(children: [
          for (final who in const ['FII', 'DII']) ...[
            Expanded(child: _flowBox(who)),
            if (who == 'FII') const SizedBox(width: 10),
          ],
        ]),
      ],
    ));
  }

  Widget _flowBox(String who) {
    final f = _flows.where((r) => r.who == who).toList();
    final row = f.isEmpty ? null : f.first;
    final net = row?.net;
    final up = (net ?? 0) >= 0;
    final color = net == null ? Brand.mint : (up ? Brand.green : Brand.red);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.vault.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who == 'FII' ? 'FII / FPI' : 'DII',
              style: const TextStyle(color: Brand.mint, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(net == null ? '\u2014' : '${up ? '+' : '-'}${_cr(net.abs())}',
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(net == null ? '' : (up ? 'net bought' : 'net sold'),
              style: TextStyle(color: color, fontSize: 11)),
          if (row?.buy != null && row?.sell != null) ...[
            const SizedBox(height: 6),
            Text('Buy ${_cr(row!.buy!)}  \u00b7  Sell ${_cr(row.sell!)}',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _breadthCard() {
    if (_breadthLoading && _breadth.isEmpty) return const SizedBox.shrink();
    return _shell(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('MARKET BREADTH', _stale ? 'delayed' : _asOf),
        const SizedBox(height: 4),
        Text('Stocks rising vs falling today \u00b7 tap to see the stocks',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
        const SizedBox(height: 10),
        for (final b in _breadth) _breadthRow(b),
      ],
    ));
  }

  void _open(_Breadth b, String filter) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => IndexStocksScreen(
                index: b.name.toUpperCase(), initialFilter: filter)),
      );

  Widget _breadthRow(_Breadth b) {
    final total = b.total == 0 ? 1 : b.total;
    final upPct = (100 * b.up / total).round();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(b, 'all'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(b.name,
                    style: const TextStyle(color: Brand.paper, fontSize: 12.5)),
              ),
              GestureDetector(
                onTap: () => _open(b, 'up'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text('${b.up} up',
                      style: const TextStyle(
                          color: Brand.green,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const Text('\u00b7', style: TextStyle(color: Brand.mint, fontSize: 11)),
              GestureDetector(
                onTap: () => _open(b, 'down'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Text('${b.down} down',
                      style: const TextStyle(
                          color: Brand.red,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              Text('\u00b7 $upPct% rising',
                  style: const TextStyle(color: Brand.mint, fontSize: 11)),
              const Icon(Icons.chevron_right, size: 16, color: Brand.mint),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(children: [
                  if (b.up > 0)
                    Expanded(flex: b.up, child: Container(color: Brand.green)),
                  if (b.flat > 0)
                    Expanded(
                        flex: b.flat,
                        child: Container(color: Colors.grey.shade600)),
                  if (b.down > 0)
                    Expanded(flex: b.down, child: Container(color: Brand.red)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 12,345.67 -> "\u20b912,345.67 Cr" with Indian digit grouping.
  String _cr(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final s = parts[0];
    String grouped;
    if (s.length <= 3) {
      grouped = s;
    } else {
      var rest = s.substring(0, s.length - 3);
      final out = <String>[];
      while (rest.length > 2) {
        out.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) out.insert(0, rest);
      grouped = '${out.join(',')},${s.substring(s.length - 3)}';
    }
    return '\u20b9$grouped.${parts[1]} Cr';
  }
}
