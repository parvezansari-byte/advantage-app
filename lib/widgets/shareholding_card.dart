import 'package:flutter/material.dart';
import '../main.dart';
import '../services/shareholding_service.dart';

/// "Who owns this stock" card: promoter / public (and FII / DII when the
/// source reports them) for the latest quarter, plus a short history.
class ShareholdingCard extends StatefulWidget {
  final String symbol;
  const ShareholdingCard({super.key, required this.symbol});

  @override
  State<ShareholdingCard> createState() => _ShareholdingCardState();
}

class _ShareholdingCardState extends State<ShareholdingCard> {
  late Future<ShareholdingResult> _future;

  @override
  void initState() {
    super.initState();
    _future = ShareholdingService.fetch(widget.symbol);
  }

  void _retry() =>
      setState(() => _future = ShareholdingService.fetch(widget.symbol));

  static String _pct(double? v) => v == null ? '\u2014' : '${v.toStringAsFixed(2)}%';

  static String _quarter(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
        'Sep', 'Oct', 'Nov', 'Dec'];
    final mi = int.tryParse(p[1]) ?? 0;
    return '${mi >= 1 && mi <= 12 ? m[mi] : p[1]} ${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<ShareholdingResult>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 64,
                child: Center(
                    child: CircularProgressIndicator(color: Brand.gold)),
              );
            }
            if (snap.hasError || snap.data?.latest == null) {
              return Row(
                children: [
                  const Expanded(
                    child: Text('Shareholding pattern is not available right now.',
                        style: TextStyle(color: Brand.mint)),
                  ),
                  TextButton(onPressed: _retry, child: const Text('Retry')),
                ],
              );
            }
            return _body(snap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(ShareholdingResult res) {
    final q = res.latest!;
    final parts = <_Part>[
      _Part('Promoters', q.promoter, Brand.gold),
      _Part('FII', q.fii, Brand.blue),
      _Part('DII', q.dii, Brand.purple),
      _Part('Public', q.public, Brand.teal),
      _Part('Other', q.other, Colors.blueGrey),
    ].where((p) => p.value != null && p.value! > 0).toList();
    final total = parts.fold<double>(0, (s, p) => s + p.value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('SHAREHOLDING PATTERN',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600)),
            Text(_quarter(q.date),
                style: const TextStyle(color: Brand.mint, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final p in parts)
                    Expanded(
                      flex: (p.value! / total * 1000).round().clamp(1, 1000),
                      child: Container(color: p.color),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: p.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.label)),
                Text(_pct(p.value),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p.label == 'Promoters' && q.promoterChg != null) ...[
                  const SizedBox(width: 8),
                  _Change(q.promoterChg!),
                ],
              ],
            ),
          ),
        if (res.quarters.length > 1) ...[
          const Divider(height: 24),
          const Text('Promoter holding by quarter',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          const SizedBox(height: 6),
          for (final h in res.quarters.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                      child: Text(_quarter(h.date),
                          style: const TextStyle(fontSize: 13))),
                  Text(_pct(h.promoter), style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
        if (res.stale)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Showing the last saved copy. The exchange could not be reached.',
                style: TextStyle(color: Brand.mint, fontSize: 11)),
          ),
      ],
    );
  }
}

class _Part {
  final String label;
  final double? value;
  final Color color;
  const _Part(this.label, this.value, this.color);
}

class _Change extends StatelessWidget {
  final double v;
  const _Change(this.v);

  @override
  Widget build(BuildContext context) {
    if (v == 0) {
      return const Text('0.00', style: TextStyle(color: Brand.mint, fontSize: 12));
    }
    final up = v > 0;
    return Text('${up ? '\u25b2' : '\u25bc'} ${v.abs().toStringAsFixed(2)}',
        style: TextStyle(color: up ? Brand.green : Brand.red, fontSize: 12));
  }
}
