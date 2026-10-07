// lib/screens/crm_client_detail_screen.dart
//
// Client profile / notes / holdings. Ported from the standalone
// advantage_crm app. Date and currency formatting is hand-rolled rather
// than using the `intl` package, to match the rest of the Advantage app
// (which doesn't depend on intl) instead of adding a new dependency for
// this one screen.

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/crm_api_service.dart';
import 'crm_add_edit_client_screen.dart';
import 'crm_orders_tab.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _fmtDateTime(String? iso) {
  if (iso == null) return '';
  try {
    final d = DateTime.parse(iso).toLocal();
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $hour12:$minute $ampm';
  } catch (_) {
    return iso;
  }
}

/// Indian-digit-grouped rupee amount, no decimals — matches the style used
/// elsewhere in the app (chart/options screens) instead of pulling in intl.
String _inr(num value) {
  final n = value.round();
  final s = n.abs().toString();
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
  return '${n < 0 ? '-' : ''}₹$grouped';
}

class CrmClientDetailScreen extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const CrmClientDetailScreen(
      {super.key, required this.ownerEmail, required this.client});

  @override
  State<CrmClientDetailScreen> createState() => _CrmClientDetailScreenState();
}

class _CrmClientDetailScreenState extends State<CrmClientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late CrmClient _client;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CrmAddEditClientScreen(
            ownerEmail: widget.ownerEmail, existing: _client),
      ),
    );
    if (changed == true) {
      final refreshed =
          await CrmApiService.getClient(widget.ownerEmail, _client.id!);
      setState(() => _client = refreshed);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.fern,
        title: const Text('Delete client?', style: TextStyle(color: Brand.paper)),
        content: Text(
          'This removes ${_client.fullName} and all their notes and holdings. This cannot be undone.',
          style: const TextStyle(color: Brand.mint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Brand.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await CrmApiService.deleteClient(widget.ownerEmail, _client.id!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: Text(_client.fullName,
            style: const TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.edit_outlined, color: Brand.mint),
              onPressed: _edit),
          IconButton(
              icon: const Icon(Icons.delete_outline, color: Brand.red),
              onPressed: _delete),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Brand.gold,
          labelColor: Brand.gold,
          unselectedLabelColor: Brand.mint,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Notes'),
            Tab(text: 'Holdings'),
            Tab(text: 'Orders'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ProfileTab(client: _client),
          _NotesTab(ownerEmail: widget.ownerEmail, client: _client),
          _HoldingsTab(ownerEmail: widget.ownerEmail, client: _client),
          CrmOrdersTab(ownerEmail: widget.ownerEmail, client: _client),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final CrmClient client;
  const _ProfileTab({required this.client});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard([
          _row('PAN', client.pan),
          _row('Email', client.email ?? '—'),
          _row('Phone', client.phone ?? '—'),
          _row('Date of birth', client.dateOfBirth ?? '—'),
        ]),
        const SizedBox(height: 12),
        _infoCard([
          _row('KYC status', client.kycStatus.replaceAll('_', ' ')),
          _row('Risk profile', client.riskProfile ?? '—'),
          _row('NSE client code', client.nseClientCode ?? 'Not registered yet'),
        ]),
        if ((client.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoCard([
            const Text('Notes',
                style: TextStyle(
                    color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Text(client.notes!, style: const TextStyle(color: Brand.paper, fontSize: 14)),
          ]),
        ],
      ],
    );
  }

  Widget _infoCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.fern.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(label, style: const TextStyle(color: Brand.mint, fontSize: 13))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Brand.paper, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

class _NotesTab extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const _NotesTab({required this.ownerEmail, required this.client});

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  List<CrmInteraction> _notes = [];
  bool _loading = true;
  String? _error;
  final _noteController = TextEditingController();
  bool _adding = false;

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
      final notes =
          await CrmApiService.listInteractions(widget.ownerEmail, widget.client.id!);
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    try {
      await CrmApiService.addInteraction(widget.ownerEmail, widget.client.id!, text);
      _noteController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add note: $e'), backgroundColor: Brand.red),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Brand.gold))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Brand.red)))
                  : _notes.isEmpty
                      ? const Center(
                          child: Text('No notes yet — log a call or meeting below.',
                              style: TextStyle(color: Brand.mint)),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: Brand.gold,
                          backgroundColor: Brand.fern,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _notes.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final n = _notes[i];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Brand.fern.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(n.note, style: const TextStyle(color: Brand.paper, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    Text(_fmtDateTime(n.createdAt),
                                        style: const TextStyle(color: Brand.mint, fontSize: 11)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    style: const TextStyle(color: Brand.paper),
                    decoration: InputDecoration(
                      hintText: 'Log a call, meeting, or reminder…',
                      hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5), fontSize: 13),
                      filled: true,
                      fillColor: Brand.fern.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _adding ? null : _addNote,
                  style: IconButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.vault),
                  icon: _adding
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Brand.vault),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HoldingsTab extends StatefulWidget {
  final String ownerEmail;
  final CrmClient client;
  const _HoldingsTab({required this.ownerEmail, required this.client});

  @override
  State<_HoldingsTab> createState() => _HoldingsTabState();
}

class _HoldingsTabState extends State<_HoldingsTab> {
  List<CrmHolding> _holdings = [];
  double _total = 0;
  String? _lastFetched;
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
      final (holdings, total, lastFetched) =
          await CrmApiService.getHoldings(widget.ownerEmail, widget.client.id!);
      setState(() {
        _holdings = holdings;
        _total = total;
        _lastFetched = lastFetched;
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Brand.red)));
    }
    if (_holdings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.pie_chart_outline, color: Brand.mint, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No holdings synced yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.paper, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Once this client is registered on NSE and the portfolio sync is set up, '
              'their mutual fund holdings will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.mint, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
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
                const Text('Total portfolio value', style: TextStyle(color: Brand.mint, fontSize: 12)),
                const SizedBox(height: 4),
                Text(_inr(_total),
                    style: const TextStyle(color: Brand.gold, fontSize: 26, fontWeight: FontWeight.bold)),
                if (_lastFetched != null) ...[
                  const SizedBox(height: 6),
                  Text('As of $_lastFetched', style: const TextStyle(color: Brand.mint, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._holdings.map((h) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brand.fern.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Brand.gold.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.schemeName,
                              style: const TextStyle(
                                  color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('${h.units} units · NAV ₹${h.nav}',
                              style: const TextStyle(color: Brand.mint, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text(_inr(h.currentValue),
                        style: const TextStyle(color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
