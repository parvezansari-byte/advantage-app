// lifestyle_screen.dart
// ---------------------------------------------------------------------------
// Lifestyle & Balance Sheet calculators, ported from the Streamlit dashboard.
//
// Tabs: Cashflow · Net Worth · House · Car · iPhone · EMI vs SIP
//
// Navigate to it with:
//     Navigator.push(context,
//         MaterialPageRoute(builder: (_) => const LifestyleScreen()));
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../main.dart';

// ===========================================================================
// MATH
// ===========================================================================

double _fv(double pv, double rate, double years) =>
    pv * math.pow(1 + rate, math.max(years, 0)).toDouble();

/// Monthly SIP needed for [target].
///
/// Uses the start-of-month convention (the trailing `(1 + r)` factor), which
/// is what the dashboard's purchase planners use — keeping these screens
/// consistent with the figures advisers already quote from it.
double _sipRequired(double target, double annualRate, double years) {
  final months = (math.max(years, 0) * 12).floor();
  if (months <= 0) return 0;
  final r = annualRate / 12;
  if (r <= 0) return target / months;
  final factor = ((math.pow(1 + r, months) - 1) / r) * (1 + r);
  return factor > 0 ? target / factor : 0;
}

double _lumpsumRequired(double target, double annualReturn, double years) =>
    years <= 0 ? target : target / math.pow(1 + annualReturn, years);

