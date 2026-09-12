// lib/screens/options_screen.dart
// ---------------------------------------------------------------------------
// Option chain: PCR, max pain, open interest by strike, and the chain table.
//
// Data comes from Dhan's Data API, which needs an active subscription and a
// valid token. Auth failures are surfaced verbatim rather than shown as a
// generic error, because they need action rather than a retry.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _num(num? v) {
  if (v == null) return '—';
  final n = v.round();
  final s = n.abs().toString();
  if (s.length <= 3) return '${n < 0 ? '-' : ''}$s';
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

/// Open interest reads better in lakhs — raw contract counts are unwieldy.
String _lakh(num? v) {
  if (v == null) return '—';
  final n = v.toDouble();
  if (n.abs() >= 10000000) return '${(n / 10000000).toStringAsFixed(2)} Cr';
  if (n.abs() >= 100000) return '${(n / 100000).toStringAsFixed(1)} L';
  if (n.abs() >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}

// ===========================================================================
// SCREEN
// ===========================================================================

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  static const _indices = [
    'NIFTY 50',
    'BANK NIFTY',
    'FIN NIFTY',
    'MIDCAP NIFTY',
  ];

  String _index = 'NIFTY 50';
  String _expiry = '';
  int _strikes = 10;

  List<String> _expiries = [];
  Map<String, dynamic>? _chain;

  bool _loadingExpiries = true;
  bool _loadingChain = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExpiries();
  }

  Future<void> _loadExpiries() async {
    setState(() {
      _loadingExpiries = true;
      _error = null;
      _expiries = [];
      _chain = null;
    });
    try {
      final e = await ApiService.getOptionExpiries(_index);
      if (!mounted) return;
      setState(() {
        _expiries = e;
        _expiry = e.isNotEmpty ? e.first : '';
      });
      if (_expiry.isNotEmpty) await _loadChain();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingExpiries = false);
    }
  }

  Future<void> _loadChain() async {
    setState(() {
      _loadingChain = true;
      _error = null;
    });
    try {
      final c = await ApiService.getOptionChain(_index,
          expiry: _expiry, strikes: _strikes);
      if (mounted) setState(() => _chain = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingChain = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('Option Chain',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _expiry.isEmpty ? _loadExpiries : _loadChain,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Brand.gold,
        backgroundColor: Brand.fern,
        onRefresh: _expiry.isEmpty ? _loadExpiries : _loadChain,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            // ---- Index chips ----
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final i in _indices)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: GestureDetector(
                        onTap: () {
                          if (_index == i) return;
                          setState(() => _index = i);
                          _loadExpiries();
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _index == i
                                ? Brand.gold.withValues(alpha: 0.18)
                                : Brand.fern.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _index == i
                                  ? Brand.gold
                                  : Brand.mint.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(i,
                              style: TextStyle(
                                  color:
                                      _index == i ? Brand.gold : Brand.mint,
                                  fontSize: 11.5,
                                  fontWeight: _index == i
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ---- Expiry chips ----
            if (_expiries.isNotEmpty) ...[
              Text('EXPIRY',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7),
                      fontSize: 9.5,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final e in _expiries.take(8))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            if (_expiry == e) return;
                            setState(() => _expiry = e);
                            _loadChain();
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _expiry == e
                                  ? Brand.green.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: _expiry == e
                                    ? Brand.green.withValues(alpha: 0.7)
                                    : Brand.mint.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(e,
                                style: TextStyle(
                                    color: _expiry == e
                                        ? Brand.green
                                        : Brand.mint,
                                    fontSize: 10.5,
                                    fontWeight: _expiry == e
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_loadingExpiries || _loadingChain)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_error != null)
              _OptionsError(
                  message: _error!,
                  onRetry: _expiry.isEmpty ? _loadExpiries : _loadChain)
            else if (_chain != null) ...[
              _MetricsPanel(chain: _chain!),
              const SizedBox(height: 18),

              // ---- Strike window ----
              Row(
                children: [
                  Text('Strikes around ATM',
                      style: TextStyle(
                          color: Brand.mint.withValues(alpha: 0.8),
                          fontSize: 11.5)),
                  const Spacer(),
                  Text('±$_strikes',
                      style: const TextStyle(
                          color: Brand.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
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
                  value: _strikes.toDouble(),
                  min: 5,
                  max: 20,
                  divisions: 15,
                  onChanged: (v) => setState(() => _strikes = v.round()),
                  onChangeEnd: (_) => _loadChain(),
                ),
              ),

              const SizedBox(height: 6),
              _OiChart(chain: _chain!),
              const SizedBox(height: 18),
              _ChainTable(chain: _chain!),
              const SizedBox(height: 14),
              Text(
                'PCR is total put OI divided by total call OI. Above 1 means '
                'put writers dominate (often support); below 0.7 means call '
                'writers dominate (often resistance). Max pain is the strike '
                'where option writers would pay out least.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.5),
                    fontSize: 10.5,
                    height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// METRICS
// ===========================================================================

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final pcr = (chain['pcr'] as num?)?.toDouble() ?? 0;
    final pcrColour = pcr > 1.0
        ? Brand.green
        : (pcr > 0.7 ? Brand.gold : Brand.red);

    Widget tile(String label, String value, Color colour) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colour.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.75),
                        fontSize: 8.5,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                FittedBox(
                  child: Text(value,
                      style: TextStyle(
                          color: colour,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tile('SPOT', _num(chain['spot'] as num?), Brand.paper),
            tile('PCR (OI)', pcr.toStringAsFixed(2), pcrColour),
            tile('MAX PAIN', _num(chain['max_pain'] as num?), Brand.gold),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            tile('PUT OI', _lakh(chain['total_pe_oi'] as num?), Brand.green),
            tile('CALL OI', _lakh(chain['total_ce_oi'] as num?), Brand.red),
            tile('ATM', _num(chain['atm'] as num?), Brand.mint),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: pcrColour.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: pcrColour.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${chain['signal']}',
                  style: TextStyle(
                      color: pcrColour,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Support ${_num(chain['support'] as num?)}',
                        style: const TextStyle(
                            color: Brand.green, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: Text(
                        'Resistance ${_num(chain['resistance'] as num?)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Brand.red, fontSize: 11.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// OI CHART
// ===========================================================================

class _OiChart extends StatelessWidget {
  const _OiChart({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final r in (chain['rows'] as List? ?? []))
        (r as Map).cast<String, dynamic>()
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, color: Brand.green),
            const SizedBox(width: 5),
            Text('Put OI',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
            const SizedBox(width: 14),
            Container(width: 10, height: 10, color: Brand.red),
            const SizedBox(width: 5),
            Text('Call OI',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 230,
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          decoration: BoxDecoration(
            color: Brand.fern.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            size: Size.infinite,
            painter: _OiPainter(
              rows: rows,
              spot: (chain['spot'] as num?)?.toDouble(),
              maxPain: (chain['max_pain'] as num?)?.toDouble(),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_num(rows.first['strike'] as num?),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
            Text('strike',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.4), fontSize: 9.5)),
            Text(_num(rows.last['strike'] as num?),
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _OiPainter extends CustomPainter {
  _OiPainter({required this.rows, this.spot, this.maxPain});

  final List<Map<String, dynamic>> rows;
  final double? spot;
  final double? maxPain;

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.isEmpty) return;

    final ce = [
      for (final r in rows) ((r['ce_oi'] as num?) ?? 0).toDouble()
    ];
    final pe = [
      for (final r in rows) ((r['pe_oi'] as num?) ?? 0).toDouble()
    ];
    final peak = math.max(
      ce.isEmpty ? 0 : ce.reduce(math.max),
      pe.isEmpty ? 0 : pe.reduce(math.max),
    );
    if (peak <= 0) return;

    final slot = size.width / rows.length;
    final barW = math.max(slot * 0.36, 1.5);

    for (var i = 0; i < rows.length; i++) {
      final centre = slot * i + slot / 2;

      // Puts left of centre, calls right — mirrors how chains are read.
      final peH = (pe[i] / peak) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(centre - barW - 0.5, size.height - peH, barW, peH),
        Paint()..color = Brand.green.withValues(alpha: 0.85),
      );

      final ceH = (ce[i] / peak) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(centre + 0.5, size.height - ceH, barW, ceH),
        Paint()..color = Brand.red.withValues(alpha: 0.85),
      );
    }

    // Marker lines for spot and max pain.
    void marker(double? value, Color colour, bool dotted) {
      if (value == null) return;
      final first = ((rows.first['strike'] as num?) ?? 0).toDouble();
      final last = ((rows.last['strike'] as num?) ?? 0).toDouble();
      if (last <= first) return;
      final ratio = ((value - first) / (last - first)).clamp(0.0, 1.0);
      final x = ratio * size.width;
      final paint = Paint()
        ..color = colour
        ..strokeWidth = 1.4;
      if (dotted) {
        var y = 0.0;
        while (y < size.height) {
          canvas.drawLine(
              Offset(x, y), Offset(x, math.min(y + 4, size.height)), paint);
          y += 8;
        }
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }

    marker(spot, Brand.gold, false);
    marker(maxPain, Brand.mint.withValues(alpha: 0.7), true);
  }

  @override
  bool shouldRepaint(covariant _OiPainter old) =>
      old.rows != rows || old.spot != spot || old.maxPain != maxPain;
}

// ===========================================================================
// CHAIN TABLE
// ===========================================================================

class _ChainTable extends StatelessWidget {
  const _ChainTable({required this.chain});

  final Map<String, dynamic> chain;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final r in (chain['rows'] as List? ?? []))
        (r as Map).cast<String, dynamic>()
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final atm = (chain['atm'] as num?)?.toDouble();

    Widget head(String t, TextAlign align) => Expanded(
          child: Text(t,
              textAlign: align,
              style: const TextStyle(
                  color: Brand.gold,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold)),
        );

    return Card(
      color: Brand.fern.withValues(alpha: 0.25),
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            color: Brand.fern.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                head('CALL OI', TextAlign.left),
                head('LTP', TextAlign.right),
                head('STRIKE', TextAlign.center),
                head('LTP', TextAlign.left),
                head('PUT OI', TextAlign.right),
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
                final strike = (r['strike'] as num?)?.toDouble();
                final isAtm = atm != null && strike == atm;

                return Container(
                  color: isAtm
                      ? Brand.gold.withValues(alpha: 0.14)
                      : (i.isEven
                          ? Colors.transparent
                          : Brand.fern.withValues(alpha: 0.12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_lakh(r['ce_oi'] as num?),
                            style: TextStyle(
                                color: Brand.red.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_num(r['ce_ltp'] as num?),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_num(strike),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: isAtm ? Brand.gold : Brand.mint,
                                fontSize: 11,
                                fontWeight: isAtm
                                    ? FontWeight.bold
                                    : FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(_num(r['pe_ltp'] as num?),
                            style: const TextStyle(
                                color: Brand.paper, fontSize: 10.5)),
                      ),
                      Expanded(
                        child: Text(_lakh(r['pe_oi'] as num?),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: Brand.green.withValues(alpha: 0.9),
                                fontSize: 10.5)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// ERROR
// ===========================================================================

class _OptionsError extends StatelessWidget {
  const _OptionsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Token and subscription problems need action, not another attempt.
    final needsAction = message.toLowerCase().contains('token') ||
        message.toLowerCase().contains('subscription') ||
        message.toLowerCase().contains('expired');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 30),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(needsAction ? Icons.key_off : Icons.cloud_off,
              color: Brand.red, size: 28),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.45)),
          if (!needsAction) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
