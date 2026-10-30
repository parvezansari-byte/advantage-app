// lib/screens/crm_risk_mismatch_screen.dart
//
// Clients whose actual equity share is far from what their saved risk profile
// calls for. Data: GET /crm/{owner}/risk-mismatch. A prompt for a conversation, not a verdict.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmRiskMismatchScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmRiskMismatchScreen({super.key, required this.ownerEmail});

  @override
  State<CrmRiskMismatchScreen> createState() => _CrmRiskMismatchScreenState();
}

class _CrmRiskMismatchScreenState extends State<CrmRiskMismatchScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _flagged = [];
  Map<String, dynamic> _counts = {};
  String _note = '';

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
              '${ApiService.baseUrl}/crm/${widget.ownerEmail}/risk-mismatch'))
          .timeout(const Duration(seconds: 90));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _flagged = (j['flagged'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _counts = Map<String, dynamic>.from(j['counts'] as Map);
        _note = '${j['note'] ?? ''}';
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
    final s = v.abs().round().toString();
    if (s.length <= 3) return '₹$s';
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},${s.substring(s.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Risk mismatch',
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
    final noProfile = (_counts['no_risk_profile'] ?? 0) as int;
    final inLine = (_counts['in_line'] ?? 0) as int;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          _flagged.isEmpty
              ? 'No client is far from their risk profile.'
              : '${_flagged.length} client${_flagged.length == 1 ? '' : 's'} far from their risk profile, biggest gap first.',
          style: const TextStyle(
              color: Brand.paper, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '$inLine in line'
          '${noProfile > 0 ? ' · $noProfile without a risk profile (set one from the client page)' : ''}.',
          style: TextStyle(color: Brand.mint.withValues(alpha: 0.8), fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final f in _flagged) _card(f),
        const SizedBox(height: 8),
        Text(_note,
            style: TextStyle(color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final a = Map<String, dynamic>.from(f['actual'] as Map);
    final t = Map<String, dynamic>.from(f['target'] as Map);
    final gap = (f['equity_gap_pp'] ?? 0) as num;
    final aggressive = gap > 0;
    final color = aggressive ? Brand.red : Brand.gold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${f['client_name']}',
                style: const TextStyle(
                    color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          Text('${f['direction']}',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 2),
        Text(
            '${'${f['profile']}'.toLowerCase()} profile · ${_inr((f['value'] ?? 0) as num)} in equity, hybrid and debt funds',
            style: TextStyle(color: Brand.mint.withValues(alpha: 0.8), fontSize: 11)),
        const SizedBox(height: 8),
        _mixRow('Now', a),
        _mixRow('Model', t),
        const SizedBox(height: 4),
        Text('Equity is ${gap.abs().toStringAsFixed(0)} points ${aggressive ? 'above' : 'below'} the model.',
            style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }

  Widget _mixRow(String label, Map<String, dynamic> m) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 48,
              child: Text(label,
                  style: const TextStyle(color: Brand.mint, fontSize: 12))),
          Expanded(
            child: Text(
                'Equity ${(m['equity'] as num).toStringAsFixed(0)}%  ·  Hybrid ${(m['hybrid'] as num).toStringAsFixed(0)}%  ·  Debt ${(m['debt'] as num).toStringAsFixed(0)}%',
                style: const TextStyle(color: Brand.paper, fontSize: 12.5)),
          ),
        ]),
      );
}
