// lib/screens/sms_tracking_screen.dart
//
// Lets the user turn on automatic expense-logging from bank debit-alert SMS,
// grant the SMS permission, manually scan recent messages, and see what's
// been auto-logged so far. Android only.

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/sms_transaction_service.dart';

class SmsTrackingScreen extends StatefulWidget {
  final String userEmail;
  const SmsTrackingScreen({super.key, required this.userEmail});

  @override
  State<SmsTrackingScreen> createState() => _SmsTrackingScreenState();
}

class _SmsTrackingScreenState extends State<SmsTrackingScreen> {
  bool _enabled = false;
  bool _loading = true;
  bool _scanning = false;
  String? _status;
  List<Map<String, dynamic>> _log = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await SmsTransactionService.isEnabled();
    final log = await SmsTransactionService.getRecentLog();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _log = log;
        _loading = false;
      });
    }
    if (enabled && Platform.isAndroid) {
      SmsTransactionService.startForegroundListening(widget.userEmail);
    }
  }

  Future<void> _toggle(bool value) async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'SMS reading is not available on iOS — Apple does not allow it.')));
      return;
    }
    if (value) {
      final alreadyDenied = await SmsTransactionService.isPermanentlyDenied();
      if (alreadyDenied) {
        if (mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Brand.vault,
              title: const Text('SMS permission needed',
                  style: TextStyle(color: Brand.paper)),
              content: const Text(
                'SMS permission was denied before, so Android will not show '
                'the request popup again. Turn it on from the app\'s system '
                'settings instead.',
                style: TextStyle(color: Brand.mint),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Open settings')),
              ],
            ),
          );
          if (openSettings == true) {
            await SmsTransactionService.openSettings();
          }
        }
        return;
      }

      final granted = await SmsTransactionService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('SMS permission was not granted.')));
        }
        return;
      }
      SmsTransactionService.startForegroundListening(widget.userEmail);
    }
    await SmsTransactionService.setEnabled(value);
    setState(() => _enabled = value);
  }

  Future<void> _scanNow() async {
    setState(() {
      _scanning = true;
      _status = null;
    });
    try {
      final added =
          await SmsTransactionService.scanRecentInbox(widget.userEmail);
      final log = await SmsTransactionService.getRecentLog();
      if (mounted) {
        setState(() {
          _log = log;
          _status = added == 0
              ? 'No new bank debit messages found.'
              : 'Added $added new expense(s) from your messages.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        title: const Text('SMS Expense Tracking',
            style: TextStyle(color: Brand.gold)),
        iconTheme: const IconThemeData(color: Brand.gold),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('AUTO-LOG FROM BANK SMS',
                      style: TextStyle(
                          color: Brand.gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'When enabled, debit-alert SMS from your bank (e.g. '
                    '"Rs 500 debited...") are automatically added as '
                    'expenses in Finance Tracker. Android only — this '
                    'cannot work on iOS. Only reliably catches messages '
                    'received while the app is open; use "Scan Now" to '
                    'catch up on anything received while it was closed.',
                    style: TextStyle(color: Brand.mint, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: SwitchListTile(
                      title: const Text('Enable SMS auto-tracking',
                          style: TextStyle(color: Brand.paper)),
                      value: _enabled,
                      activeColor: Brand.gold,
                      onChanged: _toggle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Brand.fern,
                        foregroundColor: Brand.paper,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: (_enabled && !_scanning) ? _scanNow : null,
                    icon: _scanning
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Brand.paper))
                        : const Icon(Icons.sync),
                    label:
                        Text(_scanning ? 'Scanning…' : 'Scan Recent Messages Now'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Text(_status!,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.8),
                            fontSize: 12)),
                  ],
                  const SizedBox(height: 24),
                  const Text('RECENTLY AUTO-LOGGED',
                      style: TextStyle(
                          color: Brand.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 10),
                  if (_log.isEmpty)
                    Text('Nothing logged yet.',
                        style:
                            TextStyle(color: Brand.mint.withValues(alpha: 0.6)))
                  else
                    ..._log.map((e) => Card(
                          child: ListTile(
                            title: Text(
                                '₹${(e['amount'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Brand.paper,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${e['merchant']} · ${(e['date'] as String).split('T').first}',
                                style: TextStyle(
                                    color: Brand.mint.withValues(alpha: 0.7))),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
