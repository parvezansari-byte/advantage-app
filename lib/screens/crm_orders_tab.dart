// lib/screens/crm_orders_tab.dart
//
// The "Orders" tab on a client's page: the client's mutual fund orders with
// live status, a "New order" button, and cancel for orders that are still
// open. While any order is still in progress the list refreshes itself every
// few seconds.

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/orders_api_service.dart';
import 'crm_place_order_screen.dart';

/// Indian-digit-grouped rupees. Whole amounts show no decimals; amounts with
/// paise show two.
String formatInr(num value) {
  final v = value.toDouble();
  final whole = v == v.roundToDouble();
  final fixed = v.abs().toStringAsFixed(whole ? 0 : 2);
  final parts = fixed.split('.');
  final s = parts[0];
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final buf = <String>[];
    while (rest.length > 2) {
      buf.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) buf.insert(0, rest);
    grouped = '${buf.join(',')},$last3';
  }
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  return '${v < 0 ? '-' : ''}₹$grouped$dec';
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _when(String? iso) {
  if (iso == null) return '';
  try {
    final d = DateTime.parse(iso).toLocal();
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_monthNames[d.month - 1]}, $h12:$mm $ampm';
  } catch (_) {
    return iso;
  }
}

String _statusLabel(String s) {
  switch (s) {
    case 'CREATED':
      return 'Created';
    case 'SUBMITTED':
      return 'Submitted';
    case 'PAYMENT_PENDING':
      return 'Payment pending';
    case 'CONFIRMED':
      return 'Confirmed';
    case 'ALLOTTED':
      return 'Units allotted';
    case 'FAILED':
      return 'Failed';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return s;
  }
}

Color _statusColour(String s) {
  switch (s) {
    case 'ALLOTTED':
      return Brand.green;
    case 'FAILED':
      return Brand.red;
    case 'CANCELLED':
      return Brand.mint.withValues(alpha: 0.6);
    default:
      return Brand.gold;
  }
}

String _orderSummary(CrmOrder o) {
  switch (o.orderType) {
    case 'SIP':
      return 'SIP ${formatInr(o.amount ?? 0)} on day ${o.sipDay ?? '-'}'
          ' × ${o.sipInstallments ?? '-'}';
    case 'REDEEM':
      return o.units != null
          ? 'Redeem ${o.units} units'
          : 'Redeem ${formatInr(o.amount ?? 0)}';
    default:
      return 'Purchase ${formatInr(o.amount ?? 0)}';
  }
}

class CrmOrdersTab extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const CrmOrdersTab({super.key, required this.ownerEmail, required this.client});

  @override
  State<CrmOrdersTab> createState() => _CrmOrdersTabState();
}

class _CrmOrdersTabState extends State<CrmOrdersTab> {
  List<CrmOrder> _orders = [];
  String? _mode; // STUB | LIVE, as reported by the server
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final (orders, mode) = await OrdersApiService.listOrders(
          widget.ownerEmail, widget.client.id!);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _mode = mode;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
    _syncTimer();
  }

  /// Poll every 5s while something is still in progress; stop when all done.
  void _syncTimer() {
    final open = _orders.any((o) => !o.isFinal);
    if (open && _timer == null) {
      _timer = Timer.periodic(
          const Duration(seconds: 5), (_) => _load(silent: true));
    } else if (!open && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _newOrder() async {
    final placed = await Navigator.push<CrmOrder>(
      context,
      MaterialPageRoute(
        builder: (_) => CrmPlaceOrderScreen(
          ownerEmail: widget.ownerEmail,
          client: widget.client,
          mode: _mode,
        ),
      ),
    );
    if (placed == null || !mounted) return;
    await _load(silent: true);
    if (!mounted) return;
    final failed = placed.status == 'FAILED';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: failed ? Brand.red : Brand.fern,
      content: Text(failed
          ? 'Order rejected: ${placed.failureReason ?? 'unknown reason'}'
          : placed.duplicate
              ? 'This order had already been placed - showing the existing one.'
              : 'Order placed.'),
    ));
  }

  Future<void> _cancel(CrmOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.fern,
        title: const Text('Cancel this order?',
            style: TextStyle(color: Brand.paper)),
        content: Text('${_orderSummary(o)}\n${o.schemeName}',
            style: const TextStyle(color: Brand.mint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Cancel order', style: TextStyle(color: Brand.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OrdersApiService.cancelOrder(widget.ownerEmail, o.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Brand.red, content: Text(e.toString())));
    }
    await _load(silent: true);
  }

  Widget _modeBanner() {
    if (_mode == 'LIVE') {
      return _banner(
        Brand.red,
        Icons.bolt,
        'LIVE - orders placed here go to NSE and are real.',
      );
    }
    if (_mode == 'STUB') {
      return _banner(
        Brand.teal,
        Icons.science_outlined,
        'TEST MODE - orders are simulated. Nothing is sent to NSE and no '
        'money moves.',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner(Color colour, IconData icon, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, color: colour, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: colour, fontSize: 12.5, height: 1.3)),
            ),
          ],
        ),
      );

  Widget _orderCard(CrmOrder o) {
    final colour = _statusColour(o.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(o.schemeName,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(o.status),
                    style: TextStyle(
                        color: colour,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_orderSummary(o),
              style: const TextStyle(color: Brand.gold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            [
              _when(o.createdAt),
              if (o.mode == 'STUB') 'TEST',
              if (o.nseOrderRef != null) 'Ref ${o.nseOrderRef}',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.7), fontSize: 11),
          ),
          if (o.status == 'FAILED' && o.failureReason != null) ...[
            const SizedBox(height: 4),
            Text(o.failureReason!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ],
          if (!o.isFinal) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _cancel(o),
                child: const Text('Cancel order',
                    style: TextStyle(color: Brand.red, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
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
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _modeBanner(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.gold,
              foregroundColor: Brand.vault,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _newOrder,
            icon: const Icon(Icons.add),
            label: const Text('New order',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          if (_orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: Brand.mint, size: 44),
                  const SizedBox(height: 10),
                  const Text('No orders yet',
                      style: TextStyle(
                          color: Brand.paper,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Purchases, SIPs and redemptions placed for this client '
                    'will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Brand.mint.withValues(alpha: 0.8),
                        fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ..._orders.map(_orderCard),
        ],
      ),
    );
  }
}
