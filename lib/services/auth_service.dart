// lib/services/auth_service.dart
//
// Login / signup against the same Supabase users as the web app.
//
// NOTE ON SESSION PERSISTENCE
// ---------------------------
// This deliberately does NOT use the shared_preferences plugin. That plugin
// requires Windows symlink support (Developer Mode), which is blocked by policy
// on this machine — so it cannot build.
//
// Consequence: the session lives in memory only, so you log in again each time
// the app restarts. Everything else works normally.
//
// If Developer Mode ever becomes available, swapping back to shared_preferences
// is a small change — the interface below stays identical.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AuthService {
  static String? _email;
  static String? _name;

  static String? get email => _email;
  static String? get name => _name;
  static bool get isLoggedIn => _email != null;

  /// No-op: nothing is saved to disk without a storage plugin.
  /// Kept so main.dart needs no change if persistence is added later.
  static Future<void> restore() async {}

  static void _setSession(String email, String name) {
    _email = email;
    _name = name;
  }

  static Future<void> logout() async {
    _email = null;
    _name = null;
  }

  static Future<void> login(String email, String password) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) {
      final d = jsonDecode(r.body);
      _setSession(d['email'], d['name'] ?? '');
      return;
    }
    if (r.statusCode == 401) {
      throw ApiException("Email or password doesn't match");
    }
    throw ApiException(_detail(r) ?? 'Login failed (${r.statusCode})');
  }

  static Future<void> signup(
      String email, String password, String name) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(
              {'email': email, 'password': password, 'name': name}),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) {
      final d = jsonDecode(r.body);
      _setSession(d['email'], d['name'] ?? '');
      return;
    }
    if (r.statusCode == 409) {
      throw ApiException('An account with this email already exists');
    }
    throw ApiException(_detail(r) ?? 'Signup failed (${r.statusCode})');
  }

  // =========================================================================
  // EMAIL VERIFICATION & PASSWORD RESET
  // =========================================================================

  /// Ask the server to email a signup verification code.
  static Future<void> requestSignupOtp(String email) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/signup/request-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) return;
    if (r.statusCode == 409) {
      throw ApiException(
          'An account with this email already exists. Sign in instead.');
    }
    throw ApiException(_detail(r) ?? 'Could not send the code');
  }

  /// Create the account with the emailed code.
  static Future<void> verifySignup({
    required String email,
    required String password,
    required String name,
    required String code,
  }) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/signup/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'name': name,
            'code': code,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) {
      final d = jsonDecode(r.body);
      _setSession(d['email'], d['name'] ?? '');
      return;
    }
    throw ApiException(_detail(r) ?? 'Verification failed');
  }

  /// Ask the server to email a password reset code.
  static Future<void> requestResetOtp(String email) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/reset/request-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) return;
    throw ApiException(_detail(r) ?? 'Could not send the code');
  }

  /// Set a new password using the emailed code.
  static Future<void> verifyReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final r = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/reset/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'code': code,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 200) return;
    throw ApiException(_detail(r) ?? 'Could not reset the password');
  }

  /// Pull the human-readable reason out of FastAPI's error body.
  static String? _detail(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      return d['detail']?.toString();
    } catch (_) {
      return null;
    }
  }
}
