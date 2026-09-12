// lib/utils/holdings_pdf.dart
// ---------------------------------------------------------------------------
// PDF export for Holdings Explorer - Fund Portfolio and Fund Overlap views.
// Same dark olive-green + gold theme as the web app's PDF reports, for
// visual consistency across platforms. Uses "Rs." instead of the rupee
// symbol - the pdf package's built-in fonts don't reliably include that
// glyph, same class of issue as reportlab on the web backend.
// ---------------------------------------------------------------------------

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final _olive = PdfColor.fromHex('#1F2E1A');
final _oliveCard = PdfColor.fromHex('#2A3B22');
final _gold = PdfColor.fromHex('#D4AF37');
final _cream = PdfColor.fromHex('#F5F1E6');
final _sage = PdfColor.fromHex('#B8C4AC');
final _darkBand = PdfColor.fromHex('#12190E');
final _red = PdfColor.fromHex('#DC2626');
final _orange = PdfColor.fromHex('#D97706');
final _yellow = PdfColor.fromHex('#EAB308');
final _lightGreen = PdfColor.fromHex('#65A30D');

PdfColor _overlapColor(double pct) {
  if (pct >= 60) return _red;
  if (pct >= 40) return _orange;
  if (pct >= 20) return _yellow;
  return _lightGreen;
}

pw.Widget _header(String title, String subtitle) {
  return pw.Container(
    width: double.infinity,
    color: _gold,
    padding: const pw.EdgeInsets.fromLTRB(20, 20, 20, 16),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _darkBand)),
        pw.SizedBox(height: 4),
        pw.Text(subtitle,
            style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#3A2E0F'))),
      ],
    ),
  );
}

pw.Widget _statCard(String value, String label) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: pw.BoxDecoration(
      color: _oliveCard,
      border: pw.Border.all(color: _gold, width: 1),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: _gold)),
        pw.SizedBox(height: 4),
        pw.Text(label,
            style: pw.TextStyle(fontSize: 8, color: _sage),
            textAlign: pw.TextAlign.center),
      ],
    ),
  );
}

pw.Widget _disclaimer() {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 20),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _sage, width: 0.5),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      'Disclaimer: This report is generated from AMC monthly portfolio '
      'disclosures and is for informational purposes only. It does not '
      'constitute investment advice or a recommendation to buy, hold, or '
      'sell any security. Holdings data may be delayed relative to the '
      "fund's current actual portfolio. Please consult a qualified "
      'financial advisor before making investment decisions.',
      style: pw.TextStyle(fontSize: 7.5, color: _sage, lineSpacing: 2),
    ),
  );
}

pw.TableRow _tableHeaderRow(List<String> headers) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: _darkBand),
    children: headers
        .map((h) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(h,
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _gold)),
            ))
        .toList(),
  );
}

pw.TableRow _tableDataRow(List<String> cells, {bool alt = false}) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: alt ? _oliveCard : _olive),
    children: cells
        .map((c) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(c, style: pw.TextStyle(fontSize: 8, color: _cream)),
            ))
        .toList(),
  );
}

/// PDF for a single fund's full portfolio - stat cards, sector allocation,
/// and the full holdings list.
Future<Uint8List> buildFundPortfolioPdf({
  required String fundName,
  required Map<String, dynamic> data,
}) async {
  final doc = pw.Document();
  final holdings = (data['holdings'] as List? ?? []).cast<Map>();
  final sectors = (data['sectors'] as List? ?? []).cast<Map>();

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: pw.EdgeInsets.zero,
        buildBackground: (_) => pw.Container(color: _olive),
      ),
      build: (context) => [
        _header(fundName, 'Generated ${DateTime.now().toString().substring(0, 16)} · Advantage'),
        pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: _statCard('${data['count'] ?? '—'}', 'HOLDINGS')),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                      child: _statCard(
                          '${((data['disclosed_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                          'DISCLOSED')),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                      child: _statCard(
                          '${((data['top10_pct'] as num?) ?? 0).toStringAsFixed(1)}%',
                          'TOP 10')),
                ],
              ),
              if (sectors.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('SECTOR ALLOCATION',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColor.fromHex('#3D4F32'), width: 0.5),
                  children: [
                    _tableHeaderRow(['Sector', '% of NAV']),
                    for (int i = 0; i < sectors.length && i < 12; i++)
                      _tableDataRow([
                        '${sectors[i]['industry']}',
                        '${((sectors[i]['pct_nav'] as num?) ?? 0).toStringAsFixed(1)}%',
                      ], alt: i.isOdd),
                  ],
                ),
              ],
              pw.SizedBox(height: 20),
              pw.Text('FULL HOLDINGS (${holdings.length})',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#3D4F32'), width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1.2),
                  2: pw.FlexColumnWidth(1.5),
                },
                children: [
                  _tableHeaderRow(['Instrument', '% of NAV', 'Value']),
                  for (int i = 0; i < holdings.length && i < 60; i++)
                    _tableDataRow([
                      '${holdings[i]['instrument']}',
                      '${((holdings[i]['pct_nav'] as num?) ?? 0).toStringAsFixed(2)}%',
                      _moneyText(holdings[i]['value_lakh'] as num?),
                    ], alt: i.isOdd),
                ],
              ),
              if (holdings.length > 60)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text('...and ${holdings.length - 60} more (see the app for the full list).',
                      style: pw.TextStyle(fontSize: 7.5, color: _sage)),
                ),
              _disclaimer(),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

