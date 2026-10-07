// lib/screens/crm_place_order_screen.dart
//
// Place a mutual fund order (purchase, SIP or redemption) for one client.
//
// Flow: pick type -> search and pick a fund -> enter details -> Review ->
// summary dialog with a consent tick -> Confirm & place. The server enforces
// every rule again; this screen just makes mistakes hard and errors clear.
//
// Duplicate protection: each order attempt carries an idempotency key. The
// key changes whenever any input changes, but stays the same when the user
// simply retries after a dropped connection - so a retry can never place the
// same order twice.

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/api_service.dart';
import '../services/crm_api_service.dart' show CrmApiException;
import '../services/orders_api_service.dart';
import 'crm_orders_tab.dart' show formatInr;

const _minAmount = 100.0; // the server enforces the same floor
const _kycOk = {'KYC_VALIDATED', 'KYC_REGISTERED'};

class CrmPlaceOrderScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;

  /// 'STUB' (simulated) or 'LIVE', as last reported by the server; null if unknown.
  final String? mode;
  const CrmPlaceOrderScreen(
      {super.key, required this.ownerEmail, required this.client, this.mode});

  @override
  State<CrmPlaceOrderScreen> createState() => _CrmPlaceOrderScreenState();
}

class _CrmPlaceOrderScreenState extends State<CrmPlaceOrderScreen> {
  String _type = 'PURCHASE'; // PURCHASE | SIP | REDEEM
  bool _redeemByUnits = false;

  // Fund picker
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, String>> _results = [];
  bool _searching = false;
  String? _searchError;
  Map<String, String>? _fund; // {code, name}

  // Order details
  final _amount = TextEditingController();
  final _units = TextEditingController();
  final _installments = TextEditingController(text: '12');
  int _sipDay = 5;

  bool _submitting = false;
  String? _error;
  String _key = OrdersApiService.newIdempotencyKey();

