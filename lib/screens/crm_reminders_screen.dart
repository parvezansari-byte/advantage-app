// lib/screens/crm_reminders_screen.dart
//
// Upcoming client birthdays (next 30 days) and clients whose KYC isn't cleared.
// Data: GET /crm/{owner}/reminders. A daily push covers "birthday today".

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class CrmRemindersScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmRemindersScreen({super.key, required this.ownerEmail});

  @override
  State<CrmRemindersScreen> createState() => _CrmRemindersScreenState();
}

class _CrmRemindersScreenState extends State<CrmRemindersScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _birthdays = [];
  List<Map<String, dynamic>> _kyc = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse(
              '${ApiService.baseUrl}/crm/${widget.ownerEmail}/reminders?days=30'))
          .timeout(const Duration(seconds: 60));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(body is Map ? (body['detail'] ?? res.body) : res.body);
      }
      List<Map<String, dynamic>> L(dynamic v) => (v as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _birthdays = L(body['birthdays']);
        _kyc = L(body['kyc_pending']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _when(Map<String, dynamic> b) {
    final n = b['days_until'] as int;
    if (n == 0) return 'Today';
    if (n == 1) return 'Tomorrow';
    final d = DateTime.tryParse('${b['date']}');
    return d == null ? 'In $n days' : '${d.day} ${_months[d.month - 1]} · in $n days';
  }

  Future<void> _wish(Map<String, dynamic> b) async {
    final phone = (b['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number saved for this client')));
      return;
    }
    final number = phone.length == 10 ? '91$phone' : phone;
    final text = Uri.encodeComponent(
        'Happy Birthday ${b['client_name']}! Wishing you a wonderful year ahead.');
    final ok = await launchUrl(Uri.parse('https://wa.me/$number?text=$text'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Reminders',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.red)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _title('Birthdays in the next 30 days'),
        if (_birthdays.isEmpty) _empty('No birthdays coming up.'),
        for (final b in _birthdays)
          _tile(
            icon: Icons.cake_outlined,
            title: '${b['client_name']}  ·  turning ${b['turning']}',
            sub: _when(b),
            accent: b['days_until'] == 0 ? Brand.gold : Brand.mint,
            trailing: IconButton(
              tooltip: 'Send a WhatsApp wish',
              icon: const Icon(Icons.chat_outlined, color: Brand.green),
              onPressed: () => _wish(b),
            ),
          ),
        _title('KYC not cleared'),
        if (_kyc.isEmpty) _empty('Every client is KYC cleared.'),
        for (final k in _kyc)
          _tile(
            icon: Icons.badge_outlined,
            title: '${k['client_name']}',
            sub: '${k['status']}'.replaceAll('_', ' ').toLowerCase(),
            accent: ('${k['status']}' == 'HOLD' || '${k['status']}' == 'REJECTED')
                ? Brand.red
                : Brand.gold,
          ),
      ],
    );
  }

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(s,
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _empty(String s) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(s, style: const TextStyle(color: Brand.mint, fontSize: 13)),
      );

  Widget _tile(
          {required IconData icon,
          required String title,
          required String sub,
          required Color accent,
          Widget? trailing}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(color: Brand.paper, fontSize: 14)),
              Text(sub, style: TextStyle(color: accent, fontSize: 12)),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
      );
}
