// lib/services/session.dart
// ---------------------------------------------------------------------------
// Who is signed in.
//
// The login screen knows the email; the portfolio needs it. Rather than
// threading it through every widget in between, it is held here and persisted
// so a restart doesn't sign the user out.
// ---------------------------------------------------------------------------

import 'package:shared_preferences/shared_preferences.dart';

class Session {
  Session._();

  static const _key = 'signed_in_email';

  static String? _email;

  /// Email of the signed-in user, or null when signed out.
  static String? get email => _email;

  static bool get isSignedIn => (_email ?? '').isNotEmpty;

  /// Restore a previous session. Call once at startup, before runApp.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty) _email = saved;
    } catch (_) {
      // A failure here just means the user signs in again — not worth
      // blocking startup for.
    }
  }

  /// Record a successful sign-in.
  static Future<void> signIn(String email) async {
    _email = email.trim().toLowerCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _email!);
    } catch (_) {
      // Held in memory regardless, so the current session still works.
    }
  }

  static Future<void> signOut() async {
    _email = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
