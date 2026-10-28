// lib/screens/crm_holdings_tab.dart
//
// The "Holdings" tab on a client's page. Shows the holdings the advisor has
// recorded by hand, valued at the latest NAV with gain/loss, plus any
// holdings synced from NSE (once that sync exists).

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/crm_api_service.dart';
import '../services/holdings_api_service.dart';
import 'crm_add_holding_screen.dart';
import 'crm_orders_tab.dart' show formatInr;
import 'portfolio_review_screen.dart';
import '../services/portfolio_review_service.dart' show PfRow;

/// Units to up to 3 decimals, without trailing zeros (12.500 -> 12.5).
String formatUnits(double u) {
  var s = u.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

String _signedInr(double v) => '${v >= 0 ? '+' : '-'}${formatInr(v.abs())}';

class CrmHoldingsTab extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const CrmHoldingsTab(
      {super.key, required this.ownerEmail, required this.client});

  @override
  State<CrmHoldingsTab> createState() => _CrmHoldingsTabState();
}

class _CrmHoldingsTabState extends State<CrmHoldingsTab> {
  Portfolio? _portfolio;
  List<CrmHolding> _synced = [];
  double _syncedTotal = 0;
  String? _syncedAsOf;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final portfolio =
          await HoldingsApiService.getPortfolio(widget.ownerEmail, widget.client.id!);
      var synced = <CrmHolding>[];
      var syncedTotal = 0.0;
      String? asOf;
      try {
        final (h, t, f) =
            await CrmApiService.getHoldings(widget.ownerEmail, widget.client.id!);
        synced = h;
        syncedTotal = t;
        asOf = f;
      } catch (_) {
        // The NSE-synced list is optional; ignore if it isn't available.
      }
      if (!mounted) return;
      setState(() {
        _portfolio = portfolio;
        _synced = synced;
        _syncedTotal = syncedTotal;
        _syncedAsOf = asOf;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([ManualHolding? existing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrmAddHoldingScreen(
          ownerEmail: widget.ownerEmail,
          client: widget.client,
          existing: existing,
        ),
      ),
    );
    if (changed == true) await _load(silent: true);
  }

  Color _gainColour(double? g) =>
      g == null ? Brand.mint : (g >= 0 ? Brand.green : Brand.red);

  Widget _summaryCard(PortfolioTotals t) {
    final colour = _gainColour(t.priced == 0 ? null : t.gain);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current value',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          const SizedBox(height: 4),
          Text(formatInr(t.currentValue),
              style: const TextStyle(
                  color: Brand.gold, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Invested ${formatInr(t.invested)}',
                  style: const TextStyle(color: Brand.mint, fontSize: 12)),
              const SizedBox(width: 12),
              if (t.priced > 0)
                Text(
                  '${_signedInr(t.gain)}'
                  '${t.gainPct == null ? '' : ' (${t.gainPct!.toStringAsFixed(2)}%)'}',
                  style: TextStyle(
                      color: colour, fontSize: 12, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          if (t.priced < t.total) ...[
            const SizedBox(height: 6),
            Text(
              'Latest NAV unavailable for ${t.total - t.priced} of ${t.total} '
              'holdings - they are left out of the value and gain.',
              style: const TextStyle(color: Brand.gold, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _holdingCard(ManualHolding h) {
    final colour = _gainColour(h.gain);
    return InkWell(
      onTap: () => _openEditor(h),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.schemeName,
                      style: const TextStyle(
                          color: Brand.paper,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(
                    '${formatUnits(h.units)} units · avg NAV ₹${h.avgNav.toStringAsFixed(2)}'
                    '${h.folioNumber.isEmpty ? '' : ' · Folio ${h.folioNumber}'}',
                    style: const TextStyle(color: Brand.mint, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    h.currentNav == null
                        ? 'Latest NAV unavailable'
                        : 'NAV ₹${h.currentNav!.toStringAsFixed(2)}'
                            '${h.navDate == null ? '' : ' (${h.navDate})'}',
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  h.currentValue == null ? '-' : formatInr(h.currentValue!),
                  style: const TextStyle(
                      color: Brand.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                if (h.gain != null)
                  Text(
                    '${_signedInr(h.gain!)}'
                    '${h.gainPct == null ? '' : ' (${h.gainPct!.toStringAsFixed(1)}%)'}',
                    style: TextStyle(
                        color: colour, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'SYNCED FROM NSE - ${formatInr(_syncedTotal)}'
          '${_syncedAsOf == null ? '' : ' · as of $_syncedAsOf'}',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ..._synced.map((h) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Brand.fern.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.schemeName,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('${h.units} units · NAV ₹${h.nav}',
                            style: const TextStyle(
                                color: Brand.mint, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(formatInr(h.currentValue),
                      style: const TextStyle(
                          color: Brand.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.red)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final portfolio = _portfolio!;
    final empty = portfolio.holdings.isEmpty && _synced.isEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.gold,
              foregroundColor: Brand.vault,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Add holding',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 14),
          if (empty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const Icon(Icons.pie_chart_outline,
                      color: Brand.mint, size: 44),
                  const SizedBox(height: 10),
                  const Text('No holdings recorded yet',
                      style: TextStyle(
                          color: Brand.paper,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Add what this client holds - fund, units and average buy '
                    'NAV - to see its current value and gain, and to allow '
                    'redemptions. Holdings will sync automatically once the '
                    'NSE connection is set up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          if (portfolio.holdings.isNotEmpty) ...[
            _summaryCard(portfolio.totals),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                final rows = portfolio.holdings
                    .where((h) => h.currentValue != null && h.invested > 0)
                    .map((h) => PfRow(
                        name: h.schemeName,
                        invested: h.invested,
                        current: h.currentValue!,
                        date: null))
                    .toList();
                if (rows.isEmpty) return;
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PortfolioReviewScreen(
                              initialRows: rows,
                              title: '${widget.client.fullName} - review',
                              hint: 'Recorded holdings are loaded. Dates are not stored, so tap a fund '
                                  'and add its purchase date to compare yearly returns with the '
                                  'benchmark. Without a date you see total return only.',
                            )));
              },
              icon: const Icon(Icons.fact_check_outlined, color: Brand.gold),
              label: const Text('Review portfolio vs benchmark',
                  style: TextStyle(color: Brand.gold)),
            ),
            const SizedBox(height: 12),
            ...portfolio.holdings.map(_holdingCard),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Recorded by hand. Values use the latest published NAV. Tap a '
                'holding to correct or remove it.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.55), fontSize: 11),
              ),
            ),
          ],
          if (_synced.isNotEmpty) _syncedSection(),
        ],
      ),
    );
  }
}
