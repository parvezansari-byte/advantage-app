// lib/screens/crm_followups_screen.dart
//
// Client follow-ups that are overdue or due in the next 30 days.
// Data: GET /crm/{owner}/followups. Tap the calendar to move one, the tick to mark it done.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;
import 'followup_dialog.dart';

class CrmFollowupsScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmFollowupsScreen({super.key, required this.ownerEmail});

  @override
  State<CrmFollowupsScreen> createState() => _CrmFollowupsScreenState();
}

class _CrmFollowupsScreenState extends State<CrmFollowupsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
              '${ApiService.baseUrl}/crm/${widget.ownerEmail}/followups?days=30'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _items = (j['followups'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _done(Map<String, dynamic> f) async {
    try {
      await http
          .delete(Uri.parse('${ApiService.baseUrl}/crm/${widget.ownerEmail}'
              '/clients/${f['client_id']}/followup'))
          .timeout(const Duration(seconds: 30));
    } catch (_) {}
    _load();
  }

  Future<void> _move(Map<String, dynamic> f) async {
    final changed = await editFollowup(context,
        ownerEmail: widget.ownerEmail,
        clientId: f['client_id'] as int,
        clientName: '${f['client_name']}');
    if (changed == true) _load();
  }

  String _when(Map<String, dynamic> f) {
    final n = f['days_until'] as int;
    if (n < 0) return '${-n} day${n == -1 ? '' : 's'} overdue';
    if (n == 0) return 'Due today';
    if (n == 1) return 'Tomorrow';
    return 'In $n days · ${f['due_date']}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Follow-ups',
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
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Nothing due in the next 30 days.\nSet a follow-up from a client page: three dots > Follow-up.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.mint)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final f in _items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: f['overdue'] == true
                      ? Brand.red.withValues(alpha: 0.6)
                      : Colors.transparent),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f['client_name']}',
                      style: const TextStyle(
                          color: Brand.paper,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(_when(f),
                      style: TextStyle(
                          color: f['overdue'] == true ? Brand.red : Brand.gold,
                          fontSize: 12)),
                  if ('${f['note']}'.isNotEmpty)
                    Text('${f['note']}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.85),
                            fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: 'Move',
                icon: const Icon(Icons.event_repeat, color: Brand.gold),
                onPressed: () => _move(f),
              ),
              IconButton(
                tooltip: 'Done',
                icon: const Icon(Icons.check_circle_outline, color: Brand.green),
                onPressed: () => _done(f),
              ),
            ]),
          ),
      ],
    );
  }
}
