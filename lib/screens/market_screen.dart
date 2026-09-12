// lib/screens/market_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  List<dynamic> _indices = [];
  bool _loading = true;
  String? _error;
  DateTime? _updated;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    // refresh every 60s while the user is on this screen
    _autoRefresh = Timer.periodic(
        const Duration(seconds: 60), (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await ApiService.getIndices();
      if (mounted) {
        setState(() {
          _indices = data;
          _updated = DateTime.now();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Markets',
                    style: TextStyle(
                        color: Brand.gold,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                if (_updated != null)
                  Text(
                    'Updated ${_fmtTime(_updated!)}',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.6),
                        fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Live Indian indices · refreshes every minute',
                style: TextStyle(color: Brand.mint, fontSize: 13)),
            const SizedBox(height: 16),
            if (_loading && _indices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              )
            else if (_error != null && _indices.isEmpty)
              _errorCard()
            else
              ..._indices.map((i) => _indexCard(i as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _indexCard(Map<String, dynamic> idx) {
    final value = idx['value'] ?? 0;
    final change = (idx['change'] ?? 0) as num;
    final pct = (idx['change_pct'] ?? 0) as num;
    final up = change >= 0;
    final color = up ? Brand.green : Brand.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (idx['name'] ?? '').toString(),
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fmtNum(value),
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 22,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: color, size: 24),
                    Text(
                      '${up ? '+' : ''}${_fmtNum(change)}',
                      style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.cloud_off, color: Brand.red, size: 40),
              const SizedBox(height: 12),
              Text(_error ?? 'Could not load indices',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.mint)),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Brand.gold,
                    foregroundColor: Brand.vault),
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  String _fmtNum(dynamic v) {
    if (v is! num) return v.toString();
    // group Indian-style with commas, 2 decimals
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${buf.toString()}.${parts[1]}';
  }

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
