// lib/screens/trading_screen.dart
//
// Personal stock trading via your own Dhan account (NSE/BSE equity).
// Every order here is something YOU explicitly submit by tapping a button -
// there is no automated/algo trading. Your Dhan client ID/access token
// never reach this app; they live only on the research-api server, which
// this screen talks to over the existing /trading/ endpoints.

import 'package:flutter/material.dart';
import '../main.dart';
import '../services/trading_api_service.dart';

class TradingScreen extends StatefulWidget {
  final String userEmail;
  const TradingScreen({super.key, required this.userEmail});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openOrderSheet({String? prefillSymbol, String transactionType = 'BUY'}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceOrderSheet(
        userEmail: widget.userEmail,
        prefillSymbol: prefillSymbol,
        transactionType: transactionType,
        onPlaced: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        title: const Text('Trading'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Brand.gold,
          labelColor: Brand.gold,
          unselectedLabelColor: Brand.mint,
          tabs: const [
            Tab(text: 'Holdings'),
            Tab(text: 'Positions'),
            Tab(text: 'Orders'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openOrderSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Place order'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _HoldingsTab(userEmail: widget.userEmail, onTrade: _openOrderSheet),
          _PositionsTab(userEmail: widget.userEmail),
          _OrdersTab(userEmail: widget.userEmail),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Holdings tab
// ---------------------------------------------------------------------------
class _HoldingsTab extends StatefulWidget {
  final String userEmail;
  final void Function({required String prefillSymbol, required String transactionType}) onTrade;
  const _HoldingsTab({required this.userEmail, required this.onTrade});

  @override
  State<_HoldingsTab> createState() => _HoldingsTabState();
}

class _HoldingsTabState extends State<_HoldingsTab> {
  List<Map<String, dynamic>> _holdings = [];
  bool _loading = true;
  String? _error;

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
      final h = await TradingApiService.getHoldings(widget.userEmail);
      setState(() {
        _holdings = h;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Brand.gold));
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_holdings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 60),
            Icon(Icons.inventory_2_outlined, color: Brand.mint, size: 48),
            SizedBox(height: 12),
            Text('No holdings yet', textAlign: TextAlign.center,
                style: TextStyle(color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _holdings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final h = _holdings[i];
          final symbol = (h['tradingSymbol'] ?? h['trading_symbol'] ?? '').toString();
          final qty = double.tryParse('${h['totalQty'] ?? h['quantity'] ?? 0}') ?? 0;
          final avg = double.tryParse('${h['avgCostPrice'] ?? h['average_price'] ?? 0}') ?? 0;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.fern,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(symbol, style: const TextStyle(
                          color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('$qty units @ avg ₹$avg',
                          style: const TextStyle(color: Brand.mint, fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onTrade(prefillSymbol: symbol, transactionType: 'SELL'),
                  child: const Text('Sell', style: TextStyle(color: Brand.red)),
                ),
                TextButton(
                  onPressed: () => widget.onTrade(prefillSymbol: symbol, transactionType: 'BUY'),
                  child: const Text('Buy', style: TextStyle(color: Brand.green)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Positions tab
// ---------------------------------------------------------------------------
class _PositionsTab extends StatefulWidget {
  final String userEmail;
  const _PositionsTab({required this.userEmail});

  @override
  State<_PositionsTab> createState() => _PositionsTabState();
}

class _PositionsTabState extends State<_PositionsTab> {
  List<Map<String, dynamic>> _positions = [];
  bool _loading = true;
  String? _error;

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
      final p = await TradingApiService.getPositions(widget.userEmail);
      setState(() {
        _positions = p;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Brand.gold));
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_positions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 60),
            Icon(Icons.show_chart, color: Brand.mint, size: 48),
            SizedBox(height: 12),
            Text('No open positions', textAlign: TextAlign.center,
                style: TextStyle(color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _positions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final p = _positions[i];
          final symbol = (p['tradingSymbol'] ?? p['trading_symbol'] ?? '').toString();
          final qty = double.tryParse('${p['netQty'] ?? p['quantity'] ?? 0}') ?? 0;
          final pnl = double.tryParse('${p['realizedProfit'] ?? p['realised_pnl'] ?? 0}') ?? 0;
          final pnlColor = pnl >= 0 ? Brand.green : Brand.red;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.fern,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(symbol, style: const TextStyle(
                          color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${p['productType'] ?? p['product'] ?? ''} · qty $qty',
                          style: const TextStyle(color: Brand.mint, fontSize: 12)),
                    ],
                  ),
                ),
                Text('₹$pnl', style: TextStyle(color: pnlColor, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orders tab
// ---------------------------------------------------------------------------
class _OrdersTab extends StatefulWidget {
  final String userEmail;
  const _OrdersTab({required this.userEmail});

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

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
      final o = await TradingApiService.listOrders(widget.userEmail);
      setState(() {
        _orders = o;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _cancel(String orderId) async {
    try {
      await TradingApiService.cancelOrder(widget.userEmail, orderId: orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled.')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e'), backgroundColor: Brand.red),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'TRADED':
      case 'EXECUTED':
      case 'COMPLETE':
        return Brand.green;
      case 'CANCELLED':
      case 'REJECTED':
        return Brand.red;
      default:
        return Brand.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Brand.gold));
    if (_error != null) return _ErrorBox(message: _error!, onRetry: _load);
    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 60),
            Icon(Icons.receipt_long_outlined, color: Brand.mint, size: 48),
            SizedBox(height: 12),
            Text('No orders today', textAlign: TextAlign.center,
                style: TextStyle(color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final o = _orders[i];
          final symbol = (o['tradingSymbol'] ?? o['trading_symbol'] ?? '').toString();
          final status = (o['orderStatus'] ?? o['order_status'] ?? '').toString();
          final id = (o['orderId'] ?? o['order_id'] ?? '').toString();
          final canCancel = !['TRADED', 'EXECUTED', 'COMPLETE', 'CANCELLED', 'REJECTED']
              .contains(status.toUpperCase());
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.fern,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(symbol.isEmpty ? id : symbol, style: const TextStyle(
                          color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${o['transactionType'] ?? o['transaction_type'] ?? ''} · '
                          'qty ${o['quantity'] ?? ''}',
                          style: const TextStyle(color: Brand.mint, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(status).withValues(alpha: 0.5)),
                  ),
                  child: Text(status, style: TextStyle(
                      color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                if (canCancel && id.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, color: Brand.red, size: 18),
                    onPressed: () => _cancel(id),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Place order bottom sheet
// ---------------------------------------------------------------------------
class _PlaceOrderSheet extends StatefulWidget {
  final String userEmail;
  final String? prefillSymbol;
  final String transactionType;
  final VoidCallback onPlaced;
  const _PlaceOrderSheet({
    required this.userEmail,
    this.prefillSymbol,
    this.transactionType = 'BUY',
    required this.onPlaced,
  });

  @override
  State<_PlaceOrderSheet> createState() => _PlaceOrderSheetState();
}

class _PlaceOrderSheetState extends State<_PlaceOrderSheet> {
  late final TextEditingController _symbol;
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _trigger = TextEditingController();
  late String _transactionType;
  String _orderType = 'MARKET';
  String _productType = 'CNC';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _symbol = TextEditingController(text: widget.prefillSymbol ?? '');
    _transactionType = widget.transactionType;
  }

  Future<void> _confirmAndSubmit() async {
    final symbol = _symbol.text.trim().toUpperCase();
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (symbol.isEmpty || qty <= 0) {
      setState(() => _error = 'Enter a valid symbol and quantity');
      return;
    }
    final needsPrice = _orderType == 'LIMIT';
    final price = double.tryParse(_price.text.trim()) ?? 0;
    if (needsPrice && price <= 0) {
      setState(() => _error = 'Enter a price for a LIMIT order');
      return;
    }
    final needsTrigger = _orderType == 'STOP_LOSS' || _orderType == 'STOP_LOSS_MARKET';
    final trigger = double.tryParse(_trigger.text.trim()) ?? 0;
    if (needsTrigger && trigger <= 0) {
      setState(() => _error = 'Enter a trigger price for this order type');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.fern,
        title: Text('Confirm $_transactionType order',
            style: const TextStyle(color: Brand.paper)),
        content: Text(
          '$_transactionType $qty × $symbol ($_orderType'
          '${needsPrice ? ' @ ₹$price' : ''})\n\n'
          'This places a REAL order on your Dhan account. Continue?',
          style: const TextStyle(color: Brand.mint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.vault),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Place order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await TradingApiService.placeOrder(
        widget.userEmail,
        tradingSymbol: symbol,
        quantity: qty,
        transactionType: _transactionType,
        orderType: _orderType,
        productType: _productType,
        price: needsPrice ? price : 0,
        triggerPrice: needsTrigger ? trigger : 0,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Order placed: ${res['orderStatus'] ?? res['orderId'] ?? 'submitted'}'),
        ));
        widget.onPlaced();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsPrice = _orderType == 'LIMIT';
    final needsTrigger = _orderType == 'STOP_LOSS' || _orderType == 'STOP_LOSS_MARKET';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.vault,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Place order', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Brand.gold)),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Brand.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 13)),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilterChip(
                      label: const Text('BUY'),
                      selected: _transactionType == 'BUY',
                      selectedColor: Brand.green.withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _transactionType = 'BUY'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilterChip(
                      label: const Text('SELL'),
                      selected: _transactionType == 'SELL',
                      selectedColor: Brand.red.withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _transactionType = 'SELL'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _symbol,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Brand.paper),
                decoration: const InputDecoration(labelText: 'Trading symbol (e.g. RELIANCE)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _qty,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Brand.paper),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _orderType,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: const InputDecoration(labelText: 'Order type'),
                items: const ['MARKET', 'LIMIT', 'STOP_LOSS', 'STOP_LOSS_MARKET']
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setState(() => _orderType = v ?? _orderType),
              ),
              if (needsPrice) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Brand.paper),
                  decoration: const InputDecoration(labelText: 'Price'),
                ),
              ],
              if (needsTrigger) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _trigger,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Brand.paper),
                  decoration: const InputDecoration(labelText: 'Trigger price'),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _productType,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: const InputDecoration(labelText: 'Product'),
                items: const ['CNC', 'INTRADAY', 'MARGIN']
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setState(() => _productType = v ?? _productType),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _confirmAndSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: _transactionType == 'BUY' ? Brand.green : Brand.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('$_transactionType $_orderType'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Brand.red, size: 40),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Brand.red), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
