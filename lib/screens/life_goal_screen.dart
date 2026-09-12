// life_goal_screen.dart
// ---------------------------------------------------------------------------
// Life Goal & Protection calculators, ported from the Streamlit dashboard.
//
// Tabs: Children · Retirement · Term Insurance · Monte Carlo · Rebalancing
//
// Navigate to it with:
//     Navigator.push(context,
//         MaterialPageRoute(builder: (_) => const LifeGoalScreen()));
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

/// Monthly SIP needed for [target] (start-of-month convention, matching the
/// dashboard's goal planners).
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

/// Starting SIP needed when the SIP steps up by [stepUp] each year.
double _sipRequiredStepUp(
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

/// Normally-distributed random numbers via Box-Muller.
///
/// Dart's Random only gives uniforms, and the Monte Carlo needs Gaussian
/// annual returns. Seeded so the same inputs always produce the same
/// survival probability — an advisor re-running a client's plan should not
/// see the number drift.
class _Gaussian {
  _Gaussian(int seed) : _rng = math.Random(seed);

  final math.Random _rng;
  double? _spare;

  double next(double mean, double sd) {
    if (_spare != null) {
      final v = _spare!;
      _spare = null;
      return mean + sd * v;
    }
    double u, v, s;
    do {
      u = _rng.nextDouble() * 2 - 1;
      v = _rng.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1 || s == 0);
    final mul = math.sqrt(-2 * math.log(s) / s);
    _spare = v * mul;
    return mean + sd * (u * mul);
  }
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

String lgMoney(num x) => x.isFinite ? '₹ ${_group(x.round())}' : '₹ 0';

String lgMoneyShort(num x) {
  if (!x.isFinite) return '₹ 0';
  final v = x.abs();
  if (v >= 10000000) return '₹ ${(x / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹ ${(x / 100000).toStringAsFixed(2)} L';
  return lgMoney(x);
}

// ===========================================================================
// SHARED WIDGETS
// ===========================================================================

/// A single labelled lgMoney/percent field. Used where a slider would be
/// impractical — the cashflow and net worth sheets have too many lines.
class LgMoneyField extends StatefulWidget {
  const LgMoneyField({
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
  State<LgMoneyField> createState() => _LgMoneyFieldState();
}

class _LgMoneyFieldState extends State<LgMoneyField> {
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
class LgSliderField extends StatefulWidget {
  const LgSliderField({
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
  State<LgSliderField> createState() => _LgSliderFieldState();
}

class _LgSliderFieldState extends State<LgSliderField> {
  late final TextEditingController _ctrl;

  String get _text => widget.value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _text);
  }

  @override
  void didUpdateWidget(covariant LgSliderField old) {
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

class LgSectionLabel extends StatelessWidget {
  const LgSectionLabel(this.text, {super.key});

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

class LgResultCard extends StatelessWidget {
  const LgResultCard({
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

class LgBreakdown extends StatelessWidget {
  const LgBreakdown(this.rows, {super.key, this.highlightLast = false});

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
class LgProportionBar extends StatelessWidget {
  const LgProportionBar({super.key, required this.segments});

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

class LgPdfButton extends StatefulWidget {
  const LgPdfButton({super.key, required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  State<LgPdfButton> createState() => _LgPdfButtonState();
}

class _LgPdfButtonState extends State<LgPdfButton> {
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

class LgTabBody extends StatelessWidget {
  const LgTabBody({super.key, required this.children});

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
Future<void> exportLgReportPdf({
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

class LifeGoalScreen extends StatelessWidget {
  const LifeGoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Brand.vault,
        appBar: AppBar(
          backgroundColor: Brand.vault,
          foregroundColor: Brand.paper,
          elevation: 0,
          title: const Text('Life Goal & Protection',
              style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Brand.gold,
            unselectedLabelColor: Brand.mint,
            indicatorColor: Brand.gold,
            tabs: const [
              Tab(text: 'Children'),
              Tab(text: 'Retirement'),
              Tab(text: 'Term Cover'),
              Tab(text: 'Monte Carlo'),
              Tab(text: 'Rebalancing'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ChildrenTab(),
            _RetirementTab(),
            _TermTab(),
            _MonteCarloTab(),
            _RebalanceTab(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// TAB 1 — CHILDREN PLANNER
// ===========================================================================

/// One education or marriage milestone.
class ChildGoal {
  ChildGoal({required this.name, required this.age, required this.cost});

  final String name;
  double age;
  double cost;
}

class _ChildrenTab extends StatefulWidget {
  const _ChildrenTab();

  @override
  State<_ChildrenTab> createState() => _ChildrenTabState();
}

class _ChildrenTabState extends State<_ChildrenTab> {
  double childAge = 2;
  double inflationPct = 6;
  double returnPct = 12;

  final goals = [
    ChildGoal(name: '10th Board', age: 15, cost: 300000),
    ChildGoal(name: '12th Board', age: 17, cost: 500000),
    ChildGoal(name: 'Graduation', age: 21, cost: 2000000),
    ChildGoal(name: 'Masters', age: 24, cost: 2500000),
    ChildGoal(name: 'Marriage', age: 28, cost: 3000000),
  ];

  /// Confidence band from the dashboard: longer horizons are more forgiving.
  int _probability(double yearsLeft) =>
      yearsLeft >= 10 ? 97 : (yearsLeft >= 5 ? 90 : 75);

  @override
  Widget build(BuildContext context) {
    double totalSip = 0, totalLump = 0;
    final computed = <(ChildGoal, double, double, double, double, int)>[];

    for (final g in goals) {
      final yearsLeft = math.max(g.age - childAge, 0.0);
      final futureCost = _fv(g.cost, inflationPct / 100, yearsLeft);
      final sip = _sipRequired(futureCost, returnPct / 100, yearsLeft);
      final lump = _lumpsumRequired(futureCost, returnPct / 100, yearsLeft);
      totalSip += sip;
      totalLump += lump;
      computed
          .add((g, yearsLeft, futureCost, sip, lump, _probability(yearsLeft)));
    }

    return LgTabBody(children: [
      LgSliderField(
          label: "Child's age today",
          value: childAge,
          min: 0,
          max: 25,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => childAge = v)),

      const LgSectionLabel('ASSUMPTIONS'),
      LgSliderField(
          label: 'Education inflation',
          value: inflationPct,
          min: 0,
          max: 20,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => inflationPct = v)),
      LgSliderField(
          label: 'Investment return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),

      const LgSectionLabel('MILESTONES'),
      for (final g in goals)
        Card(
          color: Brand.fern.withValues(alpha: 0.28),
          margin: const EdgeInsets.symmetric(vertical: 5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name,
                    style: const TextStyle(
                        color: Brand.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                LgMoneyField(
                  label: 'At age',
                  value: g.age,
                  suffix: '',
                  onChanged: (v) => setState(() => g.age = v),
                ),
                LgMoneyField(
                  label: 'Cost today',
                  value: g.cost,
                  onChanged: (v) => setState(() => g.cost = v),
                ),
              ],
            ),
          ),
        ),

      const SizedBox(height: 12),
      LgResultCard(
        label: 'Total monthly SIP needed',
        value: lgMoney(totalSip),
        sub: 'across all ${goals.length} milestones',
      ),
      LgResultCard(
        label: 'Or invest today (lumpsum)',
        value: lgMoneyShort(totalLump),
        color: Brand.green,
      ),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Goal',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('Yrs',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('Cost then',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('SIP',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            for (final (g, yrs, fc, sip, _, prob) in computed)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.name,
                              style: const TextStyle(
                                  color: Brand.paper, fontSize: 12)),
                          Text('$prob% likely',
                              style: TextStyle(
                                  color: prob >= 95
                                      ? Brand.green
                                      : (prob >= 90 ? Brand.gold : Brand.red),
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                    Expanded(
                        flex: 2,
                        child: Text('${yrs.round()}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.mint, fontSize: 12))),
                    Expanded(
                        flex: 3,
                        child: Text(lgMoneyShort(fc),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 12))),
                    Expanded(
                        flex: 3,
                        child: Text(lgMoney(sip),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.gold,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),

      LgPdfButton(
        onPressed: () => exportLgReportPdf(
          title: 'Children Goal Plan',
          inputs: [
            ("Child's age", '${childAge.round()} years'),
            ('Education inflation', '${inflationPct.toStringAsFixed(1)}%'),
            ('Investment return', '${returnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Total monthly SIP', lgMoney(totalSip)),
            ('Total lumpsum today', lgMoney(totalLump)),
            ('Milestones planned', '${goals.length}'),
          ],
          tableHeaders: const [
            'Goal',
            'Age',
            'Years',
            'Cost today',
            'Cost then',
            'SIP',
            'Lumpsum',
            'Prob.',
          ],
          tableTitle: 'MILESTONE DETAIL',
          tableRows: [
            for (final (g, yrs, fc, sip, lump, prob) in computed)
              [
                g.name,
                '${g.age.round()}',
                '${yrs.round()}',
                lgMoney(g.cost),
                lgMoney(fc),
                lgMoney(sip),
                lgMoney(lump),
                '$prob%',
              ],
          ],
          note: 'Create separate folios for each child goal so education and '
              'marriage lgMoney is never mixed with retirement assets. Review '
              'annually and raise the SIP as income grows.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 2 — RETIREMENT PLANNER
// ===========================================================================

/// One retirement year: balance in, expense drawn, balance out.
class RetirementYear {
  const RetirementYear({
    required this.age,
    required this.opening,
    required this.expense,
    required this.closing,
  });

  final int age;
  final double opening;
  final double expense;
  final double closing;
}

class _RetirementTab extends StatefulWidget {
  const _RetirementTab();

  @override
  State<_RetirementTab> createState() => _RetirementTabState();
}

class _RetirementTabState extends State<_RetirementTab> {
  double myAge = 35;
  double retireAge = 50;
  double planTill = 90;

  double monthlyExpense = 60000;
  double yearlyOneTime = 125000;
  double expenseInflationPct = 7;

  double equityNps = 1000000;
  double debtPpfEpf = 1000000;
  double realEstate = 0;
  double gold = 0;

  double currentSip = 57500;
  double stepUpPct = 8;
  double postRetReturnPct = 8;
  double preRetReturnPct = 12;

  @override
  Widget build(BuildContext context) {
    // Keep ages ordered as sliders move.
    final rAge = math.max(retireAge, myAge + 1);
    final tillAge = math.max(planTill, rAge + 1);

    final corpus = equityNps + debtPpfEpf + realEstate + gold;
    final yearsToRet = (rAge - myAge).round();
    final retYears = (tillAge - rAge).round();
    final infl = expenseInflationPct / 100;
    final preRet = preRetReturnPct / 100;
    final postRet = postRetReturnPct / 100;

    final annualExpToday = monthlyExpense * 12 + yearlyOneTime;
    final expenseAtRet =
        annualExpToday * math.pow(1 + infl, yearsToRet).toDouble();

    // Existing assets compound; the running SIP accumulates with step-up.
    final futureExisting = corpus * math.pow(1 + preRet, yearsToRet).toDouble();
    double sipFuture = 0, sipNow = currentSip;
    for (var y = 0; y < yearsToRet; y++) {
      for (var m = 0; m < 12; m++) {
        sipFuture = sipFuture * (1 + preRet / 12) + sipNow;
      }
      sipNow *= (1 + stepUpPct / 100);
    }
    final totalFutureAssets = futureExisting + sipFuture;

    // Corpus needed to fund an inflating expense stream through retirement.
    // Where returns beat inflation this is a growing-annuity present value;
    // otherwise fall back to the undiscounted total.
    final requiredCorpus = postRet > infl
        ? expenseAtRet *
            ((1 - math.pow((1 + infl) / (1 + postRet), retYears)) /
                (postRet - infl))
        : expenseAtRet * retYears;

    final gap = math.max(requiredCorpus - totalFutureAssets, 0.0);
    final additionalSip =
        _sipRequiredStepUp(gap, preRet, yearsToRet.toDouble(), 0.05);

    // Year-by-year drawdown.
    final schedule = <RetirementYear>[];
    double bal = totalFutureAssets, exp = expenseAtRet;
    for (var age = rAge.round(); age <= tillAge.round(); age++) {
      final opening = bal;
      bal = bal * (1 + postRet) - exp;
      schedule.add(RetirementYear(
          age: age, opening: opening, expense: exp, closing: bal));
      exp *= (1 + infl);
      if (bal <= 0) break;
    }

    final lastsUntil = schedule.isEmpty ? rAge.round() : schedule.last.age;
    final survives = schedule.isNotEmpty && schedule.last.closing > 0;

    return LgTabBody(children: [
      const LgSectionLabel('TIMELINE'),
      LgSliderField(
          label: 'My age',
          value: myAge,
          min: 18,
          max: 75,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => myAge = v)),
      LgSliderField(
          label: 'Retire at',
          value: rAge,
          min: myAge + 1,
          max: 80,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => retireAge = v)),
      LgSliderField(
          label: 'Plan till',
          value: tillAge,
          min: rAge + 1,
          max: 100,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => planTill = v)),

      const LgSectionLabel('EXPENSES'),
      LgMoneyField(
          label: 'Monthly expenses',
          value: monthlyExpense,
          onChanged: (v) => setState(() => monthlyExpense = v)),
      LgMoneyField(
          label: 'One-time yearly expenses',
          value: yearlyOneTime,
          onChanged: (v) => setState(() => yearlyOneTime = v)),
      LgSliderField(
          label: 'Expense inflation',
          value: expenseInflationPct,
          min: 0,
          max: 20,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => expenseInflationPct = v)),

      const LgSectionLabel('EXISTING ASSETS'),
      LgMoneyField(
          label: 'Equity + NPS',
          value: equityNps,
          onChanged: (v) => setState(() => equityNps = v)),
      LgMoneyField(
          label: 'Debt + PPF + EPF',
          value: debtPpfEpf,
          onChanged: (v) => setState(() => debtPpfEpf = v)),
      LgMoneyField(
          label: 'Real estate',
          value: realEstate,
          onChanged: (v) => setState(() => realEstate = v)),
      LgMoneyField(
          label: 'Gold',
          value: gold,
          onChanged: (v) => setState(() => gold = v)),

      const LgSectionLabel('CONTRIBUTIONS & RETURNS'),
      LgMoneyField(
          label: 'Current monthly SIP + NPS',
          value: currentSip,
          onChanged: (v) => setState(() => currentSip = v)),
      LgSliderField(
          label: 'Annual step-up',
          value: stepUpPct,
          min: 0,
          max: 30,
          step: 1,
          suffix: '%',
          onChanged: (v) => setState(() => stepUpPct = v)),
      LgSliderField(
          label: 'Pre-retirement return',
          value: preRetReturnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => preRetReturnPct = v)),
      LgSliderField(
          label: 'Post-retirement return',
          value: postRetReturnPct,
          min: 1,
          max: 20,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => postRetReturnPct = v)),

      const SizedBox(height: 12),
      LgResultCard(
        label: 'Corpus required at retirement',
        value: lgMoneyShort(requiredCorpus),
        sub: 'to fund ${lgMoney(expenseAtRet)}/yr rising at '
            '${expenseInflationPct.toStringAsFixed(1)}%',
      ),
      LgResultCard(
        label: 'Projected assets at retirement',
        value: lgMoneyShort(totalFutureAssets),
        color: totalFutureAssets >= requiredCorpus ? Brand.green : Brand.gold,
      ),
      LgResultCard(
        label: gap > 0 ? 'Additional SIP needed' : 'You are on track',
        value: gap > 0 ? lgMoney(additionalSip) : lgMoneyShort(-gap.abs()),
        sub: gap > 0
            ? 'on top of your current SIP, rising 5% a year'
            : 'projected assets already cover the required corpus',
        color: gap > 0 ? Brand.red : Brand.green,
      ),
      LgBreakdown([
        ('Years to retirement', '$yearsToRet'),
        ('Retirement years planned', '$retYears'),
        ('Annual expense today', lgMoney(annualExpToday)),
        ('Annual expense at retirement', lgMoney(expenseAtRet)),
        ('Existing assets grow to', lgMoney(futureExisting)),
        ('Current SIP grows to', lgMoney(sipFuture)),
        ('Shortfall', lgMoney(gap)),
      ], highlightLast: true),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: Brand.gold,
            collapsedIconColor: Brand.mint,
            title: const Text('Retirement drawdown',
                style: TextStyle(
                    color: Brand.paper,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
                survives
                    ? 'Corpus lasts through age $lastsUntil'
                    : 'Money runs out at age $lastsUntil',
                style: TextStyle(
                    color: survives ? Brand.green : Brand.red, fontSize: 12)),
            children: [
              Container(
                color: Brand.fern.withValues(alpha: 0.55),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: const Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text('Age',
                            style: TextStyle(
                                color: Brand.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('Opening',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: Brand.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('Expense',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: Brand.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Text('Closing',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: Brand.gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: schedule.length,
                  itemBuilder: (context, i) {
                    final r = schedule[i];
                    return Container(
                      color: i.isEven
                          ? Colors.transparent
                          : Brand.fern.withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text('${r.age}',
                                  style: const TextStyle(
                                      color: Brand.mint, fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text(lgMoneyShort(r.opening),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      color: Brand.paper, fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text(lgMoneyShort(r.expense),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      color: Brand.paper, fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text(
                                  lgMoneyShort(math.max(r.closing, 0)),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: r.closing > 0
                                          ? Brand.paper
                                          : Brand.red,
                                      fontSize: 11))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),

      LgPdfButton(
        onPressed: () => exportLgReportPdf(
          title: 'Retirement Plan',
          inputs: [
            ('My age', '${myAge.round()}'),
            ('Retire at', '${rAge.round()}'),
            ('Plan till', '${tillAge.round()}'),
            ('Monthly expenses', lgMoney(monthlyExpense)),
            ('One-time yearly', lgMoney(yearlyOneTime)),
            ('Expense inflation', '${expenseInflationPct.toStringAsFixed(1)}%'),
            ('Existing assets', lgMoney(corpus)),
            ('Current SIP', lgMoney(currentSip)),
            ('SIP step-up', '${stepUpPct.round()}%'),
            ('Pre-retirement return', '${preRetReturnPct.toStringAsFixed(1)}%'),
            ('Post-retirement return',
                '${postRetReturnPct.toStringAsFixed(1)}%'),
          ],
          results: [
            ('Expense at retirement', lgMoney(expenseAtRet)),
            ('Required corpus', lgMoney(requiredCorpus)),
            ('Projected assets', lgMoney(totalFutureAssets)),
            ('Gap', lgMoney(gap)),
            ('Additional SIP (5% step-up)', lgMoney(additionalSip)),
            (survives ? 'Corpus lasts through' : 'Money runs out at',
                'age $lastsUntil'),
          ],
          tableHeaders: const ['Age', 'Opening', 'Expense', 'Closing'],
          tableTitle: 'RETIREMENT DRAWDOWN',
          tableRows: [
            for (final r in schedule)
              [
                '${r.age}',
                lgMoney(r.opening),
                lgMoney(r.expense),
                lgMoney(math.max(r.closing, 0)),
              ],
          ],
          note: 'Protect the retirement corpus from child goals and lifestyle '
              'upgrades. Raise the SIP annually with income growth, and treat '
              'medical inflation as higher than general inflation.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 3 — TERM INSURANCE
// ===========================================================================

class _TermTab extends StatefulWidget {
  const _TermTab();

  @override
  State<_TermTab> createState() => _TermTabState();
}

class _TermTabState extends State<_TermTab> {
  double currentAge = 35;
  double coverTillAge = 90;
  double monthlyIncome = 200000;
  double monthlyExpense = 50000;
  double liabilities = 0;
  double existingCover = 0;

  @override
  Widget build(BuildContext context) {
    final tillAge = math.max(coverTillAge, currentAge + 1);
    final yearsLeft = tillAge - currentAge;
    final annualSurplus =
        math.max((monthlyIncome - monthlyExpense) * 12, 0.0);
    final hlv = annualSurplus * yearsLeft;
    final recommended = math.max(hlv + liabilities - existingCover, 0.0);

    // A quick sanity multiple advisors quote alongside HLV.
    final incomeMultiple =
        monthlyIncome > 0 ? recommended / (monthlyIncome * 12) : 0.0;

    return LgTabBody(children: [
      const LgSectionLabel('YOU'),
      LgSliderField(
          label: 'Current age',
          value: currentAge,
          min: 18,
          max: 75,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => currentAge = v)),
      LgSliderField(
          label: 'Cover till age',
          value: tillAge,
          min: currentAge + 1,
          max: 100,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => coverTillAge = v)),

      const LgSectionLabel('INCOME & OBLIGATIONS'),
      LgMoneyField(
          label: 'Monthly income',
          value: monthlyIncome,
          onChanged: (v) => setState(() => monthlyIncome = v)),
      LgMoneyField(
          label: 'Monthly expenses',
          value: monthlyExpense,
          onChanged: (v) => setState(() => monthlyExpense = v)),
      LgMoneyField(
          label: 'Outstanding liabilities',
          value: liabilities,
          onChanged: (v) => setState(() => liabilities = v)),
      LgMoneyField(
          label: 'Existing cover',
          value: existingCover,
          onChanged: (v) => setState(() => existingCover = v)),

      const SizedBox(height: 12),
      LgResultCard(
        label: 'Recommended additional cover',
        value: lgMoneyShort(recommended),
        sub: recommended > 0
            ? 'on top of your existing ${lgMoneyShort(existingCover)}'
            : 'your existing cover already meets the estimate',
        color: recommended > 0 ? Brand.gold : Brand.green,
      ),
      LgBreakdown([
        ('Years of cover needed', '${yearsLeft.round()}'),
        ('Annual surplus (income − expenses)', lgMoney(annualSurplus)),
        ('Human life value', lgMoney(hlv)),
        ('Plus liabilities', lgMoney(liabilities)),
        ('Less existing cover', lgMoney(existingCover)),
        ('Recommended cover', lgMoney(recommended)),
      ], highlightLast: true),
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Brand.mint, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'That is about ${incomeMultiple.toStringAsFixed(0)}x your '
                  'annual income. A term plan is protection, not investment — '
                  'buying earlier locks in a lower premium.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.85), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      LgPdfButton(
        onPressed: () => exportLgReportPdf(
          title: 'Term Insurance Assessment',
          inputs: [
            ('Current age', '${currentAge.round()}'),
            ('Cover till age', '${tillAge.round()}'),
            ('Monthly income', lgMoney(monthlyIncome)),
            ('Monthly expenses', lgMoney(monthlyExpense)),
            ('Outstanding liabilities', lgMoney(liabilities)),
            ('Existing cover', lgMoney(existingCover)),
          ],
          results: [
            ('Years of cover', '${yearsLeft.round()}'),
            ('Annual surplus', lgMoney(annualSurplus)),
            ('Human life value', lgMoney(hlv)),
            ('Recommended cover', lgMoney(recommended)),
            ('Multiple of annual income',
                '${incomeMultiple.toStringAsFixed(1)}x'),
          ],
          note: 'A term plan is a protection product, not an investment. '
              'Buying early reduces premium and locks in insurability. '
              'Reassess after marriage, children, or a large loan.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 4 — RETIREMENT MONTE CARLO
// ===========================================================================

class _MonteCarloTab extends StatefulWidget {
  const _MonteCarloTab();

  @override
  State<_MonteCarloTab> createState() => _MonteCarloTabState();
}

class _MonteCarloTabState extends State<_MonteCarloTab> {
  double corpus = 30000000;
  double withdrawal = 1200000;
  double years = 30;
  double runs = 1000;
  double returnPct = 12;
  double volatilityPct = 12;
  double inflationPct = 6;

  @override
  Widget build(BuildContext context) {
    // Seeded so the same inputs always give the same answer.
    final rng = _Gaussian(123);
    final n = runs.round();
    final yrs = years.round();
    final mean = returnPct / 100;
    final sd = volatilityPct / 100;
    final infl = inflationPct / 100;

    var success = 0;
    final endings = <double>[];

    for (var run = 0; run < n; run++) {
      var bal = corpus;
      var wd = withdrawal;
      var ok = true;
      for (var y = 0; y < yrs; y++) {
        bal = bal * (1 + rng.next(mean, sd)) - wd;
        wd *= (1 + infl);
        if (bal <= 0) {
          ok = false;
          break;
        }
      }
      endings.add(math.max(bal, 0));
      if (ok) success++;
    }

    endings.sort();
    final successRate = n > 0 ? success / n * 100 : 0.0;
    final median = endings.isEmpty
        ? 0.0
        : (endings.length.isOdd
            ? endings[endings.length ~/ 2]
            : (endings[endings.length ~/ 2 - 1] +
                    endings[endings.length ~/ 2]) /
                2);
    final p10 = endings.isEmpty
        ? 0.0
        : endings[(endings.length * 0.10).floor().clamp(0, endings.length - 1)];
    final p90 = endings.isEmpty
        ? 0.0
        : endings[(endings.length * 0.90).floor().clamp(0, endings.length - 1)];

    final firstYearRate = corpus > 0 ? withdrawal / corpus * 100 : 0.0;

    final verdict = successRate >= 90
        ? 'Comfortable'
        : (successRate >= 75 ? 'Workable but tight' : 'High risk of running out');
    final verdictColor = successRate >= 90
        ? Brand.green
        : (successRate >= 75 ? Brand.gold : Brand.red);

    return LgTabBody(children: [
      const LgSectionLabel('THE PLAN'),
      LgSliderField(
          label: 'Retirement corpus',
          value: corpus,
          min: 1000000,
          max: 500000000,
          step: 1000000,
          suffix: '₹',
          onChanged: (v) => setState(() => corpus = v)),
      LgSliderField(
          label: 'Annual withdrawal',
          value: withdrawal,
          min: 100000,
          max: 50000000,
          step: 100000,
          suffix: '₹',
          onChanged: (v) => setState(() => withdrawal = v)),
      LgSliderField(
          label: 'Retirement years',
          value: years,
          min: 5,
          max: 50,
          step: 1,
          suffix: 'yr',
          onChanged: (v) => setState(() => years = v)),

      const LgSectionLabel('MARKET ASSUMPTIONS'),
      LgSliderField(
          label: 'Average return',
          value: returnPct,
          min: 1,
          max: 25,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => returnPct = v)),
      LgSliderField(
          label: 'Volatility (std. dev.)',
          value: volatilityPct,
          min: 1,
          max: 35,
          step: 1,
          suffix: '%',
          onChanged: (v) => setState(() => volatilityPct = v)),
      LgSliderField(
          label: 'Inflation',
          value: inflationPct,
          min: 0,
          max: 15,
          step: 0.5,
          decimals: 1,
          suffix: '%',
          onChanged: (v) => setState(() => inflationPct = v)),
      LgSliderField(
          label: 'Simulation runs',
          value: runs,
          min: 100,
          max: 5000,
          step: 100,
          onChanged: (v) => setState(() => runs = v)),

      const SizedBox(height: 12),
      LgResultCard(
        label: 'Survival probability',
        value: '${successRate.toStringAsFixed(1)}%',
        sub: '$verdict — $success of $n simulations lasted the full '
            '$yrs years',
        color: verdictColor,
      ),

      // Outcome spread bar.
      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OUTCOME SPREAD',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.8),
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      Expanded(
                        flex: math.max((100 - successRate).round(), 0),
                        child: Container(color: Brand.red),
                      ),
                      Expanded(
                        flex: math.max(successRate.round(), 0),
                        child: Container(color: Brand.green),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ran out: ${(100 - successRate).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Brand.red, fontSize: 11)),
                  Text('Survived: ${successRate.toStringAsFixed(1)}%',
                      style: const TextStyle(color: Brand.green, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),

      LgBreakdown([
        ('First-year withdrawal rate',
            '${firstYearRate.toStringAsFixed(2)}%'),
        ('Median ending corpus', lgMoneyShort(median)),
        ('Poor outcome (10th pct)', lgMoneyShort(p10)),
        ('Good outcome (90th pct)', lgMoneyShort(p90)),
        ('Simulations run', '$n'),
      ]),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.insights, color: Brand.mint, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Each run draws a different sequence of yearly returns from a '
                  'normal distribution. Poor returns early in retirement hurt '
                  'far more than the same returns later — which is why the '
                  'spread matters more than the average.',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.85), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),

      LgPdfButton(
        onPressed: () => exportLgReportPdf(
          title: 'Retirement Monte Carlo',
          inputs: [
            ('Retirement corpus', lgMoney(corpus)),
            ('Annual withdrawal', lgMoney(withdrawal)),
            ('Retirement years', '$yrs'),
            ('Average return', '${returnPct.toStringAsFixed(1)}%'),
            ('Volatility', '${volatilityPct.toStringAsFixed(0)}%'),
            ('Inflation', '${inflationPct.toStringAsFixed(1)}%'),
            ('Simulation runs', '$n'),
          ],
          results: [
            ('Survival probability', '${successRate.toStringAsFixed(1)}%'),
            ('Verdict', verdict),
            ('First-year withdrawal rate',
                '${firstYearRate.toStringAsFixed(2)}%'),
            ('Median ending corpus', lgMoney(median)),
            ('10th percentile', lgMoney(p10)),
            ('90th percentile', lgMoney(p90)),
          ],
          note: 'Returns are drawn from a normal distribution, which '
              'understates the fat tails of real markets. Treat the survival '
              'probability as a comparison tool between plans, not a promise.',
        ),
      ),
    ]);
  }
}

// ===========================================================================
// TAB 5 — PORTFOLIO REBALANCING
// ===========================================================================

class _RebalanceTab extends StatefulWidget {
  const _RebalanceTab();

  @override
  State<_RebalanceTab> createState() => _RebalanceTabState();
}

class _RebalanceTabState extends State<_RebalanceTab> {
  double curEquity = 600000;
  double curDebt = 300000;
  double curGold = 100000;

  double tgtEquity = 60;
  double tgtDebt = 30;
  double tgtGold = 10;

  @override
  Widget build(BuildContext context) {
    final total = curEquity + curDebt + curGold;
    final tgtTotal = tgtEquity + tgtDebt + tgtGold;

    double targetOf(double pct) => tgtTotal > 0 ? total * pct / tgtTotal : 0;

    final rows = <(String, double, double, Color)>[
      ('Equity', curEquity, targetOf(tgtEquity), Brand.gold),
      ('Debt', curDebt, targetOf(tgtDebt), Brand.green),
      ('Gold', curGold, targetOf(tgtGold), Brand.mint),
    ];

    final drift = rows.fold<double>(
        0, (s, r) => s + (r.$3 - r.$2).abs());

    return LgTabBody(children: [
      const LgSectionLabel('CURRENT HOLDINGS'),
      LgMoneyField(
          label: 'Equity',
          value: curEquity,
          onChanged: (v) => setState(() => curEquity = v)),
      LgMoneyField(
          label: 'Debt',
          value: curDebt,
          onChanged: (v) => setState(() => curDebt = v)),
      LgMoneyField(
          label: 'Gold',
          value: curGold,
          onChanged: (v) => setState(() => curGold = v)),

      const LgSectionLabel('TARGET ALLOCATION'),
      LgSliderField(
          label: 'Equity target',
          value: tgtEquity,
          min: 0,
          max: 100,
          step: 5,
          suffix: '%',
          onChanged: (v) => setState(() => tgtEquity = v)),
      LgSliderField(
          label: 'Debt target',
          value: tgtDebt,
          min: 0,
          max: 100,
          step: 5,
          suffix: '%',
          onChanged: (v) => setState(() => tgtDebt = v)),
      LgSliderField(
          label: 'Gold target',
          value: tgtGold,
          min: 0,
          max: 100,
          step: 5,
          suffix: '%',
          onChanged: (v) => setState(() => tgtGold = v)),

      if (tgtTotal != 100)
        Card(
          color: Brand.red.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Brand.red, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Targets add up to ${tgtTotal.round()}%, not 100%. '
                    'Amounts below are scaled proportionally.',
                    style: const TextStyle(color: Brand.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),

      const SizedBox(height: 12),
      LgResultCard(
        label: 'Total portfolio',
        value: lgMoneyShort(total),
        sub: drift > 0
            ? '${lgMoneyShort(drift / 2)} needs to move to hit target'
            : 'already at target',
      ),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              color: Brand.fern.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Text('Asset',
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('Current',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('Target',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('Action',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: Brand.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            for (final (name, cur, tgt, colour) in rows)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
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
                        flex: 3,
                        child: Text(lgMoneyShort(cur),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 12))),
                    Expanded(
                        flex: 3,
                        child: Text(lgMoneyShort(tgt),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.mint, fontSize: 12))),
                    Expanded(
                      flex: 3,
                      child: Text(
                        (tgt - cur).abs() < 1
                            ? '—'
                            : '${tgt > cur ? "BUY" : "SELL"} '
                                '${lgMoneyShort((tgt - cur).abs())}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: (tgt - cur).abs() < 1
                                ? Brand.mint
                                : (tgt > cur ? Brand.green : Brand.red),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),

      Card(
        color: Brand.fern.withValues(alpha: 0.28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: LgProportionBar(segments: [
            ('Equity', curEquity, Brand.gold),
            ('Debt', curDebt, Brand.green),
            ('Gold', curGold, Brand.mint),
          ]),
        ),
      ),

      LgPdfButton(
        onPressed: () => exportLgReportPdf(
          title: 'Portfolio Rebalancing',
          inputs: [
            ('Current equity', lgMoney(curEquity)),
            ('Current debt', lgMoney(curDebt)),
            ('Current gold', lgMoney(curGold)),
            ('Target equity', '${tgtEquity.round()}%'),
            ('Target debt', '${tgtDebt.round()}%'),
            ('Target gold', '${tgtGold.round()}%'),
          ],
          results: [
            ('Total portfolio', lgMoney(total)),
            ('Amount to move', lgMoney(drift / 2)),
          ],
          tableHeaders: const [
            'Asset',
            'Current',
            'Target',
            'Buy / Sell',
          ],
          tableTitle: 'REBALANCING ACTIONS',
          tableRows: [
            for (final (name, cur, tgt, _) in rows)
              [
                name,
                lgMoney(cur),
                lgMoney(tgt),
                '${tgt >= cur ? "+" : ""}${lgMoney(tgt - cur)}',
              ],
          ],
          note: 'Rebalancing sells what has done well and buys what has not, '
              'which is what keeps risk at the level you chose. Consider tax '
              'and exit loads before acting, and rebalance no more than once '
              'or twice a year.',
        ),
      ),
    ]);
  }
}
