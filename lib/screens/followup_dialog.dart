// lib/screens/followup_dialog.dart
//
// Set, move or clear a client's follow-up (next review date + note).
// Returns true when something changed.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<bool?> editFollowup(BuildContext context,
    {required String ownerEmail,
    required int clientId,
    required String clientName}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _FollowupDialog(
        ownerEmail: ownerEmail, clientId: clientId, clientName: clientName),
  );
}

class _FollowupDialog extends StatefulWidget {
  final String ownerEmail;
  final int clientId;
  final String clientName;
  const _FollowupDialog(
      {required this.ownerEmail,
      required this.clientId,
      required this.clientName});

  @override
  State<_FollowupDialog> createState() => _FollowupDialogState();
}

class _FollowupDialogState extends State<_FollowupDialog> {
  final _note = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 30));
  bool _loading = true;
  bool _busy = false;
  bool _exists = false;
  String? _error;

  String get _url =>
      '${ApiService.baseUrl}/crm/${widget.ownerEmail}/clients/${widget.clientId}/followup';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res =
          await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final f = jsonDecode(res.body)['followup'];
        if (f != null) {
          _exists = true;
          _date = DateTime.tryParse('${f['due_date']}') ?? _date;
          _note.text = '${f['note'] ?? ''}';
        }
      } else {
        _error = 'Could not load (HTTP ${res.statusCode}).';
      }
    } catch (e) {
      _error = 'Could not load: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .put(Uri.parse(_url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'due_date': _ymd(_date), 'note': _note.text}))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final j = jsonDecode(res.body);
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await http.delete(Uri.parse(_url)).timeout(const Duration(seconds: 30));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not clear: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Brand.fern,
      title: Text('Follow-up: ${widget.clientName}',
          style: const TextStyle(color: Brand.paper, fontSize: 16)),
      content: _loading
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(color: Brand.gold)))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.event, color: Brand.gold),
                label: Text(_ymd(_date),
                    style: const TextStyle(color: Brand.gold)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLength: 300,
                maxLines: 2,
                style: const TextStyle(color: Brand.paper),
                decoration: InputDecoration(
                  hintText: 'What to do (optional)',
                  hintStyle:
                      TextStyle(color: Brand.mint.withValues(alpha: 0.6)),
                ),
              ),
              if (_error != null)
                Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 12)),
            ]),
      actions: [
        if (_exists)
          TextButton(
              onPressed: _busy ? null : _clear,
              child: const Text('Clear', style: TextStyle(color: Brand.red))),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Brand.gold, foregroundColor: Brand.vault),
            onPressed: (_busy || _loading) ? null : _save,
            child: const Text('Save')),
      ],
    );
  }
}
