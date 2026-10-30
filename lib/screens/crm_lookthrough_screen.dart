// lib/screens/crm_lookthrough_screen.dart
//
// "What does this client really own?" Opens up each fund and adds up the
// rupee exposure to individual stocks and sectors across all of them, and lists
// pairs of funds that mostly hold the same stocks.
// Data: GET /crm/{owner}/clients/{id}/lookthrough

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmLookthroughScreen extends StatefulWidget {
  final String ownerEmail;
  final int clientId;
  final String clientName;

  /// When given, these [{name, current}] holdings are analysed through
  /// POST /portfolio/lookthrough instead of loading a client's saved holdings.
  final List<Map<String, dynamic>>? holdings;

  const CrmLookthroughScreen(
      {super.key,
      this.ownerEmail = '',
      this.clientId = 0,
      required this.clientName,
      this.holdings});

  @override
  State<CrmLookthroughScreen> createState() => _CrmLookthroughScreenState();
}

class _CrmLookthroughScreenState extends State<CrmLookthroughScreen> {
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
      final res = widget.holdings != null
          ? await http
              .post(Uri.parse('${ApiService.baseUrl}/portfolio/lookthrough'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'holdings': widget.holdings}))
              .timeout(const Duration(seconds: 90))
          : await http
              .get(Uri.parse('${ApiService.baseUrl}/crm/${widget.ownerEmail}'
                  '/clients/${widget.clientId}/lookthrough'))
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

  List<Map<String, dynamic>> _l(String k) => ((_d[k] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: Text('What ${widget.clientName == 'Your portfolio' ? 'you own' : widget.clientName + ' owns'}',
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 17)),
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
    final total = (_d['total_value'] ?? 0) as num;
    if (total == 0) {
      return const Center(
          child: Text('No priced holdings to analyse.',
              style: TextStyle(color: Brand.mint)));
    }
    final stocks = _l('top_stocks');
    final sectors = _l('sectors');
    final pairs = _l('overlapping_pairs');
    final skipped = _l('not_analysed');
    final coverage = (_d['coverage_pct'] ?? 0) as num;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_inr(total)} portfolio',
              style: const TextStyle(
                  color: Brand.gold, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${_d['funds_analysed']} funds opened up · ${coverage.toStringAsFixed(0)}% of the value analysed'
            ' · ${_d['stocks_total']} different stocks',
            style: const TextStyle(color: Brand.mint, fontSize: 12),
          ),
        ])),
        if (pairs.isNotEmpty) ...[
          _title('Funds that hold the same stocks'),
          for (final p in pairs)
            _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['overlap_pct']}% overlap',
                  style: TextStyle(
                      color: (p['overlap_pct'] as num) >= 60
                          ? Brand.red
                          : Brand.gold,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${p['a']}', style: const TextStyle(color: Brand.paper, fontSize: 12)),
              Text('${p['b']}', style: const TextStyle(color: Brand.paper, fontSize: 12)),
            ])),
        ],
        _title('Top stocks across all funds'),
        _box(Column(children: [
          for (final s in stocks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Brand.paper, fontSize: 13)),
                    Text(
                        'in ${s['funds']} fund${s['funds'] == 1 ? '' : 's'}${s['sector'] == null ? '' : ' · ${s['sector']}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${s['pct_of_portfolio']}%',
                      style: TextStyle(
                          color: s['flag'] == true ? Brand.gold : Brand.paper,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(_inr((s['value'] ?? 0) as num),
                      style: const TextStyle(color: Brand.mint, fontSize: 11)),
                ]),
              ]),
            ),
        ])),
        _title('Sectors'),
        _box(Column(children: [
          for (final s in sectors)
            _bar('${s['sector']}', (s['pct_of_portfolio'] ?? 0) as num),
        ])),
        if (skipped.isNotEmpty) ...[
          _title('Not analysed'),
          _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final s in skipped)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                      child: Text('${s['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Brand.paper, fontSize: 12))),
                  Text(_inr((s['value'] ?? 0) as num),
                      style: const TextStyle(color: Brand.mint, fontSize: 12)),
                ]),
              ),
            const SizedBox(height: 4),
            Text(
                'Debt, gold and funds missing from the holdings snapshot are not opened up.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
          ])),
        ],
        const SizedBox(height: 12),
        Text('${_d['note'] ?? ''}',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _box(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(s,
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _bar(String label, num pct) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.paper, fontSize: 13))),
            Text('${pct.toStringAsFixed(1)}%',
                style: const TextStyle(color: Brand.mint, fontSize: 12)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 5,
              backgroundColor: Brand.vault,
              color: Brand.gold,
            ),
          ),
        ]),
      );
}
