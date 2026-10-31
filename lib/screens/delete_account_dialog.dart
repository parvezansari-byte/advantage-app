// lib/screens/delete_account_dialog.dart
//
// "Delete my account" - required by Google Play for apps with accounts.
// Asks for the password and the word DELETE, calls POST /account/delete, and
// reports back through [onDeleted] so the caller can sign out and go to login.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../services/api_service.dart' show ApiService;

Future<void> confirmDeleteAccount(
  BuildContext context, {
  required String email,
  required VoidCallback onDeleted,
}) async {
  final pw = TextEditingController();
  final word = TextEditingController();
  String? error;
  bool busy = false;

  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: Brand.fern,
        title: const Text('Delete account?',
            style: TextStyle(color: Brand.paper)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes $email and the data linked to it '
                '(expenses, loans, holdings, alerts and, for advisors, the '
                'client book). Order records may be kept where the law '
                'requires it. This cannot be undone.',
                style: const TextStyle(color: Brand.mint, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw,
                obscureText: true,
                style: const TextStyle(color: Brand.paper),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              TextField(
                controller: word,
                style: const TextStyle(color: Brand.paper),
                decoration:
                    const InputDecoration(labelText: 'Type DELETE to confirm'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(color: Brand.red, fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.red),
            onPressed: busy
                ? null
                : () async {
                    if (word.text.trim() != 'DELETE') {
                      setS(() => error = 'Type DELETE in capitals to confirm.');
                      return;
                    }
                    if (pw.text.isEmpty) {
                      setS(() => error = 'Enter your password.');
                      return;
                    }
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final r = await http
                          .post(
                            Uri.parse('${ApiService.baseUrl}/account/delete'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(
                                {'email': email, 'password': pw.text}),
                          )
                          .timeout(const Duration(seconds: 60));
                      if (r.statusCode == 200) {
                        if (ctx.mounted) Navigator.pop(ctx, true);
                        return;
                      }
                      var msg = 'Could not delete (${r.statusCode}).';
                      try {
                        final d = jsonDecode(r.body)['detail'];
                        if (d != null) msg = '$d';
                      } catch (_) {}
                      setS(() {
                        busy = false;
                        error = msg;
                      });
                    } catch (_) {
                      setS(() {
                        busy = false;
                        error = 'Could not reach the server. Try again shortly.';
                      });
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Delete forever'),
          ),
        ],
      ),
    ),
  );
  pw.dispose();
  word.dispose();
  if (done == true) onDeleted();
}
