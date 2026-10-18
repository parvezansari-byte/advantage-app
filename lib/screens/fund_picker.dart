// lib/screens/fund_picker.dart
//
// Search-as-you-type mutual fund picker. Shows a search box with results;
// once a fund is picked it shows a card with a "Change" button. The parent
// owns the selection ({'code': ..., 'name': ...}) and is told about changes.

import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/api_service.dart';

class FundPicker extends StatefulWidget {
  final Map<String, String>? selected;
  final ValueChanged<Map<String, String>?> onChanged;
  const FundPicker({super.key, required this.selected, required this.onChanged});

  @override
  State<FundPicker> createState() => _FundPickerState();
}

class _FundPickerState extends State<FundPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, String>> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 3) {
      setState(() {
        _results = [];
        _error = null;
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
                {'code': '${r['schemeCode']}', 'name': '${r['schemeName']}'}
          ];
          _searching = false;
          _error = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _searching = false;
          _error = 'Fund search failed. Check your connection and retry.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    if (sel != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(sel['name']!,
                  style: const TextStyle(
                      color: Brand.paper,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => widget.onChanged(null),
              child: const Text('Change'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          style: const TextStyle(color: Brand.paper),
          decoration: InputDecoration(
            labelText: 'Search fund',
            hintText: 'e.g. parag parikh flexi',
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
          ),
          onChanged: _onChanged,
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.gold)),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: const TextStyle(color: Brand.red, fontSize: 12)),
          ),
        if (!_searching &&
            _error == null &&
            _search.text.trim().length >= 3 &&
            _results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No funds found.',
                style: TextStyle(
                    color: Brand.mint.withValues(alpha: 0.7), fontSize: 12)),
          ),
        ..._results.map((r) => InkWell(
              onTap: () {
                setState(() {
                  _results = [];
                  _search.clear();
                });
                widget.onChanged(r);
              },
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
}
