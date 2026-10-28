// lib/screens/crm_add_holding_screen.dart
//
// Record (or correct) a holding for a client: fund, units and average buy
// NAV, plus an optional folio number. Adding a fund the client already holds
// merges the new units into the existing line with a weighted-average NAV.
// Editing changes the existing line as-is and can delete it.

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/crm_api_service.dart' show CrmApiException;
import '../services/holdings_api_service.dart';
import 'crm_holdings_tab.dart' show formatUnits;
import 'crm_orders_tab.dart' show formatInr;
import 'fund_picker.dart';

class CrmAddHoldingScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  final ManualHolding? existing; // null = add mode
  const CrmAddHoldingScreen(
      {super.key,
      required this.ownerEmail,
      required this.client,
      this.existing});

  @override
  State<CrmAddHoldingScreen> createState() => _CrmAddHoldingScreenState();
}

class _CrmAddHoldingScreenState extends State<CrmAddHoldingScreen> {
  Map<String, String>? _fund;
  final _units = TextEditingController();
  final _nav = TextEditingController();
  final _folio = TextEditingController();
  DateTime? _buyDate;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _fund = {'code': e.schemeCode, 'name': e.schemeName};
      _units.text = formatUnits(e.units);
      _nav.text = e.avgNav.toString();
      _folio.text = e.folioNumber;
      _buyDate = e.buyDate == null ? null : DateTime.tryParse(e.buyDate!);
    }
  }

  @override
  void dispose() {
    _units.dispose();
    _nav.dispose();
    _folio.dispose();
    super.dispose();
  }

  String? _iso(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _buyDate ?? DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (d != null) setState(() => _buyDate = d);
  }

  double? _parse(String s) => double.tryParse(s.replaceAll(',', '').trim());

  Future<void> _save() async {
    if (_fund == null) {
      setState(() => _error = 'Pick a fund first.');
      return;
    }
    final units = _parse(_units.text);
    final nav = _parse(_nav.text);
    if (units == null || units <= 0) {
      setState(() => _error = 'Enter the number of units.');
      return;
    }
    if (nav == null || nav <= 0) {
      setState(() => _error = 'Enter the average buy NAV per unit.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final folio = _folio.text.trim();
      if (_isEdit) {
        await HoldingsApiService.updateHolding(
            widget.ownerEmail, widget.existing!.id,
            units: units,
            avgNav: nav,
            folioNumber: folio,
            buyDate: _iso(_buyDate),
            clearBuyDate: _buyDate == null && widget.existing!.buyDate != null);
      } else {
        await HoldingsApiService.addHolding(
          widget.ownerEmail,
          widget.client.id!,
          schemeCode: _fund!['code']!,
          schemeName: _fund!['name']!,
          units: units,
          avgNav: nav,
          folioNumber: folio.isEmpty ? null : folio,
          buyDate: _iso(_buyDate),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on CrmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the server. Check your connection and retry.";
        _saving = false;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.fern,
        title: const Text('Remove this holding?',
            style: TextStyle(color: Brand.paper)),
        content: Text(widget.existing!.schemeName,
            style: const TextStyle(color: Brand.mint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Brand.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await HoldingsApiService.deleteHolding(
          widget.ownerEmail, widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
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
    final units = _parse(_units.text);
    final nav = _parse(_nav.text);
    final invested = (units != null && nav != null && units > 0 && nav > 0)
        ? units * nav
        : null;
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: Text(_isEdit ? 'Edit holding' : 'Add holding',
            style: const TextStyle(color: Brand.gold)),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Brand.red),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(widget.client.fullName,
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _label('FUND'),
            if (_isEdit)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_fund!['name']!,
                    style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              )
            else
              FundPicker(
                selected: _fund,
                onChanged: (f) => setState(() {
                  _fund = f;
                  _error = null;
                }),
              ),
            const SizedBox(height: 16),
            _label('DETAILS'),
            TextField(
              controller: _units,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Brand.paper),
              decoration: _dec(_isEdit ? 'Units held' : 'Units'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nav,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Brand.paper),
              decoration: _dec('Average buy NAV (per unit)', prefix: '₹ '),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folio,
              style: const TextStyle(color: Brand.paper),
              decoration: _dec('Folio number (optional)'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event, color: Brand.gold),
                  label: Text(
                      _buyDate == null
                          ? 'Purchase date (optional)'
                          : 'Bought ${_buyDate!.day.toString().padLeft(2, '0')}-${_buyDate!.month.toString().padLeft(2, '0')}-${_buyDate!.year}',
                      style: const TextStyle(color: Brand.gold)),
                ),
              ),
              if (_buyDate != null)
                IconButton(
                  tooltip: 'Clear date',
                  icon: const Icon(Icons.close, color: Brand.mint),
                  onPressed: () => setState(() => _buyDate = null),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'With a date, the portfolio review can compare yearly returns with the benchmark.',
                style: TextStyle(color: Brand.mint.withValues(alpha: 0.7), fontSize: 11.5),
              ),
            ),
            if (invested != null) ...[
              const SizedBox(height: 12),
              Text('Invested value: ${formatInr(invested)}',
                  style: const TextStyle(color: Brand.gold, fontSize: 13)),
            ],
            if (!_isEdit) ...[
              const SizedBox(height: 10),
              Text(
                'If the client already holds this fund, these units are added '
                'to the existing line and the average NAV is recalculated. If both '
                'purchases have dates, the line keeps their average, weighted by amount.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.3),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Brand.red.withValues(alpha: 0.4)),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Brand.red, fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Brand.gold,
                foregroundColor: Brand.vault,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.vault),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Add holding',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
