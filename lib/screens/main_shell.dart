// lib/screens/main_shell.dart
//
// Bottom navigation shell. Each tab hosts one of the existing screens.
// The screens keep their own Scaffold/AppBar — we simply switch between
// them with an IndexedStack so each tab preserves its state.

import 'package:flutter/material.dart';
import '../main.dart';
import 'home_screen.dart';
import 'market_screen.dart';
import 'funds_screen.dart';
import 'doctor_screen.dart';
import 'xray_screen.dart';

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
    FundsScreen(),
    DoctorScreen(),
    XrayScreen(),
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
            icon: Icon(Icons.pie_chart_outline, color: Brand.mint),
            selectedIcon: Icon(Icons.pie_chart, color: Brand.gold),
            label: 'Funds',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined, color: Brand.mint),
            selectedIcon: Icon(Icons.medical_services, color: Brand.gold),
            label: 'Doctor',
          ),
          NavigationDestination(
            icon: Icon(Icons.biotech_outlined, color: Brand.mint),
            selectedIcon: Icon(Icons.biotech, color: Brand.gold),
            label: 'X-ray',
          ),
        ],
      ),
    );
  }
}
