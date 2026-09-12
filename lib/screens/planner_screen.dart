// lib/screens/planner_screen.dart
//
// Financial planner — same logic as the web platform:
//   • 6-question risk profile (0-6 score → Conservative/Moderate/Aggressive)
//   • goal-based SIP calculation
//   • suggested asset allocation
//
// The maths runs entirely on-device (no server needed), so it's instant.

import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  // Each question: index 2 (last option) signals highest risk tolerance.
  final _questions = const [
    ('Your age group', ['Above 50', '35 to 50', 'Under 35']),
    ('When will you need this money?',
        ['Within 3 years', '3 to 7 years', 'After 7 years']),
    ('How stable is your income?',
        ['Not very stable', 'Fairly stable', 'Very stable']),
    ('If your investment fell 20% in a month, you would…',
        ['Sell to stop losses', 'Wait and watch', 'Stay calm or invest more']),
    ('Your investing experience',
        ['New to investing', 'Some experience', 'Experienced']),
    ('What matters more to you?',
        ['Protecting my money', 'Balance of both', 'Maximising growth']),
  ];

  // selected option index per question (default middle)
  late List<int> _answers = List.filled(6, 1);

  double _target = 1000000; // ₹10 lakh default
  double _years = 10;

  bool _showPlan = false;

  // ---- scoring (mirrors the web app exactly) ----
  int get _score {
    int s = 0;
    // age: "Under 35" (index 2)
    if (_answers[0] == 2) s++;
    // horizon: "After 7 years" (index 2)
    if (_answers[1] == 2) s++;
    // income: "Very stable" (index 2)
    if (_answers[2] == 2) s++;
    // reaction: "Stay calm or invest more" (index 2)
    if (_answers[3] == 2) s++;
    // experience: "Some experience" or "Experienced" (index 1 or 2)
    if (_answers[4] >= 1) s++;
    // priority: "Maximising growth" (index 2)
    if (_answers[5] == 2) s++;
    return s;
  }

  String get _profile {
    final s = _score;
    if (s <= 2) return 'Conservative';
    if (s <= 4) return 'Moderate';
    return 'Aggressive';
  }

  Map<String, int> get _allocation {
    switch (_profile) {
      case 'Conservative':
        return {'Equity': 30, 'Debt': 60, 'Gold': 10};
      case 'Aggressive':
        return {'Equity': 75, 'Debt': 15, 'Gold': 10};
      default:
        return {'Equity': 55, 'Debt': 35, 'Gold': 10};
    }
  }

  /// Expected annual return assumption by profile (same as web).
  double get _expectedReturn {
    switch (_profile) {
      case 'Conservative':
        return 9;
      case 'Aggressive':
        return 13;
      default:
        return 11;
    }
  }

  /// Monthly SIP needed to reach target — same annuity formula as the web app.
  double get _sipNeeded {
    final months = _years * 12;
    final r = (_expectedReturn / 100) / 12;
    if (months <= 0) return 0;
    if (r == 0) return _target / months;
    return _target * r / (pow(1 + r, months) - 1);
  }

  String _inr(double x) {
    if (x >= 10000000) return '₹${(x / 10000000).toStringAsFixed(2)} Cr';
    if (x >= 100000) return '₹${(x / 100000).toStringAsFixed(2)} L';
    final s = x.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₹$buf';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Financial Planner',
              style: TextStyle(
                  color: Brand.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Find your risk profile and a goal-based plan',
              style: TextStyle(color: Brand.mint, fontSize: 13)),
          const SizedBox(height: 20),

          // ---- Step 1: risk questions ----
          _stepLabel('STEP 1 · YOUR RISK PROFILE'),
          ...List.generate(_questions.length, (i) => _questionCard(i)),
          const SizedBox(height: 8),

          // live profile result
          Card(
            color: Brand.gold.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_score / 6',
                          style: const TextStyle(
                              color: Brand.gold,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const Text('Risk score',
                          style:
                              TextStyle(color: Brand.mint, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_profile,
                            style: const TextStyle(
                                color: Brand.paper,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          _allocation.entries
                              .map((e) => '${e.key} ${e.value}%')
                              .join('  ·  '),
                          style: const TextStyle(
                              color: Brand.mint, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Step 2: goal ----
          _stepLabel('STEP 2 · YOUR GOAL'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Target amount: ${_inr(_target)}',
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Slider(
                    value: _target,
                    min: 100000,
                    max: 50000000,
                    divisions: 100,
                    activeColor: Brand.gold,
                    label: _inr(_target),
                    onChanged: (v) => setState(() => _target = v),
                  ),
                  const SizedBox(height: 8),
                  Text('Time horizon: ${_years.round()} years',
                      style: const TextStyle(
                          color: Brand.paper,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Slider(
                    value: _years,
                    min: 1,
                    max: 40,
                    divisions: 39,
                    activeColor: Brand.gold,
                    label: '${_years.round()} yr',
                    onChanged: (v) => setState(() => _years = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Step 3: the plan ----
          _stepLabel('STEP 3 · YOUR PLAN'),
          Card(
            color: Brand.fern.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Monthly SIP needed',
                      style: TextStyle(color: Brand.mint, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    _inr(_sipNeeded),
                    style: const TextStyle(
                        color: Brand.gold,
                        fontSize: 38,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'to reach ${_inr(_target)} in ${_years.round()} years\n'
                    'assuming ~${_expectedReturn.round()}% annual return '
                    '(${_profile.toLowerCase()} portfolio)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Brand.mint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Estimates only, based on assumed returns — not guaranteed and not '
            'investment advice. Actual returns vary. Consider a SEBI-registered '
            'advisor for personal planning.',
            style: TextStyle(
                color: Brand.mint.withValues(alpha: 0.5), fontSize: 11),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _stepLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(s,
            style: const TextStyle(
                color: Brand.gold,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold)),
      );

  Widget _questionCard(int i) {
    final (question, options) = _questions[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i + 1}. $question',
                style: const TextStyle(
                    color: Brand.paper,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(options.length, (j) {
                final selected = _answers[i] == j;
                return GestureDetector(
                  onTap: () => setState(() => _answers[i] = j),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? Brand.gold
                          : Brand.vault.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? Brand.gold
                            : Brand.mint.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      options[j],
                      style: TextStyle(
                        color: selected ? Brand.vault : Brand.mint,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
