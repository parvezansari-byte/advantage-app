// lib/services/sms_transaction_service.dart
//
// Reads bank debit-alert SMS on the phone and auto-logs them as expenses in
// Finance Tracker. Android only — iOS does not allow third-party apps to
// read SMS at all, so this feature silently does nothing there.
//
// Reliability note: listening for NEW messages only works while the app
// process is alive (foreground, or briefly after backgrounding, before
// Android kills it). Use scanRecentInbox() to catch up on anything the
// live listener missed.

import 'dart:convert';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class ParsedTransaction {
  final double amount;
  final String merchant;
  final String rawBody;
  final DateTime date;

  ParsedTransaction({
    required this.amount,
    required this.merchant,
    required this.rawBody,
    required this.date,
  });
}

class SmsTransactionService {
  static final Telephony _telephony = Telephony.instance;
  static const String _processedKey = 'sms_processed_hashes';
  static const String _enabledKey = 'sms_tracking_enabled';
  static const String _logKey = 'sms_tracking_log';

  /// Whether the user has turned this feature on (persisted locally).
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Whether SMS permission is currently granted.
  static Future<bool> hasPermission() async {
    return Permission.sms.isGranted;
  }

  /// Whether the user has permanently denied SMS permission (checked
  /// "Don't ask again" / denied it a second time) — Android will no longer
  /// show the system dialog in this case, so the only way forward is the
  /// app's own settings screen.
  static Future<bool> isPermanentlyDenied() async {
    return Permission.sms.isPermanentlyDenied;
  }

  /// Asks for SMS permission via the OS runtime-permission dialog. Returns
  /// true if granted.
  ///
  /// Uses permission_handler rather than another_telephony's own
  /// requestPhoneAndSmsPermissions: that method has a known issue on some
  /// Android/plugin-registration combinations where it silently fails
  /// ("No implementation found") and the system dialog never appears at
  /// all, which is what was happening here. permission_handler's SMS
  /// request is far more reliable and widely used for exactly this.
  static Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// Opens the app's own system settings page, for when permission was
  /// permanently denied and the OS will no longer show the request dialog.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Starts listening for new incoming SMS while the app process is alive.
  static void startForegroundListening(String userEmail) {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        _handleMessage(message.body ?? '', message.date, userEmail);
      },
      listenInBackground: false,
    );
  }

  /// Scans the last [days] days of the SMS inbox for bank debit messages
  /// not already logged, and adds them as expenses. Returns how many were
  /// newly added.
  static Future<int> scanRecentInbox(String userEmail, {int days = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    int added = 0;
    for (final m in messages) {
      final ts = m.date;
      if (ts == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(ts);
      if (date.isBefore(cutoff)) break; // sorted newest-first
      final didAdd = await _handleMessage(m.body ?? '', ts, userEmail);
      if (didAdd) added++;
    }
    return added;
  }

  /// Parses [body]; if it looks like a bank debit alert and hasn't been
  /// processed before, logs it as an expense. Returns true if it added one.
  static Future<bool> _handleMessage(
      String body, int? timestampMs, String userEmail) async {
    final parsed = _parseDebitSms(body, timestampMs);
    if (parsed == null) return false;

    final hash = _hashOf(parsed);
    final prefs = await SharedPreferences.getInstance();
    final processed = prefs.getStringList(_processedKey) ?? [];
    if (processed.contains(hash)) return false; // already logged

    try {
      await ApiService.addExpense(
        userEmail,
        amount: parsed.amount,
        category: 'Bank SMS (Auto)',
        description: '[Auto] ${parsed.merchant}',
        expenseDate: '${parsed.date.year.toString().padLeft(4, '0')}-'
            '${parsed.date.month.toString().padLeft(2, '0')}-'
            '${parsed.date.day.toString().padLeft(2, '0')}',
      );
    } catch (_) {
      return false; // network hiccup - don't mark as processed, retry next scan
    }

    processed.add(hash);
    final trimmed = processed.length > 500
        ? processed.sublist(processed.length - 500)
        : processed;
    await prefs.setStringList(_processedKey, trimmed);

    await _appendToLog(parsed);
    return true;
  }

  static String _hashOf(ParsedTransaction t) {
    return '${t.amount}-${t.date.toIso8601String().substring(0, 10)}-'
        '${t.rawBody.hashCode}';
  }

  /// Conservative parser for common Indian bank debit-alert SMS formats
  /// (SBI/HDFC/ICICI/Axis/Kotak and similar). Only fires on messages that
  /// clearly look like a bank debit alert, to avoid logging random
  /// unrelated SMS (like OTP codes) as expenses.
  static ParsedTransaction? _parseDebitSms(String body, int? timestampMs) {
    final text = body.toLowerCase();

    final looksLikeDebit =
        RegExp(r'\b(debited|debit of|spent|withdrawn)\b').hasMatch(text);
    if (!looksLikeDebit) return null;

    final looksLikeBank =
        RegExp(r'\b(a/c|acct|account|avl bal|available balance|bank)\b')
            .hasMatch(text);
    if (!looksLikeBank) return null;

    final amountMatch =
        RegExp(r'(?:rs\.?|inr)\s*\.?\s*([\d,]+(?:\.\d{1,2})?)')
            .firstMatch(text);
    if (amountMatch == null) return null;
    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return null;

    String merchant = 'Bank transaction';
    final atMatch = RegExp(r'\bat\s+([a-z0-9 .&_-]{3,30})').firstMatch(text);
    final towardsMatch =
        RegExp(r'\btowards\s+([a-z0-9 .&_-]{3,30})').firstMatch(text);
    final vpaMatch =
        RegExp(r'\bto\s+vpa\s+([a-z0-9.@_-]{3,40})').firstMatch(text);
    if (atMatch != null) {
      merchant = atMatch.group(1)!.trim();
    } else if (towardsMatch != null) {
      merchant = towardsMatch.group(1)!.trim();
    } else if (vpaMatch != null) {
      merchant = vpaMatch.group(1)!.trim();
    }
    merchant = merchant.isEmpty
        ? 'Bank transaction'
        : merchant[0].toUpperCase() + merchant.substring(1);

    final date = timestampMs != null
        ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
        : DateTime.now();

    return ParsedTransaction(
      amount: amount,
      merchant: merchant,
      rawBody: body,
      date: date,
    );
  }

  // ---- Recent-activity log, shown in the app so the user can see/verify
  // ---- what's been auto-logged (last 50 entries, stored locally only).
  static Future<List<Map<String, dynamic>>> getRecentLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logKey) ?? [];
    return raw.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  static Future<void> _appendToLog(ParsedTransaction t) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logKey) ?? [];
    raw.insert(
        0,
        jsonEncode({
          'amount': t.amount,
          'merchant': t.merchant,
          'date': t.date.toIso8601String(),
        }));
    final trimmed = raw.length > 50 ? raw.sublist(0, 50) : raw;
    await prefs.setStringList(_logKey, trimmed);
  }
}
