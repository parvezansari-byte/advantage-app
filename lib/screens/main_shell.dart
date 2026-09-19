// lib/screens/main_shell.dart
//
// Bottom navigation shell. Each tab hosts one of the existing screens.
// The screens keep their own Scaffold/AppBar — we simply switch between
// them with an IndexedStack so each tab preserves its state.
//
// Trimmed to 5 tabs (Research, Markets, Stocks, Funds, More) so the bar
// doesn't get crowded — Doctor, Reports, and everything else now live
// inside the More tab (see more_screen.dart), alongside Home's own
// menu-card shortcuts to the same screens.
import 'package:flutter/material.dart';
import '../main.dart';
import 'home_screen.dart';
import 'market_screen.dart';
import 'stocks_screen.dart';
import 'funds_screen.dart';
import 'more_screen.dart';
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _tabs = const [
    HomeScreen(),
    MarketScreen(),
    StocksScreen(),
    FundsScreen(),
    MoreScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Brand.fern.withValues(alpha: 0.55),
        indicatorColor: Brand.gold.withValues(alpha: 0.25),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search, color: Brand.mint),
            selectedIcon: Icon(Icons.search, color: Brand.gold),
            label: 'Research',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart, color: Brand.mint),
            selectedIcon: Icon(Icons.show_chart, color: Brand.gold),
            label: 'Markets',
          ),
          NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined, color: Brand.mint),
            selectedIcon: Icon(Icons.candlestick_chart, color: Brand.gold),
            label: 'Stocks',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline, color: Brand.mint),
            selectedIcon: Icon(Icons.pie_chart, color: Brand.gold),
            label: 'Funds',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz, color: Brand.mint),
            selectedIcon: Icon(Icons.more_horiz, color: Brand.gold),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
