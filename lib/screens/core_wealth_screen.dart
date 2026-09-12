// core_wealth_screen.dart
// ---------------------------------------------------------------------------
// Core Wealth Planning: Goal Feasibility, Portfolio Allocation, and a live
// Fund Explorer backed by your API.
//
// The fund tab computes returns from real NAV history rather than quoting
// stored figures — mfapi.in only supplies NAV series and scheme metadata, so
// CAGR is derived here. Expense ratio, AUM and Sharpe are not available from
// that source and are deliberately not shown rather than faked.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// MATH
// ===========================================================================

double _fv(double pv, double rate, double years) =>
    pv * math.pow(1 + rate, math.max(years, 0)).toDouble();

/// Compound annual growth rate between two NAVs [years] apart.
double? _cagr(double from, double to, double years) {
  if (from <= 0 || to <= 0 || years <= 0) return null;
  return (math.pow(to / from, 1 / years).toDouble() - 1) * 100;
}

// ===========================================================================
// FORMATTING
// ===========================================================================

String _group(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return (n < 0 ? '-' : '') + s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final buf = <String>[];
  while (rest.length > 2) {
    buf.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) buf.insert(0, rest);
  return '${n < 0 ? '-' : ''}${buf.join(',')},$last3';
}

String cwMoney(num x) => x.isFinite ? '₹ ${_group(x.round())}' : '₹ 0';

String cwMoneyShort(num x) {
  if (!x.isFinite) return '₹ 0';
  final v = x.abs();
  if (v >= 10000000) return '₹ ${(x / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹ ${(x / 100000).toStringAsFixed(2)} L';
  return cwMoney(x);
}

/// mfapi returns dates as dd-MM-yyyy.
DateTime? _parseNavDate(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

// ===========================================================================
// SHARED WIDGETS
// ===========================================================================

/// A single labelled cwMoney/percent field. Used where a slider would be
/// impractical — the cashflow and net worth sheets have too many lines.
class CwMoneyField extends StatefulWidget {
  const CwMoneyField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = '₹',
    this.decimals = 0,
  });

  final String label;
  final double value;
  final String suffix;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<CwMoneyField> createState() => _CwMoneyFieldState();
}

class _CwMoneyFieldState extends State<CwMoneyField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value.toStringAsFixed(widget.decimals));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.label,
                style: const TextStyle(color: Brand.paper, fontSize: 13)),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Brand.paper, fontSize: 14),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                prefixText: widget.suffix == '₹' ? '₹ ' : null,
                suffixText: widget.suffix == '%' ? '%' : null,
                prefixStyle: const TextStyle(color: Brand.mint),
                suffixStyle: const TextStyle(color: Brand.mint),
                filled: true,
                fillColor: Brand.fern.withValues(alpha: 0.35),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Brand.mint.withValues(alpha: 0.3)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Brand.gold),
                ),
              ),
              onChanged: (raw) {
                final p = double.tryParse(raw.replaceAll(',', '').trim());
                if (p != null) widget.onChanged(math.max(p, 0));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider + field, for the planners where dragging is natural.
class CwSliderField extends StatefulWidget {
  const CwSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
    this.decimals = 0,
    this.step,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final int decimals;
  final double? step;
  final ValueChanged<double> onChanged;

  @override
  State<CwSliderField> createState() => _CwSliderFieldState();
}

class _CwSliderFieldState extends State<CwSliderField> {
  late final TextEditingController _ctrl;

  String get _text => widget.value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _text);
  }

  @override
  void didUpdateWidget(covariant CwSliderField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && _ctrl.text != _text) _ctrl.text = _text;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final p = double.tryParse(raw.replaceAll(',', '').trim());
    if (p == null) return;
    widget.onChanged(p.clamp(widget.min, widget.max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final divisions = widget.step == null
        ? null
        : ((widget.max - widget.min) / widget.step!).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label,
                    style: const TextStyle(color: Brand.paper, fontSize: 14)),
              ),
              SizedBox(
                width: 116,
                child: TextField(
                  controller: _ctrl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Brand.paper),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: widget.suffix.isEmpty ? null : widget.suffix,
                    suffixStyle: const TextStyle(color: Brand.mint),
                    filled: true,
                    fillColor: Brand.fern.withValues(alpha: 0.35),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Brand.mint.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Brand.gold),
                    ),
                  ),
                  onChanged: _commit,
                  onSubmitted: _commit,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Brand.gold,
              inactiveTrackColor: Brand.fern.withValues(alpha: 0.5),
              thumbColor: Brand.gold,
              overlayColor: Brand.gold.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max).toDouble(),
              min: widget.min,
              max: widget.max,
              divisions: divisions,
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class CwSectionLabel extends StatelessWidget {
  const CwSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Text(text,
              style: const TextStyle(
                  color: Brand.gold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
                height: 1, color: Brand.gold.withValues(alpha: 0.25)),
          ),
        ],
      ),
    );
  }
}

