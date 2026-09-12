// lib/screens/doctor_screen.dart
//
// PORTFOLIO DOCTOR — the app's most distinctive feature.
//
// The user enters their holdings; the Python backend computes REAL diagnostics
// (effective holdings via Herfindahl, hidden correlation between stocks, sector
// tilt, performance vs NIFTY) and we display them.
//
// Nothing here is invented — every number comes from the /doctor endpoint.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class Holding {
  final String symbol;
  final double invested;
  final double currentValue;

  Holding({
    required this.symbol,
    required this.invested,
    required this.currentValue,
  });

  double get pnlPct =>
      invested == 0 ? 0 : (currentValue - invested) / invested * 100;

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'invested': invested,
        'current_value': currentValue,
        'pnl_pct': pnlPct,
      };
}

class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  final List<Holding> _holdings = [];
  final _symbolCtrl = TextEditingController();
  final _investedCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  void _addHolding() {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    final inv = double.tryParse(_investedCtrl.text.trim());
    final val = double.tryParse(_valueCtrl.text.trim());

    if (sym.isEmpty || inv == null || val == null || inv <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a symbol, invested amount and current value'),
          backgroundColor: Brand.red,
        ),
      );
      return;
    }

    setState(() {
      _holdings.add(
          Holding(symbol: sym, invested: inv, currentValue: val));
      _symbolCtrl.clear();
      _investedCtrl.clear();
      _valueCtrl.clear();
      _result = null; // diagnosis is stale now
    });
  }

  Future<void> _diagnose() async {
    if (_holdings.length < 2) {
      setState(() => _error = 'Add at least 2 holdings for a diagnosis.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final res = await ApiService.diagnose(
          _holdings.map((h) => h.toJson()).toList());
      if (mounted) setState(() => _result = res);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Diagnosis failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _investedCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🩺 Portfolio Doctor')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A candid diagnosis of what you actually own — concentration, '
            'hidden correlation, and whether the risk paid off.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4),
          ),
          const SizedBox(height: 20),

          // ---- add holding ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ADD A HOLDING',
                      style: TextStyle(
                          color: Brand.mint,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _symbolCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Brand.paper),
                    decoration: const InputDecoration(
                        hintText: 'Symbol — e.g. RELIANCE'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _investedCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Brand.paper),
                          decoration:
                              const InputDecoration(hintText: 'Invested ₹'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _valueCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Brand.paper),
                          decoration:
                              const InputDecoration(hintText: 'Now worth ₹'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.gold,
                        side: const BorderSide(color: Brand.gold),
                      ),
                      onPressed: _addHolding,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- current holdings ----
          if (_holdings.isNotEmpty) ...[
            const Text('YOUR HOLDINGS',
                style: TextStyle(
                    color: Brand.mint,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._holdings.asMap().entries.map((e) {
              final h = e.value;
              final up = h.pnlPct >= 0;
              return Card(
                child: ListTile(
                  title: Text(h.symbol,
                      style: const TextStyle(
                          color: Brand.paper, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '₹${h.invested.toStringAsFixed(0)} → '
                    '₹${h.currentValue.toStringAsFixed(0)}',
                    style: const TextStyle(color: Brand.mint, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${up ? '+' : ''}${h.pnlPct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: up ? Brand.green : Brand.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: Brand.mint),
                        onPressed: () => setState(() {
                          _holdings.removeAt(e.key);
                          _result = null;
                        }),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _loading ? null : _diagnose,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault),
                      )
                    : const Icon(Icons.medical_services),
                label: Text(_loading ? 'Diagnosing…' : 'Diagnose my portfolio',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Brand.red.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Brand.red),
                title: Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 13)),
              ),
            ),
          ],

          if (_result != null) ...[
            const SizedBox(height: 24),
            _DiagnosisView(result: _result!),
          ],
        ],
      ),
    );
  }
}

/// Displays the REAL computed diagnostics from the backend.
class _DiagnosisView extends StatelessWidget {
  final Map<String, dynamic> result;
  const _DiagnosisView({required this.result});

  @override
  Widget build(BuildContext context) {
    final effective = result['effective_holdings'];
    final nHoldings = result['n_holdings'] ?? 0;
    final top3 = result['top3_weight_pct'];
    final topHolding = result['top_holding'];
    final topWeight = result['top_weight_pct'];
    final maxDd = result['max_drawdown_pct'];
    final beating = result['n_beating_nifty'];
    final pairs = (result['high_correlation_pairs'] as List?) ?? [];
    final sectors = (result['sectors'] as List?) ?? [];

    // The headline insight: are you as diversified as you think?
    final illusion = effective != null &&
        nHoldings > 0 &&
        (effective as num) < nHoldings * 0.7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DIAGNOSIS',
            style: TextStyle(
                color: Brand.gold,
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // ---- the diversification illusion ----
        if (illusion)
          Card(
            color: Brand.red.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Brand.red, size: 20),
                      SizedBox(width: 8),
                      Text('Diversification illusion',
                          style: TextStyle(
                              color: Brand.red,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You hold $nHoldings stocks — but because of how your money '
                    'is weighted, you effectively own only $effective.',
                    style: const TextStyle(
                        color: Brand.paper, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // ---- key metrics ----
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _metric('Effective holdings', '${effective ?? '—'}',
                'of $nHoldings owned'),
            _metric('Top 3 weight',
                top3 != null ? '${(top3 as num).toStringAsFixed(0)}%' : '—',
                'of your money'),
            _metric('Biggest position', '$topHolding',
                topWeight != null
                    ? '${(topWeight as num).toStringAsFixed(0)}%'
                    : ''),
            _metric('Max drawdown',
                maxDd != null
                    ? '${(maxDd as num).toStringAsFixed(0)}%'
                    : '—',
                'worst fall'),
          ],
        ),

        // ---- hidden correlation: the key finding ----
        if (pairs.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            color: Brand.gold.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️ These move together',
                      style: TextStyle(
                          color: Brand.gold, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'They look like separate bets, but they rise and fall '
                    'together — so a shock hits them all at once.',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.85),
                        fontSize: 12,
                        height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  ...pairs.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.link,
                                size: 14, color: Brand.mint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${p['a']} ↔ ${p['b']}',
                                  style: const TextStyle(
                                      color: Brand.paper, fontSize: 13)),
                            ),
                            Text('${p['corr']}',
                                style: const TextStyle(
                                    color: Brand.gold,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],

        // ---- vs NIFTY ----
        if (beating != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.show_chart, color: Brand.gold),
              title: Text('$beating of $nHoldings beat the NIFTY 50',
                  style: const TextStyle(
                      color: Brand.paper, fontWeight: FontWeight.bold)),
              subtitle: Text(
                result['nifty_1y_pct'] != null
                    ? 'NIFTY returned ${result['nifty_1y_pct']}% over the year'
                    : '',
                style: const TextStyle(color: Brand.mint, fontSize: 12),
              ),
            ),
          ),
        ],

        // ---- sector tilt ----
        if (sectors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('SECTOR EXPOSURE',
              style: TextStyle(
                  color: Brand.mint,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...sectors.take(5).map((s) {
            final pct = (s['weight_pct'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s['sector']}',
                          style: const TextStyle(
                              color: Brand.paper, fontSize: 13)),
                      Text('${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Brand.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
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
                          pct > 40 ? Brand.red : Brand.gold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 20),
        Text(
          'Computed from your real holdings. For information only — '
          'not investment advice.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.5), fontSize: 11),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, String sub) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(color: Brand.mint, fontSize: 11)),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.6),
                        fontSize: 10)),
            ],
          ),
        ),
      );
}