/// PDF for a 2-4 fund overlap comparison - pairwise matrix, ranked pair
/// list, and stocks held by every selected fund.
Future<Uint8List> buildOverlapPdf({
  required List<String> fundLabels,
  required List<List<double>> matrix,
  required List<Map<String, dynamic>> heldByAll,
}) async {
  final doc = pw.Document();
  final n = fundLabels.length;

  final pairs = <(String, String, double)>[];
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      pairs.add((fundLabels[i], fundLabels[j], matrix[i][j]));
    }
  }
  pairs.sort((a, b) => b.$3.compareTo(a.$3));
  final avgOverlap =
      pairs.isEmpty ? 0.0 : pairs.map((p) => p.$3).reduce((a, b) => a + b) / pairs.length;

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: pw.EdgeInsets.zero,
        buildBackground: (_) => pw.Container(color: _olive),
      ),
      build: (context) => [
        _header('Fund Overlap Report',
            'Generated ${DateTime.now().toString().substring(0, 16)} · Advantage'),
        pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(child: _statCard('$n', 'FUNDS COMPARED')),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                      child: _statCard('${avgOverlap.toStringAsFixed(1)}%', 'AVG OVERLAP')),
                  pw.SizedBox(width: 8),
                  pw.Expanded(child: _statCard('${heldByAll.length}', 'HELD BY ALL')),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('FUNDS COMPARED',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(height: 6),
              for (final f in fundLabels)
                pw.Text('• $f', style: pw.TextStyle(fontSize: 9, color: _cream)),
              pw.SizedBox(height: 18),
              pw.Text('PAIRWISE OVERLAP MATRIX',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#3D4F32'), width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: _darkBand),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
                      for (final f in fundLabels)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(f.length > 14 ? '${f.substring(0, 14)}…' : f,
                              style: pw.TextStyle(
                                  fontSize: 8, fontWeight: pw.FontWeight.bold, color: _gold)),
                        ),
                    ],
                  ),
                  for (int i = 0; i < n; i++)
                    pw.TableRow(
                      children: [
                        pw.Container(
                          color: _darkBand,
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                              fundLabels[i].length > 14
                                  ? '${fundLabels[i].substring(0, 14)}…'
                                  : fundLabels[i],
                              style: pw.TextStyle(
                                  fontSize: 8, fontWeight: pw.FontWeight.bold, color: _gold)),
                        ),
                        for (int j = 0; j < n; j++)
                          pw.Container(
                            color: i == j ? _darkBand : _overlapColor(matrix[i][j]),
                            padding: const pw.EdgeInsets.all(6),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              i == j ? '—' : '${matrix[i][j].toStringAsFixed(0)}%',
                              style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: i == j ? _gold : PdfColors.white),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Text('PAIRWISE OVERLAP SUMMARY',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#3D4F32'), width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(1),
                },
                children: [
                  _tableHeaderRow(['Fund', 'vs. Fund', 'Overlap']),
                  for (int i = 0; i < pairs.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: i.isOdd ? _oliveCard : _olive),
                      children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(pairs[i].$1,
                                style: pw.TextStyle(fontSize: 8, color: _cream))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(pairs[i].$2,
                                style: pw.TextStyle(fontSize: 8, color: _cream))),
                        pw.Container(
                          color: _overlapColor(pairs[i].$3),
                          padding: const pw.EdgeInsets.all(6),
                          alignment: pw.Alignment.center,
                          child: pw.Text('${pairs[i].$3.toStringAsFixed(1)}%',
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                      ],
                    ),
                ],
              ),
              if (heldByAll.isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Text('STOCKS HELD BY ALL $n FUNDS (${heldByAll.length})',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold, color: _gold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColor.fromHex('#3D4F32'), width: 0.5),
                  children: [
                    _tableHeaderRow(['Stock']),
                    for (int i = 0; i < heldByAll.length && i < 40; i++)
                      _tableDataRow(['${heldByAll[i]['instrument']}'], alt: i.isOdd),
                  ],
                ),
              ] else
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text('No single stock is held by all $n selected funds.',
                      style: pw.TextStyle(fontSize: 9, color: _cream)),
                ),
              _disclaimer(),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

String _moneyText(num? lakh) {
  if (lakh == null) return '—';
  final cr = lakh / 100;
  if (cr >= 1000) return 'Rs. ${(cr / 1000).round()}k Cr';
  if (cr >= 1) return 'Rs. ${cr.toStringAsFixed(1)} Cr';
  return 'Rs. ${lakh.toStringAsFixed(1)} L';
}
