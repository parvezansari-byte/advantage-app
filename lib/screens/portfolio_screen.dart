// lib/screens/portfolio_screen.dart
// ---------------------------------------------------------------------------
// Portfolio: saved holdings valued at live prices.
//
// Holdings persist per signed-in user, so they survive closing the app. Adding
// the same symbol twice merges into one position at a weighted-average price
// rather than creating a duplicate.
//
// A holding whose price can't be fetched is shown but left out of the totals —
// counting it at cost would quietly overstate the gain.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/api_service.dart';

// ===========================================================================
// FORMATTING
// ===========================================================================

String _group(int n) {
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

String _money(num? v) => v == null ? '—' : '₹${_group(v.round())}';

String _moneyShort(num? v) {
  if (v == null) return '—';
  final a = v.abs();
  if (a >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (a >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  return _money(v);
}

String _signedMoney(num? v) {
  if (v == null) return '—';
  return '${v >= 0 ? '+' : '-'}₹${_group(v.abs().round())}';
}

String _signedPct(num? v) {
  if (v == null) return '—';
  return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
}

Color _pnlColour(num? v) {
  if (v == null) return Brand.mint;
  if (v > 0) return Brand.green;
  if (v < 0) return Brand.red;
  return Brand.mint;
}

// ===========================================================================
// SCREEN
// ===========================================================================

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key, required this.email});

  /// Holdings are stored per user, so the screen needs to know who's signed in.
  final String email;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  Map<String, dynamic>? _data;
  List<String> _symbols = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSymbols();
  }

  /// The stock universe backs the add-holding dropdown. It's a slow call and
  /// not needed to render the portfolio, so it loads independently.
  Future<void> _loadSymbols() async {
    try {
      final s = await ApiService.getStockList();
      if (mounted) setState(() => _symbols = s);
    } catch (_) {
      // The add sheet falls back to free text if this fails.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getPortfolio(widget.email);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddHoldingSheet(
        email: widget.email,
        symbols: _symbols,
      ),
    );
    if (added == true) _load();
  }

  Future<void> _confirmDelete(String symbol) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Brand.fern,
        title: const Text('Remove holding',
            style: TextStyle(color: Brand.paper, fontSize: 16)),
        content: Text('Remove $symbol from your portfolio?',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.9), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Brand.mint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Brand.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ApiService.deleteHolding(widget.email, symbol);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final holdings = (_data?['holdings'] as List?) ?? [];
    final totals =
        (_data?['totals'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        elevation: 0,
        title: const Text('My Portfolio',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.gold,
        foregroundColor: Brand.vault,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add holding',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.gold))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: Brand.gold,
                  backgroundColor: Brand.fern,
                  onRefresh: _load,
                  child: holdings.isEmpty
                      ? _EmptyState(onAdd: _openAddSheet)
                      : ListView(
                          padding:
                              const EdgeInsets.fromLTRB(14, 10, 14, 90),
                          children: [
                            _SummaryCard(totals: totals, data: _data!),
                            const SizedBox(height: 16),
                            if ((totals['unpriced'] as int? ?? 0) > 0)
                              _UnpricedNotice(
                                  count: totals['unpriced'] as int),
                            const _SectionLabel('HOLDINGS'),
                            for (final h in holdings)
                              _HoldingCard(
                                holding:
                                    (h as Map).cast<String, dynamic>(),
                                onDelete: () =>
                                    _confirmDelete('${h['symbol']}'),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              'Prices are live where available. Figures exclude '
                              'brokerage, taxes and charges, so realised P&L '
                              'will differ.',
                              style: TextStyle(
                                  color: Brand.mint.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  height: 1.4),
                            ),
                          ],
                        ),
                ),
    );
  }
}

