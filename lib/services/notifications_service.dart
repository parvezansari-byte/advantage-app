// lib/services/notifications_service.dart
//
// The list of push alerts the server has sent (signal flips, hourly digest,
// tests). Only the account owner has any; everyone else gets a 403, which the
// bell treats as "hide yourself".

import 'dart:convert';
import 'authed_http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';

class AppNotification {
  final int id;
  final String title;
  final String body;
  final String kind; // signal | digest | test | info
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        kind: (j['kind'] ?? 'info').toString(),
        read: j['read'] == true,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString())?.toLocal(),
      );
}

class NotificationsResult {
  final List<AppNotification> items;
  final int unread;
  const NotificationsResult(this.items, this.unread);
}

class NotificationsService {
  static String _base() {
    final email = AuthService.email;
    if (email == null || email.isEmpty) {
      throw ApiException('Sign in to see notifications');
    }
    return '${ApiService.baseUrl}/push/${Uri.encodeComponent(email)}/history';
  }

  static String? _detail(http.Response r) {
    try {
      return jsonDecode(r.body)['detail']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<NotificationsResult> fetch({int limit = 50}) async {
    final r = await http
        .get(Uri.parse('${_base()}?limit=$limit'))
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw ApiException(_detail(r) ?? 'Could not load notifications (${r.statusCode})');
    }
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (d['items'] as List? ?? [])
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return NotificationsResult(items, (d['unread'] as num?)?.toInt() ?? 0);
  }

  static Future<void> markAllRead() async {
    final r = await http
        .post(Uri.parse('${_base()}/read'))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw ApiException(_detail(r) ?? 'Could not mark as read (${r.statusCode})');
    }
  }
}
