// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'stock_screen.dart';
import 'planner_screen.dart';
import 'xray_screen.dart';
import 'calculator_screen.dart';
import 'lifestyle_screen.dart';
import 'life_goal_screen.dart';
import 'core_wealth_screen.dart';
import 'news_screen.dart';
import 'sectors_screen.dart';
import 'chart_screen.dart';
import 'options_screen.dart';
import 'holdings_screen.dart';
import 'backtest_screen.dart';
import 'portfolio_screen.dart';
import 'tax_screen.dart';
import 'finance_screen.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool? _apiUp; // null = still checking
  List<Map<String, dynamic>> _allStocksDetailed = []; // symbol/sector/cap
  List<String> _sectors = [];
  String _sectorFilter = 'All Sectors';
  String _capFilter = 'All Caps';

  @override
  void initState() {
    super.initState();
    _checkApi();
    _loadStocks();
  }

  Future<void> _checkApi() async {
    final up = await ApiService.ping();
    if (mounted) setState(() => _apiUp = up);
  }

  Future<void> _loadStocks() async {
    try {
      final d = await ApiService.getStockListDetailed();
      final stocks = (d['stocks'] as List? ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final sectors = (d['sectors'] as List? ?? []).map((e) => '$e').toList();
      if (mounted) {
        setState(() {
          _allStocksDetailed = stocks;
          _sectors = sectors;
        });
      }
    } catch (_) {
      // search still works by typing a full symbol even if the list fails
    }
  }

  List<String> get _filteredSymbols {
    return _allStocksDetailed
        .where((s) =>
            (_sectorFilter == 'All Sectors' || s['sector'] == _sectorFilter) &&
            (_capFilter == 'All Caps' || s['cap'] == _capFilter))
        .map((s) => '${s['symbol']}')
        .toList();
  }

  void _openStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockScreen(symbol: s)),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- brand ----
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Brand.gold,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.search,
                        color: Brand.vault, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Advantage',
                      style: TextStyle(
                        color: Brand.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Brand.mint, size: 20),
                    tooltip: 'Sign out',
                    onPressed: () async {
                      await AuthService.logout();
                      if (!context.mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                  ),
                ],
              ),
              if (AuthService.name != null && AuthService.name!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Signed in as ${AuthService.name}',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.6),
                          fontSize: 11)),
                ),
              const SizedBox(height: 8),
              Container(width: 50, height: 3, color: Brand.gold),
              const SizedBox(height: 24),

              const Text(
                'Stop taking tips.',
                style: TextStyle(
                    color: Brand.paper,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const Text(
                'Start doing research.',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // ---- connection status (honest about failures) ----
              _ConnectionBanner(apiUp: _apiUp, onRetry: _checkApi),
              const SizedBox(height: 20),

              // ---- filters: sector + market cap ----
              if (_sectors.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        value: _sectorFilter,
                        options: ['All Sectors', ..._sectors],
                        onChanged: (v) => setState(() => _sectorFilter = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterDropdown(
                        value: _capFilter,
                        options: const ['All Caps', 'LARGECAP', 'MIDCAP', 'SMALLCAP', 'ALLEQUITIES'],
                        onChanged: (v) => setState(() => _capFilter = v),
                      ),
                    ),
                  ],
                ),
              if (_sectors.isNotEmpty) const SizedBox(height: 10),

              // ---- search with autocomplete over ~500 stocks ----
                            Autocomplete<String>(
                optionsBuilder: (TextEditingValue value) {
                  final q = value.text.trim().toUpperCase();
                  final pool = _filteredSymbols;
                  if (q.isEmpty) return pool.take(50);
                  return pool.where((s) => s.contains(q)).take(30);
                },
                onSelected: (s) => _openStock(s),
                                fieldViewBuilder:
                    (context, controller, focusNode, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Brand.paper),
                    decoration: InputDecoration(
                      hintText: _allStocksDetailed.isEmpty
                          ? 'Loading stock list…'
                          : 'Search ${_filteredSymbols.length} stocks — e.g. RELIANCE',
                      prefixIcon:
                          const Icon(Icons.search, color: Brand.mint),
                    ),
                    onChanged: (v) => _searchCtrl.text = v,
                    onSubmitted: (v) {
                      onSubmit();
                      _openStock(v);
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
                        constraints: const BoxConstraints(
                            maxHeight: 280, maxWidth: 360),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: options
                              .map((s) => ListTile(
                                    dense: true,
                                    title: Text(s,
                                        style: const TextStyle(
                                            color: Brand.paper)),
                                    onTap: () => onSelected(s),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.gold,
                    foregroundColor: Brand.vault,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _openStock(_searchCtrl.text),
                  child: const Text('Analyse',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 28),

              // ---- RESEARCH ----
              const _SectionLabel('RESEARCH'),
              _MenuCard(
                icon: Icons.candlestick_chart,
                iconColor: Brand.blue,
                title: 'Live Chart',
                subtitle: 'Intraday and long-term price charts',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ChartScreen())),
              ),
              _MenuCard(
                icon: Icons.donut_small,
                iconColor: Brand.blue,
                title: 'Sector Performance',
                subtitle: 'Which sectors are leading and lagging',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SectorsScreen())),
              ),
              _MenuCard(
                icon: Icons.newspaper,
                iconColor: Brand.blue,
                title: 'Market Terminal',
                subtitle: 'FII/DII flows and live market news',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NewsScreen())),
              ),
              _MenuCard(
                icon: Icons.stacked_bar_chart,
                iconColor: Brand.blue,
                title: 'Option Chain',
                subtitle: 'PCR, max pain and open interest by strike',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const OptionsScreen())),
              ),
              const SizedBox(height: 18),

              // ---- PORTFOLIO ----
              const _SectionLabel('PORTFOLIO'),
              _MenuCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: Brand.purple,
                title: 'My Portfolio',
                subtitle: 'Track your holdings and live P&L',
                onTap: () {
                  final email = AuthService.email;
                  if (email == null || email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Sign in to track your portfolio')),
                    );
                    return;
                  }
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => PortfolioScreen(email: email)));
                },
              ),
              _MenuCard(
                icon: Icons.travel_explore,
                iconColor: Brand.purple,
                title: 'Holdings Explorer',
                subtitle: 'What funds own, and how much they overlap',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HoldingsScreen())),
              ),
              _MenuCard(
                icon: Icons.query_stats,
                iconColor: Brand.purple,
                title: 'Stock Analysis',
                subtitle: 'Search 2,000+ stocks — fundamentals, technicals & statements',
                onTap: () {
                  _scrollCtrl.animateTo(0,
                      duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Type a stock name in the search bar above'),
                        duration: Duration(seconds: 2)),
                  );
                },
              ),
              _MenuCard(
                icon: Icons.biotech,
                iconColor: Brand.purple,
                title: 'Portfolio X-ray',
                subtitle: 'Do your funds secretly own the same stocks?',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const XrayScreen())),
              ),
              _MenuCard(
                icon: Icons.science_outlined,
                iconColor: Brand.purple,
                title: 'Strategy Backtest',
                subtitle: 'Test a strategy against real price history',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BacktestScreen())),
              ),
              const SizedBox(height: 18),

              // ---- PLANNING ----
              const _SectionLabel('PLANNING'),
              _MenuCard(
                icon: Icons.savings,
                iconColor: Brand.teal,
                title: 'Financial Planner',
                subtitle: 'Risk profile + how much to invest monthly',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PlannerScreen())),
              ),
              _MenuCard(
                icon: Icons.account_balance,
                iconColor: Brand.teal,
                title: 'Core Wealth Planning',
                subtitle: 'Goal check, allocation and live fund returns',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CoreWealthScreen())),
              ),
              _MenuCard(
                icon: Icons.family_restroom,
                iconColor: Brand.teal,
                title: 'Life Goal & Protection',
                subtitle: 'Children, retirement, insurance and rebalancing',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LifeGoalScreen())),
              ),
              _MenuCard(
                icon: Icons.account_balance_wallet,
                iconColor: Brand.teal,
                title: 'Lifestyle & Balance Sheet',
                subtitle: 'Cashflow, net worth, house, car and EMI vs SIP',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LifestyleScreen())),
              ),
              _MenuCard(
                icon: Icons.calculate,
                iconColor: Brand.teal,
                title: 'Calculators',
                subtitle: 'SIP, lumpsum, goal, step-up, SWP and EMI',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CalculatorScreen())),
              ),
              const SizedBox(height: 18),

              // ---- MONEY MANAGEMENT ----
              const _SectionLabel('MONEY MANAGEMENT'),
              _MenuCard(
                icon: Icons.receipt_long_outlined,
                iconColor: Brand.gold,
                title: 'Tax Calculator',
                subtitle: 'STCG/LTCG from your real trades',
                onTap: () {
                  final email = AuthService.email;
                  if (email == null || email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Sign in to use the tax calculator')),
                    );
                    return;
                  }
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => TaxScreen(userEmail: email)));
                },
              ),
              _MenuCard(
                icon: Icons.savings_outlined,
                iconColor: Brand.gold,
                title: 'Finance Tracker',
                subtitle: 'Spending, loans, debt & pending dues',
                onTap: () {
                  final email = AuthService.email;
                  if (email == null || email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Sign in to use the finance tracker')),
                    );
                    return;
                  }
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => FinanceScreen(userEmail: email)));
                },
              ),
              const SizedBox(height: 24),

              const Text('POPULAR',
                  style: TextStyle(
                      color: Brand.mint,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'RELIANCE',
                  'TCS',
                  'HDFCBANK',
                  'INFY',
                  'ICICIBANK',
                  'ITC',
                ].map((s) => ActionChip(
                      label: Text(s),
                      backgroundColor: Brand.fern.withValues(alpha: 0.4),
                      labelStyle: const TextStyle(color: Brand.paper),
                      side: BorderSide(
                          color: Brand.mint.withValues(alpha: 0.15)),
                      onPressed: () => _openStock(s),
                    )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple styled dropdown for the sector/cap search filters - matches
/// the app's dark-card visual language rather than the platform default.
class _FilterDropdown extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Brand.mint.withValues(alpha: 0.22)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Brand.fern,
          icon: const Icon(Icons.expand_more, color: Brand.mint, size: 18),
          style: const TextStyle(color: Brand.paper, fontSize: 12),
          items: options
              .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// One reusable card for every home-screen menu item - replaces what was
/// ~15 separate, nearly-identical Card/InkWell/Row blocks with a single
/// widget, so future visual changes only need to happen in one place.
class _MenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.75),
                            fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Brand.mint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small caps category label above each group of menu cards - same
/// styling as the existing 'POPULAR' label, extracted for reuse.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              color: Brand.mint,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold)),
    );
  }
}

/// Shows whether the phone can actually reach the Python API.
/// This is the #1 thing that goes wrong, so we surface it clearly
/// instead of letting the user hit a mysterious error later.
class _ConnectionBanner extends StatelessWidget {
  final bool? apiUp;
  final VoidCallback onRetry;

  const _ConnectionBanner({required this.apiUp, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (apiUp == null) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Connecting to the API…',
              style: TextStyle(color: Brand.mint, fontSize: 13)),
        ),
      );
    }

    if (apiUp == true) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Brand.green),
          title: const Text('Connected to backend',
              style: TextStyle(color: Brand.green, fontSize: 13)),
          subtitle: Text(ApiService.baseUrl,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Brand.red),
                SizedBox(width: 10),
                Text("Can't reach the API",
                    style: TextStyle(
                        color: Brand.red, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Check that:\n'
              '1. The Python API is running (uvicorn api:app)\n'
              '2. The URL is right for where you are running this\n'
              '   • Emulator → http://10.0.2.2:8000\n'
              '   • Real phone → http://<your-PC-IP>:8000',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.5),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
