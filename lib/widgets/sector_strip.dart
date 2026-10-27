// lib/widgets/sector_strip.dart
// Sector heat strip for the Markets screen: one coloured tile per sector, greener when it is
// up and redder when it is down. Uses the same /sectors data as the Sectors screen.

import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/sectors_screen.dart';
import '../services/api_service.dart';

class SectorStrip extends StatefulWidget {
  const SectorStrip({super.key});

  @override
  State<SectorStrip> createState() => _SectorStripState();
}

class _Sector {
  final String name;
  final double? d1, m1;
  _Sector(this.name, this.d1, this.m1);
}

class _SectorStripState extends State<SectorStrip> {
  List<_Sector> _sectors = [];
  bool _loading = true;
  bool _failed = false;
  bool _oneDay = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double? _n(dynamic v) => v is num ? v.toDouble() : null;

  Future<void> _load() async {
    try {
      final d = await ApiService.getSectors();
      final rows = <_Sector>[
        for (final s in (d['sectors'] as List? ?? const []))
          _Sector('${(s as Map)['name']}', _n(s['return_1d']), _n(s['return_1m'])),
      ];
      if (!mounted) return;
      setState(() {
        _sectors = rows;
        _failed = rows.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = _sectors.isEmpty);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _value(_Sector s) => _oneDay ? s.d1 : s.m1;

  Color _tint(double? v) {
    if (v == null) return Brand.fern.withValues(alpha: 0.3);
    final strength = (v.abs() / (_oneDay ? 2.5 : 8.0)).clamp(0.0, 1.0);
    final base = v >= 0 ? Brand.green : Brand.red;
    return base.withValues(alpha: 0.14 + 0.5 * strength);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final sorted = [..._sectors]..sort((a, b) =>
        (_value(b) ?? -999).compareTo(_value(a) ?? -999));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('SECTORS',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.bold)),
            Row(children: [
              _toggle('Today', _oneDay, () => setState(() => _oneDay = true)),
              const SizedBox(width: 6),
              _toggle('1 month', !_oneDay, () => setState(() => _oneDay = false)),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading && _sectors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold))),
          )
        else
          LayoutBuilder(builder: (context, c) {
            const gap = 8.0;
            final w = (c.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final s in sorted) _tile(s, w)],
            );
          }),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SectorsScreen())),
            child: const Text('All sector details',
                style: TextStyle(color: Brand.gold, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on
                ? Brand.gold.withValues(alpha: 0.18)
                : Brand.fern.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Brand.gold : Colors.transparent),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Brand.gold : Brand.mint,
                  fontSize: 11,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  Widget _tile(_Sector s, double width) {
    final v = _value(s);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SectorsScreen())),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _tint(v),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                v == null
                    ? '\u2014'
                    : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%',
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
