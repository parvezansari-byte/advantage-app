// lib/services/push_service.dart
//
// Firebase Cloud Messaging (push notifications), Android only for now.
//
// - While the app is CLOSED or in the background, Android shows the
//   notification in the system tray by itself - no Dart code runs.
// - While the app is OPEN, FCM doesn't display anything, so we show a
//   SnackBar instead (see _showForeground).
// - If Firebase isn't configured in this build (no google-services.json yet),
//   init() quietly does nothing and the rest of the app is unaffected.

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'auth_service.dart';

class PushService {
  PushService._();

  /// Hooked into MaterialApp so foreground messages can show a SnackBar from
  /// anywhere in the app.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static bool _ready = false;
  static String? _registeredFor; // "email|token" last sent to the server

  /// Call once from main(), before runApp.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('Push disabled (Firebase not configured in this build): $e');
      return;
    }
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.instance.onTokenRefresh.listen(_register);
  }

  /// Call after the user is logged in: asks for notification permission and
  /// registers this phone's token against their email on the server.
  static Future<void> syncToken() async {
    if (!_ready) return;
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _register(token);
    } catch (e) {
      debugPrint('Push token sync failed: $e');
    }
  }

  static Future<void> _register(String token) async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    final key = '$email|$token';
    if (_registeredFor == key) return;
    try {
      final r = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/push/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'email': email, 'token': token, 'platform': 'android'}),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 200) _registeredFor = key;
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  /// Asks the server to push a test notification to this account's phones.
  /// Returns a human-readable result for a SnackBar.
  static Future<String> sendTest() async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return 'Sign in first.';
    if (!_ready) {
      return 'Push is not set up in this build yet (Firebase config missing).';
    }
    await syncToken();
    try {
      final r = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/push/test'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 60));
      final body = jsonDecode(r.body);
      if (r.statusCode == 200) {
        return 'Sent to ${body['sent']} of ${body['devices']} device(s). '
            'Close the app to see it in the tray.';
      }
      return '${body['detail'] ?? 'Test failed (${r.statusCode})'}';
    } catch (e) {
      return 'Test failed: $e';
    }
  }

  static void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.title != null)
              Text(n.title!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            if (n.body != null) Text(n.body!),
          ],
        ),
      ),
    );
  }
}
