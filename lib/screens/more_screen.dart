// lib/screens/more_screen.dart
//
// Central hub for everything not in the main 5 bottom-nav tabs: Doctor
// and Reports (moved out of the bottom bar to keep it from getting
// crowded), plus a full index of every other screen already reachable
// from Home's menu cards - so More is a complete map of the app, while
// Home keeps its own shortcuts too.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'doctor_screen.dart';
import 'research_reports_screen.dart';
import 'chart_screen.dart';
import 'sectors_screen.dart';
import 'news_screen.dart';
import 'options_screen.dart';
import 'portfolio_screen.dart';
import 'holdings_screen.dart';
import 'xray_screen.dart';
import 'backtest_screen.dart';
import 'planner_screen.dart';
import 'core_wealth_screen.dart';
import 'life_goal_screen.dart';
import 'lifestyle_screen.dart';
import 'calculator_screen.dart';
import 'tax_screen.dart';
import 'finance_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _requireEmail(
    BuildContext context, {
    required String message,
    required Widget Function(String email) builder,
  }) {
    final email = AuthService.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => builder(email)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('More',
              style: TextStyle(
                  color: Brand.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Everything else in Advantage.',
              style: TextStyle(color: Brand.mint, fontSize: 13)),
          const SizedBox(height: 20),

          _MenuCard(
            icon: Icons.medical_services,
            iconColor: Brand.blue,
            title: 'Doctor',
            subtitle: 'Portfolio health check and diagnosis',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DoctorScreen())),
          ),
          _MenuCard(
            icon: Icons.picture_as_pdf,
            iconColor: Brand.blue,
            title: 'Research Reports',
            subtitle: 'Full PDF report with AI analysis and links',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ResearchReportsScreen())),
          ),
          const SizedBox(height: 18),

          const _SectionLabel('RESEARCH'),
          _MenuCard(
            icon: Icons.candlestick_chart,
            iconColor: Brand.mint,
            title: 'Live Chart',
            subtitle: 'Intraday and long-term price charts',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChartScreen())),
          ),
          _MenuCard(
            icon: Icons.donut_small,
            iconColor: Brand.mint,
            title: 'Sector Performance',
            subtitle: 'Which sectors are leading and lagging',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SectorsScreen())),
          ),
          _MenuCard(
            icon: Icons.newspaper,
            iconColor: Brand.mint,
            title: 'Market Terminal',
            subtitle: 'FII/DII flows and live market news',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NewsScreen())),
          ),
          _MenuCard(
            icon: Icons.stacked_bar_chart,
            iconColor: Brand.mint,
            title: 'Option Chain',
            subtitle: 'PCR, max pain and open interest by strike',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OptionsScreen())),
          ),
          const SizedBox(height: 18),

          const _SectionLabel('PORTFOLIO'),
          _MenuCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: Brand.purple,
            title: 'My Portfolio',
            subtitle: 'Track your holdings and live P&L',
            onTap: () => _requireEmail(
              context,
              message: 'Sign in to track your portfolio',
              builder: (email) => PortfolioScreen(email: email),
            ),
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

          const _SectionLabel('MONEY MANAGEMENT'),
          _MenuCard(
            icon: Icons.receipt_long_outlined,
            iconColor: Brand.gold,
            title: 'Tax Calculator',
            subtitle: 'STCG/LTCG from your real trades',
            onTap: () => _requireEmail(
              context,
              message: 'Sign in to use the tax calculator',
              builder: (email) => TaxScreen(userEmail: email),
            ),
          ),
          _MenuCard(
            icon: Icons.savings_outlined,
            iconColor: Brand.gold,
            title: 'Finance Tracker',
            subtitle: 'Spending, loans, debt & pending dues',
            onTap: () => _requireEmail(
              context,
              message: 'Sign in to use the finance tracker',
              builder: (email) => FinanceScreen(userEmail: email),
            ),
          ),
          const SizedBox(height: 18),

          _ExternalLinksSection(),
        ],
      ),
    );
  }
}

class _ExternalLinksSection extends StatelessWidget {
  static const _links = [
    ('AdvisorKhoj', 'https://www.advisorkhoj.com', '\ud83c\udfaf'),
    ('Value Research', 'https://www.valueresearchonline.com', '\u2705'),
    ('Morningstar India', 'https://www.morningstar.in', '\ud83c\udf1f'),
    ('Moneycontrol', 'https://www.moneycontrol.com', '\ud83d\udcb0'),
    ('AMFI India', 'https://www.amfiindia.com', '\ud83c\udfdb\ufe0f'),
    ('NSE India', 'https://www.nseindia.com', '\ud83d\udcc8'),
    ('Wealthy', 'https://www.wealthy.in', '\ud83d\udcbc'),
  ];

  Future<void> _open(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.link, color: Brand.gold, size: 18),
          title: const Text('EXTERNAL RESEARCH LINKS',
              style: TextStyle(
                  color: Brand.paper,
                  fontSize: 12.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.bold)),
          iconColor: Brand.mint,
          collapsedIconColor: Brand.mint,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _links.map((l) {
                final (label, url, emoji) = l;
                return OutlinedButton(
                  onPressed: () => _open(context, url),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.paper,
                    side: BorderSide(color: Brand.mint.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(label, style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same card styling as Home's menu cards - kept as a separate copy here
/// (rather than shared) since it's a tiny private widget and this avoids
/// touching home_screen.dart at all.
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold)),
    );
  }
}
