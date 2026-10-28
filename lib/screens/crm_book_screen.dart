// lib/screens/crm_book_screen.dart
//
// Client book overview from GET /crm/{owner}/book-summary: total value across
// all clients, asset-class split, concentration, top clients and top funds.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmBookScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmBookScreen({super.key, required this.ownerEmail});

  @override
  State<CrmBookScreen> createState() => _CrmBookScreenState();
}

class _CrmBookScreenState extends State<CrmBookScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _d = {};

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
      final res = await http
          .get(Uri.parse(
              '${ApiService.baseUrl}/crm/${widget.ownerEmail}/book-summary'))
          .timeout(const Duration(seconds: 90));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(body is Map ? (body['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(body as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _inr(num v) {
    final neg = v < 0;
    final s = v.abs().round().toString();
    String out;
    if (s.length <= 3) {
      out = s;
    } else {
      var rest = s.substring(0, s.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      out = '${parts.join(',')},${s.substring(s.length - 3)}';
    }
    return '${neg ? '-' : ''}₹$out';
  }

  List<Map<String, dynamic>> _list(String k) => ((_d[k] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Client book',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.red)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    final t = Map<String, dynamic>.from((_d['totals'] ?? {}) as Map);
    final conc = Map<String, dynamic>.from((_d['concentration'] ?? {}) as Map);
    final gain = ((t['gain'] ?? 0) as num).toDouble();
    final gp = t['gain_pct'];
    if ((t['holdings'] ?? 0) == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No client holdings recorded yet.',
              style: TextStyle(color: Brand.mint)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total value',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          Text(_inr((t['value'] ?? 0) as num),
              style: const TextStyle(
                  color: Brand.gold, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${gain >= 0 ? '+' : ''}${_inr(gain)}'
            '${gp == null ? '' : '  (${(gp as num) >= 0 ? '+' : ''}${gp.toStringAsFixed(1)}%)'}'
            '  on ${_inr((t['invested'] ?? 0) as num)} invested',
            style: TextStyle(
                color: gain >= 0 ? Brand.green : Brand.red, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '${t['clients']} of ${t['clients_total']} clients hold funds · '
            '${t['funds']} funds · ${t['holdings']} holdings'
            '${(t['unpriced'] ?? 0) > 0 ? ' · ${t['unpriced']} without a NAV' : ''}',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.8), fontSize: 11),
          ),
        ])),
        _title('Asset classes'),
        _box(Column(children: [
          for (final a in _list('asset_classes'))
            _bar('${a['asset_class']}', (a['share_pct'] ?? 0) as num,
                _inr((a['value'] ?? 0) as num)),
        ])),
        _title('Concentration'),
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv('Largest client', '${conc['top_client_pct'] ?? '–'}% of the book'),
          _kv('Top 5 clients', '${conc['top5_clients_pct'] ?? '–'}%'),
          _kv('Largest fund', '${conc['top_fund_pct'] ?? '–'}%'),
        ])),
        _title('Top clients'),
        _box(Column(children: [
          for (final c in _list('clients'))
            _row('${c['client_name']}',
                '${c['funds']} fund${c['funds'] == 1 ? '' : 's'} · ${c['share_pct']}%',
                _inr((c['value'] ?? 0) as num)),
        ])),
        _title('Top funds'),
        _box(Column(children: [
          for (final f in _list('funds'))
            _row('${f['scheme_name']}',
                '${f['clients']} client${f['clients'] == 1 ? '' : 's'} · ${f['share_pct']}%',
                _inr((f['value'] ?? 0) as num)),
        ])),
      ],
    );
  }

  Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text(s,
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: Brand.mint, fontSize: 13))),
          Text(v, style: const TextStyle(color: Brand.paper, fontSize: 13)),
        ]),
      );

  Widget _bar(String label, num pct, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: Brand.paper, fontSize: 13))),
            Text('$value · ${pct.toStringAsFixed(1)}%',
                style: const TextStyle(color: Brand.mint, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: Brand.vault,
              color: Brand.gold,
            ),
          ),
        ]),
      );

  Widget _row(String title, String sub, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.paper, fontSize: 13)),
              Text(sub,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.8), fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  color: Brand.gold, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}
