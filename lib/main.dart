// lib/main.dart
//
// Advantage — Flutter app
// Talks to your Python FastAPI backend (api.py).

import 'package:flutter/material.dart';
import 'screens/main_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore a saved session so returning users skip the login screen.
  await AuthService.restore();
  runApp(const ResearchApp());
}

/// Brand colours — same identity as the web platform.
class Brand {
  static const vault = Color(0xFF0A2E24);   // deep green background
  static const fern = Color(0xFF1C5943);    // lighter green
  static const gold = Color(0xFFC9A227);    // accent
  static const paper = Color(0xFFFBFAF7);   // near-white text
  static const mint = Color(0xFFDCEFE6);    // muted text
  static const green = Color(0xFF10B981);   // gains
  static const red = Color(0xFFEF4444);     // losses
  // Category accent colors, tuned bright enough to stay visible against
  // the dark green background (unlike the web app's palette, which
  // assumes a light background) - used to group the home screen menu
  // into labeled sections instead of one long gold-only list.
  static const blue = Color(0xFF6C8EF5);
  static const purple = Color(0xFFB88CF0);
  static const teal = Color(0xFF4FC3C9);
}

class ResearchApp extends StatelessWidget {
  const ResearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advantage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Brand.vault,
        colorScheme: const ColorScheme.dark(
          primary: Brand.gold,
          surface: Brand.vault,
          onSurface: Brand.paper,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.gold,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Brand.fern.withValues(alpha: 0.35),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Brand.mint.withValues(alpha: 0.12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Brand.fern.withValues(alpha: 0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
        ),
      ),
      home: AuthService.isLoggedIn
          ? const MainShell()
          : const LoginScreen(),
    );
  }
}
