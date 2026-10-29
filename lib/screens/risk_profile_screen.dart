// lib/screens/risk_profile_screen.dart
//
// Eight-question risk profile for a client. Questions and scoring come from
// the API (GET /risk/questions, POST /risk/score). "Save to client" writes the
// result into the client's Risk profile field and returns true.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/api_service.dart' show ApiService;
import '../services/authed_http.dart' as http;
import '../services/crm_api_service.dart';

class RiskProfileScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const RiskProfileScreen(
      {super.key, required this.ownerEmail, required this.client});

  @override
  State<RiskProfileScreen> createState() => _RiskProfileScreenState();
}

class _RiskProfileScreenState extends State<RiskProfileScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _questions = [];
  List<int?> _answers = [];
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/risk/questions'))
          .timeout(const Duration(seconds: 60));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final q = (j['questions'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _questions = q;
        _answers = List<int?>.filled(q.length, null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the questions. $e';
        _loading = false;
      });
    }
  }

  bool get _complete => _answers.isNotEmpty && !_answers.contains(null);

  Future<void> _score() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(Uri.parse('${ApiService.baseUrl}/risk/score'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'answers': _answers.map((a) => a!).toList()}))
          .timeout(const Duration(seconds: 60));
      final j = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception(j is Map ? (j['detail'] ?? res.body) : res.body);
      }
      if (!mounted) return;
      setState(() {
        _result = Map<String, dynamic>.from(j as Map);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    final c = widget.client;
    setState(() => _busy = true);
    try {
      await CrmApiService.updateClient(
        widget.ownerEmail,
        c.id!,
        CrmClient(
          id: c.id,
          fullName: c.fullName,
          pan: c.pan,
          email: c.email,
          phone: c.phone,
          dateOfBirth: c.dateOfBirth,
          nseClientCode: c.nseClientCode,
          kycStatus: c.kycStatus,
          riskProfile: '${_result!['profile']}',
          notes: c.notes,
          createdAt: c.createdAt,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: Text('Risk profile: ${widget.client.fullName}',
            style: const TextStyle(
                color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? 'No questions',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.red)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _loadQuestions, child: const Text('Try again')),
          ]),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (var i = 0; i < _questions.length; i++) _question(i),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Brand.gold, foregroundColor: Brand.vault),
          onPressed: (_complete && !_busy) ? _score : null,
          child: Text(_complete ? 'See profile' : 'Answer all questions'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Brand.red)),
          ),
        if (_result != null) ..._resultWidgets(_result!),
      ],
    );
  }

  Widget _question(int i) {
    final q = _questions[i];
    final options = (q['options'] as List).map((e) => '$e').toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${i + 1}. ${q['text']}',
            style: const TextStyle(
                color: Brand.paper, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (var k = 0; k < options.length; k++)
            ChoiceChip(
              label: Text(options[k], style: const TextStyle(fontSize: 12)),
              selected: _answers[i] == k + 1,
              selectedColor: Brand.gold,
              onSelected: (_) => setState(() {
                _answers[i] = k + 1;
                _result = null;
              }),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _resultWidgets(Map<String, dynamic> r) {
    final mix = Map<String, dynamic>.from(r['mix'] as Map);
    final adjusted = ((r['adjusted'] as List?) ?? []).map((e) => '$e').toList();
    final current = widget.client.riskProfile;
    return [
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['label']}',
              style: const TextStyle(
                  color: Brand.gold, fontSize: 26, fontWeight: FontWeight.bold)),
          Text('Score ${r['score']} of ${r['max_score']}',
              style: const TextStyle(color: Brand.mint, fontSize: 12)),
          const SizedBox(height: 10),
          const Text('Starting mix',
              style: TextStyle(color: Brand.mint, fontSize: 12)),
          Text(
              'Equity ${mix['equity']}%  ·  Hybrid ${mix['hybrid']}%  ·  Debt ${mix['debt']}%',
              style: const TextStyle(color: Brand.paper, fontSize: 14)),
          for (final a in adjusted)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(a,
                  style: const TextStyle(color: Brand.gold, fontSize: 12)),
            ),
          if (current != null && current.isNotEmpty && current != r['profile'])
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Saved profile today: $current',
                  style: const TextStyle(color: Brand.mint, fontSize: 12)),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Brand.green, foregroundColor: Brand.vault),
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save to client'),
      ),
      const SizedBox(height: 8),
      Text('${r['note'] ?? ''}',
          style: TextStyle(
              color: Brand.mint.withValues(alpha: 0.7), fontSize: 11)),
    ];
  }
}
