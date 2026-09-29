// lib/screens/macro_report_screen.dart

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../main.dart';
import '../services/api_service.dart';

class MacroReportScreen extends StatefulWidget {
  const MacroReportScreen({super.key});

  @override
  State<MacroReportScreen> createState() => _MacroReportScreenState();
}

class _MacroReportScreenState extends State<MacroReportScreen> {
  String _period = 'daily';
  bool _loading = false;
  bool _generatingPdf = false;
  Map<String, dynamic>? _report;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getMacroReport(_period);
      if (mounted) setState(() => _report = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final bytes = await ApiService.getMacroReportPdf(_period);
      await Printing.sharePdf(
          bytes: bytes, filename: 'macro_report_$_period.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        title: const Text('Market Report', style: TextStyle(color: Brand.gold)),
        iconTheme: const IconThemeData(color: Brand.gold),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('MARKET / MACRO REPORT',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'A data-grounded snapshot of indices, commodities, currency, '
              'and FII/DII flows, with an AI narrative built only from the '
              'real numbers below — no fabricated news.',
              style: TextStyle(color: Brand.mint, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _periodChip('daily', 'Daily'),
                const SizedBox(width: 8),
                _periodChip('weekly', 'Weekly'),
                const SizedBox(width: 8),
                _periodChip('monthly', 'Monthly'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _loading ? null : _generate,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.vault))
                  : const Text('Generate Report'),
            ),
            const SizedBox(height: 20),
            if (_error != null) _errorCard(_error!),
            if (_report != null) ..._reportViews(_report!),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    final selected = _period == value;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _period = value),
        selectedColor: Brand.gold,
        backgroundColor: Brand.gold.withValues(alpha: 0.08),
        labelStyle: TextStyle(
            color: selected ? Brand.vault : Brand.mint,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _errorCard(String msg) => Card(
        color: Brand.red.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(msg, style: const TextStyle(color: Brand.red)),
        ),
      );

  List<Widget> _reportViews(Map<String, dynamic> report) {
    final snapshot = (report['snapshot'] as List<dynamic>? ?? []);
    final fiiDii = report['fii_dii'] as Map<String, dynamic>?;
    final aiSummary = (report['ai_summary'] ?? '').toString();
    final generatedAt = (report['generated_at'] ?? '').toString();

    return [
      Text('Generated $generatedAt',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SNAPSHOT',
                  style: TextStyle(
                      color: Brand.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 10),
              ...snapshot.map((s) {
                final m = s as Map<String, dynamic>;
                final pct = (m['change_pct'] as num?)?.toDouble() ?? 0;
                final up = pct >= 0;
                final color = up ? Brand.green : Brand.red;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(m['name'].toString(),
                            style: const TextStyle(
                                color: Brand.paper,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(_fmt(m['value']),
                          style: const TextStyle(color: Brand.paper)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                            '${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      if (fiiDii != null) ...[
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FII / DII ACTIVITY',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 10),
                _flowRow('FII net', fiiDii['fii_net_total']),
                _flowRow('DII net', fiiDii['dii_net_total']),
                _flowRow('Combined', fiiDii['combined_net']),
                const SizedBox(height: 4),
                Text(
                    'Over ${fiiDii['total_days']} trading day(s) · '
                    '${fiiDii['fii_buying_days']} FII-buying day(s)',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7),
                        fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('AI ANALYSIS',
                      style: TextStyle(
                          color: Brand.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Brand.mint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('AI-generated — not financial advice',
                        style: TextStyle(color: Brand.mint, fontSize: 9)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(aiSummary.replaceAll('**', ''),
                  style: const TextStyle(color: Brand.paper, height: 1.4)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Brand.fern,
            foregroundColor: Brand.paper,
            minimumSize: const Size.fromHeight(48)),
        onPressed: _generatingPdf ? null : _downloadPdf,
        icon: _generatingPdf
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.paper))
            : const Icon(Icons.picture_as_pdf),
        label: Text(_generatingPdf ? 'Generating…' : 'Download PDF Report'),
      ),
      const SizedBox(height: 30),
    ];
  }

  Widget _flowRow(String label, dynamic value) {
    final v = (value as num?)?.toDouble() ?? 0;
    final color = v >= 0 ? Brand.green : Brand.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Brand.mint, fontSize: 13)),
          Text('₹${v.toStringAsFixed(0)} cr',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v is! num) return v.toString();
    return v.toStringAsFixed(2);
  }
}