double _emi(double principal, double annualRate, double years) {
  final r = annualRate / 12;
  final n = (years * 12).floor();
  if (n <= 0) return 0;
  if (r == 0) return principal / n;
  final p = math.pow(1 + r, n).toDouble();
  return principal * r * p / (p - 1);
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

String money(num x) => x.isFinite ? '₹ ${_group(x.round())}' : '₹ 0';

String moneyShort(num x) {
  if (!x.isFinite) return '₹ 0';
  final v = x.abs();
  if (v >= 10000000) return '₹ ${(x / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹ ${(x / 100000).toStringAsFixed(2)} L';
  return money(x);
}

// ===========================================================================
// SHARED WIDGETS
// ===========================================================================

/// A single labelled money/percent field. Used where a slider would be
/// impractical — the cashflow and net worth sheets have too many lines.
class MoneyField extends StatefulWidget {
  const MoneyField({
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
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
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
class SliderField extends StatefulWidget {
  const SliderField({
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
  State<SliderField> createState() => _SliderFieldState();
}

class _SliderFieldState extends State<SliderField> {
  late final TextEditingController _ctrl;

  String get _text => widget.value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _text);
  }

  @override
  void didUpdateWidget(covariant SliderField old) {
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

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

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

class ResultCard extends StatelessWidget {
  const ResultCard({
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

class Breakdown extends StatelessWidget {
  const Breakdown(this.rows, {super.key, this.highlightLast = false});

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
class ProportionBar extends StatelessWidget {
  const ProportionBar({super.key, required this.segments});

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

class PdfButton extends StatefulWidget {
  const PdfButton({super.key, required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<PdfButton> createState() => _PdfButtonState();
}

class _PdfButtonState extends State<PdfButton> {
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

class TabBody extends StatelessWidget {
  const TabBody({super.key, required this.children});

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
Future<void> exportReportPdf({
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

class LifestyleScreen extends StatelessWidget {
  const LifestyleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          elevation: 0,
          title: const Text('Lifestyle & Balance Sheet',
              style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Brand.gold,
            unselectedLabelColor: Brand.mint,
            indicatorColor: Brand.gold,
            tabs: const [
              Tab(text: 'Cashflow'),
              Tab(text: 'Net Worth'),
              Tab(text: 'House'),
              Tab(text: 'Car'),
              Tab(text: 'iPhone'),
              Tab(text: 'EMI vs SIP'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CashflowTab(),
            _NetWorthTab(),
            _HouseTab(),
            _CarTab(),
            _PhoneTab(),
            _EmiVsSipTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — CASHFLOW PLANNER
// ===========================================================================

class _CashflowTab extends StatefulWidget {
  const _CashflowTab();

  @override
  State<_CashflowTab> createState() => _CashflowTabState();
}

class _CashflowTabState extends State<_CashflowTab> {
  // Inflows
  double salary = 1000000;
  double side = 0;
  double invIncome = 0;
  double otherIncome = 0;

  // Fixed
  double rent = 300000;
  double utilities = 60000;
  double debt = 0;
  double insurance = 50000;
  double childcare = 0;

  // Variable
  double groceries = 120000;
  double dining = 60000;
  double transport = 50000;
  double shopping = 50000;

  // Savings
  double emergency = 50000;
  double retirement = 100000;
  double investments = 150000;

  double get inflow => salary + side + invIncome + otherIncome;
  double get fixed => rent + utilities + debt + insurance + childcare;
  double get variable => groceries + dining + transport + shopping;
  double get savings => emergency + retirement + investments;
  double get outflow => fixed + variable + savings;
  double get net => inflow - outflow;

  @override
  Widget build(BuildContext context) {
    final savingsRate = inflow > 0 ? (savings + net) / inflow * 100 : 0.0;

    return TabBody(children: [
      const SectionLabel('CASH INFLOWS'),
      MoneyField(
          label: 'Salary / wages (after tax)',
          value: salary,
          onChanged: (v) => setState(() => salary = v)),
      MoneyField(
          label: 'Side hustle / freelance',
          value: side,
          onChanged: (v) => setState(() => side = v)),
      MoneyField(
          label: 'Investment income',
          value: invIncome,
          onChanged: (v) => setState(() => invIncome = v)),
      MoneyField(
          label: 'Other income (rental, refunds)',
          value: otherIncome,
          onChanged: (v) => setState(() => otherIncome = v)),

      const SectionLabel('FIXED EXPENSES'),
      MoneyField(
          label: 'Rent / mortgage',
          value: rent,
          onChanged: (v) => setState(() => rent = v)),
      MoneyField(
          label: 'Utilities',
          value: utilities,
          onChanged: (v) => setState(() => utilities = v)),
      MoneyField(
          label: 'Debt payments',
          value: debt,
          onChanged: (v) => setState(() => debt = v)),
      MoneyField(
          label: 'Insurance',
          value: insurance,
          onChanged: (v) => setState(() => insurance = v)),
      MoneyField(
          label: 'Childcare / alimony',
          value: childcare,
          onChanged: (v) => setState(() => childcare = v)),

      const SectionLabel('VARIABLE EXPENSES'),
      MoneyField(
          label: 'Groceries',
          value: groceries,
          onChanged: (v) => setState(() => groceries = v)),
      MoneyField(
          label: 'Dining out / entertainment',
          value: dining,
          onChanged: (v) => setState(() => dining = v)),
      MoneyField(
          label: 'Transport / fuel',
          value: transport,
          onChanged: (v) => setState(() => transport = v)),
      MoneyField(
          label: 'Shopping / subscriptions',
          value: shopping,
          onChanged: (v) => setState(() => shopping = v)),

      const SectionLabel('SAVINGS & INVESTMENTS'),
      MoneyField(
          label: 'Emergency fund',
          value: emergency,
          onChanged: (v) => setState(() => emergency = v)),
      MoneyField(
          label: 'Retirement contributions',
          value: retirement,
          onChanged: (v) => setState(() => retirement = v)),
      MoneyField(
          label: 'Investments',
          value: investments,
          onChanged: (v) => setState(() => investments = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: net >= 0 ? 'Net surplus' : 'Net deficit',
        value: money(net.abs()),
        sub: net >= 0
            ? 'left over after everything'
            : 'you are spending more than you earn',
        color: net >= 0 ? Brand.green : Brand.red,
      ),
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ProportionBar(segments: [
            ('Fixed', fixed, Brand.red),
            ('Variable', variable, Brand.gold),
            ('Savings', savings, Brand.green),
            if (net > 0) ('Surplus', net, Brand.mint),
          ]),
        ),
      ),
      Breakdown([
        ('Total inflow', money(inflow)),
        ('Fixed expenses', money(fixed)),
        ('Variable expenses', money(variable)),
        ('Savings & investments', money(savings)),
        ('Total outflow', money(outflow)),
        ('Savings rate', '${savingsRate.toStringAsFixed(1)}%'),
        ('Net cashflow', money(net)),
      ], highlightLast: true),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'Cashflow Planner',
          inputs: [
            ('Total inflow', money(inflow)),
            ('Fixed expenses', money(fixed)),
            ('Variable expenses', money(variable)),
            ('Savings & investments', money(savings)),
          ],
          results: [
            ('Total inflow (A)', money(inflow)),
            ('Total outflow (B)', money(outflow)),
            ('Net cashflow (A-B)', money(net)),
            ('Savings rate', '${savingsRate.toStringAsFixed(1)}%'),
          ],
          tableHeaders: const ['Category', 'Item', 'Amount'],
          tableTitle: 'LINE ITEMS',
          tableRows: [
            ['Inflow', 'Salary / wages', money(salary)],
            ['Inflow', 'Side hustle', money(side)],
            ['Inflow', 'Investment income', money(invIncome)],
            ['Inflow', 'Other income', money(otherIncome)],
            ['Fixed', 'Rent / mortgage', money(rent)],
            ['Fixed', 'Utilities', money(utilities)],
            ['Fixed', 'Debt payments', money(debt)],
            ['Fixed', 'Insurance', money(insurance)],
            ['Fixed', 'Childcare / alimony', money(childcare)],
            ['Variable', 'Groceries', money(groceries)],
            ['Variable', 'Dining / entertainment', money(dining)],
            ['Variable', 'Transport / fuel', money(transport)],
            ['Variable', 'Shopping / subscriptions', money(shopping)],
            ['Savings', 'Emergency fund', money(emergency)],
            ['Savings', 'Retirement', money(retirement)],
            ['Savings', 'Investments', money(investments)],
            ['', 'NET CASHFLOW', money(net)],
          ],
          note: 'Positive cashflow should be directed toward goals and an '
              'emergency reserve. Track lifestyle inflation yearly and keep '
              'fixed obligations controlled to protect investing capacity.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 2 — NET WORTH
// ===========================================================================

class _NetWorthTab extends StatefulWidget {
  const _NetWorthTab();

  @override
  State<_NetWorthTab> createState() => _NetWorthTabState();
}

class _NetWorthTabState extends State<_NetWorthTab> {
  double mf = 2000000;
  double equity = 1000000;
  double realEstate = 5000000;
  double cash = 500000;
  double gold = 300000;

  double homeLoan = 0;
  double carLoan = 0;
  double otherLoan = 0;

  double get assets => mf + equity + realEstate + cash + gold;
  double get liabilities => homeLoan + carLoan + otherLoan;
  double get netWorth => assets - liabilities;

  @override
  Widget build(BuildContext context) {
    final liquid = mf + equity + cash + gold;
    final ratio = assets > 0 ? liabilities / assets * 100 : 0.0;

    return TabBody(children: [
      const SectionLabel('ASSETS'),
      MoneyField(
          label: 'Mutual funds',
          value: mf,
          onChanged: (v) => setState(() => mf = v)),
      MoneyField(
          label: 'Direct equity',
          value: equity,
          onChanged: (v) => setState(() => equity = v)),
      MoneyField(
          label: 'Real estate',
          value: realEstate,
          onChanged: (v) => setState(() => realEstate = v)),
      MoneyField(
          label: 'Cash / bank',
          value: cash,
          onChanged: (v) => setState(() => cash = v)),
      MoneyField(
          label: 'Gold / other assets',
          value: gold,
          onChanged: (v) => setState(() => gold = v)),

      const SectionLabel('LIABILITIES'),
      MoneyField(
          label: 'Home loan',
          value: homeLoan,
          onChanged: (v) => setState(() => homeLoan = v)),
      MoneyField(
          label: 'Car loan',
          value: carLoan,
          onChanged: (v) => setState(() => carLoan = v)),
      MoneyField(
          label: 'Other loans',
          value: otherLoan,
          onChanged: (v) => setState(() => otherLoan = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: 'Net worth',
        value: moneyShort(netWorth),
        sub: 'assets minus liabilities',
        color: netWorth >= 0 ? Brand.gold : Brand.red,
      ),
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ProportionBar(segments: [
            ('Mutual funds', mf, Brand.gold),
            ('Equity', equity, Brand.green),
            ('Real estate', realEstate, Brand.mint),
            ('Cash', cash, Brand.paper),
            ('Gold', gold, Brand.red),
          ]),
        ),
      ),
      Breakdown([
        ('Total assets', money(assets)),
        ('Total liabilities', money(liabilities)),
        ('Liquid assets', money(liquid)),
        ('Debt-to-asset ratio', '${ratio.toStringAsFixed(1)}%'),
        ('Net worth', money(netWorth)),
      ], highlightLast: true),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'Net Worth Statement',
          inputs: [
            ('Total assets', money(assets)),
            ('Total liabilities', money(liabilities)),
          ],
          results: [
            ('Net worth', money(netWorth)),
            ('Liquid assets', money(liquid)),
            ('Debt-to-asset ratio', '${ratio.toStringAsFixed(1)}%'),
          ],
          tableHeaders: const ['Type', 'Item', 'Amount'],
          tableTitle: 'BALANCE SHEET',
          tableRows: [
            ['Asset', 'Mutual funds', money(mf)],
            ['Asset', 'Direct equity', money(equity)],
            ['Asset', 'Real estate', money(realEstate)],
            ['Asset', 'Cash / bank', money(cash)],
            ['Asset', 'Gold / other', money(gold)],
            ['', 'TOTAL ASSETS', money(assets)],
            ['Liability', 'Home loan', money(homeLoan)],
            ['Liability', 'Car loan', money(carLoan)],
            ['Liability', 'Other loans', money(otherLoan)],
            ['', 'TOTAL LIABILITIES', money(liabilities)],
            ['', 'NET WORTH', money(netWorth)],
          ],
          note: 'A net worth statement is a snapshot on one date. Review it '
              'quarterly and watch the direction of travel more than the '
              'absolute figure.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 3 — HOUSE PLANNING
// ===========================================================================

class _HouseTab extends StatefulWidget {
  const _HouseTab();

  @override
  State<_HouseTab> createState() => _HouseTabState();
}

class _HouseTabState extends State<_HouseTab> {
  double cost = 10000000;
  double available = 2000000;
  double afterYears = 5;
  double loanRatePct = 8.5;
  double loanYears = 20;
  double inflationPct = 6;
  double returnPct = 12;

  @override
  Widget build(BuildContext context) {
    final futureCost = _fv(cost, inflationPct / 100, afterYears);
    final targetDown = futureCost * 0.20;
    final gap = math.max(targetDown - available, 0.0);
    final sipNeed = _sipRequired(gap, returnPct / 100, afterYears);
    final loanAmount = math.max(futureCost - targetDown, 0.0);
    final emi = _emi(loanAmount, loanRatePct / 100, loanYears);
    final totalInterest = emi * (loanYears * 12).floor() - loanAmount;

    return TabBody(children: [
      const SectionLabel('THE HOUSE'),
      SliderField(
          label: 'House cost today',
          value: cost,
          min: 1000000,
          max: 200000000,
          step: 500000,
          suffix: '₹',
          onChanged: (v) => setState(() => cost = v)),
      SliderField(
          label: 'Buy after',
          value: afterYears,
          min: 1,
          max: 30,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => afterYears = v)),
      SliderField(
          label: 'Down payment available',
          value: available,
          min: 0,
          max: 50000000,
          step: 100000,
          suffix: '₹',
          onChanged: (v) => setState(() => available = v)),

      const SectionLabel('THE LOAN'),
      SliderField(
          label: 'Home loan rate',
          value: loanRatePct,
          min: 5,
          max: 15,
          step: 0.1,
          decimals: 2,
          suffix: '%',
          onChanged: (v) => setState(() => loanRatePct = v)),
      SliderField(
          label: 'Loan tenure',
          value: loanYears,
          min: 5,
          max: 30,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => loanYears = v)),

      const SectionLabel('ASSUMPTIONS'),
      SliderField(
          label: 'Inflation',
          value: inflationPct,
          min: 0,
          max: 15,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => inflationPct = v)),
      SliderField(
          label: 'Investment return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: 'Monthly SIP for down payment',
        value: money(sipNeed),
        sub: 'for ${afterYears.round()} years to cover the 20% down payment',
      ),
      ResultCard(
        label: 'Estimated EMI after purchase',
        value: money(emi),
        sub: '${loanYears.round()}-year loan at '
            '${loanRatePct.toStringAsFixed(2)}%',
        color: Brand.green,
      ),
      Breakdown([
        ('House cost today', money(cost)),
        ('Future cost in ${afterYears.round()} yr', money(futureCost)),
        ('20% down payment', money(targetDown)),
        ('Already available', money(available)),
        ('Funding gap', money(gap)),
        ('Loan amount', money(loanAmount)),
        ('Total interest over loan', money(totalInterest)),
      ]),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'House Planning',
          inputs: [
            ('House cost today', money(cost)),
            ('Buy after', '${afterYears.round()} years'),
            ('Down payment available', money(available)),
            ('Home loan rate', '${loanRatePct.toStringAsFixed(2)}%'),
            ('Loan tenure', '${loanYears.round()} years'),
            ('Inflation', '${inflationPct.toStringAsFixed(1)}%'),
            ('Investment return', '${returnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Future house cost', money(futureCost)),
            ('20% down payment', money(targetDown)),
            ('Funding gap', money(gap)),
            ('Monthly SIP needed', money(sipNeed)),
            ('Loan amount', money(loanAmount)),
            ('Estimated EMI', money(emi)),
            ('Total interest', money(totalInterest)),
          ],
          note: 'Assumes a 20% down payment. Lenders may require more, and '
              'stamp duty and registration are not included above.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 4 — CAR PURCHASE
// ===========================================================================

class _CarTab extends StatefulWidget {
  const _CarTab();

  @override
  State<_CarTab> createState() => _CarTabState();
}

class _CarTabState extends State<_CarTab> {
  double cost = 1500000;
  double down = 300000;
  double afterYears = 3;
  double inflationPct = 6;
  double returnPct = 12;

  @override
  Widget build(BuildContext context) {
    final futureCost = _fv(cost, inflationPct / 100, afterYears);
    final gap = math.max(futureCost - down, 0.0);
    final sipNeed = _sipRequired(gap, returnPct / 100, afterYears);
    final lumpNeed = _lumpsumRequired(gap, returnPct / 100, afterYears);

    return TabBody(children: [
      SliderField(
          label: 'Car cost today',
          value: cost,
          min: 200000,
          max: 50000000,
          step: 50000,
          suffix: '₹',
          onChanged: (v) => setState(() => cost = v)),
      SliderField(
          label: 'Down payment available',
          value: down,
          min: 0,
          max: 10000000,
          step: 50000,
          suffix: '₹',
          onChanged: (v) => setState(() => down = v)),
      SliderField(
          label: 'Purchase after',
          value: afterYears,
          min: 1,
          max: 20,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => afterYears = v)),

      const SectionLabel('ASSUMPTIONS'),
      SliderField(
          label: 'Inflation',
          value: inflationPct,
          min: 0,
          max: 15,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => inflationPct = v)),
      SliderField(
          label: 'Investment return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: 'Monthly SIP needed',
        value: money(sipNeed),
        sub: 'for ${afterYears.round()} years',
      ),
      ResultCard(
        label: 'Or invest today (lumpsum)',
        value: money(lumpNeed),
        color: Brand.green,
      ),
      Breakdown([
        ('Cost today', money(cost)),
        ('Future cost in ${afterYears.round()} yr', money(futureCost)),
        ('Down payment available', money(down)),
        ('Funding gap', money(gap)),
      ]),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'Car Purchase Planner',
          inputs: [
            ('Car cost today', money(cost)),
            ('Down payment available', money(down)),
            ('Purchase after', '${afterYears.round()} years'),
            ('Inflation', '${inflationPct.toStringAsFixed(1)}%'),
            ('Investment return', '${returnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Future car cost', money(futureCost)),
            ('Funding gap', money(gap)),
            ('Monthly SIP', money(sipNeed)),
            ('Lumpsum today', money(lumpNeed)),
          ],
          note: 'A car is a depreciating asset. Consider whether financing it '
              'is worth the wealth foregone by not investing the same amount.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 5 — iPHONE / GADGET
// ===========================================================================

class _PhoneTab extends StatefulWidget {
  const _PhoneTab();

  @override
  State<_PhoneTab> createState() => _PhoneTabState();
}

class _PhoneTabState extends State<_PhoneTab> {
  double cost = 80000;
  double months = 12;
  double existing = 10000;
  double inflationPct = 6;
  double returnPct = 12;

  @override
  Widget build(BuildContext context) {
    // Inflation compounded monthly, matching the dashboard.
    final monthlyInfl =
        math.pow(1 + inflationPct / 100, 1 / 12).toDouble() - 1;
    final futureCost = cost * math.pow(1 + monthlyInfl, months).toDouble();
    final gap = math.max(futureCost - existing, 0.0);

    final r = returnPct / 100 / 12;
    final n = months.floor();
    final sipNeed = (r > 0 && n > 0)
        ? gap / (((math.pow(1 + r, n) - 1) / r) * (1 + r))
        : (n > 0 ? gap / n : gap);

    return TabBody(children: [
      SliderField(
          label: 'Cost today',
          value: cost,
          min: 5000,
          max: 500000,
          step: 1000,
          suffix: '₹',
          onChanged: (v) => setState(() => cost = v)),
      SliderField(
          label: 'Buy after',
          value: months,
          min: 1,
          max: 60,
          step: 1,
          suffix: 'mo',
          onChanged: (v) => setState(() => months = v)),
      SliderField(
          label: 'Existing savings',
          value: existing,
          min: 0,
          max: 500000,
          step: 1000,
          suffix: '₹',
          onChanged: (v) => setState(() => existing = v)),

      const SectionLabel('ASSUMPTIONS'),
      SliderField(
          label: 'Inflation',
          value: inflationPct,
          min: 0,
          max: 15,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => inflationPct = v)),
      SliderField(
          label: 'Investment return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: 'Save every month',
        value: money(sipNeed),
        sub: 'for ${months.round()} months',
      ),
      Breakdown([
        ('Cost today', money(cost)),
        ('Cost in ${months.round()} months', money(futureCost)),
        ('Existing savings', money(existing)),
        ('Funding gap', money(gap)),
        ('Total you will save', money(sipNeed * months)),
      ]),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'Gadget Purchase Planner',
          inputs: [
            ('Cost today', money(cost)),
            ('Buy after', '${months.round()} months'),
            ('Existing savings', money(existing)),
            ('Inflation', '${inflationPct.toStringAsFixed(1)}%'),
            ('Investment return', '${returnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Future cost', money(futureCost)),
            ('Funding gap', money(gap)),
            ('Monthly saving needed', money(sipNeed)),
          ],
          note: 'For short horizons, keep the money in a liquid or ultra-short '
              'debt fund rather than equity — a 12-month goal cannot absorb a '
              'market drawdown.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 6 — EMI vs SIP
// ===========================================================================

class _EmiVsSipTab extends StatefulWidget {
  const _EmiVsSipTab();

  @override
  State<_EmiVsSipTab> createState() => _EmiVsSipTabState();
}

class _EmiVsSipTabState extends State<_EmiVsSipTab> {
  double assetCost = 1000000;
  double downPayment = 200000;
  double loanRatePct = 9;
  double loanYears = 5;
  double sipReturnPct = 12;
  double compareYears = 5;
  double stepUpPct = 0;

  @override
  Widget build(BuildContext context) {
    final principal = math.max(assetCost - downPayment, 0.0);
    final emi = _emi(principal, loanRatePct / 100, loanYears);

    // Invest an amount equal to the EMI for the comparison period.
    final months = (compareYears * 12).floor();
    double corpus = 0, invested = 0, monthly = emi;
    for (var m = 1; m <= months; m++) {
      corpus = corpus * (1 + sipReturnPct / 100 / 12) + monthly;
      invested += monthly;
      if (stepUpPct > 0 && m % 12 == 0) monthly *= (1 + stepUpPct / 100);
    }

    final emiMonths = math.min((loanYears * 12).floor(), months);
    final totalEmiOutflow = emi * emiMonths;
    final wealthGap = corpus - totalEmiOutflow;

    return TabBody(children: [
      const SectionLabel('THE LOAN'),
      SliderField(
          label: 'Asset cost',
          value: assetCost,
          min: 100000,
          max: 100000000,
          step: 100000,
          suffix: '₹',
          onChanged: (v) => setState(() => assetCost = v)),
      SliderField(
          label: 'Down payment',
          value: downPayment,
          min: 0,
          max: 50000000,
          step: 50000,
          suffix: '₹',
          onChanged: (v) => setState(() => downPayment = v)),
      SliderField(
          label: 'Loan interest rate',
          value: loanRatePct,
          min: 1,
          max: 25,
          step: 0.25,
          decimals: 2,
          suffix: '%',
          onChanged: (v) => setState(() => loanRatePct = v)),
      SliderField(
          label: 'Loan tenure',
          value: loanYears,
          min: 1,
          max: 30,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => loanYears = v)),

      const SectionLabel('THE ALTERNATIVE'),
      SliderField(
          label: 'Expected SIP return',
          value: sipReturnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => sipReturnPct = v)),
      SliderField(
          label: 'Comparison period',
          value: compareYears,
          min: 1,
          max: 30,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => compareYears = v)),
      SliderField(
          label: 'SIP annual step-up',
          value: stepUpPct,
          min: 0,
          max: 30,
          step: 1,
          suffix: '%',
          onChanged: (v) => setState(() => stepUpPct = v)),

      const SizedBox(height: 12),
      ResultCard(
        label: 'Monthly EMI',
        value: money(emi),
        sub: '${loanYears.round()}-year loan on ${money(principal)}',
      ),
      ResultCard(
        label: 'If you invested that EMI instead',
        value: moneyShort(corpus),
        sub: 'over ${compareYears.round()} years at '
            '${sipReturnPct.toStringAsFixed(1)}%',
        color: Brand.green,
      ),
      ResultCard(
        label: wealthGap >= 0 ? 'Wealth foregone' : 'Loan comes out ahead by',
        value: moneyShort(wealthGap.abs()),
        sub: wealthGap >= 0
            ? 'the opportunity cost of financing this asset'
            : 'investing would not have beaten the loan cost',
        color: wealthGap >= 0 ? Brand.red : Brand.green,
      ),
      Breakdown([
        ('Loan principal', money(principal)),
        ('Monthly EMI', money(emi)),
        ('Total EMI outflow', money(totalEmiOutflow)),
        ('Equivalent SIP invested', money(invested)),
        ('Projected SIP corpus', money(corpus)),
        ('Net wealth difference', money(wealthGap)),
      ], highlightLast: true),
      PdfButton(
        onPressed: () => exportReportPdf(
          title: 'EMI vs SIP Comparison',
          inputs: [
            ('Asset cost', money(assetCost)),
            ('Down payment', money(downPayment)),
            ('Loan rate', '${loanRatePct.toStringAsFixed(2)}%'),
            ('Loan tenure', '${loanYears.round()} years'),
            ('SIP return', '${sipReturnPct.toStringAsFixed(1)}%'),
            ('Comparison period', '${compareYears.round()} years'),
            ('SIP step-up', '${stepUpPct.round()}%'),
          ],
          results: [
            ('Monthly EMI', money(emi)),
            ('Total EMI outflow', money(totalEmiOutflow)),
            ('SIP corpus if invested', money(corpus)),
            ('Net wealth difference', money(wealthGap)),
          ],
          tableHeaders: const ['Metric', 'Value'],
          tableTitle: 'COMPARISON',
          tableRows: [
            ['Loan principal', money(principal)],
            ['Monthly EMI', money(emi)],
            ['Total EMI outflow', money(totalEmiOutflow)],
            ['Equivalent SIP', money(emi)],
            ['Total SIP invested', money(invested)],
            ['Projected SIP corpus', money(corpus)],
            ['Net wealth difference', money(wealthGap)],
          ],
          note: 'This compares financing an asset against investing the same '
              'monthly amount. It ignores the asset\'s own value or resale '
              'price, so it is most useful for depreciating and '
              'non-essential purchases.',
        ),
      ),
    ]);
  }
}