  bool get _kycValid => _kycOk.contains(widget.client.kycStatus);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _amount.dispose();
    _units.dispose();
    _installments.dispose();
    super.dispose();
  }

  /// Any input changed: this is a different order, so it gets a new key.
  void _touch() {
    _key = OrdersApiService.newIdempotencyKey();
    _error = null;
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 3) {
      setState(() {
        _results = [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final raw = await ApiService.searchFunds(query);
        if (!mounted || _search.text.trim() != query) return;
        setState(() {
          _results = [
            for (final r in raw)
              if (r is Map)
                {
                  'code': '${r['schemeCode']}',
                  'name': '${r['schemeName']}',
                }
          ];
          _searching = false;
          _searchError = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searching = false;
          _searchError = 'Fund search failed. Check your connection and retry.';
        });
      }
    });
  }

  double? _parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim());

  /// Returns an error message, or null if the form is valid.
  String? _validate() {
    if (_fund == null) return 'Pick a fund first.';
    final amount = _parseNum(_amount.text);
    final units = _parseNum(_units.text);
    if (_type == 'REDEEM' && _redeemByUnits) {
      if (units == null || units <= 0) return 'Enter the number of units.';
    } else {
      if (amount == null || amount <= 0) return 'Enter an amount.';
      if (_type != 'REDEEM' && amount < _minAmount) {
        return 'Minimum amount is ${formatInr(_minAmount)}.';
      }
    }
    if (_type == 'SIP') {
      final n = int.tryParse(_installments.text.trim());
      if (n == null || n < 1 || n > 360) {
        return 'Installments must be between 1 and 360.';
      }
    }
    return null;
  }

  String _typeLabel() {
    switch (_type) {
      case 'SIP':
        return 'SIP';
      case 'REDEEM':
        return 'Redemption';
      default:
        return 'Purchase';
    }
  }

  Future<void> _review() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var consent = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: Brand.fern,
            title: const Text('Review order',
                style: TextStyle(color: Brand.paper)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Client', widget.client.fullName),
                  _summaryRow('Fund', _fund!['name']!),
                  _summaryRow('Type', _typeLabel()),
                  if (_type == 'REDEEM' && _redeemByUnits)
                    _summaryRow('Units', _units.text.trim())
                  else
                    _summaryRow(
                        _type == 'SIP' ? 'Monthly amount' : 'Amount',
                        formatInr(_parseNum(_amount.text) ?? 0)),
                  if (_type == 'SIP') ...[
                    _summaryRow('SIP day', 'Day $_sipDay of each month'),
                    _summaryRow('Installments', _installments.text.trim()),
                  ],
                  if (widget.mode == 'STUB')
                    _summaryRow('Mode', 'TEST - simulated, no real order'),
                  if (widget.mode == 'LIVE')
                    _summaryRow('Mode', 'LIVE - real order to NSE'),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Brand.gold,
                    checkColor: Brand.vault,
                    value: consent,
                    onChanged: (v) => setLocal(() => consent = v ?? false),
                    title: const Text(
                      'The client has authorised this order and has been '
                      'given the scheme documents and commission disclosure.',
                      style: TextStyle(color: Brand.mint, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Back')),
              TextButton(
                onPressed: consent ? () => Navigator.pop(ctx, true) : null,
                child: Text('Confirm & place',
                    style: TextStyle(
                        color: consent
                            ? Brand.gold
                            : Brand.mint.withValues(alpha: 0.4),
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true) await _place();
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Brand.paper, fontSize: 13)),
            ),
          ],
        ),
      );

  Future<void> _place() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final byUnits = _type == 'REDEEM' && _redeemByUnits;
      final order = await OrdersApiService.placeOrder(
        widget.ownerEmail,
        widget.client.id!,
        schemeCode: _fund!['code']!,
        schemeName: _fund!['name']!,
        orderType: _type,
        amount: byUnits ? null : _parseNum(_amount.text),
        units: byUnits ? _parseNum(_units.text) : null,
        sipDay: _type == 'SIP' ? _sipDay : null,
        sipInstallments:
            _type == 'SIP' ? int.tryParse(_installments.text.trim()) : null,
        idempotencyKey: _key,
      );
      if (mounted) Navigator.pop(context, order);
    } on CrmApiException catch (e) {
      // The server answered, so we know the order was NOT placed.
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    } catch (_) {
      // No answer (timeout / dropped connection): the order may or may not
      // exist. The key is unchanged, so pressing Review again is safe.
      if (!mounted) return;
      setState(() {
        _error = "Couldn't confirm whether the order was placed. Check the "
            'Orders tab first. If it is not listed there, you can safely '
            'try again - the same order cannot be placed twice.';
        _submitting = false;
      });
    }
  }

  InputDecoration _dec(String label, {String? hint, String? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      prefixStyle: const TextStyle(color: Brand.paper),
      labelStyle: const TextStyle(color: Brand.mint),
      hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Brand.fern.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Brand.gold, width: 1.5),
      ),
    );
  }

  Widget _box(Color colour, IconData icon, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _typeChip(String value, String label) {
    final selected = _type == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: Brand.gold,
        backgroundColor: Brand.fern.withValues(alpha: 0.4),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: selected ? Brand.vault : Brand.mint,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => setState(() {
          _type = value;
          _touch();
        }),
      ),
    );
  }

  Widget _fundPicker() {
    if (_fund != null) {
      final isDirect = _fund!['name']!.toLowerCase().contains('direct');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Brand.fern.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_fund!['name']!,
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _fund = null;
                    _touch();
                  }),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          if (isDirect) ...[
            const SizedBox(height: 8),
            _box(
              Brand.gold,
              Icons.info_outline,
              'This is a Direct plan. Distributors normally place Regular-plan '
              'orders - check this is intended.',
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          style: const TextStyle(color: Brand.paper),
          decoration: _dec('Search fund', hint: 'e.g. parag parikh flexi'),
          onChanged: _onSearchChanged,
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
                child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.gold))),
          ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_searchError!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ),
        if (!_searching &&
            _searchError == null &&
            _search.text.trim().length >= 3 &&
            _results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No funds found.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
          ),
        ..._results.map((r) => InkWell(
              onTap: () => setState(() {
                _fund = r;
                _results = [];
                _search.clear();
                _touch();
              }),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(r['name']!,
                    style: const TextStyle(color: Brand.paper, fontSize: 12.5)),
              ),
            )),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t,
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final byUnits = _type == 'REDEEM' && _redeemByUnits;
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('New order', style: TextStyle(color: Brand.gold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (widget.mode == 'STUB')
              _box(Brand.teal, Icons.science_outlined,
                  'TEST MODE - this order is simulated. Nothing is sent to NSE.'),
            if (widget.mode == 'LIVE')
              _box(Brand.red, Icons.bolt,
                  'LIVE - this order will be sent to NSE and is real.'),
            Text(widget.client.fullName,
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (!_kycValid)
              _box(
                Brand.red,
                Icons.block,
                'KYC status is ${widget.client.kycStatus.replaceAll('_', ' ')}. '
                'Orders can only be placed once KYC is validated or registered '
                '- update the client first.',
              ),
            _label('ORDER TYPE'),
            Row(children: [
              _typeChip('PURCHASE', 'Purchase'),
              _typeChip('SIP', 'SIP'),
              _typeChip('REDEEM', 'Redeem'),
            ]),
            const SizedBox(height: 12),
            _label('FUND'),
            _fundPicker(),
            const SizedBox(height: 16),
            _label('DETAILS'),
            if (_type == 'REDEEM')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Brand.gold,
                title: const Text('Redeem by units',
                    style: TextStyle(color: Brand.paper, fontSize: 14)),
                value: _redeemByUnits,
                onChanged: (v) => setState(() {
                  _redeemByUnits = v;
                  _touch();
                }),
              ),
            if (byUnits)
              TextField(
                controller: _units,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Units'),
                onChanged: (_) => setState(_touch),
              )
            else
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Brand.paper),
                decoration: _dec(
                    _type == 'SIP' ? 'Monthly amount' : 'Amount',
                    prefix: '₹ '),
                onChanged: (_) => setState(_touch),
              ),
            if (_type == 'SIP') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _sipDay,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('SIP day of month'),
                items: [
                  for (var d = 1; d <= 28; d++)
                    DropdownMenuItem(value: d, child: Text('Day $d')),
                ],
                onChanged: (v) => setState(() {
                  _sipDay = v ?? _sipDay;
                  _touch();
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _installments,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Number of installments', hint: '12'),
                onChanged: (_) => setState(_touch),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              _box(Brand.red, Icons.error_outline, _error!),
            ],
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_submitting || !_kycValid) ? null : _review,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.vault),
                    )
                  : const Text('Review order',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
