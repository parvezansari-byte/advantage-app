// lib/screens/crm_add_edit_client_screen.dart
//
// Add/edit a CRM client. Ported from the standalone advantage_crm app.

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/crm_api_service.dart';

class CrmAddEditClientScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient? existing; // null = add mode
  const CrmAddEditClientScreen(
      {super.key, required this.ownerEmail, this.existing});

  @override
  State<CrmAddEditClientScreen> createState() =>
      _CrmAddEditClientScreenState();
}

class _CrmAddEditClientScreenState extends State<CrmAddEditClientScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pan;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _dob;
  late final TextEditingController _nseCode;
  late final TextEditingController _notes;
  late String _kycStatus;
  String? _riskProfile;
  bool _saving = false;
  String? _error;

  static const _kycOptions = [
    'PENDING',
    'KYC_VALIDATED',
    'KYC_REGISTERED',
    'HOLD',
    'REJECTED'
  ];
  static const _riskOptions = ['CONSERVATIVE', 'MODERATE', 'AGGRESSIVE'];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.fullName ?? '');
    _pan = TextEditingController(text: e?.pan ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _dob = TextEditingController(text: e?.dateOfBirth ?? '');
    _nseCode = TextEditingController(text: e?.nseClientCode ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _kycStatus = e?.kycStatus ?? 'PENDING';
    _riskProfile = e?.riskProfile;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1930),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Brand.gold,
            surface: Brand.fern,
            onSurface: Brand.paper,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _dob.text = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = CrmClient(
      fullName: _name.text.trim(),
      pan: _pan.text.trim().toUpperCase(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      dateOfBirth: _dob.text.trim().isEmpty ? null : _dob.text.trim(),
      nseClientCode:
          _nseCode.text.trim().isEmpty ? null : _nseCode.text.trim(),
      kycStatus: _kycStatus,
      riskProfile: _riskProfile,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    try {
      if (_isEdit) {
        await CrmApiService.updateClient(
            widget.ownerEmail, widget.existing!.id!, client);
      } else {
        await CrmApiService.addClient(widget.ownerEmail, client);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Brand.mint),
      hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
      suffixIcon: suffixIcon,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: Text(_isEdit ? 'Edit client' : 'Add client',
            style: const TextStyle(color: Brand.gold)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Brand.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Brand.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Brand.red, fontSize: 13)),
                ),
              ],
              TextFormField(
                controller: _name,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Full name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pan,
                style: const TextStyle(color: Brand.paper),
                textCapitalization: TextCapitalization.characters,
                decoration: _dec('PAN *', hint: 'ABCDE1234F'),
                validator: (v) {
                  final val = (v ?? '').trim().toUpperCase();
                  if (val.isEmpty) return 'Required';
                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(val)) {
                    return 'Enter a valid 10-character PAN';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dob,
                readOnly: true,
                onTap: _pickDob,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec(
                  'Date of birth',
                  suffixIcon:
                      const Icon(Icons.calendar_today, color: Brand.mint, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nseCode,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('NSE client code'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _kycStatus,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('KYC status'),
                items: _kycOptions
                    .map((k) => DropdownMenuItem(
                        value: k, child: Text(k.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setState(() => _kycStatus = v ?? _kycStatus),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _riskProfile,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Risk profile'),
                items: _riskOptions
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setState(() => _riskProfile = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                style: const TextStyle(color: Brand.paper),
                decoration: _dec('Notes'),
              ),
              const SizedBox(height: 24),
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
                    : Text(_isEdit ? 'Save changes' : 'Add client',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
