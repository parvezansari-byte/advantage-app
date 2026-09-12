// lib/screens/xray_screen.dart
//
// PORTFOLIO X-RAY — see what you ACTUALLY own.
//
// You hold 5 funds and feel diversified. But they might all own HDFC Bank,
// Reliance and Infosys. You could be 15% exposed to one company without ever
// having bought a share of it.
//
// The backend does the look-through maths; this screen surfaces the finding.

import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class FundHolding {
  final String schemeCode;
  final String name;
  final double value;

  FundHolding(
      {required this.schemeCode, required this.name, required this.value});

  Map<String, dynamic> toJson() => {
        'scheme_code': schemeCode,
        'name': name,
        'value': value,
      };
}

class XrayScreen extends StatefulWidget {
  const XrayScreen({super.key});

  @override
  State<XrayScreen> createState() => _XrayScreenState();
}

class _XrayScreenState extends State<XrayScreen> {
  final List<FundHolding> _funds = [];
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '100000');

  List<dynamic> _results = [];
  bool _searching = false;
  Timer? _debounce;

  Map<String, dynamic>? _xray;
  bool _loading = false;
  String? _error;

  /// Debounced search — we don't fire a request on every keystroke.
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final res = await ApiService.searchFunds(q.trim());
      if (mounted) setState(() => _results = res.take(8).toList());
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addFund(dynamic fund) {
    final code = fund['schemeCode'].toString();
    final name = fund['schemeName'].toString();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (amount <= 0) {
      _snack('Enter how much you have invested in this fund');
      return;
    }
    if (_funds.any((f) => f.schemeCode == code)) {
      _snack('Already added');
      return;
    }

    setState(() {
      _funds.add(
          FundHolding(schemeCode: code, name: name, value: amount));
      _searchCtrl.clear();
      _results = [];
      _xray = null; // previous x-ray is stale
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Brand.red),
    );
  }

  Future<void> _runXray() async {
    setState(() {
      _loading = true;
      _error = null;
      _xray = null;
    });
    try {
      final res =
          await ApiService.xray(_funds.map((f) => f.toJson()).toList());
      if (mounted) setState(() => _xray = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'X-ray failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔬 Portfolio X-ray')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'You hold several funds and feel diversified. But they might all '
            'own the same stocks underneath. This shows what you actually own.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4),
          ),
          const SizedBox(height: 20),

          // ---- add a fund ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ADD A FUND YOU HOLD',
                      style: TextStyle(
                          color: Brand.mint,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Brand.paper),
                    decoration: const InputDecoration(
                      hintText: 'Amount invested ₹',
                      prefixIcon:
                          Icon(Icons.currency_rupee, color: Brand.mint, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Brand.paper),
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search fund — e.g. Parag Parikh Flexi',
                      prefixIcon:
                          const Icon(Icons.search, color: Brand.mint),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Brand.gold),
                              ),
                            )
                          : null,
                    ),
                  ),

                  // search results
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._results.map((f) => InkWell(
                          onTap: () => _addFund(f),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                const Icon(Icons.add_circle_outline,
                                    size: 18, color: Brand.gold),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f['schemeName'].toString(),
                                    style: const TextStyle(
                                        color: Brand.paper, fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- funds added ----
          if (_funds.isNotEmpty) ...[
            const Text('YOUR FUNDS',
                style: TextStyle(
                    color: Brand.mint,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._funds.asMap().entries.map((e) => Card(
                  child: ListTile(
                    title: Text(
                      e.value.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Brand.paper, fontSize: 13),
                    ),
                    subtitle: Text(
                      '₹${e.value.value.toStringAsFixed(0)}',
                      style: const TextStyle(color: Brand.gold, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Brand.mint),
                      onPressed: () => setState(() {
                        _funds.removeAt(e.key);
                        _xray = null;
                      }),
                    ),
                  ),
                )),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _loading ? null : _runXray,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault))
                    : const Icon(Icons.biotech),
                label: Text(
                  _loading ? 'Looking inside…' : 'X-ray my funds',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add at least one fund above. Add two or more to see whether '
                  'they secretly hold the same stocks.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7),
                      fontSize: 13),
                ),
              ),
            ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Brand.red.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: Brand.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Brand.red,
                              fontSize: 12.5,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_xray != null) ...[
            const SizedBox(height: 24),
            _XrayResults(data: _xray!),
          ],
        ],
      ),
    );
  }
}

