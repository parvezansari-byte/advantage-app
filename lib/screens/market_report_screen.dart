// lib/screens/market_report_screen.dart
//
// Daily / weekly / monthly market report as a PDF, built by the API from live data
// (GET /report/market.pdf). The adviser can add a short note with their own commentary
// (the news behind the moves), which is printed in its own box in the report.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as authed;
import '../services/session.dart';

class MarketReportScreen extends StatefulWidget {
  const MarketReportScreen({super.key});

  @override
  State<MarketReportScreen> createState() => _MarketReportScreenState();
}

class _MarketReportScreenState extends State<MarketReportScreen> {
  String _kind = 'daily';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  Uint8List? _pdf;
  String? _pdfKind;
  bool _mailing = false;

  static const _labels = {
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _error = null;
      _pdf = null;
    });
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/report/market.pdf').replace(
        queryParameters: {
          'kind': _kind,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 120));
      if (res.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _pdf = res.bodyBytes;
          _pdfKind = _kind;
        });
      } else if (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) {
        throw 'The server is waking up or the market data is slow. Wait a minute and try again.';
      } else {
        throw 'Could not build the report (${res.statusCode}).';
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailMe() async {
    final email = Session.email;
    if (email == null || email.isEmpty) return;
    setState(() => _mailing = true);
    String msg;
    try {
      final uri = Uri.parse(
              '${ApiService.baseUrl}/report/${Uri.encodeComponent(email)}/email')
          .replace(queryParameters: {
        'kind': _pdfKind ?? _kind,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      final res = await authed
          .post(uri)
          .timeout(const Duration(seconds: 120));
      if (res.statusCode == 200) {
        msg = 'Report emailed to $email';
      } else if (res.statusCode == 429) {
        msg = 'Please wait a minute before sending another email.';
      } else {
        msg = 'Could not send the email (${res.statusCode}).';
      }
    } catch (_) {
      msg = 'Could not send the email. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() => _mailing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _fileName {
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'advantage_${_pdfKind}_market_report_${d.year}-$m-$day.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Market report', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A PDF with index levels, sectors, global cues, key levels, FII/DII '
            '(daily), outlook and charts, made from live data. The text states what '
            'moved; it does not explain the news behind it, so add that in the note '
            'if you want it in the report.',
            style: TextStyle(color: Brand.mint, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: [
              for (final e in _labels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {_kind},
            onSelectionChanged:
                _busy ? null : (s) => setState(() => _kind = s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((st) =>
                  st.contains(WidgetState.selected) ? Brand.vault : Brand.paper),
              backgroundColor: WidgetStateProperty.resolveWith((st) =>
                  st.contains(WidgetState.selected)
                      ? Brand.gold
                      : Brand.fern.withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            {
              'daily': 'Latest session versus the one before.',
              'weekly': 'Last 5 sessions.',
              'monthly': 'Last 21 sessions, with the past year on the chart.',
            }[_kind]!,
            style: const TextStyle(color: Brand.mint, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 4,
            maxLength: 1500,
            style: const TextStyle(color: Brand.paper),
            decoration: InputDecoration(
              labelText: "Adviser's note (optional)",
              hintText: 'For example: why crude moved, results season, policy news...',
              hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
              filled: true,
              fillColor: Brand.fern.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.gold,
              foregroundColor: Brand.vault,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _build,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(_busy ? 'Building the report...' : 'Build report'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Brand.gold)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Brand.red, fontSize: 13)),
            ),
          if (_pdf != null) ...[
            const SizedBox(height: 14),
            Text('${_labels[_pdfKind]} report ready (${(_pdf!.length / 1024).round()} KB).',
                style: const TextStyle(
                    color: Brand.green, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.gold,
                      side: BorderSide(color: Brand.gold.withValues(alpha: 0.6)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => Printing.layoutPdf(
                        onLayout: (_) async => _pdf!, name: _fileName),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View / print'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.green,
                      foregroundColor: Brand.vault,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () =>
                        Printing.sharePdf(bytes: _pdf!, filename: _fileName),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.mint,
                side: BorderSide(color: Brand.mint.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: _mailing ? null : _emailMe,
              icon: _mailing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.email_outlined),
              label: Text(_mailing ? 'Sending...' : 'Email me this report'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'For information only. Not investment advice. Add your SEBI registration '
            'details in the note if you share this with clients.',
            style: TextStyle(color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
