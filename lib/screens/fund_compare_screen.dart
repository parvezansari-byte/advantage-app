// lib/screens/fund_compare_screen.dart
// ---------------------------------------------------------------------------
// Compare 1 to 3 mutual funds side by side (returns, risk, cost, size), see how
// each ranks in its category, and look at higher-returning alternatives in the
// same category. Past data only; not investment advice.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/portfolio_review_service.dart';

String _num(num? v, {int dp = 2}) => v == null ? '-' : v.toStringAsFixed(dp);

String _aum(num? v) {
  if (v == null) return '-';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)} lakh Cr';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K Cr';
  return '${v.toStringAsFixed(0)} Cr';
}

String _short(String name) {
  var n = name.split(' - ').first;
  n = n.replaceAll(RegExp(r'\s*Fund$'), '');
  return n;
}

class FundCompareScreen extends StatefulWidget {
  final List<String>? initial;
  const FundCompareScreen({super.key, this.initial});
  @override
  State<FundCompareScreen> createState() => _FundCompareScreenState();
}

class _FundCompareScreenState extends State<FundCompareScreen> {
  final List<String> _names = [];
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _names.addAll(widget.initial!.take(3));
    if (_names.isNotEmpty) _load();
  }

  Future<void> _load() async {
    if (_names.isEmpty) {
      setState(() => _data = null);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await PortfolioReviewService.compare(_names);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.vault,
      builder: (_) => const _SearchSheet(),
    );
    if (name == null || _names.contains(name)) return;
    if (_names.length >= 3) _names.removeAt(2);
    _names.add(name);
    await _load();
  }

  void _use(String name, String replacing) {
    final i = _names.indexOf(replacing);
    if (_names.contains(name)) return;
    if (_names.length < 3) {
      _names.add(name);
    } else if (i >= 0) {
      _names[i] = name;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Compare funds'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final n in _names)
              InputChip(
                backgroundColor: Brand.fern,
                label: Text(_short(n), style: const TextStyle(color: Brand.paper, fontSize: 12)),
                deleteIconColor: Brand.mint,
                onDeleted: () {
                  _names.remove(n);
                  _load();
                },
              ),
            if (_names.length < 3)
              ActionChip(
                backgroundColor: Brand.gold,
                avatar: const Icon(Icons.add, size: 16, color: Brand.vault),
                label: const Text('Add fund', style: TextStyle(color: Brand.vault, fontSize: 12)),
                onPressed: _busy ? null : _add,
              ),
          ]),
          if (_names.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Add up to 3 funds to compare them side by side',
                    style: TextStyle(color: Brand.mint)),
              ),
            ),
          if (_busy)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Brand.red)),
            ),
          if (_data != null && !_busy) ..._content(_data!),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final funds = (d['funds'] as List).cast<Map<String, dynamic>>();
    final rows = (d['rows'] as List).cast<Map<String, dynamic>>();
    final best = (d['best'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt()));
    final alts = d['alternatives'] as Map<String, dynamic>;
    final notes = (d['notes'] as List).map((e) => '$e').toList();

    Widget cell(String t, {bool bold = false, bool hi = false, Color? color, TextAlign a = TextAlign.right}) =>
        Expanded(
          flex: 2,
          child: Text(t,
              textAlign: a,
              style: TextStyle(
                  color: color ?? (hi ? Brand.gold : Brand.paper),
                  fontSize: 12,
                  fontWeight: (bold || hi) ? FontWeight.w700 : FontWeight.w400)),
        );

    Widget line(String label, List<Widget> cells, {bool shade = false}) => Container(
          color: shade ? Brand.fern.withOpacity(0.35) : null,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Row(children: [
            Expanded(flex: 3, child: Text(label, style: const TextStyle(color: Brand.mint, fontSize: 11.5))),
            ...cells,
          ]),
        );

    final out = <Widget>[
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        color: Brand.fern.withOpacity(0.6),
        child: Row(children: [
          const Expanded(flex: 3, child: SizedBox()),
          for (final f in funds)
            cell(_short('${f['name']}'), bold: true, a: TextAlign.right, color: Brand.paper),
        ]),
      ),
      line('Category', [for (final f in funds) cell('${f['category']}')]),
      line('Benchmark', [for (final f in funds) cell('${f['benchmark'] ?? '-'}'.replaceAll(' - TRI', ''))], shade: true),
      for (var r = 0; r < rows.length; r++)
        line(
          '${rows[r]['label']}',
          [
            for (var i = 0; i < funds.length; i++)
              () {
                final key = '${rows[r]['key']}';
                final v = (funds[i]['values'] as Map<String, dynamic>)[key] as num?;
                final txt = key == 'aum' ? _aum(v) : _num(v);
                return cell(txt, hi: best[key] == i);
              }(),
          ],
          shade: r.isEven,
        ),
      line('Rank in category (3y)', [
        for (final f in funds)
          cell(f['rank_3y'] == null ? '-' : '${f['rank_3y']['rank']} of ${f['rank_3y']['of']}'),
      ]),
      line('Category typical 3y %', [
        for (final f in funds) cell(_num((f['category_median'] as Map)['r_3y'] as num?, dp: 1)),
      ], shade: true),
      line('Benchmark typical 3y %', [
        for (final f in funds) cell(_num((f['benchmark_median'] as Map)['r_3y'] as num?, dp: 1)),
      ]),
      line('Manager', [for (final f in funds) cell('${f['manager'] ?? '-'}')], shade: true),
      line('Exit load', [for (final f in funds) cell('${f['exit_load'] ?? '-'}'.split('.').first)]),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Gold = best of the funds shown on that row.', style: TextStyle(color: Brand.mint, fontSize: 10.5)),
      ),
      const SizedBox(height: 18),
      const Text('SAME CATEGORY, HIGHER PAST RETURN',
          style: TextStyle(color: Brand.gold, fontWeight: FontWeight.w700, letterSpacing: .6)),
    ];

    for (final f in funds) {
      final list = (alts['${f['name']}'] as List? ?? []).cast<Map<String, dynamic>>();
      out.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text('Instead of ${_short('${f['name']}')}',
            style: const TextStyle(color: Brand.paper, fontWeight: FontWeight.w600, fontSize: 13)),
      ));
      if (list.isEmpty) {
        out.add(const Text('No comparable funds found.', style: TextStyle(color: Brand.mint, fontSize: 12)));
      }
      for (final a in list) {
        final diff = a['vs_selected_pp'] as num?;
        out.add(Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Brand.fern.withOpacity(0.5), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['name']}'.split(' - ').first,
                    style: const TextStyle(color: Brand.paper, fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                    '${a['basis']} ${_num((a['r_3y'] ?? a['r_1y']) as num?, dp: 1)}%'
                    '${diff == null ? '' : ' (${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} pts)'}'
                    '  •  cost ${_num(a['expense_ratio'] as num?)}%  •  ${_aum(a['aum'] as num?)}',
                    style: const TextStyle(color: Brand.mint, fontSize: 11)),
              ]),
            ),
            TextButton(
              onPressed: () => _use('${a['name']}', '${f['name']}'),
              child: const Text('Compare', style: TextStyle(color: Brand.gold, fontSize: 12)),
            ),
          ]),
        ));
      }
    }
    out.add(const SizedBox(height: 12));
    for (final n in notes) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(n, style: const TextStyle(color: Brand.mint, fontSize: 11)),
      ));
    }
    return out;
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _c = TextEditingController();
  List<String> _hits = [];
  Timer? _deb;

  @override
  void dispose() {
    _deb?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _deb?.cancel();
    if (q.trim().length < 3) {
      setState(() => _hits = []);
      return;
    }
    _deb = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await PortfolioReviewService.searchFunds(q);
        if (mounted) setState(() => _hits = r);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Find a fund', style: TextStyle(color: Brand.paper, fontSize: 16, fontWeight: FontWeight.w700)),
        TextField(
          controller: _c,
          autofocus: true,
          style: const TextStyle(color: Brand.paper),
          decoration: const InputDecoration(
            hintText: 'Type at least 3 letters, e.g. flexi cap',
            hintStyle: TextStyle(color: Brand.mint),
          ),
          onChanged: _onChanged,
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(shrinkWrap: true, children: [
            for (final h in _hits)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(h, style: const TextStyle(color: Brand.mint, fontSize: 12.5)),
                onTap: () => Navigator.pop(context, h),
              ),
          ]),
        ),
      ]),
    );
  }
}