// ===========================================================================
// SUMMARY
// ===========================================================================

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals, required this.data});

  final Map<String, dynamic> totals;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final pnl = totals['pnl'] as num?;
    final pnlPct = totals['pnl_pct'] as num?;
    final colour = _pnlColour(pnl);
    final best = (data['best'] as Map?)?.cast<String, dynamic>();
    final worst = (data['worst'] as Map?)?.cast<String, dynamic>();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CURRENT VALUE',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.8),
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_money(totals['current'] as num?),
              style: const TextStyle(
                  color: Brand.paper,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                  (pnl ?? 0) >= 0
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  color: colour,
                  size: 16),
              const SizedBox(width: 4),
              Text('${_signedMoney(pnl)}  (${_signedPct(pnlPct)})',
                  style: TextStyle(
                      color: colour,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Brand.mint.withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invested',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7),
                            fontSize: 10)),
                    const SizedBox(height: 3),
                    Text(_money(totals['invested'] as num?),
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Positions',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.7),
                            fontSize: 10)),
                    const SizedBox(height: 3),
                    Text('${totals['priced'] ?? 0}',
                        style: const TextStyle(
                            color: Brand.paper,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (best != null || worst != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (best != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Best',
                            style: TextStyle(
                                color: Brand.mint.withValues(alpha: 0.7),
                                fontSize: 10)),
                        const SizedBox(height: 3),
                        Text(
                            '${best['symbol']}  '
                            '${_signedPct(best['pnl_pct'] as num?)}',
                            style: const TextStyle(
                                color: Brand.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (worst != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Worst',
                            style: TextStyle(
                                color: Brand.mint.withValues(alpha: 0.7),
                                fontSize: 10)),
                        const SizedBox(height: 3),
                        Text(
                            '${worst['symbol']}  '
                            '${_signedPct(worst['pnl_pct'] as num?)}',
                            style: const TextStyle(
                                color: Brand.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UnpricedNotice extends StatelessWidget {
  const _UnpricedNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Brand.gold, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count holding${count == 1 ? '' : 's'} could not be priced and '
              '${count == 1 ? 'is' : 'are'} left out of the totals.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.9),
                  fontSize: 11,
                  height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// HOLDING CARD
// ===========================================================================

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({required this.holding, required this.onDelete});

  final Map<String, dynamic> holding;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final priced = holding['priced'] == true;
    final pnl = holding['pnl'] as num?;
    final colour = _pnlColour(pnl);
    final weight = (holding['weight_pct'] as num?)?.toDouble() ?? 0;

    return Card(
      color: Brand.fern.withValues(alpha: 0.28),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${holding['symbol']}',
                          style: const TextStyle(
                              color: Brand.paper,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${(holding['qty'] as num?)?.toStringAsFixed(0) ?? '—'} '
                        'shares @ ${_money(holding['avg_price'] as num?)}',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.75),
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        priced
                            ? _money(holding['current'] as num?)
                            : 'Not priced',
                        style: TextStyle(
                            color: priced
                                ? Brand.paper
                                : Brand.mint.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    if (priced) ...[
                      const SizedBox(height: 2),
                      Text(
                          '${_signedMoney(pnl)}  '
                          '(${_signedPct(holding['pnl_pct'] as num?)})',
                          style: TextStyle(
                              color: colour,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: Brand.mint.withValues(alpha: 0.6), size: 17),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (priced) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                        label: 'LTP',
                        value: _money(holding['price'] as num?)),
                  ),
                  Expanded(
                    child: _MiniStat(
                        label: 'INVESTED',
                        value: _moneyShort(holding['invested'] as num?)),
                  ),
                  Expanded(
                    child: _MiniStat(
                        label: 'WEIGHT',
                        value: '${weight.toStringAsFixed(1)}%'),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              // Weight bar gives the position's share of the portfolio at a
              // glance, which the number alone doesn't convey.
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 4,
                  child: Row(
                    children: [
                      Expanded(
                        flex: math.max((weight * 10).round(), 1),
                        child: Container(color: colour.withValues(alpha: 0.8)),
                      ),
                      Expanded(
                        flex: math.max(((100 - weight) * 10).round(), 1),
                        child: Container(
                            color: Brand.fern.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.6),
                fontSize: 8.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Brand.paper,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ===========================================================================
// ADD HOLDING
// ===========================================================================

class _AddHoldingSheet extends StatefulWidget {
  const _AddHoldingSheet({required this.email, required this.symbols});

  final String email;
  final List<String> symbols;

  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  String? _symbol;
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double? get _qty => double.tryParse(_qtyCtrl.text.trim());
  double? get _price => double.tryParse(_priceCtrl.text.trim());

  bool get _valid =>
      _symbol != null &&
      (_qty ?? 0) > 0 &&
      (_price ?? 0) > 0;

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _error = 'Pick a stock and enter quantity and price');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await ApiService.addHolding(
        widget.email,
        symbol: _symbol!,
        qty: _qty!,
        avgPrice: _price!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      // "merged" tells the user their existing position was averaged rather
      // than duplicated, which is otherwise invisible.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r['action'] == 'merged'
              ? '${r['symbol']} merged — now ${r['qty']} @ ₹${r['avg_price']}'
              : '${r['symbol']} added'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSymbol() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SymbolPicker(symbols: widget.symbols),
    );
    if (picked != null) setState(() => _symbol = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Add holding',
                style: TextStyle(
                    color: Brand.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // ---- Stock dropdown ----
            const _SectionLabel('STOCK'),
            GestureDetector(
              onTap: _pickSymbol,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 14),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _symbol == null
                        ? Brand.mint.withValues(alpha: 0.22)
                        : Brand.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_symbol ?? 'Choose a stock',
                          style: TextStyle(
                              color: _symbol == null
                                  ? Brand.mint.withValues(alpha: 0.5)
                                  : Brand.paper,
                              fontSize: 14,
                              fontWeight: _symbol == null
                                  ? FontWeight.normal
                                  : FontWeight.w600)),
                    ),
                    Icon(Icons.expand_more,
                        color: Brand.mint.withValues(alpha: 0.7), size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('QUANTITY'),
                      _NumberField(
                        controller: _qtyCtrl,
                        hint: 'e.g. 50',
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('BUY PRICE'),
                      _NumberField(
                        controller: _priceCtrl,
                        hint: 'e.g. 1200',
                        prefix: '₹ ',
                        allowDecimal: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_valid) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total investment',
                        style: TextStyle(
                            color: Brand.mint.withValues(alpha: 0.85),
                            fontSize: 12)),
                    Text(_money(_qty! * _price!),
                        style: const TextStyle(
                            color: Brand.gold,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Brand.red, fontSize: 12)),
            ],

            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                  disabledBackgroundColor:
                      Brand.fern.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: (_saving || !_valid) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault),
                      )
                    : const Text('Save holding',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adding a stock you already hold merges the two at a '
              'weighted-average price.',
              style: TextStyle(
                  color: Brand.mint.withValues(alpha: 0.55),
                  fontSize: 10,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.prefix,
    this.allowDecimal = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final String? prefix;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        allowDecimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      style: const TextStyle(color: Brand.paper, fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Brand.mint.withValues(alpha: 0.45), fontSize: 13),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: Brand.gold, fontSize: 14),
        filled: true,
        fillColor: Brand.fern.withValues(alpha: 0.35),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Brand.mint.withValues(alpha: 0.22)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Brand.gold),
        ),
      ),
    );
  }
}

/// Searchable list of the stock universe — 500 symbols is far too many for a
/// plain dropdown on a phone.
class _SymbolPicker extends StatefulWidget {
  const _SymbolPicker({required this.symbols});

  final List<String> symbols;

  @override
  State<_SymbolPicker> createState() => _SymbolPickerState();
}

class _SymbolPickerState extends State<_SymbolPicker> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toUpperCase();
    final filtered = needle.isEmpty
        ? widget.symbols
        : widget.symbols.where((s) => s.contains(needle)).toList()
      ..sort((a, b) {
        // Prefix matches first — typing "REL" should surface RELIANCE, not
        // something that merely contains those letters.
        if (needle.isEmpty) return 0;
        final aStarts = a.startsWith(needle);
        final bStarts = b.startsWith(needle);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.compareTo(b);
      });

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.mint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Brand.paper, fontSize: 14),
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: widget.symbols.isEmpty
                      ? 'Type a symbol'
                      : 'Search ${widget.symbols.length} stocks',
                  hintStyle:
                      TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
                  prefixIcon:
                      const Icon(Icons.search, color: Brand.mint, size: 20),
                  filled: true,
                  fillColor: Brand.fern.withValues(alpha: 0.35),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 13),
                  enabledBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Brand.mint.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Brand.gold),
                  ),
                ),
              ),
            ),

            // If the universe failed to load, typing a symbol by hand still
            // works rather than blocking the whole flow.
            if (widget.symbols.isEmpty && _query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, color: Brand.gold, size: 18),
                  title: Text('Use "${_query.trim().toUpperCase()}"',
                      style: const TextStyle(
                          color: Brand.paper, fontSize: 13)),
                  onTap: () =>
                      Navigator.pop(context, _query.trim().toUpperCase()),
                ),
              ),

            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: filtered.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(filtered[i],
                      style: const TextStyle(
                          color: Brand.paper, fontSize: 13.5)),
                  onTap: () => Navigator.pop(context, filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// SHARED
// ===========================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text,
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.8),
              fontSize: 9.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Column(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 46, color: Brand.mint.withValues(alpha: 0.35)),
              const SizedBox(height: 16),
              Text('No holdings yet',
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50),
                child: Text(
                  'Add a stock with the quantity and price you bought at, and '
                  'your live P&L appears here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.6),
                      fontSize: 12,
                      height: 1.45),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.gold,
                  foregroundColor: Brand.vault,
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add your first holding'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 36, color: Brand.mint.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    height: 1.4)),
            const SizedBox(height: 16),
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
        ),
      ),
    );
  }
}
