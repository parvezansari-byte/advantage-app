// lib/screens/notifications_screen.dart
//
// Notifications list + the bell (with unread count) used on the home screen.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/notifications_service.dart';

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}

IconData _iconFor(String kind) {
  switch (kind) {
    case 'signal':
      return Icons.show_chart;
    case 'digest':
      return Icons.article_outlined;
    case 'nav':
      return Icons.trending_up;
    case 'test':
      return Icons.notifications_active_outlined;
    default:
      return Icons.notifications_none;
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final res = await NotificationsService.fetch();
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
      // Keep the unread dots visible on this view, but clear the bell's count.
      if (res.unread > 0) {
        try {
          await NotificationsService.markAllRead();
        } catch (_) {}
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not reach the server. Pull down to try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : RefreshIndicator(
              color: Brand.gold,
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Brand.red)),
                        ),
                      ),
                    ])
                  : _items.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Icon(Icons.notifications_none,
                              size: 48, color: Brand.mint.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'No alerts yet.\nSignal changes and the hourly\nmarket digest will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.7)),
                            ),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _NotificationCard(_items[i]),
                        ),
            ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification n;
  const _NotificationCard(this.n);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: n.read ? 0.25 : 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: n.read
                ? Brand.mint.withValues(alpha: 0.1)
                : Brand.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(n.kind), color: Brand.gold, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n.title,
                          style: const TextStyle(
                              color: Brand.paper,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                    if (!n.read)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                            color: Brand.gold, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(n.body,
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          height: 1.35)),
                ],
                const SizedBox(height: 8),
                Text(_ago(n.createdAt),
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bell for the home header. Shows the unread count and opens the list.
/// Hides itself if the server says this account has no alerts (non-owner).
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final res = await NotificationsService.fetch(limit: 1);
      if (mounted) setState(() { _available = true; _unread = res.unread; });
    } catch (_) {
      if (mounted) setState(() => _available = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Brand.mint, size: 22),
          tooltip: 'Notifications',
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            _refresh();
          },
        ),
        if (_unread > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: Brand.red, borderRadius: BorderRadius.circular(10)),
                child: Text(_unread > 99 ? '99+' : '$_unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }
}
