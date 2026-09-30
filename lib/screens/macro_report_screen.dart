// lib/screens/macro_report_screen.dart
//
// FULL REPLACEMENT FILE — copy this entire file's contents over your
// existing lib/screens/macro_report_screen.dart. It adds a per-user
// "EMAIL ALERTS" toggle card (Daily/Weekly/Monthly) using AuthService.email;
// everything else is unchanged from your current file.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  bool _daily = false, _weekly = false, _monthly = false;
  bool _alertsLoading = true;
  bool _alertsSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAlertSettings();
  }

  Future<void> _loadAlertSettings() async {
    final email = AuthService.email;
    if (email == null) {
      setState(() => _alertsLoading = false);
      return;
    }
    try {
      final s = await ApiService.getAlertSettings(email);
      if (mounted) {
        setState(() {
          _daily = s['daily'] == true;
          _weekly = s['weekly'] == true;
          _monthly = s['monthly'] == true;
          _alertsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _alertsLoading = false);
    }
  }

  Future<void> _saveAlertSettings() async {
    final email = AuthService.email;
    if (email == null) return;
    setState(() => _alertsSaving = true);
    try {
      await ApiService.setAlertSettings(email,
          daily: _daily, weekly: _weekly, monthly: _monthly);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save alert settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _alertsSaving = false);
    }
  }

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
            _alertsCard(),
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

  Widget _alertsCard() {
    final loggedIn = AuthService.email != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('EMAIL ALERTS',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                if (_alertsSaving) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
                loggedIn
                    ? 'Get this report emailed to ${AuthService.email} automatically.'
                    : 'Log in to receive this report by email automatically.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.6), fontSize: 10.5)),
            const SizedBox(height: 8),
            if (!loggedIn)
              const SizedBox()
            else if (_alertsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(),
              )
            else ...[
              _alertSwitch('Daily', _daily, (v) {
                setState(() => _daily = v);
                _saveAlertSettings();
              }),
              _alertSwitch('Weekly', _weekly, (v) {
                setState(() => _weekly = v);
                _saveAlertSettings();
              }),
              _alertSwitch('Monthly', _monthly, (v) {
                setState(() => _monthly = v);
                _saveAlertSettings();
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(color: Brand.paper)),
      value: value,
      activeColor: Brand.gold,
      onChanged: onChanged,
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
    final news = (report['news'] as List<dynamic>? ?? []);
    final aiSummary = (report['ai_summary'] ?? '').toString();
    final generatedAt = (report['generated_at'] ?? '').toString();
    final tone = (report['tone'] ?? '').toString();
    final toneColor = _toneColor((report['tone_color'] ?? '').toString());

    return [
      Text('Generated $generatedAt',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
      const SizedBox(height: 10),
      if (tone.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
              color: toneColor,
              borderRadius: BorderRadius.circular(10)),
          child: Text('OVERALL TONE: $tone',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        const SizedBox(height: 14),
      ],
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
      if (news.isNotEmpty) ...[
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MARKET NEWS HIGHLIGHTS',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                Text('Real recent headlines from the News tab — not AI-written.',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.6),
                        fontSize: 10.5)),
                const SizedBox(height: 10),
                ...news.map((n) {
                  final m = n as Map<String, dynamic>;
                  final impact = (m['impact'] ?? '').toString();
                  final color = _impactColor(impact);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 8),
                          width: 4,
                          height: 4,
                          decoration:
                              BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['title'].toString(),
                                  style: const TextStyle(
                                      color: Brand.paper,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 3),
                              Text(
                                  '${m['source'] ?? ''} · ${m['age'] ?? ''} · $impact impact',
                                  style: TextStyle(
                                      color: Brand.mint.withValues(alpha: 0.6),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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

  Color _toneColor(String key) {
    switch (key) {
      case 'red':
        return Brand.red;
      case 'green':
        return Brand.green;
      default:
        return const Color(0xFFD97706); // amber
    }
  }

  Color _impactColor(String impact) {
    switch (impact) {
      case 'High':
        return Brand.red;
      case 'Medium':
        return const Color(0xFFD97706); // amber
      default:
        return Brand.mint;
    }
  }
}
