// lib/services/client_summary_share.dart
//
// Fetches a WhatsApp-ready portfolio summary for a client from the API and
// opens WhatsApp addressed to the client's saved phone number. If there is no
// phone number or WhatsApp can't be opened, the text is copied instead.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart' show ApiService;
import 'authed_http.dart' as http;

Future<void> shareClientSummary(
    BuildContext context, String ownerEmail, int clientId) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing summary…')));
  try {
    final res = await http
        .get(Uri.parse(
            '${ApiService.baseUrl}/crm/$ownerEmail/clients/$clientId/summary-text'))
        .timeout(const Duration(seconds: 60));
    final j = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
    }
    final text = '${j['text']}';
    final digits = '${j['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    messenger.hideCurrentSnackBar();
    if (digits.isNotEmpty) {
      final number = digits.length == 10 ? '91$digits' : digits;
      final uri =
          Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(
        content: Text(digits.isEmpty
            ? 'No phone number saved. Summary copied, paste it into any chat.'
            : 'Could not open WhatsApp. Summary copied instead.')));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text('Could not prepare the summary: '
            '${'$e'.replaceFirst('Exception: ', '')}')));
  }
}