class _XrayResults extends StatelessWidget {
  final Map<String, dynamic> data;
  const _XrayResults({required this.data});

  @override
  Widget build(BuildContext context) {
    final stocks = (data['stocks'] as List?) ?? [];
    final overlaps = (data['overlaps'] as List?) ?? [];
    final sectors = (data['sectors'] as List?) ?? [];
    final missing = (data['missing'] as List?) ?? [];
    final top = data['top_stock'];
    final nUnique = data['n_unique_stocks'] ?? 0;
    final top10 = data['top10_pct'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('WHAT YOU ACTUALLY OWN',
            style: TextStyle(
                color: Brand.gold,
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // honest about coverage gaps
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No holdings data for ${missing.length} fund(s) — excluded '
                  'from these numbers rather than guessed at.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7),
                      fontSize: 11.5),
                ),
              ),
            ),
          ),

        // ---- headline metrics ----
        Row(
          children: [
            Expanded(
              child: _metric('Stocks you really own', '$nUnique',
                  'across all funds'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric(
                  'Top 10 concentration',
                  top10 != null
                      ? '${(top10 as num).toStringAsFixed(0)}%'
                      : '—',
                  'of your money'),
            ),
          ],
        ),
        if (top != null) ...[
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.trending_up, color: Brand.gold),
              title: Text('Biggest hidden position: ${top['stock']}',
                  style: const TextStyle(
                      color: Brand.paper,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${(top['pct_of_portfolio'] as num).toStringAsFixed(1)}% of '
                'your money — without buying a single share directly',
                style: const TextStyle(color: Brand.mint, fontSize: 11.5),
              ),
            ),
          ),
        ],

        // ---- THE KEY FINDING ----
        if (overlaps.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            color: Brand.red.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Brand.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('The diversification illusion',
                            style: TextStyle(
                                color: Brand.red,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You own these stocks through MORE THAN ONE fund. '
                    'Different funds — same companies underneath.',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ...overlaps.take(8).map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                o['stock'].toString(),
                                style: const TextStyle(
                                    color: Brand.paper, fontSize: 13),
                              ),
                            ),
                            Text(
                              '${(o['pct_of_portfolio'] as num).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  color: Brand.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Brand.red.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${(o['held_by'] as List).length} funds',
                                style: const TextStyle(
                                    color: Brand.red, fontSize: 10.5),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ] else if (stocks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: Brand.green.withValues(alpha: 0.1),
            child: const ListTile(
              leading: Icon(Icons.check_circle, color: Brand.green),
              title: Text('No stock is held by more than one fund',
                  style: TextStyle(color: Brand.green, fontSize: 13)),
              subtitle: Text('Your funds genuinely don\'t overlap.',
                  style: TextStyle(color: Brand.mint, fontSize: 11.5)),
            ),
          ),
        ],

        // ---- sector look-through ----
        if (sectors.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('YOUR REAL SECTOR EXPOSURE',
              style: TextStyle(
                  color: Brand.mint,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Aggregated across every stock inside every fund you hold.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
          const SizedBox(height: 10),
          ...sectors.take(6).map((s) {
            final pct = (s['pct'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('${s['sector']}',
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 12.5)),
                      ),
                      Text('${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Brand.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Brand.fern.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation(
                          pct > 35 ? Brand.red : Brand.gold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        // ---- full list ----
        if (stocks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('All $nUnique stocks (look-through)',
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              children: stocks.take(40).map<Widget>((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(s['stock'].toString(),
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 12.5)),
                      ),
                      Text(
                        '${(s['pct_of_portfolio'] as num).toStringAsFixed(2)}%',
                        style: const TextStyle(
                            color: Brand.mint, fontSize: 12.5),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Text(
          'Holdings via AMFI monthly disclosures — funds report holdings '
          'monthly, so this reflects their last disclosure. Not investment advice.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.5),
              fontSize: 10.5,
              height: 1.4),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, String sub) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Brand.mint, fontSize: 11)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              Text(sub,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.6),
                      fontSize: 10)),
            ],
          ),
        ),
      );
}
