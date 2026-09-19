// lib/screens/research_reports_screen.dart
//
// Dedicated tab: pick a stock, see an inline preview (score, analyst
// consensus, fundamentals, risk flags, and links), then optionally
// generate the full PDF report (adds trend tables, dividends, news, and
// AI analysis), shared/saved via the same Printing.sharePdf pattern
// already used by holdings_pdf.dart.

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/api_service.dart';

class ResearchReportsScreen extends StatefulWidget {
  const ResearchReportsScreen({super.key});

  @override
  State<ResearchReportsScreen> createState() => _ResearchReportsScreenState();
}

class _ResearchReportsScreenState extends State<ResearchReportsScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allStocksDetailed = [];
  bool _loadingList = true;
  String? _selectedSymbol;

  Map<String, dynamic>? _summary;
  bool _loadingSummary = false;
  String? _summaryError;

  bool _generating = false;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  Future<void> _loadStocks() async {
    try {
      final d = await ApiService.getStockListDetailed();
      final stocks = (d['stocks'] as List? ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (mounted) setState(() => _allStocksDetailed = stocks);
    } catch (_) {
      // search box still works by typing a full symbol even if this fails
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  List<String> get _filteredSymbols {
    final q = _searchCtrl.text.trim().toUpperCase();
    final all = _allStocksDetailed.map((s) => '${s['symbol']}').toList();
    if (q.isEmpty) return all.take(50).toList();
    return all.where((s) => s.contains(q)).take(30).toList();
  }

  Future<void> _selectStock(String symbol) async {
    setState(() {
      _selectedSymbol = symbol;
      _summary = null;
      _summaryError = null;
      _pdfError = null;
      _loadingSummary = true;
    });
    try {
      final s = await ApiService.getResearchSummary(symbol);
      if (mounted) setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _summaryError = '$e');
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _generateAndShare() async {
    final symbol = _selectedSymbol?.trim().toUpperCase();
    if (symbol == null || symbol.isEmpty) return;
    setState(() {
      _generating = true;
      _pdfError = null;
    });
    try {
      final bytes = await ApiService.getResearchReportPdf(symbol);
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'research_${symbol}_report.pdf',
      );
    } catch (e) {
      if (mounted) setState(() => _pdfError = '$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Research Reports',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Pick a stock for a quick preview, or generate the full PDF '
              'report with trends, news, and AI analysis.',
              style: TextStyle(color: Brand.mint, fontSize: 13),
            ),
            const SizedBox(height: 20),

            const Text('SELECT A STOCK',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Autocomplete<String>(
              optionsBuilder: (TextEditingValue value) {
                _searchCtrl.text = value.text;
                return _filteredSymbols;
              },
              onSelected: _selectStock,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Brand.paper),
                  onChanged: (v) => _searchCtrl.text = v,
                  decoration: InputDecoration(
                    hintText: _loadingList
                        ? 'Loading stock list\u2026'
                        : 'Search a stock \u2014 e.g. RELIANCE',
                    prefixIcon: const Icon(Icons.search, color: Brand.mint),
                  ),
                  onSubmitted: (v) {
                    onSubmit();
                    _selectStock(v.trim().toUpperCase());
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Brand.fern,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 280, maxWidth: 360),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: options
                            .map((s) => ListTile(
                                  dense: true,
                                  title: Text(s,
                                      style:
                                          const TextStyle(color: Brand.paper)),
                                  onTap: () => onSelected(s),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),

            if (_selectedSymbol != null) ...[
              const SizedBox(height: 18),
              if (_loadingSummary)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child:
                      Center(child: CircularProgressIndicator(color: Brand.gold)),
                )
              else if (_summaryError != null)
                _errorBox(_summaryError!)
              else if (_summary != null)
                _summaryCard(_summary!),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_generating || _selectedSymbol == null) ? null : _generateAndShare,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  disabledBackgroundColor: Brand.gold.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _generating
                      ? 'Generating full report\u2026'
                      : 'Generate Full PDF Report',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            if (_generating) ...[
              const SizedBox(height: 10),
              Text(
                'This adds trend tables, dividends, recent news, and an '
                'AI-generated analysis on top of the preview above \u2014 it '
                'can take up to a minute. Please wait.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5),
              ),
            ],
            if (_pdfError != null) ...[
              const SizedBox(height: 14),
              _errorBox(_pdfError!),
            ],

            const SizedBox(height: 24),
            Text(
              'The preview above uses live fundamentals and technicals. The '
              'full PDF additionally includes revenue/balance sheet/cash '
              'flow trends, dividend history, recent news, and an '
              'AI-generated analysis. For education only \u2014 not investment '
              'advice.',
              style: TextStyle(color: Brand.mint.withValues(alpha: 0.55), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Brand.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Brand.red, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> s) {
    final score = (s['score'] as Map?) ?? {};
    final fundamentals = (s['fundamentals'] as Map?) ?? {};
    final riskFlags = (s['risk_flags'] as List?) ?? [];
    final consensus = s['consensus'] as Map?;
    final range5y = s['range_5y'] as Map?;
    final links = (s['links'] as Map?) ?? {};

    final verdict = '${score['verdict'] ?? ''}';
    final verdictColor = verdict == 'STRONG' || verdict == 'POSITIVE'
        ? Brand.green
        : (verdict == 'WEAK' ? Brand.red : Brand.gold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s['name'] ?? _selectedSymbol}',
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                if (s['sector'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${s['sector']}'
                      '${s['market_cap_cr'] != null ? '  \u00b7  \u20b9${s['market_cap_cr']} cr mcap' : ''}',
                      style: const TextStyle(color: Brand.mint, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('${score['score'] ?? '\u2014'}/10',
                        style: TextStyle(
                            color: verdictColor,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(verdict,
                          style: TextStyle(
                              color: verdictColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Valuation ${score['val'] ?? '\u2014'}   |   '
                  'Quality ${score['qual'] ?? '\u2014'}   |   '
                  'Momentum ${score['mom'] ?? '\u2014'}',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),

        if (consensus != null) ...[
          const SizedBox(height: 10),
          _infoCard('ANALYST CONSENSUS', [
            _kv('Rating', '${consensus['reco'] ?? '\u2014'}'),
            _kv('Mean target',
                consensus['target'] != null ? '\u20b9${consensus['target']}' : '\u2014'),
            _kv('Implied upside',
                consensus['upside'] != null
                    ? '${(consensus['upside'] as num).toStringAsFixed(1)}%'
                    : '\u2014'),
            _kv('Analysts covering', '${consensus['n_analysts'] ?? '\u2014'}'),
          ]),
        ],

        const SizedBox(height: 10),
        _infoCard('FUNDAMENTALS', [
          _kv('PE', '${fundamentals['pe'] ?? '\u2014'}'),
          _kv('PB', '${fundamentals['pb'] ?? '\u2014'}'),
          _kv('EV/EBITDA', '${fundamentals['ev_ebitda'] ?? '\u2014'}'),
          _kv('ROE %', '${fundamentals['roe_pct'] ?? '\u2014'}'),
          _kv('Net Margin %', '${fundamentals['net_margin_pct'] ?? '\u2014'}'),
          _kv('Debt/Equity', '${fundamentals['debt_to_equity'] ?? '\u2014'}'),
        ]),

        if (range5y != null) ...[
          const SizedBox(height: 10),
          _infoCard('5-YEAR PRICE RANGE', [
            _kv('Low \u2192 High',
                '\u20b9${range5y['low_5y']} \u2192 \u20b9${range5y['high_5y']}'),
            _kv('Current percentile', '${range5y['percentile_5y']}th'),
          ]),
        ],

        if (riskFlags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RISK FLAGS',
                      style: TextStyle(
                          color: Brand.gold,
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final flag in riskFlags)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('\u2022  $flag',
                          style: const TextStyle(
                              color: Brand.paper, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LINKS',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _linkRow('Search official annual report',
                    links['annual_report_search'] as String?),
                _linkRow(
                    'NSE company filings page', links['nse_filings'] as String?),
                _linkRow(
                    'View on the Crescent website', links['crescent_site'] as String?),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoCard(String title, List<Widget> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Brand.gold,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
          Text(value,
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _linkRow(String label, String? url) {
    return InkWell(
      onTap: () => _openLink(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.open_in_new, color: Brand.gold, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Brand.gold,
                      fontSize: 12.5,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}
