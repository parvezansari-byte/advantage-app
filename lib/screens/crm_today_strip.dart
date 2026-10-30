// lib/screens/crm_today_strip.dart
//
// A row of tappable chips above the client list:
//   funds behind benchmark  ->  Review watch
//   birthdays this week     ->  Reminders
//   KYC pending             ->  Reminders
// Reminder counts load first (fast); the behind-benchmark count loads on its own
// because it needs live NAVs. Any failure just hides that chip.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;
import 'crm_reminders_screen.dart';
import 'crm_watch_screen.dart';

class CrmTodayStrip extends StatefulWidget {
  final String ownerEmail;
  const CrmTodayStrip({super.key, required this.ownerEmail});

  @override
  State<CrmTodayStrip> createState() => _CrmTodayStripState();
}

class _CrmTodayStripState extends State<CrmTodayStrip> {
  int? _birthdays; // in the next 7 days
  int? _today; // birthdays today
  int? _kyc;
  int? _behind;
  bool _behindLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
    _loadBehind();
  }

  Future<Map<String, dynamic>?> _get(String path, int seconds) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}$path'))
          .timeout(Duration(seconds: seconds));
      if (res.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadReminders() async {
    final j = await _get('/crm/${widget.ownerEmail}/reminders?days=7', 45);
    if (!mounted || j == null) return;
    final c = Map<String, dynamic>.from((j['counts'] ?? {}) as Map);
    setState(() {
      _birthdays = (c['birthdays'] ?? 0) as int;
      _today = (c['today'] ?? 0) as int;
      _kyc = (c['kyc_pending'] ?? 0) as int;
    });
  }

  Future<void> _loadBehind() async {
    final j = await _get('/crm/${widget.ownerEmail}/review-watch', 90);
    if (!mounted) return;
    setState(() {
      _behindLoading = false;
      if (j != null) {
        final c = Map<String, dynamic>.from((j['counts'] ?? {}) as Map);
        _behind = (c['behind'] ?? 0) as int;
      }
    });
  }

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (_behindLoading) {
      chips.add(_chip(Icons.trending_down, 'Checking funds…', Brand.mint, null));
    } else if (_behind != null) {
      chips.add(_chip(
          Icons.trending_down,
          _behind == 0 ? 'No fund behind' : '$_behind behind benchmark',
          _behind == 0 ? Brand.mint : Brand.red,
          () => _open(CrmWatchScreen(ownerEmail: widget.ownerEmail))));
    }
    if (_birthdays != null) {
      final label = (_today ?? 0) > 0
          ? '$_today birthday${_today == 1 ? '' : 's'} today'
          : _birthdays == 0
              ? 'No birthdays this week'
              : '$_birthdays birthday${_birthdays == 1 ? '' : 's'} this week';
      chips.add(_chip(Icons.cake_outlined, label,
          (_birthdays ?? 0) > 0 ? Brand.gold : Brand.mint,
          () => _open(CrmRemindersScreen(ownerEmail: widget.ownerEmail))));
    }
    if (_kyc != null && _kyc! > 0) {
      chips.add(_chip(Icons.badge_outlined, '$_kyc KYC pending', Brand.gold,
          () => _open(CrmRemindersScreen(ownerEmail: widget.ownerEmail))));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color, VoidCallback? onTap) =>
      ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        backgroundColor: Brand.fern.withValues(alpha: 0.6),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        onPressed: onTap,
      );
}
