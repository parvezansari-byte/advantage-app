// lib/screens/aum_trend_card.dart
//
// Trend of the whole client book: current value and amount invested over time,
// from GET /crm/{owner}/aum-history. Shown on the Client book screen.
// Snapshots are saved once a day, so a new install starts with an empty chart.

import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;

class AumTrendCard extends StatefulWidget {
  final String ownerEmail;
  const AumTrendCard({super.key, required this.ownerEmail});

  @override
  State<AumTrendCard> createState() => _AumTrendCardState();
}

class _AumTrendCardState extends State<AumTrendCard> {
  static const _periods = {'1M': 30, '3M': 90, '6M': 180, '1Y': 365};
  String _period = '6M';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pts = [];
  Map<String, dynamic>? _change;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/crm/${widget.ownerEmail}'
              '/aum-history?days=${_periods[_period]}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _pts = (j['points'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _change = j['change'] == null
            ? null
            : Map<String, dynamic>.from(j['change'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _short(num v) {
    final a = v.abs();
    final sign = v < 0 ? '-' : '';
    if (a >= 1e7) return '$sign₹${(a / 1e7).toStringAsFixed(2)} Cr';
    if (a >= 1e5) return '$sign₹${(a / 1e5).toStringAsFixed(2)} L';
    return '$sign₹${a.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Book value over time',
                style: TextStyle(
                    color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          for (final p in _periods.keys)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text(p, style: const TextStyle(fontSize: 11)),
                selected: _period == p,
                selectedColor: Brand.gold,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  _period = p;
                  _load();
                },
              ),
            ),
        ]),
        const SizedBox(height: 8),
        if (_loading)
          const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator(color: Brand.gold)))
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 12))
        else if (_pts.length < 2)
          Text(
            _pts.isEmpty
                ? 'No history yet. A snapshot is saved every night, so the chart fills in from tomorrow.'
                : 'One snapshot so far. The chart appears after the next nightly snapshot.',
            style: const TextStyle(color: Brand.mint, fontSize: 12),
          )
        else ...[
          SizedBox(height: 170, child: _chart()),
          const SizedBox(height: 8),
          Row(children: [
            _legend(Brand.gold, 'Value'),
            const SizedBox(width: 14),
            _legend(Brand.mint, 'Invested'),
          ]),
          if (_change != null) ...[
            const SizedBox(height: 8),
            _kv('Change in value',
                '${_short((_change!['value_change'] ?? 0) as num)}'
                    '${_change!['value_change_pct'] == null ? '' : ' (${_change!['value_change_pct']}%)'}'),
            _kv('New money added', _short((_change!['new_money'] ?? 0) as num)),
            _kv('Market movement',
                _short((_change!['market_movement'] ?? 0) as num)),
          ],
        ],
      ]),
    );
  }

  Widget _chart() {
    final values = [for (final p in _pts) (p['value'] as num).toDouble()];
    final invested = [for (final p in _pts) (p['invested'] as num).toDouble()];
    final all = [...values, ...invested];
    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) * 0.1 + 1;
    lo -= pad;
    hi += pad;
    final step = (_pts.length / 4).ceilToDouble().clamp(1, 1000).toDouble();
    LineChartBarData line(List<double> ys, Color c, double w) => LineChartBarData(
          spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: false,
          color: c,
          barWidth: w,
          dotData: const FlDotData(show: false),
        );
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_pts.length - 1).toDouble(),
        minY: lo,
        maxY: hi,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Brand.mint.withValues(alpha: 0.12), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: step,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= _pts.length) return const SizedBox.shrink();
                final d = '${_pts[i]['day']}'; // YYYY-MM-DD
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(d.substring(5),
                      style: const TextStyle(color: Brand.mint, fontSize: 9.5)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 58,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(_short(v),
                    style: const TextStyle(color: Brand.mint, fontSize: 9.5)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((s) {
              final i = s.x.round().clamp(0, _pts.length - 1);
              return LineTooltipItem(
                '${_pts[i]['day']}\n${_short(s.y)}',
                const TextStyle(
                    color: Brand.paper, fontSize: 11, fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          line(invested, Brand.mint.withValues(alpha: 0.7), 1.5),
          line(values, Brand.gold, 2.5),
        ],
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(color: Brand.mint, fontSize: 11)),
      ]);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: Brand.mint, fontSize: 12))),
          Text(v, style: const TextStyle(color: Brand.paper, fontSize: 12)),
        ]),
      );
}
