// lib/screens/crm_tax_screen.dart
//
// Capital-gains estimate for one client (GET /crm/{owner}/clients/{id}/tax-gains):
// short vs long term, estimated tax if everything were redeemed today, the
// tax-free LTCG headroom, and holdings about to turn long-term.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmTaxScreen extends StatefulWidget {
  final String ownerEmail;
  final int clientId;
  final String clientName;
  const CrmTaxScreen(
      {super.key,
      required this.ownerEmail,
      required this.clientId,
      required this.clientName});

  @override
  State<CrmTaxScreen> createState() => _CrmTaxScreenState();
}

class _CrmTaxScreenState extends State<CrmTaxScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _d = {};
  int _slab = 30;

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
          .get(Uri.parse('${ApiService.baseUrl}/crm/${widget.ownerEmail}'
              '/clients/${widget.clientId}/tax-gains?slab=$_slab'))
          .timeout(const Duration(seconds: 60));
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

  Map<String, dynamic> _m(String k) =>
      Map<String, dynamic>.from((_d[k] ?? {}) as Map);
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
        title: Text('Tax: ${widget.clientName}',
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 18)),
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
    final eq = _m('equity');
    final debt = _m('debt');
    final skipped = _m('skipped');
    final soon = _l('turning_long_term');
    final rows = _l('holdings');
    if (rows.isEmpty) {
      return const Center(
          child: Text('No priced holdings for this client.',
              style: TextStyle(color: Brand.mint)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Estimated tax if redeemed today',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          Text(_inr((_d['total_tax'] ?? 0) as num),
              style: const TextStyle(
                  color: Brand.gold, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _kv('Equity short term (20%)', _inr((eq['stcg_tax'] ?? 0) as num)),
          _kv('Equity long term (12.5%)', _inr((eq['ltcg_tax'] ?? 0) as num)),
          _kv('Debt (slab $_slab%)', _inr((debt['tax'] ?? 0) as num)),
          const SizedBox(height: 6),
          Row(children: [
            const Text('Slab rate: ',
                style: TextStyle(color: Brand.mint, fontSize: 12)),
            for (final s in const [0, 5, 10, 15, 20, 30])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$s%', style: const TextStyle(fontSize: 11)),
                  selected: _slab == s,
                  selectedColor: Brand.gold,
                  onSelected: (_) {
                    _slab = s;
                    _load();
                  },
                ),
              ),
          ]),
        ])),
        _title('Tax-free headroom'),
        _box(Text(
          'Long-term equity gains so far: ${_inr((eq['long_term_gain'] ?? 0) as num)}. '
          '${(eq['exemption_left'] ?? 0) > 0 ? 'You can still book about ${_inr((eq['exemption_left']) as num)} of long-term gains this year without tax (₹1.25 lakh exemption).' : 'The ₹1.25 lakh yearly exemption is used up.'}',
          style: const TextStyle(color: Brand.paper, fontSize: 13),
        )),
        if (soon.isNotEmpty) ...[
          _title('Turning long-term soon'),
          for (final s in soon)
            _box(Row(children: [
              Expanded(
                  child: Text('${s['scheme_name']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Brand.paper, fontSize: 13))),
              const SizedBox(width: 8),
              Text(
                  'in ${s['days_left']}d · gain ${_inr((s['gain'] ?? 0) as num)}',
                  style: const TextStyle(color: Brand.gold, fontSize: 12)),
            ])),
        ],
        _title('Holdings'),
        for (final r in rows) _holding(r),
        if ((skipped['no_date'] ?? 0) > 0 || (skipped['no_nav'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Left out: ${skipped['no_date']} equity holding(s) without a purchase date, '
              '${skipped['no_nav']} without a NAV.',
              style: const TextStyle(color: Brand.gold, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        Text('${_d['note'] ?? ''}',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _holding(Map<String, dynamic> r) {
    final gain = (r['gain'] ?? 0) as num;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['scheme_name']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Brand.paper, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '${r['asset_class']} · ${r['days'] == null ? 'no purchase date' : '${r['days']} days held'}'
          '${r['term'] == null ? '' : ' · ${r['term']} term'}',
          style: const TextStyle(color: Brand.mint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: Text('${r['treatment'] ?? ''}',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.8), fontSize: 11))),
          Text('${gain >= 0 ? '+' : ''}${_inr(gain)}',
              style: TextStyle(
                  color: gain >= 0 ? Brand.green : Brand.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _box(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: Brand.mint, fontSize: 13))),
          Text(v, style: const TextStyle(color: Brand.paper, fontSize: 13)),
        ]),
      );
}