class CwResultCard extends StatelessWidget {
  const CwResultCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.gold;
    return Card(
      color: Brand.fern.withValues(alpha: 0.45),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8),
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: c, fontSize: 28, fontWeight: FontWeight.bold)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.75), fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class CwBreakdown extends StatelessWidget {
  const CwBreakdown(this.rows, {super.key, this.highlightLast = false});

  final List<(String, String)> rows;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (highlightLast && i == rows.length - 1)
                Divider(color: Brand.gold.withValues(alpha: 0.3), height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(rows[i].$1,
                        style: TextStyle(
                            color: highlightLast && i == rows.length - 1
                                ? Brand.gold
                                : Brand.mint.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: highlightLast && i == rows.length - 1
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    Text(rows[i].$2,
                        style: TextStyle(
                            color: highlightLast && i == rows.length - 1
                                ? Brand.gold
                                : Brand.paper,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal proportion bar — used for cashflow and net worth splits.
class CwProportionBar extends StatelessWidget {
  const CwProportionBar({super.key, required this.segments});

  /// (label, value, colour) — zero-value segments are skipped.
  final List<(String, double, Color)> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + math.max(e.$2, 0));
    if (total <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (_, v, c) in segments)
                    if (v > 0)
                      Expanded(
                        flex: math.max((v / total * 1000).round(), 1),
                        child: Container(color: c),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (label, v, c) in segments)
                if (v > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$label ${(v / total * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.85),
                            fontSize: 11),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class CwPdfButton extends StatefulWidget {
  const CwPdfButton({super.key, required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<CwPdfButton> createState() => _CwPdfButtonState();
}

class _CwPdfButtonState extends State<CwPdfButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.gold,
            foregroundColor: Brand.vault,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.vault),
                )
              : const Icon(Icons.picture_as_pdf, size: 20),
          label: Text(_busy ? 'Preparing…' : 'Download PDF'),
        ),
      ),
    );
  }
}

class CwTabBody extends StatelessWidget {
  const CwTabBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      );
}

// ===========================================================================
// PDF
// ===========================================================================

/// Generic report: assumptions block, results block, optional line-item table.
Future<void> exportCwReportPdf({
  required String title,
  required List<(String, String)> inputs,
  required List<(String, String)> results,
  List<List<String>> tableRows = const [],
  List<String> tableHeaders = const [],
  String tableTitle = 'DETAIL',
  String? note,
}) async {
  final doc = pw.Document();
  final now = DateTime.now();

  pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(v,
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        pw.Header(
          level: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated ${now.day.toString().padLeft(2, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-${now.year}',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('INPUTS',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700)),
                    pw.SizedBox(height: 6),
                    for (final (k, v) in inputs) kv(k, v),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('RESULT',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700)),
                    pw.SizedBox(height: 6),
                    for (final (k, v) in results) kv(k, v),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (tableRows.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(tableTitle,
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: tableHeaders,
            data: tableRows,
            headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 15,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              for (var i = 1; i < math.max(tableHeaders.length, 2); i++)
                i: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          note ??
              'Projections assume constant rates and are illustrative only. '
                  'Actual outcomes will vary. Not investment advice.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: '$safe.pdf');
}



// ===========================================================================
// SCREEN
// ===========================================================================

class CoreWealthScreen extends StatelessWidget {
  const CoreWealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          elevation: 0,
          title: const Text('Core Wealth Planning',
              style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: Brand.gold,
            unselectedLabelColor: Brand.mint,
            indicatorColor: Brand.gold,
            tabs: const [
              Tab(text: 'Goal Check'),
              Tab(text: 'Allocation'),
              Tab(text: 'Funds'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _GoalFeasibilityTab(),
            _AllocationTab(),
            _FundExplorerTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — GOAL FEASIBILITY
// ===========================================================================

class _GoalFeasibilityTab extends StatefulWidget {
  const _GoalFeasibilityTab();

  @override
  State<_GoalFeasibilityTab> createState() => _GoalFeasibilityTabState();
}

class _GoalFeasibilityTabState extends State<_GoalFeasibilityTab> {
  double target = 5000000;
  double years = 10;
  double existing = 500000;
  double sip = 20000;
  double returnPct = 12;

  @override
  Widget build(BuildContext context) {
    final r = returnPct / 100;

    // Existing corpus compounds; the SIP accumulates on top of it.
    final existingGrows = _fv(existing, r, years);
    double projected = existingGrows;
    final months = (years * 12).floor();
    for (var m = 0; m < months; m++) {
      projected = projected * (1 + r / 12) + sip;
    }

    final shortfall = target - projected;
    final feasibility = target > 0 ? projected / target * 100 : 0.0;
    final onTrack = shortfall <= 0;

    // What it would take to close a gap.
    final extraSip = onTrack
        ? 0.0
        : () {
            final rr = r / 12;
            if (months <= 0) return shortfall;
            final factor = rr <= 0
                ? months.toDouble()
                : ((math.pow(1 + rr, months) - 1) / rr) * (1 + rr);
            return factor > 0 ? shortfall / factor : 0.0;
          }();

    final verdict = feasibility >= 100
        ? 'On track'
        : (feasibility >= 75 ? 'Close — small push needed' : 'Significant gap');
    final verdictColour = feasibility >= 100
        ? Brand.green
        : (feasibility >= 75 ? Brand.gold : Brand.red);

    return CwTabBody(children: [
      const CwSectionLabel('THE GOAL'),
      CwSliderField(
          label: 'Target amount',
          value: target,
          min: 100000,
          max: 200000000,
          step: 100000,
          suffix: '₹',
          onChanged: (v) => setState(() => target = v)),
      CwSliderField(
          label: 'Years to goal',
          value: years,
          min: 1,
          max: 40,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => years = v)),

      const CwSectionLabel('WHAT YOU HAVE'),
      CwMoneyField(
          label: 'Existing corpus for this goal',
          value: existing,
          onChanged: (v) => setState(() => existing = v)),
      CwMoneyField(
          label: 'Current monthly SIP',
          value: sip,
          onChanged: (v) => setState(() => sip = v)),
      CwSliderField(
          label: 'Expected return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),

      const SizedBox(height: 12),
      CwResultCard(
        label: 'Feasibility',
        value: '${feasibility.toStringAsFixed(0)}%',
        sub: verdict,
        color: verdictColour,
      ),

      // Progress bar capped at 100% so an over-funded goal doesn't overflow.
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      Expanded(
                        flex: math.max(
                            math.min(feasibility, 100).round(), 1),
                        child: Container(color: verdictColour),
                      ),
                      if (feasibility < 100)
                        Expanded(
                          flex: (100 - feasibility).round(),
                          child: Container(
                              color: Brand.fern.withValues(alpha: 0.6)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Projected ${cwMoneyShort(projected)}',
                      style: TextStyle(color: verdictColour, fontSize: 11)),
                  Text('Target ${cwMoneyShort(target)}',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.8),
                          fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),

      if (!onTrack)
        CwResultCard(
          label: 'Additional SIP to close the gap',
          value: cwMoney(extraSip),
          sub: 'on top of your current ${cwMoney(sip)}',
          color: Brand.red,
        ),

      CwBreakdown([
        ('Existing corpus grows to', cwMoney(existingGrows)),
        ('SIP contributes', cwMoney(projected - existingGrows)),
        ('Total projected value', cwMoney(projected)),
        ('Target', cwMoney(target)),
        (onTrack ? 'Surplus' : 'Shortfall', cwMoney(shortfall.abs())),
      ], highlightLast: true),

      CwPdfButton(
        onPressed: () => exportCwReportPdf(
          title: 'Goal Feasibility Check',
          inputs: [
            ('Target amount', cwMoney(target)),
            ('Years to goal', '${years.round()}'),
            ('Existing corpus', cwMoney(existing)),
            ('Current monthly SIP', cwMoney(sip)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Projected value', cwMoney(projected)),
            ('Target', cwMoney(target)),
            (onTrack ? 'Surplus' : 'Shortfall', cwMoney(shortfall.abs())),
            ('Feasibility', '${feasibility.toStringAsFixed(1)}%'),
            ('Verdict', verdict),
            if (!onTrack) ('Additional SIP needed', cwMoney(extraSip)),
          ],
          note: 'Feasibility above 100% means the current plan overshoots the '
              'goal — you could reduce the SIP or bring the goal forward. '
              'Re-check annually, since both returns and income change.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 2 — PORTFOLIO ALLOCATION
// ===========================================================================

class _AllocationTab extends StatefulWidget {
  const _AllocationTab();

  @override
  State<_AllocationTab> createState() => _AllocationTabState();
}

class _AllocationTabState extends State<_AllocationTab> {
  double total = 10000000;
  String risk = 'Moderate';

  /// Model allocations from the dashboard.
  static const _models = {
    'Conservative': (30, 50, 10, 10),
    'Moderate': (55, 25, 10, 10),
    'Aggressive': (75, 10, 5, 10),
  };

  static const _rationale = {
    'Conservative':
        'Capital preservation first. Debt carries the load, with just enough '
            'equity to stay ahead of inflation.',
    'Moderate':
        'Balanced growth. Equity drives returns while debt cushions the '
            'drawdowns.',
    'Aggressive':
        'Growth first. Accepts deeper drawdowns in exchange for higher '
            'long-term compounding.',
  };

  @override
  Widget build(BuildContext context) {
    final (eq, debt, gold, cash) = _models[risk]!;
    final rows = <(String, int, Color)>[
      ('Equity', eq, Brand.gold),
      ('Debt', debt, Brand.green),
      ('Gold', gold, Brand.mint),
      ('Cash / Liquid', cash, Brand.paper),
    ];

    return CwTabBody(children: [
      CwSliderField(
          label: 'Total investible corpus',
          value: total,
          min: 100000,
          max: 500000000,
          step: 100000,
          suffix: '₹',
          onChanged: (v) => setState(() => total = v)),

      const CwSectionLabel('RISK PROFILE'),
      Row(
        children: [
          for (final r in _models.keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => risk = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: risk == r
                          ? Brand.gold.withValues(alpha: 0.2)
                          : Brand.fern.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: risk == r
                            ? Brand.gold
                            : Brand.mint.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      r,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: risk == r ? Brand.gold : Brand.mint,
                        fontSize: 12,
                        fontWeight:
                            risk == r ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      const SizedBox(height: 14),
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(_rationale[risk]!,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.85),
                  fontSize: 12,
                  height: 1.4)),
        ),
      ),

      const SizedBox(height: 8),
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: CwProportionBar(segments: [
            for (final (name, pct, colour) in rows)
              (name, total * pct / 100, colour),
          ]),
        ),
      ),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text('Asset class',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 4,
                      child: Text('Amount',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            for (final (name, pct, colour) in rows)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: colour,
                                borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: 8),
                          Text(name,
                              style: const TextStyle(
                                  color: Brand.paper, fontSize: 12)),
                        ],
                      ),
                    ),
                    Expanded(
                        flex: 2,
                        child: Text('$pct%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.mint, fontSize: 12))),
                    Expanded(
                        flex: 4,
                        child: Text(cwMoneyShort(total * pct / 100),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),

      CwPdfButton(
        onPressed: () => exportCwReportPdf(
          title: 'Portfolio Allocation',
          inputs: [
            ('Total corpus', cwMoney(total)),
            ('Risk profile', risk),
          ],
          results: [
            for (final (name, pct, _) in rows)
              (name, '$pct%  ·  ${cwMoney(total * pct / 100)}'),
          ],
          tableHeaders: const ['Asset class', 'Allocation %', 'Amount'],
          tableTitle: 'MODEL ALLOCATION',
          tableRows: [
            for (final (name, pct, _) in rows)
              [name, '$pct%', cwMoney(total * pct / 100)],
          ],
          note: '${_rationale[risk]!} These are model weights, not personal '
              'advice — adjust for your own goals, time horizon and existing '
              'holdings.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 3 — FUND EXPLORER (live)
// ===========================================================================

/// Returns computed from a scheme's own NAV history.
class FundAnalysis {
  const FundAnalysis({
    required this.schemeCode,
    required this.name,
    required this.fundHouse,
    required this.category,
    required this.latestNav,
    required this.navDate,
    this.return1y,
    this.return3y,
    this.return5y,
    this.sinceInception,
    this.volatility,
    required this.historyPoints,
  });

  final String schemeCode;
  final String name;
  final String fundHouse;
  final String category;
  final double latestNav;
  final String navDate;

  /// Annualised percentages. Null when the fund is too young for that window.
  final double? return1y;
  final double? return3y;
  final double? return5y;
  final double? sinceInception;

  /// Annualised standard deviation of monthly returns, in percent.
  final double? volatility;

  final int historyPoints;

  String get riskLabel {
    final v = volatility;
    if (v == null) return 'Unknown';
    if (v < 5) return 'Low';
    if (v < 12) return 'Moderate';
    if (v < 20) return 'Moderate-High';
    return 'High';
  }
}

/// Turns the API's NAV history into annualised returns.
///
/// mfapi gives a descending list of {date, nav}. We walk back from the latest
/// NAV to find the closest observation to each anniversary, then annualise.
FundAnalysis? analyseFund(Map<String, dynamic> payload, String schemeCode) {
  final meta = (payload['meta'] as Map?) ?? {};
  final raw = (payload['nav_history'] as List?) ?? [];
  if (raw.isEmpty) return null;

  // Parse into (date, nav), newest first, dropping unusable rows.
  final points = <(DateTime, double)>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final d = _parseNavDate('${e['date']}');
    final n = double.tryParse('${e['nav']}');
    if (d != null && n != null && n > 0) points.add((d, n));
  }
  if (points.isEmpty) return null;
  points.sort((a, b) => b.$1.compareTo(a.$1));

  final latest = points.first;

  /// NAV closest to [years] before the latest date, if the history reaches it.
  (DateTime, double)? navYearsAgo(double years) {
    final targetDate = DateTime(
      latest.$1.year - years.floor(),
      latest.$1.month,
      latest.$1.day,
    );
    if (points.last.$1.isAfter(targetDate)) return null; // not enough history
    (DateTime, double)? best;
    var bestGap = double.infinity;
    for (final p in points) {
      final gap =
          (p.$1.difference(targetDate).inDays).abs().toDouble();
      if (gap < bestGap) {
        bestGap = gap;
        best = p;
      }
    }
    // Reject if the nearest observation is more than ~2 months off.
    return bestGap <= 60 ? best : null;
  }

  double? ret(double years) {
    final past = navYearsAgo(years);
    if (past == null) return null;
    final actualYears =
        latest.$1.difference(past.$1).inDays / 365.25;
    return _cagr(past.$2, latest.$2, actualYears);
  }

  final oldest = points.last;
  final inceptionYears =
      latest.$1.difference(oldest.$1).inDays / 365.25;

  // Volatility from month-end NAVs over the available history.
  double? vol;
  final monthly = <double>[];
  DateTime? lastMonth;
  double? lastNav;
  for (final p in points.reversed) {
    final key = DateTime(p.$1.year, p.$1.month);
    if (lastMonth == null || key.isAfter(lastMonth)) {
      if (lastNav != null && lastNav > 0) {
        monthly.add(p.$2 / lastNav - 1);
      }
      lastMonth = key;
      lastNav = p.$2;
    }
  }
  if (monthly.length >= 12) {
    final mean = monthly.reduce((a, b) => a + b) / monthly.length;
    final variance = monthly
            .map((r) => math.pow(r - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        (monthly.length - 1);
    vol = math.sqrt(variance) * math.sqrt(12) * 100;
  }

  return FundAnalysis(
    schemeCode: schemeCode,
    name: '${meta['scheme_name'] ?? 'Unknown scheme'}',
    fundHouse: '${meta['fund_house'] ?? '—'}',
    category: '${meta['scheme_category'] ?? '—'}',
    latestNav: latest.$2,
    navDate:
        '${latest.$1.day.toString().padLeft(2, '0')}-${latest.$1.month.toString().padLeft(2, '0')}-${latest.$1.year}',
    return1y: ret(1),
    return3y: ret(3),
    return5y: ret(5),
    sinceInception: inceptionYears >= 1
        ? _cagr(oldest.$2, latest.$2, inceptionYears)
        : null,
    volatility: vol,
    historyPoints: points.length,
  );
}

class _FundExplorerTab extends StatefulWidget {
  const _FundExplorerTab();

  @override
  State<_FundExplorerTab> createState() => _FundExplorerTabState();
}

class _FundExplorerTabState extends State<_FundExplorerTab> {
  final _searchCtrl = TextEditingController();

  List<dynamic> _results = [];
  bool _searching = false;
  String? _searchError;

  final List<FundAnalysis> _compared = [];
  bool _loadingFund = false;
  String? _fundError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 3) {
      setState(() => _searchError = 'Type at least 3 characters');
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _results = [];
    });
    try {
      final r = await ApiService.searchFunds(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _searchError = 'No schemes matched "$q"';
      });
    } catch (e) {
      if (mounted) setState(() => _searchError = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addFund(String schemeCode, String fallbackName) async {
    if (_compared.any((f) => f.schemeCode == schemeCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already added')),
      );
      return;
    }
    setState(() {
      _loadingFund = true;
      _fundError = null;
    });
    try {
      final payload = await ApiService.getFund(schemeCode);
      final analysis = analyseFund(payload, schemeCode);
      if (!mounted) return;
      if (analysis == null) {
        setState(() => _fundError = 'No usable NAV history for $fallbackName');
      } else {
        setState(() {
          _compared.add(analysis);
          _results = [];
          _searchCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _fundError = '$e');
    } finally {
      if (mounted) setState(() => _loadingFund = false);
    }
  }

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    return CwTabBody(children: [
      const CwSectionLabel('SEARCH FUNDS'),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Brand.paper),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'e.g. Parag Parikh, HDFC, Nifty index',
                hintStyle:
                    TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.search, color: Brand.mint),
                filled: true,
                fillColor: Brand.fern.withValues(alpha: 0.35),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Brand.mint.withValues(alpha: 0.3)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Brand.gold),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
              ),
              onPressed: _searching ? null : _search,
              child: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.vault),
                    )
                  : const Text('Go'),
            ),
          ),
        ],
      ),

      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_searchError!,
              style: const TextStyle(color: Brand.red, fontSize: 12)),
        ),

      if (_loadingFund)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Brand.gold),
              ),
              SizedBox(width: 12),
              Text('Fetching NAV history…',
                  style: TextStyle(color: Brand.mint, fontSize: 12)),
            ],
          ),
        ),

      if (_fundError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_fundError!,
              style: const TextStyle(color: Brand.red, fontSize: 12)),
        ),

      // ---- Search results ----
      if (_results.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          color: Brand.fern.withValues(alpha: 0.28),
          child: Column(
            children: [
              for (final r in _results.take(15))
                ListTile(
                  dense: true,
                  title: Text('${r['schemeName'] ?? '—'}',
                      style: const TextStyle(
                          color: Brand.paper, fontSize: 12.5)),
                  subtitle: Text('Code ${r['schemeCode']}',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.7),
                          fontSize: 11)),
                  trailing: const Icon(Icons.add_circle_outline,
                      color: Brand.gold, size: 20),
                  onTap: () => _addFund(
                      '${r['schemeCode']}', '${r['schemeName'] ?? ''}'),
                ),
            ],
          ),
        ),
      ],

      // ---- Empty state ----
      if (_compared.isEmpty && _results.isEmpty && !_searching) ...[
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(Icons.query_stats,
                  size: 44, color: Brand.mint.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('Search for a fund to see its real returns',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7), fontSize: 13)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  'Returns are computed from the scheme\'s own NAV history, '
                  'not from stored figures.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.5), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],

      // ---- Compared funds ----
      for (final f in _compared) ...[
        const SizedBox(height: 10),
        Card(
          color: Brand.fern.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              style: const TextStyle(
                                  color: Brand.paper,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 3),
                          Text('${f.fundHouse}  ·  ${f.category}',
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.75),
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Brand.mint, size: 18),
                      onPressed: () =>
                          setState(() => _compared.remove(f)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Stat(label: '1Y', value: _pct(f.return1y)),
                    _Stat(label: '3Y', value: _pct(f.return3y)),
                    _Stat(label: '5Y', value: _pct(f.return5y)),
                    _Stat(
                        label: 'Since start',
                        value: _pct(f.sinceInception)),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Brand.mint.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('NAV ₹${f.latestNav.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Brand.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text('as of ${f.navDate}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7),
                            fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'Volatility ${f.volatility == null ? "—" : "${f.volatility!.toStringAsFixed(1)}%"}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.8),
                            fontSize: 11)),
                    Text('Risk: ${f.riskLabel}',
                        style: TextStyle(
                            color: f.riskLabel == 'Low'
                                ? Brand.green
                                : (f.riskLabel == 'High'
                                    ? Brand.red
                                    : Brand.gold),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],

      if (_compared.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          _compared.any((f) => f.return5y == null || f.return3y == null)
              ? 'Some windows show "—" because the API returns a limited NAV '
                  'history. Raise the nav_history cap in api.py to about 2000 '
                  'records to unlock 3Y and 5Y returns.'
              : 'Returns are annualised (CAGR) from the scheme\'s own NAV '
                  'history. Expense ratio, AUM and Sharpe are not available '
                  'from this data source, so they are not shown.',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.6),
              fontSize: 10.5,
              height: 1.4),
        ),
        CwPdfButton(
          onPressed: () => exportCwReportPdf(
            title: 'Fund Comparison',
            inputs: [
              ('Funds compared', '${_compared.length}'),
              ('Data source', 'AMFI via mfapi.in'),
              ('Returns basis', 'CAGR from NAV history'),
            ],
            results: [
              for (final f in _compared)
                (
                  f.name.length > 34 ? '${f.name.substring(0, 34)}…' : f.name,
                  '3Y ${_pct(f.return3y)}  ·  5Y ${_pct(f.return5y)}'
                ),
            ],
            tableHeaders: const [
              'Fund',
              'AMC',
              'NAV',
              '1Y',
              '3Y',
              '5Y',
              'Vol.',
              'Risk',
            ],
            tableTitle: 'FUND DETAIL',
            tableRows: [
              for (final f in _compared)
                [
                  f.name,
                  f.fundHouse,
                  f.latestNav.toStringAsFixed(2),
                  _pct(f.return1y),
                  _pct(f.return3y),
                  _pct(f.return5y),
                  f.volatility == null
                      ? '—'
                      : '${f.volatility!.toStringAsFixed(1)}%',
                  f.riskLabel,
                ],
            ],
            note: 'Returns are annualised from the scheme\'s own NAV history '
                'and are not adjusted for exit loads or taxes. Past returns '
                'do not predict future returns.',
          ),
        ),
      ],
    ]);
  }
}

/// One return figure in the fund card.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 10)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: value == '—' ? Brand.mint : Brand.paper,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
