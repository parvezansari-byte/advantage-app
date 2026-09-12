// calculator_screen.dart
// ---------------------------------------------------------------------------
// Investment calculators, ported 1:1 from the Streamlit dashboard's
// calculator.py so the numbers match exactly.
//
// Tabs: SIP · Lumpsum · Goal · Step-up SIP · SWP · EMI
//
// Add to your routes, e.g.:
//     Navigator.push(context,
//         MaterialPageRoute(builder: (_) => const CalculatorScreen()));
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../main.dart';

// ===========================================================================
// MATH — direct ports of calculator.py
// ===========================================================================

/// pv * (1 + rate)^years
double futureValue(double pv, double rate, double years) =>
    pv * math.pow(1 + rate, math.max(years, 0)).toDouble();

/// Future value of a monthly SIP.
///
/// Contributions are treated as arriving at the END of each month, matching
/// the dashboard's accumulation loop (corpus = corpus * (1 + r) + sip).
/// This keeps the headline figure identical to the month-by-month schedule.
double futureValueSip(double monthly, double annualReturn, double years) {
  final months = (math.max(years, 0) * 12).floor();
  if (months <= 0) return 0;
  final r = annualReturn / 12;
  if (r <= 0) return monthly * months;
  return monthly * ((math.pow(1 + r, months) - 1) / r);
}

/// Lumpsum needed today to reach [target].
double lumpsumRequired(double target, double annualReturn, double years) {
  if (years <= 0) return target;
  return target / math.pow(1 + annualReturn, years);
}

/// Monthly SIP needed to reach [target] (end-of-month contributions).
double monthlySipRequired(double target, double annualRate, double years) {
  final months = (math.max(years, 0) * 12).floor();
  if (months <= 0) return 0;
  final r = annualRate / 12;
  if (r <= 0) return target / months;
  final factor = (math.pow(1 + r, months) - 1) / r;
  return factor > 0 ? target / factor : 0;
}

