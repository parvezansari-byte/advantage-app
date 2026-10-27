// lib/screens/index_chart_screen.dart
// Price chart for one index. Opens when you tap an index on the Markets screen.

import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../services/api_service.dart';

class IndexChartScreen extends StatefulWidget {
  final String name;
  const IndexChartScreen({super.key, required this.name});

  @override
  State<IndexChartScreen> createState() => _IndexChartScreenState();
}

class _Pt {
  final String date;
  final double close;
  _Pt(this.date, this.close);
}

class _IndexChartScreenState extends State<IndexChartScreen> {
  static const _periods = ['1W', '1M', '3M', '6M', '1Y', '5Y'];

  String _period = '1M';
  List<_Pt> _pts = [];
  double _change = 0, _changePct = 0, _high = 0, _low = 0, _last = 0;
  bool _loading = true;
  bool _stale = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = Uri.encodeQueryComponent(widget.name);
      final r = await http
          .get(Uri.parse(
              '${ApiService.baseUrl}/indices/history?name=$q&period=$_period'))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode != 200) {
        throw Exception(r.statusCode == 503
            ? 'Price history is unavailable right now. Try again in a minute.'
            : 'Could not load the chart (${r.statusCode}).');
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final pts = <_Pt>[
        for (final p in (d['points'] as List? ?? const []))
          _Pt('${(p as Map)['d']}', (p['c'] as num).toDouble()),
      ];
      if (!mounted || id != _requestId) return;
      setState(() {
        _pts = pts;
        _change = (d['change'] as num?)?.toDouble() ?? 0;
        _changePct = (d['change_pct'] as num?)?.toDouble() ?? 0;
        _high = (d['high'] as num?)?.toDouble() ?? 0;
        _low = (d['low'] as num?)?.toDouble() ?? 0;
        _last = (d['last'] as num?)?.toDouble() ?? 0;
        _stale = d['stale'] == true;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  String _fmt(double v) {
    final parts = v.toStringAsFixed(2).split('.');
    final s = parts[0];
    if (s.length <= 3) return '$s.${parts[1]}';
    var rest = s.substring(0, s.length - 3);
    final out = <String>[];
    while (rest.length > 2) {
      out.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) out.insert(0, rest);
    return '${out.join(',')},${s.substring(s.length - 3)}.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final up = _change >= 0;
    final color = up ? Brand.green : Brand.red;
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: Text(widget.name,
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_pts.isNotEmpty) ...[
            Text(_fmt(_last),
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
                '${up ? '+' : ''}${_fmt(_change)}  (${up ? '+' : ''}${_changePct.toStringAsFixed(2)}%) over $_period',
                style: TextStyle(
                    color: color, fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (_stale)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('Showing the last saved data',
                    style: TextStyle(color: Brand.gold, fontSize: 11)),
              ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 6, children: [
            for (final p in _periods) _chip(p),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: _loading && _pts.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Brand.gold))
                : (_error != null && _pts.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Brand.mint)),
                            const SizedBox(height: 10),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Brand.gold,
                                  foregroundColor: Brand.vault),
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _chart(color),
          ),
          if (_pts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              _stat('High', _fmt(_high)),
              _stat('Low', _fmt(_low)),
              _stat('From', _pts.first.date),
            ]),
          ],
          const SizedBox(height: 16),
          Text(
              'Closing values. Source: Yahoo Finance. Past movement does not predict the future.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.6), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _chip(String p) {
    final on = p == _period;
    return GestureDetector(
      onTap: () {
        if (on) return;
        setState(() => _period = p);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? Brand.gold.withValues(alpha: 0.18)
              : Brand.fern.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? Brand.gold : Colors.transparent),
        ),
        child: Text(p,
            style: TextStyle(
                color: on ? Brand.gold : Brand.mint,
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Brand.mint, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _chart(Color color) {
    final spots = [
      for (var i = 0; i < _pts.length; i++) FlSpot(i.toDouble(), _pts[i].close),
    ];
    final pad = (_high - _low) * 0.08;
    final step = (_pts.length / 4).ceilToDouble().clamp(1, 1000).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_pts.length - 1).toDouble(),
        minY: _low - pad,
        maxY: _high + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Brand.mint.withValues(alpha: 0.12), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: step,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= _pts.length) return const SizedBox.shrink();
                final d = _pts[i].date; // YYYY-MM-DD
                final label = _period == '1Y' || _period == '5Y'
                    ? d.substring(2, 7)
                    : d.substring(5);
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(label,
                      style: const TextStyle(color: Brand.mint, fontSize: 9.5)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(v.toStringAsFixed(0),
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
                '${_pts[i].date}\n${_fmt(s.y)}',
                const TextStyle(
                    color: Brand.paper,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
          ),
        ],
      ),
    );
  }
}
