// lib/screens/crm_import_holdings_screen.dart
//
// Bulk-add a client's holdings from a CSV file. Columns (header row, any
// order): scheme_code or fund/scheme name, units, avg_nav (average buy NAV),
// optional buy_date (yyyy-mm-dd) and folio. The server checks every row first
// (preview), then saves the valid ones.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/holdings_api_service.dart';

class CrmImportHoldingsScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const CrmImportHoldingsScreen(
      {super.key, required this.ownerEmail, required this.client});

  @override
  State<CrmImportHoldingsScreen> createState() =>
      _CrmImportHoldingsScreenState();
}

class _CrmImportHoldingsScreenState extends State<CrmImportHoldingsScreen> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _preview;
  String? _fileName;
  String? _error;
  bool _busy = false;
  bool _saved = false;

  static List<String> _splitLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQ = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQ && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = !inQ;
        }
      } else if (ch == ',' && !inQ) {
        out.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString().trim());
    return out;
  }

  static int _col(List<String> head, List<String> names) {
    for (var i = 0; i < head.length; i++) {
      if (names.contains(head[i])) return i;
    }
    return -1;
  }

  /// Returns rows for the API, or throws a readable message.
  static List<Map<String, dynamic>> parseCsv(String text) {
    final lines = text
        .replaceAll('\r', '')
        .replaceAll('﻿', '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw 'The file needs a header row and at least one holding.';
    }
    final head = _splitLine(lines.first)
        .map((h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'))
        .toList();
    final cCode = _col(head, ['scheme_code', 'code', 'amfi_code']);
    final cName = _col(head,
        ['scheme_name', 'fund_name', 'fund', 'scheme', 'name']);
    final cUnits = _col(head, ['units', 'quantity', 'qty', 'balance_units']);
    final cNav = _col(head, [
      'avg_nav',
      'average_nav',
      'buy_nav',
      'purchase_nav',
      'avg_price',
      'average_price',
      'nav'
    ]);
    final cDate = _col(head, ['buy_date', 'purchase_date', 'date']);
    final cFolio = _col(head, ['folio', 'folio_number', 'folio_no']);
    if (cCode < 0 && cName < 0) {
      throw 'Add a "scheme_code" or "fund_name" column.';
    }
    if (cUnits < 0 || cNav < 0) {
      throw 'Add "units" and "avg_nav" columns.';
    }
    String? at(List<String> r, int c) =>
        (c >= 0 && c < r.length && r[c].isNotEmpty) ? r[c] : null;
    double? toNum(String? s) =>
        s == null ? null : double.tryParse(s.replaceAll(RegExp(r'[,₹\s]'), ''));
    final out = <Map<String, dynamic>>[];
    for (final line in lines.skip(1)) {
      final r = _splitLine(line);
      out.add({
        'scheme_code': at(r, cCode),
        'scheme_name': at(r, cName),
        'units': toNum(at(r, cUnits)),
        'avg_nav': toNum(at(r, cNav)),
        'buy_date': at(r, cDate),
        'folio_number': at(r, cFolio),
      });
    }
    return out;
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _preview = null;
      _saved = false;
    });
    try {
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (f == null) return;
      setState(() => _busy = true);
      final bytes = await f.readAsBytes();
      final rows = parseCsv(utf8.decode(bytes, allowMalformed: true));
      final p = await HoldingsApiService.importHoldings(
          widget.ownerEmail, widget.client.id!, rows,
          dryRun: true);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _fileName = f.name;
        _preview = p;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await HoldingsApiService.importHoldings(
          widget.ownerEmail, widget.client.id!, _rows);
      if (!mounted) return;
      setState(() {
        _preview = r;
        _saved = true;
        _rows = [];
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final errors = ((p?['errors'] as List?) ?? const []).cast<dynamic>();
    final items = ((p?['preview'] as List?) ?? const []).cast<dynamic>();
    final valid = (p?['valid'] as num?)?.toInt() ?? 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _saved);
      },
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          title: Text('Import holdings - ${widget.client.fullName}',
              style: const TextStyle(fontSize: 16)),
          leading: BackButton(
              onPressed: () => Navigator.pop(context, _saved)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Choose a CSV file with a header row. Columns: scheme_code (or '
              'fund_name), units, avg_nav, and optionally buy_date '
              '(yyyy-mm-dd) and folio. In Excel use File > Save as > CSV. '
              'Funds already held are merged into the existing line.',
              style: TextStyle(color: Brand.mint, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  minimumSize: const Size.fromHeight(46)),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName == null ? 'Choose CSV file' : 'Choose another file'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 13)),
              ),
            if (p != null && _saved)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Done: ${p['added']} added, ${p['merged']} merged'
                  '${errors.isEmpty ? '' : ', ${errors.length} skipped'}.',
                  style: const TextStyle(
                      color: Brand.green, fontWeight: FontWeight.bold),
                ),
              ),
            if (p != null && !_saved) ...[
              const SizedBox(height: 14),
              Text('$_fileName: $valid ready, ${errors.length} with problems',
                  style: const TextStyle(
                      color: Brand.paper, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final it in items.take(60))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${it['row']}. ${it['scheme_name']}  -  '
                    '${it['units']} units @ ${it['avg_nav']}',
                    style: const TextStyle(color: Brand.mint, fontSize: 12),
                  ),
                ),
              if (items.length > 60)
                Text('... and ${items.length - 60} more',
                    style: const TextStyle(color: Brand.mint, fontSize: 12)),
            ],
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Skipped rows',
                  style: TextStyle(
                      color: Brand.red, fontWeight: FontWeight.bold)),
              for (final e in errors.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('Row ${e['row']}: ${e['error']}',
                      style: const TextStyle(color: Brand.red, fontSize: 12)),
                ),
            ],
            if (p != null && !_saved && valid > 0) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Brand.green,
                    foregroundColor: Brand.vault,
                    minimumSize: const Size.fromHeight(46)),
                onPressed: _busy ? null : _import,
                child: Text('Import $valid holdings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
