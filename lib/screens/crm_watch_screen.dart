// lib/screens/crm_watch_screen.dart
//
// "Review watch": client holdings whose fund has fallen behind its benchmark.
// Data comes from GET /crm/{owner}/review-watch (same verdict as the
// portfolio review). A weekly push tells you when a fund newly slips.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmWatchScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmWatchScreen({super.key, required this.ownerEmail});

  @override
  State<CrmWatchScreen> createState() => _CrmWatchScreenState();
}

class _CrmWatchScreenState extends State<CrmWatchScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _behind = [];
  Map<String, dynamic> _counts = {};

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
              '${ApiService.baseUrl}/crm/${widget.ownerEmail}/review-watch'))
          .timeout(const Duration(seconds: 90));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(body is Map ? (body['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _behind = (body['behind'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _counts = Map<String, dynamic>.from(body['counts'] as Map);
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
    final s = v.round().toString();
    if (s.length <= 3) return '₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }

  String _pp(dynamic v) {
    if (v == null) return '–';
    final d = (v as num).toDouble();
    return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} pp';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Review watch',
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
    final undated = (_counts['undated'] ?? 0) as int;
    final judged = (_counts['judged'] ?? 0) as int;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          _behind.isEmpty
              ? 'No client fund is behind its benchmark right now.'
              : '${_behind.length} holding${_behind.length == 1 ? '' : 's'} behind their benchmark, worst first.',
          style: const TextStyle(
              color: Brand.paper, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Checked $judged holding${judged == 1 ? '' : 's'}'
          '${undated > 0 ? '. $undated skipped: add a purchase date to include them' : ''}.',
          style: TextStyle(color: Brand.mint.withValues(alpha: 0.8), fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final b in _behind) _card(b),
      ],
    );
  }

  Widget _card(Map<String, dynamic> b) {
    final cagr = b['cagr_pct'] ?? b['abs_pct'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${b['client_name']}',
                style: const TextStyle(
                    color: Brand.gold, fontWeight: FontWeight.bold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: Brand.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: const Text('Behind',
                style: TextStyle(color: Brand.red, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('${b['scheme_name']}',
            style: const TextStyle(color: Brand.paper, fontSize: 13)),
        const SizedBox(height: 8),
        Text(
          '${_inr(b['invested'] as num)} → ${_inr(b['current'] as num)}'
          '${cagr == null ? '' : '  ·  ${(cagr as num).toStringAsFixed(1)}% a year'}',
          style: const TextStyle(color: Brand.mint, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'vs benchmark ${_pp(b['vs_benchmark_pp'])}   ·   vs category ${_pp(b['vs_category_pp'])}',
          style: const TextStyle(color: Brand.red, fontSize: 12),
        ),
        if ((b['why'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${b['why']}',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.8), fontSize: 11)),
        ],
      ]),
    );
  }
}
