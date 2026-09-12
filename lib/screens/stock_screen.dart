// lib/screens/stock_screen.dart
//
// Full stock analysis — matches the web platform: price hero, Fundamentals
// tab (Valuation / Profitability / Health / Growth & Cash) and Technicals tab.
// All data comes from /stock/{symbol}, which already returns every ratio.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class StockScreen extends StatefulWidget {
  final String symbol;
  const StockScreen({super.key, required this.symbol});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _statements;
  bool _loadingStatements = false;
  String? _error;
  bool _loading = true;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChange);
    _load();
  }

  void _onTabChange() {
    // Lazy-load statements only when the user first opens that tab.
    if (_tabs.index == 2 && _statements == null && !_loadingStatements) {
      _loadStatements();
    }
  }

  Future<void> _loadStatements() async {
    setState(() => _loadingStatements = true);
    try {
      final s = await ApiService.getStatements(widget.symbol);
      if (mounted) setState(() => _statements = s);
    } catch (_) {
      // handled in the tab UI
    } finally {
      if (mounted) setState(() => _loadingStatements = false);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChange);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getStock(widget.symbol);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        bottom: _data == null
            ? null
            : TabBar(
                controller: _tabs,
                labelColor: Brand.gold,
                unselectedLabelColor: Brand.mint,
                indicatorColor: Brand.gold,
                tabs: const [
                  Tab(text: 'Fundamentals'),
                  Tab(text: 'Technicals'),
                  Tab(text: 'Financials'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _fundamentalsTab(),
                    _technicalsTab(),
                    _financialsTab(),
                  ],
                ),
    );
  }

  Widget _priceHero() {
    final f = (_data!['fundamentals'] ?? {}) as Map<String, dynamic>;
    final t = (_data!['technicals'] ?? {}) as Map<String, dynamic>;
    // On a partial response there are no technicals, but Dhan still supplied
    // a live price under fundamentals.
    final price = t['close'] ?? f['current_price'];
    final ret1y = t['ret_1y_pct'];
    final isUp = (ret1y ?? 0) >= 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((f['name'] ?? widget.symbol).toString(),
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            if (f['sector'] != null)
              Text(
                '${f['sector']}${f['market_cap_cr'] != null ? '  \u00b7  \u20b9${_fmt(f['market_cap_cr'])} cr mcap' : ''}',
                style: const TextStyle(color: Brand.mint, fontSize: 12),
              ),
            const SizedBox(height: 14),
            Text(price != null ? '\u20b9${_fmt(price)}' : '\u2014',
                style: const TextStyle(
                    color: Brand.gold,
                    fontSize: 34,
                    fontWeight: FontWeight.bold)),
            if (ret1y != null)
              Row(children: [
                Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isUp ? Brand.green : Brand.red, size: 16),
                const SizedBox(width: 4),
                Text('${_fmt(ret1y)}% (1 year)',
                    style: TextStyle(
                        color: isUp ? Brand.green : Brand.red,
                        fontWeight: FontWeight.bold)),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _fundamentalsTab() {
    final f = (_data!['fundamentals'] ?? {}) as Map<String, dynamic>;
    return ListView(
      children: [
        _partialBanner(),
        _priceHero(),
        _group('VALUATION', [
          _Row('P/E', _fmt(f['pe'])),
          _Row('Forward P/E', _fmt(f['forward_pe'])),
          _Row('P/B', _fmt(f['pb'])),
          _Row('P/S', _fmt(f['ps'])),
          _Row('EV/EBITDA', _fmt(f['ev_ebitda'])),
          _Row('PEG', _fmt(f['peg'])),
          _Row('EPS', '\u20b9${_fmt(f['eps'])}'),
          _Row('Book Value', '\u20b9${_fmt(f['book_value'])}'),
          _Row('Dividend Yield', '${_fmt(f['dividend_yield_pct'])}%'),
        ]),
        _group('PROFITABILITY', [
          _Row('ROE', '${_fmt(f['roe_pct'])}%'),
          _Row('ROA', '${_fmt(f['roa_pct'])}%'),
          _Row('Gross Margin', '${_fmt(f['gross_margin_pct'])}%'),
          _Row('Operating Margin', '${_fmt(f['operating_margin_pct'])}%'),
          _Row('Net Margin', '${_fmt(f['net_margin_pct'])}%'),
        ]),
        _group('FINANCIAL HEALTH', [
          _Row('Debt / Equity', _fmt(f['debt_to_equity'])),
          _Row('Current Ratio', _fmt(f['current_ratio'])),
          _Row('Quick Ratio', _fmt(f['quick_ratio'])),
          _Row('Interest Coverage', _fmt(f['interest_coverage'])),
        ]),
        _group('GROWTH & CASH', [
          _Row('Revenue Growth', '${_fmt(f['revenue_growth_pct'])}%'),
          _Row('Earnings Growth', '${_fmt(f['earnings_growth_pct'])}%'),
          _Row('Free Cashflow', '\u20b9${_fmt(f['free_cashflow_cr'])} cr'),
          _Row('Operating Cashflow', '\u20b9${_fmt(f['operating_cashflow_cr'])} cr'),
        ]),
        _disclaimer(),
      ],
    );
  }

  Widget _technicalsTab() {
    final t = (_data!['technicals'] ?? {}) as Map<String, dynamic>;
    return ListView(
      children: [
        _partialBanner(),
        _priceHero(),
        _group('TREND & MOMENTUM', [
          _Row('Trend', t['trend']?.toString() ?? '\u2014'),
          _Row('MA Signal', t['ma_signal']?.toString() ?? '\u2014'),
          _Row('RSI (14)', _fmt(t['rsi'])),
          _Row('RSI Signal', t['rsi_signal']?.toString() ?? '\u2014'),
          _Row('MACD Signal', t['macd_signal']?.toString() ?? '\u2014'),
        ]),
        _group('PRICE LEVELS', [
          _Row('52-week High', '\u20b9${_fmt(t['52w_high'])}'),
          _Row('52-week Low', '\u20b9${_fmt(t['52w_low'])}'),
          _Row('From 52w High', '${_fmt(t['pct_from_52w_high'])}%'),
          _Row('1-month Return', '${_fmt(t['ret_1m_pct'])}%'),
          _Row('1-year Return', '${_fmt(t['ret_1y_pct'])}%'),
        ]),
        _group('RISK', [
          _Row('Volatility (annual)', '${_fmt(t['volatility_pct'])}%'),
          _Row('ATR', _fmt(t['atr'])),
          _Row('Stochastic %K', _fmt(t['stoch_k'])),
        ]),
        _disclaimer(),
      ],
    );
  }

  Widget _financialsTab() {
    if (_loadingStatements) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_statements == null) {
      return const Center(
        child: Text('Loading financial statements…',
            style: TextStyle(color: Brand.mint)),
      );
    }
    final income = _statements!['income'] as Map<String, dynamic>?;
    final balance = _statements!['balance'] as Map<String, dynamic>?;
    final cashflow = _statements!['cashflow'] as Map<String, dynamic>?;

    final hasAny = [income, balance, cashflow].any(
        (s) => s != null && (s['rows'] as List?)?.isNotEmpty == true);

    if (!hasAny) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Text(
            'Financial statements aren\u2019t available from the data source '
            'for this stock.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.mint),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statementTable('INCOME STATEMENT (\u20b9 cr)', income),
        _statementTable('BALANCE SHEET (\u20b9 cr)', balance),
        _statementTable('CASH FLOW (\u20b9 cr)', cashflow),
        _disclaimer(),
      ],
    );
  }

  Widget _statementTable(String title, Map<String, dynamic>? stmt) {
    final periods =
        (stmt?['periods'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (stmt?['rows'] as List?) ?? [];
    if (periods.isEmpty || rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Brand.gold,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 44,
                columnSpacing: 22,
                headingTextStyle: const TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                dataTextStyle:
                    const TextStyle(color: Brand.paper, fontSize: 12),
                columns: [
                  const DataColumn(label: Text('Item')),
                  ...periods.map((p) => DataColumn(label: Text(p))),
                ],
                rows: rows.map<DataRow>((r) {
                  final item = (r['item'] ?? '').toString();
                  final values = (r['values'] ?? {}) as Map<String, dynamic>;
                  return DataRow(cells: [
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(item,
                          style: const TextStyle(
                              color: Brand.mint, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    )),
                    ...periods.map((p) {
                      final v = values[p];
                      return DataCell(Text(v == null
                          ? '\u2014'
                          : _fmtCr(v is num ? v.toDouble() : null)));
                    }),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtCr(double? v) {
    if (v == null) return '\u2014';
    return v.abs() >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  Widget _group(String title, List<_Row> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      style: const TextStyle(
                          color: Brand.gold,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.label,
                            style: const TextStyle(
                                color: Brand.mint, fontSize: 13)),
                        Text(r.value,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown when the API could only return a live price — Yahoo throttles per
  /// IP, and every user of this server shares one. Without this, the empty
  /// rows below read as missing data rather than a temporary limit.
  Widget _partialBanner() {
    if (_data?['partial'] != true) return const SizedBox.shrink();
    final notice = _data?['notice']?.toString() ??
        'Some data is temporarily unavailable.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: Brand.gold, size: 16),
                const SizedBox(width: 7),
                const Text('Partial data',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 7),
            Text(notice,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.45)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.gold,
                  side: BorderSide(color: Brand.gold.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry now', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer() => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Data via Yahoo Finance (may be delayed). For information only \u2014 '
          'not investment advice.',
          style:
              TextStyle(color: Brand.mint.withValues(alpha: 0.5), fontSize: 11),
        ),
      );

  String _fmt(dynamic v) {
    if (v == null) return '\u2014';
    if (v is num) {
      return v.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
    }
    return v.toString();
  }
}

class _Row {
  final String label;
  final String value;
  _Row(this.label, this.value);
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, color: Brand.red, size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.mint)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold, foregroundColor: Brand.vault),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