/// Starting SIP needed when the SIP steps up by [stepUp] each year.
/// Binary search, same as the Python version.
double monthlySipRequiredStepUp(
    double target, double annualReturn, double years, double stepUp) {
  final months = (math.max(years, 0) * 12).floor();
  if (months <= 0) return 0;
  final r = annualReturn / 12;
  double low = 0, high = math.max(target, 1);
  for (var i = 0; i < 80; i++) {
    final mid = (low + high) / 2;
    double corpus = 0, sip = mid;
    for (var m = 1; m <= months; m++) {
      corpus = corpus * (1 + r) + sip;
      if (m % 12 == 0) sip *= (1 + stepUp);
    }
    if (corpus >= target) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return high;
}

/// Corpus needed to sustain a monthly withdrawal for [years].
double swpCorpusRequired(
    double monthlyWithdrawal, double annualReturn, double years) {
  final r = annualReturn / 12;
  final n = (years * 12).floor();
  if (n <= 0) return 0;
  if (r == 0) return monthlyWithdrawal * n;
  return monthlyWithdrawal * ((1 - math.pow(1 + r, -n)) / r);
}

/// Equated monthly instalment.
double emiCalculator(double principal, double annualRate, double years) {
  final r = annualRate / 12;
  final n = (years * 12).floor();
  if (n <= 0) return 0;
  if (r == 0) return principal / n;
  final pow = math.pow(1 + r, n).toDouble();
  return principal * r * pow / (pow - 1);
}

// ===========================================================================
// FORMATTING
// ===========================================================================

/// Indian-style grouping: 12,34,567
String _indianGroup(int n) {
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

String fmt(num x) {
  if (!x.isFinite) return '₹ 0';
  return '₹ ${_indianGroup(x.round())}';
}

/// Short form for headline numbers: ₹1.24 Cr / ₹45.6 L / ₹92,000
String fmtShort(num x) {
  if (!x.isFinite) return '₹ 0';
  final v = x.abs();
  if (v >= 10000000) return '₹ ${(x / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹ ${(x / 100000).toStringAsFixed(2)} L';
  return fmt(x);
}

// ===========================================================================
// SCHEDULE MODEL
// ===========================================================================

/// One month of a projection. [invested] is cumulative money in;
/// [balance] is the corpus (or outstanding loan) at month end.
class ScheduleRow {
  const ScheduleRow({
    required this.month,
    required this.contribution,
    required this.invested,
    required this.interest,
    required this.balance,
  });

  final int month;
  final double contribution;
  final double invested;
  final double interest;
  final double balance;

  int get year => ((month - 1) ~/ 12) + 1;
}

/// Month-by-month SIP accumulation. Mirrors the Streamlit loop:
///   corpus = corpus * (1 + r/12) + sip
/// with the SIP stepping up every 12 months when [stepUp] > 0.
List<ScheduleRow> sipSchedule({
  required double monthly,
  required double annualReturn,
  required double years,
  double stepUp = 0,
}) {
  final months = (math.max(years, 0) * 12).floor();
  final r = annualReturn / 12;
  final rows = <ScheduleRow>[];
  double corpus = 0, invested = 0, sip = monthly;

  for (var m = 1; m <= months; m++) {
    corpus = corpus * (1 + r) + sip;
    invested += sip;
    rows.add(ScheduleRow(
      month: m,
      contribution: sip,
      invested: invested,
      interest: corpus - invested,
      balance: corpus,
    ));
    if (m % 12 == 0) sip *= (1 + stepUp);
  }
  return rows;
}

/// Month-by-month growth of a one-time investment.
List<ScheduleRow> lumpsumSchedule({
  required double amount,
  required double annualReturn,
  required double years,
}) {
  final months = (math.max(years, 0) * 12).floor();
  final r = annualReturn / 12;
  final rows = <ScheduleRow>[];
  double corpus = amount;

  for (var m = 1; m <= months; m++) {
    corpus *= (1 + r);
    rows.add(ScheduleRow(
      month: m,
      contribution: m == 1 ? amount : 0,
      invested: amount,
      interest: corpus - amount,
      balance: corpus,
    ));
  }
  return rows;
}

/// Month-by-month drawdown. [contribution] is the withdrawal;
/// [invested] tracks the running total withdrawn.
List<ScheduleRow> swpSchedule({
  required double corpus,
  required double monthlyWithdrawal,
  required double annualReturn,
  required double years,
}) {
  final months = (math.max(years, 0) * 12).floor();
  final r = annualReturn / 12;
  final rows = <ScheduleRow>[];
  double bal = corpus, withdrawn = 0;

  for (var m = 1; m <= months; m++) {
    final growth = bal * r;
    bal = bal + growth - monthlyWithdrawal;
    withdrawn += monthlyWithdrawal;
    rows.add(ScheduleRow(
      month: m,
      contribution: monthlyWithdrawal,
      invested: withdrawn,
      interest: growth,
      balance: math.max(bal, 0),
    ));
    if (bal <= 0) break;
  }
  return rows;
}

/// Loan amortisation. [interest] is that month's interest portion,
/// [contribution] the EMI, [balance] the outstanding principal.
List<ScheduleRow> emiSchedule({
  required double principal,
  required double annualRate,
  required double years,
}) {
  final months = (math.max(years, 0) * 12).floor();
  final r = annualRate / 12;
  final emi = emiCalculator(principal, annualRate, years);
  final rows = <ScheduleRow>[];
  double bal = principal, paid = 0;

  for (var m = 1; m <= months; m++) {
    final interest = bal * r;
    final principalPart = emi - interest;
    bal = math.max(bal - principalPart, 0);
    paid += emi;
    rows.add(ScheduleRow(
      month: m,
      contribution: emi,
      invested: paid,
      interest: interest,
      balance: bal,
    ));
  }
  return rows;
}

// ===========================================================================
// PDF EXPORT
// ===========================================================================

/// Builds and shares a PDF for one calculator.
///
/// [inputs] are printed as a summary block, [results] as the headline figures,
/// and [rows] becomes the month-by-month table.
Future<void> exportSchedulePdf({
  required BuildContext context,
  required String title,
  required List<(String, String)> inputs,
  required List<(String, String)> results,
  required List<ScheduleRow> rows,
  required List<String> columns,
  required List<String> Function(ScheduleRow) rowBuilder,
}) async {
  final doc = pw.Document();
  final generated = DateTime.now();

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 10)),
            pw.Text(v,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(title,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            ),
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
                'Generated ${generated.day.toString().padLeft(2, '0')}-'
                '${generated.month.toString().padLeft(2, '0')}-${generated.year}',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // ---- Inputs & results side by side ----
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
                    pw.Text('ASSUMPTIONS',
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
        pw.SizedBox(height: 16),

        pw.Text('MONTH-BY-MONTH SCHEDULE',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),

        pw.TableHelper.fromTextArray(
          headers: columns,
          data: rows.map(rowBuilder).toList(),
          headerStyle: pw.TextStyle(
              fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellHeight: 14,
          cellAlignments: {
            0: pw.Alignment.center,
            for (var i = 1; i < columns.length; i++) i: pw.Alignment.centerRight,
          },
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),

        pw.SizedBox(height: 14),
        pw.Text(
          'Projections assume a constant rate of return and are illustrative '
          'only. Actual returns will vary. This is not investment advice.',
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

class CalculatorScreen extends StatelessWidget {
  const CalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          elevation: 0,
          title: const Text('Calculators',
              style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Brand.gold,
            unselectedLabelColor: Brand.mint,
            indicatorColor: Brand.gold,
            tabs: const [
              Tab(text: 'SIP'),
              Tab(text: 'SIP + SWP'),
              Tab(text: 'Lumpsum'),
              Tab(text: 'Goal'),
              Tab(text: 'Step-up SIP'),
              Tab(text: 'SWP'),
              Tab(text: 'EMI'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SipTab(),
            _SipSwpTab(),
            _LumpsumTab(),
            _GoalTab(),
            _StepUpTab(),
            _SwpTab(),
            _EmiTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// SHARED WIDGETS
// ===========================================================================

/// Labelled slider with a synced numeric text field.
class _InputRow extends StatefulWidget {
  const _InputRow({
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
  State<_InputRow> createState() => _InputRowState();
}

class _InputRowState extends State<_InputRow> {
  late final TextEditingController _ctrl;

  String get _text => widget.value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _text);
  }

  @override
  void didUpdateWidget(covariant _InputRow old) {
    super.didUpdateWidget(old);
    // Keep the field in sync when the slider moves, but don't fight the user
    // while they're typing in it.
    if (widget.value != old.value && _ctrl.text != _text) {
      _ctrl.text = _text;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '').trim());
    if (parsed == null) return;
    widget.onChanged(parsed.clamp(widget.min, widget.max).toDouble());
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
              valueIndicatorColor: Brand.fern,
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

/// Big headline result card.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
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

/// Two-column breakdown rows.
class _Breakdown extends StatelessWidget {
  const _Breakdown(this.rows, {super.key});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(k,
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.85),
                            fontSize: 13)),
                    Text(v,
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible month-by-month table. Renders lazily so a 480-row
/// schedule doesn't cost anything until the user opens it.
class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({
    required this.rows,
    required this.columns,
    required this.rowBuilder,
    this.title = 'Month-by-month schedule',
  });

  final List<ScheduleRow> rows;
  final List<String> columns;
  final List<String> Function(ScheduleRow) rowBuilder;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Brand.gold,
          collapsedIconColor: Brand.mint,
          title: Text(title,
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text('${rows.length} months',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
          children: [
            // Header
            Container(
              color: Brand.fern.withValues(alpha: 0.55),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    Expanded(
                      flex: i == 0 ? 2 : 3,
                      child: Text(
                        columns[i],
                        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                        style: const TextStyle(
                            color: Brand.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final cells = rowBuilder(rows[i]);
                  final isYearEnd = rows[i].month % 12 == 0;
                  return Container(
                    color: isYearEnd
                        ? Brand.gold.withValues(alpha: 0.08)
                        : (i.isEven
                            ? Colors.transparent
                            : Brand.fern.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    child: Row(
                      children: [
                        for (var c = 0; c < cells.length; c++)
                          Expanded(
                            flex: c == 0 ? 2 : 3,
                            child: Text(
                              cells[c],
                              textAlign:
                                  c == 0 ? TextAlign.left : TextAlign.right,
                              style: TextStyle(
                                color: c == 0
                                    ? Brand.mint
                                    : Brand.paper.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: isYearEnd
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width "Download PDF" button.
class _PdfButton extends StatefulWidget {
  const _PdfButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<_PdfButton> createState() => _PdfButtonState();
}

class _PdfButtonState extends State<_PdfButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

class _TabBody extends StatelessWidget {
  const _TabBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: children,
    );
  }
}

// ===========================================================================
// TAB 1 — SIP
// ===========================================================================

class _SipTab extends StatefulWidget {
  const _SipTab();

  @override
  State<_SipTab> createState() => _SipTabState();
}

class _SipTabState extends State<_SipTab> {
  double monthly = 10000;
  double returnPct = 12;
  double years = 15;

  static const _cols = ['M', 'SIP', 'Invested', 'Gain', 'Corpus'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmt(r.contribution),
        fmtShort(r.invested),
        fmtShort(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final rows =
        sipSchedule(monthly: monthly, annualReturn: returnPct / 100, years: years);
    final fv = rows.isEmpty ? 0.0 : rows.last.balance;
    final invested = rows.isEmpty ? 0.0 : rows.last.invested;
    final gain = fv - invested;

    return _TabBody(children: [
      _InputRow(
        label: 'Monthly investment',
        value: monthly,
        min: 500,
        max: 500000,
        step: 500,
        suffix: '₹',
        onChanged: (v) => setState(() => monthly = v),
      ),
      _InputRow(
        label: 'Expected return',
        value: returnPct,
        min: 1,
        max: 30,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => returnPct = v),
      ),
      _InputRow(
        label: 'Duration',
        value: years,
        min: 1,
        max: 40,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Estimated corpus',
        value: fmtShort(fv),
        sub: 'after ${years.round()} years at ${returnPct.toStringAsFixed(1)}% p.a.',
      ),
      _Breakdown([
        ('Total invested', fmt(invested)),
        ('Estimated gains', fmt(gain)),
        ('Final value', fmt(fv)),
        ('Gain multiple',
            invested > 0 ? '${(fv / invested).toStringAsFixed(2)}x' : '—'),
      ]),
      _ScheduleTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'SIP Calculator',
          inputs: [
            ('Monthly investment', fmt(monthly)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}% p.a.'),
            ('Duration', '${years.round()} years'),
          ],
          results: [
            ('Total invested', fmt(invested)),
            ('Estimated gains', fmt(gain)),
            ('Final corpus', fmt(fv)),
          ],
          rows: rows,
          columns: const ['Month', 'SIP', 'Invested', 'Gain', 'Corpus'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 2 — LUMPSUM
// ===========================================================================

class _LumpsumTab extends StatefulWidget {
  const _LumpsumTab();

  @override
  State<_LumpsumTab> createState() => _LumpsumTabState();
}

class _LumpsumTabState extends State<_LumpsumTab> {
  double amount = 500000;
  double returnPct = 12;
  double years = 10;

  static const _cols = ['M', 'Invested', 'Gain', 'Value'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmtShort(r.invested),
        fmtShort(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final rows = lumpsumSchedule(
        amount: amount, annualReturn: returnPct / 100, years: years);
    final fv = rows.isEmpty ? amount : rows.last.balance;
    final gain = fv - amount;

    return _TabBody(children: [
      _InputRow(
        label: 'Investment amount',
        value: amount,
        min: 10000,
        max: 50000000,
        step: 10000,
        suffix: '₹',
        onChanged: (v) => setState(() => amount = v),
      ),
      _InputRow(
        label: 'Expected return',
        value: returnPct,
        min: 1,
        max: 30,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => returnPct = v),
      ),
      _InputRow(
        label: 'Duration',
        value: years,
        min: 1,
        max: 40,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Estimated value',
        value: fmtShort(fv),
        sub: 'after ${years.round()} years at ${returnPct.toStringAsFixed(1)}% p.a.',
      ),
      _Breakdown([
        ('Invested', fmt(amount)),
        ('Estimated gains', fmt(gain)),
        ('Final value', fmt(fv)),
        ('Gain multiple',
            amount > 0 ? '${(fv / amount).toStringAsFixed(2)}x' : '—'),
      ]),
      _ScheduleTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'Lumpsum Calculator',
          inputs: [
            ('Investment amount', fmt(amount)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}% p.a.'),
            ('Duration', '${years.round()} years'),
          ],
          results: [
            ('Invested', fmt(amount)),
            ('Estimated gains', fmt(gain)),
            ('Final value', fmt(fv)),
          ],
          rows: rows,
          columns: const ['Month', 'Invested', 'Gain', 'Value'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 3 — GOAL
// ===========================================================================

class _GoalTab extends StatefulWidget {
  const _GoalTab();

  @override
  State<_GoalTab> createState() => _GoalTabState();
}

class _GoalTabState extends State<_GoalTab> {
  double target = 10000000;
  double returnPct = 12;
  double years = 15;

  static const _cols = ['M', 'SIP', 'Invested', 'Gain', 'Corpus'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmt(r.contribution),
        fmtShort(r.invested),
        fmtShort(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final sip = monthlySipRequired(target, returnPct / 100, years);
    final lump = lumpsumRequired(target, returnPct / 100, years);
    final rows =
        sipSchedule(monthly: sip, annualReturn: returnPct / 100, years: years);
    final totalViaSip = rows.isEmpty ? 0.0 : rows.last.invested;

    return _TabBody(children: [
      _InputRow(
        label: 'Target corpus',
        value: target,
        min: 100000,
        max: 100000000,
        step: 100000,
        suffix: '₹',
        onChanged: (v) => setState(() => target = v),
      ),
      _InputRow(
        label: 'Expected return',
        value: returnPct,
        min: 1,
        max: 30,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => returnPct = v),
      ),
      _InputRow(
        label: 'Time to goal',
        value: years,
        min: 1,
        max: 40,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Monthly SIP required',
        value: fmt(sip),
        sub: 'to reach ${fmtShort(target)} in ${years.round()} years',
      ),
      _ResultCard(
        label: 'Or invest today (lumpsum)',
        value: fmtShort(lump),
        color: Brand.green,
      ),
      _Breakdown([
        ('Target', fmt(target)),
        ('Total invested via SIP', fmt(totalViaSip)),
        ('Gains via SIP', fmt(target - totalViaSip)),
      ]),
      _ScheduleTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'Goal Planner',
          inputs: [
            ('Target corpus', fmt(target)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}% p.a.'),
            ('Time to goal', '${years.round()} years'),
          ],
          results: [
            ('Monthly SIP required', fmt(sip)),
            ('Lumpsum alternative', fmt(lump)),
            ('Total invested via SIP', fmt(totalViaSip)),
          ],
          rows: rows,
          columns: const ['Month', 'SIP', 'Invested', 'Gain', 'Corpus'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 4 — STEP-UP SIP
// ===========================================================================

class _StepUpTab extends StatefulWidget {
  const _StepUpTab();

  @override
  State<_StepUpTab> createState() => _StepUpTabState();
}

class _StepUpTabState extends State<_StepUpTab> {
  double target = 10000000;
  double returnPct = 12;
  double years = 15;
  double stepUpPct = 10;

  static const _cols = ['M', 'SIP', 'Invested', 'Gain', 'Corpus'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmt(r.contribution),
        fmtShort(r.invested),
        fmtShort(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final startSip = monthlySipRequiredStepUp(
        target, returnPct / 100, years, stepUpPct / 100);
    final flatSip = monthlySipRequired(target, returnPct / 100, years);
    final rows = sipSchedule(
      monthly: startSip,
      annualReturn: returnPct / 100,
      years: years,
      stepUp: stepUpPct / 100,
    );
    final total = rows.isEmpty ? 0.0 : rows.last.invested;
    final finalSip = rows.isEmpty ? startSip : rows.last.contribution;

    return _TabBody(children: [
      _InputRow(
        label: 'Target corpus',
        value: target,
        min: 100000,
        max: 100000000,
        step: 100000,
        suffix: '₹',
        onChanged: (v) => setState(() => target = v),
      ),
      _InputRow(
        label: 'Expected return',
        value: returnPct,
        min: 1,
        max: 30,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => returnPct = v),
      ),
      _InputRow(
        label: 'Time to goal',
        value: years,
        min: 1,
        max: 40,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      _InputRow(
        label: 'Annual step-up',
        value: stepUpPct,
        min: 0,
        max: 25,
        step: 1,
        suffix: '%',
        onChanged: (v) => setState(() => stepUpPct = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Starting monthly SIP',
        value: fmt(startSip),
        sub: 'increasing ${stepUpPct.round()}% every year',
      ),
      _Breakdown([
        ('Flat SIP (no step-up)', fmt(flatSip)),
        ('You start lower by', fmt(math.max(flatSip - startSip, 0))),
        ('Final year SIP', fmt(finalSip)),
        ('Total invested', fmtShort(total)),
      ]),
      _ScheduleTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'Step-up SIP Planner',
          inputs: [
            ('Target corpus', fmt(target)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}% p.a.'),
            ('Time to goal', '${years.round()} years'),
            ('Annual step-up', '${stepUpPct.round()}%'),
          ],
          results: [
            ('Starting SIP', fmt(startSip)),
            ('Final year SIP', fmt(finalSip)),
            ('Total invested', fmt(total)),
          ],
          rows: rows,
          columns: const ['Month', 'SIP', 'Invested', 'Gain', 'Corpus'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 5 — SWP
// ===========================================================================

class _SwpTab extends StatefulWidget {
  const _SwpTab();

  @override
  State<_SwpTab> createState() => _SwpTabState();
}

class _SwpTabState extends State<_SwpTab> {
  double withdrawal = 50000;
  double returnPct = 8;
  double years = 25;

  static const _cols = ['M', 'Withdrawn', 'Growth', 'Balance'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmtShort(r.invested),
        fmt(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final corpus = swpCorpusRequired(withdrawal, returnPct / 100, years);
    final rows = swpSchedule(
      corpus: corpus,
      monthlyWithdrawal: withdrawal,
      annualReturn: returnPct / 100,
      years: years,
    );
    final totalWithdrawn = rows.isEmpty ? 0.0 : rows.last.invested;

    return _TabBody(children: [
      _InputRow(
        label: 'Monthly withdrawal',
        value: withdrawal,
        min: 5000,
        max: 1000000,
        step: 5000,
        suffix: '₹',
        onChanged: (v) => setState(() => withdrawal = v),
      ),
      _InputRow(
        label: 'Expected return',
        value: returnPct,
        min: 1,
        max: 20,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => returnPct = v),
      ),
      _InputRow(
        label: 'Withdrawal period',
        value: years,
        min: 1,
        max: 50,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Corpus needed',
        value: fmtShort(corpus),
        sub: 'to withdraw ${fmt(withdrawal)}/month for ${years.round()} years',
      ),
      _Breakdown([
        ('Total withdrawn', fmtShort(totalWithdrawn)),
        ('Starting corpus', fmt(corpus)),
        ('Growth covers',
            totalWithdrawn > 0
                ? '${(((totalWithdrawn - corpus) / totalWithdrawn) * 100).clamp(0, 100).toStringAsFixed(0)}%'
                : '—'),
      ]),
      _ScheduleTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'SWP Calculator',
          inputs: [
            ('Monthly withdrawal', fmt(withdrawal)),
            ('Expected return', '${returnPct.toStringAsFixed(1)}% p.a.'),
            ('Withdrawal period', '${years.round()} years'),
          ],
          results: [
            ('Corpus needed', fmt(corpus)),
            ('Total withdrawn', fmt(totalWithdrawn)),
          ],
          rows: rows,
          columns: const ['Month', 'Withdrawn', 'Growth', 'Balance'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 6 — EMI
// ===========================================================================

class _EmiTab extends StatefulWidget {
  const _EmiTab();

  @override
  State<_EmiTab> createState() => _EmiTabState();
}

class _EmiTabState extends State<_EmiTab> {
  double principal = 3000000;
  double ratePct = 8.5;
  double years = 20;

  static const _cols = ['M', 'EMI', 'Interest', 'Outstanding'];

  List<String> _row(ScheduleRow r) => [
        '${r.month}',
        fmt(r.contribution),
        fmt(r.interest),
        fmtShort(r.balance),
      ];

  @override
  Widget build(BuildContext context) {
    final emi = emiCalculator(principal, ratePct / 100, years);
    final rows = emiSchedule(
        principal: principal, annualRate: ratePct / 100, years: years);
    final totalPaid = rows.isEmpty ? 0.0 : rows.last.invested;
    final interest = totalPaid - principal;

    return _TabBody(children: [
      _InputRow(
        label: 'Loan amount',
        value: principal,
        min: 50000,
        max: 50000000,
        step: 50000,
        suffix: '₹',
        onChanged: (v) => setState(() => principal = v),
      ),
      _InputRow(
        label: 'Interest rate',
        value: ratePct,
        min: 1,
        max: 25,
        step: 0.1,
        decimals: 2,
        suffix: '%',
        onChanged: (v) => setState(() => ratePct = v),
      ),
      _InputRow(
        label: 'Tenure',
        value: years,
        min: 1,
        max: 30,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => years = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Monthly EMI',
        value: fmt(emi),
        sub: '${rows.length} payments at ${ratePct.toStringAsFixed(2)}% p.a.',
      ),
      _Breakdown([
        ('Principal', fmt(principal)),
        ('Total interest', fmt(interest)),
        ('Total payable', fmt(totalPaid)),
        ('Interest as % of loan',
            principal > 0
                ? '${((interest / principal) * 100).toStringAsFixed(0)}%'
                : '—'),
      ]),
      _ScheduleTable(
        rows: rows,
        columns: _cols,
        rowBuilder: _row,
        title: 'Amortisation schedule',
      ),
      _PdfButton(
        onPressed: () => exportSchedulePdf(
          context: context,
          title: 'EMI Calculator',
          inputs: [
            ('Loan amount', fmt(principal)),
            ('Interest rate', '${ratePct.toStringAsFixed(2)}% p.a.'),
            ('Tenure', '${years.round()} years'),
          ],
          results: [
            ('Monthly EMI', fmt(emi)),
            ('Total interest', fmt(interest)),
            ('Total payable', fmt(totalPaid)),
          ],
          rows: rows,
          columns: const ['Month', 'EMI', 'Interest', 'Outstanding'],
          rowBuilder: _row,
        ),
      ),
    ]);
  }
}

// ===========================================================================
// SIP + SWP PLANNER
// ===========================================================================

/// One year of the two-phase plan. During accumulation [sipMonthly] is set
/// and withdrawals are zero; during drawdown the reverse.
class PlanRow {
  const PlanRow({
    required this.age,
    required this.opening,
    required this.sipMonthly,
    required this.sipYearly,
    required this.swpMonthly,
    required this.swpYearly,
    required this.closing,
  });

  final int age;
  final double opening;
  final double sipMonthly;
  final double sipYearly;
  final double swpMonthly;
  final double swpYearly;
  final double closing;

  bool get isAccumulation => sipYearly > 0;
}

/// Two-phase projection: step-up SIP until [sipTillAge], then an escalating
/// SWP from [swpStartAge] until the corpus runs out (or age 110).
///
/// Mirrors the dashboard loop exactly — monthly compounding within each year,
/// SIP stepped up and withdrawal escalated once per year.
List<PlanRow> sipSwpPlan({
  required int currentAge,
  required int sipTillAge,
  required int swpStartAge,
  required double sipMonthly,
  required double sipReturn,
  required double sipStepUp,
  required double swpMonthly,
  required double swpReturn,
  required double swpStepUp,
}) {
  final rows = <PlanRow>[];
  double corpus = 0;
  double monthly = sipMonthly;

  // --- Accumulation ---
  for (var age = currentAge; age < sipTillAge; age++) {
    final opening = corpus;
    double invested = 0;
    for (var m = 0; m < 12; m++) {
      corpus = corpus * (1 + sipReturn / 12) + monthly;
      invested += monthly;
    }
    rows.add(PlanRow(
      age: age,
      opening: opening,
      sipMonthly: monthly,
      sipYearly: invested,
      swpMonthly: 0,
      swpYearly: 0,
      closing: corpus,
    ));
    monthly *= (1 + sipStepUp);
  }

  // --- Gap years, if SWP starts later than the SIP ends ---
  for (var age = sipTillAge; age < swpStartAge; age++) {
    final opening = corpus;
    for (var m = 0; m < 12; m++) {
      corpus *= (1 + sipReturn / 12);
    }
    rows.add(PlanRow(
      age: age,
      opening: opening,
      sipMonthly: 0,
      sipYearly: 0,
      swpMonthly: 0,
      swpYearly: 0,
      closing: corpus,
    ));
  }

  // --- Drawdown ---
  double wd = swpMonthly;
  for (var age = swpStartAge; age <= 110; age++) {
    final opening = corpus;
    final yearly = wd * 12;
    for (var m = 0; m < 12; m++) {
      corpus = corpus * (1 + swpReturn / 12) - wd;
    }
    rows.add(PlanRow(
      age: age,
      opening: opening,
      sipMonthly: 0,
      sipYearly: 0,
      swpMonthly: wd,
      swpYearly: yearly,
      closing: corpus,
    ));
    wd *= (1 + swpStepUp);
    if (corpus <= 0) break;
  }

  return rows;
}

class _SipSwpTab extends StatefulWidget {
  const _SipSwpTab();

  @override
  State<_SipSwpTab> createState() => _SipSwpTabState();
}

class _SipSwpTabState extends State<_SipSwpTab> {
  double currentAge = 30;
  double sipTillAge = 40;
  double swpStartAge = 40;
  double sipAmount = 50000;
  double sipReturnPct = 13;
  double sipStepPct = 10;
  double swpAmount = 150000;
  double swpStepPct = 8;
  double swpReturnPct = 9;

  static const _cols = ['Age', 'Opening', 'SIP/yr', 'SWP/yr', 'Closing'];

  List<String> _row(PlanRow r) => [
        '${r.age}',
        fmtShort(r.opening),
        r.sipYearly > 0 ? fmtShort(r.sipYearly) : '—',
        r.swpYearly > 0 ? fmtShort(r.swpYearly) : '—',
        fmtShort(math.max(r.closing, 0)),
      ];

  @override
  Widget build(BuildContext context) {
    // Keep the ages coherent as the user drags sliders around.
    final tillAge = math.max(sipTillAge, currentAge + 1);
    final startAge = math.max(swpStartAge, tillAge);

    final rows = sipSwpPlan(
      currentAge: currentAge.round(),
      sipTillAge: tillAge.round(),
      swpStartAge: startAge.round(),
      sipMonthly: sipAmount,
      sipReturn: sipReturnPct / 100,
      sipStepUp: sipStepPct / 100,
      swpMonthly: swpAmount,
      swpReturn: swpReturnPct / 100,
      swpStepUp: swpStepPct / 100,
    );

    final accumulation = rows.where((r) => r.isAccumulation);
    final drawdown = rows.where((r) => r.swpYearly > 0);

    final totalInvested =
        accumulation.fold<double>(0, (s, r) => s + r.sipYearly);
    final totalWithdrawn = drawdown.fold<double>(0, (s, r) => s + r.swpYearly);
    final corpusAtStart = drawdown.isEmpty
        ? (rows.isEmpty ? 0.0 : rows.last.closing)
        : drawdown.first.opening;
    final lastAge = rows.isEmpty ? startAge.round() : rows.last.age;
    final finalCorpus = rows.isEmpty ? 0.0 : math.max(rows.last.closing, 0);

    // If money is still left at 110 the plan never depleted.
    final survived = finalCorpus > 0;

    return _TabBody(children: [
      const _SectionLabel('ACCUMULATION'),
      _InputRow(
        label: 'Current age',
        value: currentAge,
        min: 18,
        max: 80,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => currentAge = v),
      ),
      _InputRow(
        label: 'SIP till age',
        value: tillAge,
        min: currentAge + 1,
        max: 90,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => sipTillAge = v),
      ),
      _InputRow(
        label: 'Monthly SIP',
        value: sipAmount,
        min: 1000,
        max: 1000000,
        step: 1000,
        suffix: '₹',
        onChanged: (v) => setState(() => sipAmount = v),
      ),
      _InputRow(
        label: 'Return during SIP',
        value: sipReturnPct,
        min: 1,
        max: 25,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => sipReturnPct = v),
      ),
      _InputRow(
        label: 'Annual step-up',
        value: sipStepPct,
        min: 0,
        max: 30,
        step: 1,
        suffix: '%',
        onChanged: (v) => setState(() => sipStepPct = v),
      ),
      const SizedBox(height: 12),
      const _SectionLabel('WITHDRAWAL'),
      _InputRow(
        label: 'SWP start age',
        value: startAge,
        min: tillAge,
        max: 100,
        step: 1,
        suffix: 'yr',
        onChanged: (v) => setState(() => swpStartAge = v),
      ),
      _InputRow(
        label: 'Monthly withdrawal',
        value: swpAmount,
        min: 5000,
        max: 2000000,
        step: 5000,
        suffix: '₹',
        onChanged: (v) => setState(() => swpAmount = v),
      ),
      _InputRow(
        label: 'Yearly increase',
        value: swpStepPct,
        min: 0,
        max: 25,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => swpStepPct = v),
      ),
      _InputRow(
        label: 'Return in withdrawal phase',
        value: swpReturnPct,
        min: 1,
        max: 25,
        step: 0.5,
        decimals: 1,
        suffix: '%',
        onChanged: (v) => setState(() => swpReturnPct = v),
      ),
      const SizedBox(height: 8),
      _ResultCard(
        label: 'Corpus at withdrawal start',
        value: fmtShort(corpusAtStart),
        sub: 'at age ${startAge.round()}',
      ),
      _ResultCard(
        label: survived ? 'Corpus lasts beyond age 110' : 'Money runs out at age',
        value: survived ? fmtShort(finalCorpus) : '$lastAge',
        sub: survived
            ? 'still remaining after withdrawals'
            : 'withdrawals stop here',
        color: survived ? Brand.green : Brand.red,
      ),
      _Breakdown([
        ('Total invested', fmt(totalInvested)),
        ('Total withdrawn', fmt(totalWithdrawn)),
        ('Withdrawal years', '${drawdown.length}'),
        ('First year withdrawal',
            drawdown.isEmpty ? '—' : '${fmt(drawdown.first.swpMonthly)}/mo'),
        ('Last year withdrawal',
            drawdown.isEmpty ? '—' : '${fmt(drawdown.last.swpMonthly)}/mo'),
      ]),
      _PlanTable(rows: rows, columns: _cols, rowBuilder: _row),
      _PdfButton(
        onPressed: () => exportPlanPdf(
          context: context,
          title: 'SIP + SWP Planner',
          inputs: [
            ('Current age', '${currentAge.round()}'),
            ('SIP till age', '${tillAge.round()}'),
            ('Monthly SIP', fmt(sipAmount)),
            ('Return during SIP', '${sipReturnPct.toStringAsFixed(1)}%'),
            ('Annual step-up', '${sipStepPct.round()}%'),
            ('SWP start age', '${startAge.round()}'),
            ('Monthly withdrawal', fmt(swpAmount)),
            ('Yearly increase', '${swpStepPct.toStringAsFixed(1)}%'),
            ('Withdrawal phase return', '${swpReturnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Corpus at start of SWP', fmt(corpusAtStart)),
            ('Total invested', fmt(totalInvested)),
            ('Total withdrawn', fmt(totalWithdrawn)),
            (survived ? 'Corpus left at 110' : 'Money runs out at age',
                survived ? fmt(finalCorpus) : '$lastAge'),
          ],
          rows: rows,
        ),
      ),
    ]);
  }
}

/// Small uppercase divider label.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
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

/// Year-by-year cashflow table, colour-coded by phase.
class _PlanTable extends StatelessWidget {
  const _PlanTable({
    required this.rows,
    required this.columns,
    required this.rowBuilder,
  });

  final List<PlanRow> rows;
  final List<String> columns;
  final List<String> Function(PlanRow) rowBuilder;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: Brand.gold,
          collapsedIconColor: Brand.mint,
          title: const Text('Year-by-year cashflow',
              style: TextStyle(
                  color: Brand.paper,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text('${rows.length} years',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++)
                    Expanded(
                      flex: i == 0 ? 2 : 3,
                      child: Text(
                        columns[i],
                        textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                        style: const TextStyle(
                            color: Brand.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final cells = rowBuilder(r);
                  final bg = r.isAccumulation
                      ? Brand.green.withValues(alpha: 0.10)
                      : (r.swpYearly > 0
                          ? Brand.gold.withValues(alpha: 0.08)
                          : Colors.transparent);
                  return Container(
                    color: bg,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    child: Row(
                      children: [
                        for (var c = 0; c < cells.length; c++)
                          Expanded(
                            flex: c == 0 ? 2 : 3,
                            child: Text(
                              cells[c],
                              textAlign:
                                  c == 0 ? TextAlign.left : TextAlign.right,
                              style: TextStyle(
                                color: c == 0
                                    ? Brand.mint
                                    : Brand.paper.withValues(alpha: 0.9),
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  _LegendDot(
                      color: Brand.green.withValues(alpha: 0.35),
                      label: 'Investing'),
                  const SizedBox(width: 16),
                  _LegendDot(
                      color: Brand.gold.withValues(alpha: 0.35),
                      label: 'Withdrawing'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.8), fontSize: 11)),
      ],
    );
  }
}

/// PDF export for the two-phase plan (wider table than the single-column ones).
Future<void> exportPlanPdf({
  required BuildContext context,
  required String title,
  required List<(String, String)> inputs,
  required List<(String, String)> results,
  required List<PlanRow> rows,
}) async {
  final doc = pw.Document();
  final generated = DateTime.now();

  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 9)),
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
                'Generated ${generated.day.toString().padLeft(2, '0')}-'
                '${generated.month.toString().padLeft(2, '0')}-${generated.year}',
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
                    pw.Text('ASSUMPTIONS',
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
        pw.SizedBox(height: 16),
        pw.Text('YEAR-BY-YEAR CASHFLOW',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Age',
            'Opening',
            'SIP/mo',
            'SIP/yr',
            'SWP/mo',
            'SWP/yr',
            'Closing',
          ],
          data: rows
              .map((r) => [
                    '${r.age}',
                    fmt(r.opening),
                    r.sipMonthly > 0 ? fmt(r.sipMonthly) : '-',
                    r.sipYearly > 0 ? fmt(r.sipYearly) : '-',
                    r.swpMonthly > 0 ? fmt(r.swpMonthly) : '-',
                    r.swpYearly > 0 ? fmt(r.swpYearly) : '-',
                    fmt(math.max(r.closing, 0)),
                  ])
              .toList(),
          headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.blueGrey700),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellHeight: 14,
          cellAlignments: {
            0: pw.Alignment.center,
            for (var i = 1; i < 7; i++) i: pw.Alignment.centerRight,
          },
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Projections assume constant rates of return in each phase and are '
          'illustrative only. Actual returns will vary. Not investment advice.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: 'SIP_SWP_Planner.pdf');
}
