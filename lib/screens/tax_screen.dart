// tax_screen.dart
//
// Two sections: a form to log buy/sell transactions, and a tax report view
// (STCG/LTCG breakdown for a selected financial year).
//
// NOTE: This is written with plain Material widgets and Theme.of(context)
// colors so it drops in cleanly. If your other screens use shared constants
// (e.g. an AppColors/AppTextStyles file), swap those in for consistency -
// I don't have visibility into that file from what's been shared so far.

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TaxScreen extends StatefulWidget {
  const TaxScreen({super.key, required this.userEmail});

  final String userEmail;

  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Add-transaction form state
  final _symbolCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  DateTime _tradeDate = DateTime.now();
  String _transactionType = 'BUY';
  String _assetType = 'EQUITY';
  bool _savingTransaction = false;
  String? _formError;

  // Tax report state
  String _selectedFy = '2025-26';
  Map<String, dynamic>? _report;
  bool _loadingReport = false;
  String? _reportError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _symbolCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loadingReport = true;
      _reportError = null;
    });
    try {
      final report = await ApiService.getTaxReport(widget.userEmail, fy: _selectedFy);
      setState(() => _report = report);
    } catch (e) {
      setState(() => _reportError = e.toString());
    } finally {
      setState(() => _loadingReport = false);
    }
  }

  Future<void> _submitTransaction() async {
    setState(() => _formError = null);

    final symbol = _symbolCtrl.text.trim();
    final qty = double.tryParse(_qtyCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());

    if (symbol.isEmpty || qty == null || qty <= 0 || price == null || price <= 0) {
      setState(() => _formError = 'Enter a valid symbol, quantity, and price');
      return;
    }

    setState(() => _savingTransaction = true);
    try {
      await ApiService.addTransaction(
        widget.userEmail,
        symbol: symbol,
        transactionType: _transactionType,
        quantity: qty,
        price: price,
        tradeDate:
            '${_tradeDate.year}-${_tradeDate.month.toString().padLeft(2, '0')}-${_tradeDate.day.toString().padLeft(2, '0')}',
        assetType: _assetType,
      );
      _symbolCtrl.clear();
      _qtyCtrl.clear();
      _priceCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction logged')),
        );
      }
      _loadReport(); // refresh the report since data changed
    } catch (e) {
      setState(() => _formError = e.toString());
    } finally {
      setState(() => _savingTransaction = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tradeDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _tradeDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tax Calculator'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Log Transaction'),
            Tab(text: 'Tax Report'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTransactionForm(),
          _buildReportView(),
        ],
      ),
    );
  }

  Widget _buildTransactionForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Log every buy and sell for accurate STCG/LTCG classification. '
            'Enter your historical trades once as a backfill, then log new ones as you make them.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _symbolCtrl,
            decoration: const InputDecoration(labelText: 'Symbol', hintText: 'e.g. TCS'),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _transactionType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                    DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                  ],
                  onChanged: (v) => setState(() => _transactionType = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _assetType,
                  decoration: const InputDecoration(labelText: 'Asset type'),
                  items: const [
                    DropdownMenuItem(value: 'EQUITY', child: Text('Equity')),
                    DropdownMenuItem(value: 'DEBT', child: Text('Debt')),
                  ],
                  onChanged: (v) => setState(() => _assetType = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price per unit'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Trade date'),
            subtitle: Text(
                '${_tradeDate.year}-${_tradeDate.month.toString().padLeft(2, '0')}-${_tradeDate.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(_formError!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _savingTransaction ? null : _submitTransaction,
            child: _savingTransaction
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Transaction'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportView() {
    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedFy,
              decoration: const InputDecoration(labelText: 'Financial Year'),
              items: const [
                DropdownMenuItem(value: '2023-24', child: Text('FY 2023-24')),
                DropdownMenuItem(value: '2024-25', child: Text('FY 2024-25')),
                DropdownMenuItem(value: '2025-26', child: Text('FY 2025-26')),
                DropdownMenuItem(value: '2026-27', child: Text('FY 2026-27')),
              ],
              onChanged: (v) {
                setState(() => _selectedFy = v!);
                _loadReport();
              },
            ),
            const SizedBox(height: 16),
            if (_loadingReport) const Center(child: CircularProgressIndicator()),
            if (_reportError != null)
              Text(_reportError!, style: const TextStyle(color: Colors.red)),
            if (_report != null) _buildReportSummary(_report!),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSummary(Map<String, dynamic> report) {
    final equity = report['equity'] as Map<String, dynamic>;
    final debt = report['debt'] as Map<String, dynamic>;
    final breakdown = report['transaction_breakdown'] as List<dynamic>;
    final notes = report['notes'] as List<dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimated tax: ₹${report['total_tax_estimate']}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Divider(height: 24),
                Text('Equity STCG (20%): ₹${equity['stcg_gain']} → tax ₹${equity['stcg_tax_estimate']}'),
                const SizedBox(height: 4),
                Text('Equity LTCG: ₹${equity['ltcg_gain']} (exemption used: ₹${equity['ltcg_exemption_applied']})'),
                Text('Taxable LTCG (12.5%): ₹${equity['ltcg_taxable']} → tax ₹${equity['ltcg_tax_estimate']}'),
                const SizedBox(height: 4),
                Text('Debt gains: ₹${debt['gain']} — ${debt['note']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Transaction breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...breakdown.map((row) => Card(
              child: ListTile(
                title: Text('${row['symbol']} — ${row['classification']}'),
                subtitle: Text(
                    'Bought ${row['buy_date']} @ ${row['buy_price']}, sold ${row['sell_date']} @ ${row['sell_price']}\n'
                    'Qty: ${row['quantity']}, held ${row['holding_days']} days'),
                trailing: Text('₹${row['gain']}',
                    style: TextStyle(
                        color: (row['gain'] as num) >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold)),
                isThreeLine: true,
              ),
            )),
        const SizedBox(height: 16),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: notes
                  .map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $n', style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
