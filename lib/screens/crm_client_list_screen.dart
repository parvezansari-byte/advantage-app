// lib/screens/crm_client_list_screen.dart
//
// Client book entry point. Ported from the standalone advantage_crm app —
// the only change is that it's handed the already-logged-in email instead
// of asking for one on a separate "identify" screen, since the main
// Advantage app already knows who's signed in.

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/crm_client.dart';
import '../services/crm_api_service.dart';
import 'crm_add_edit_client_screen.dart';
import 'crm_client_detail_screen.dart';

class CrmClientListScreen extends StatefulWidget {
  final String ownerEmail;
  const CrmClientListScreen({super.key, required this.ownerEmail});

  @override
  State<CrmClientListScreen> createState() => _CrmClientListScreenState();
}

class _CrmClientListScreenState extends State<CrmClientListScreen> {
  List<CrmClient> _clients = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _search = '';

  static const _avatarColors = [
    Brand.gold,
    Brand.blue,
    Brand.purple,
    Brand.teal,
    Brand.green
  ];

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
      final clients =
          await CrmApiService.listClients(widget.ownerEmail, search: _search);
      setState(() {
        _clients = clients;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _avatarColor(String pan) =>
      _avatarColors[pan.hashCode.abs() % _avatarColors.length];

  Color _kycColor(String status) {
    switch (status.toUpperCase()) {
      case 'KYC_VALIDATED':
      case 'KYC_REGISTERED':
        return Brand.green;
      case 'HOLD':
      case 'REJECTED':
        return Brand.red;
      default:
        return Brand.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        foregroundColor: Brand.paper,
        title: const Text('Clients',
            style: TextStyle(color: Brand.gold, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Brand.mint),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.gold,
        foregroundColor: Brand.vault,
        onPressed: () async {
          final added = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CrmAddEditClientScreen(ownerEmail: widget.ownerEmail),
            ),
          );
          if (added == true) _load();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add client'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Brand.paper),
                decoration: InputDecoration(
                  hintText: 'Search by name, PAN, or email',
                  hintStyle: TextStyle(
                      color: Brand.mint.withValues(alpha: 0.6), fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Brand.mint),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, color: Brand.mint),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                            _load();
                          },
                        ),
                  filled: true,
                  fillColor: Brand.fern.withValues(alpha: 0.4),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (v) {
                  setState(() => _search = v.trim());
                  _load();
                },
              ),
            ),
            _SummaryStrip(clients: _clients),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Brand.gold));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Brand.red, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Brand.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Brand.gold, foregroundColor: Brand.vault),
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, color: Brand.mint, size: 48),
              const SizedBox(height: 12),
              const Text(
                'No clients yet',
                style: TextStyle(
                    color: Brand.paper,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap "Add client" to build your book.',
                style: TextStyle(color: Brand.mint, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.gold,
      backgroundColor: Brand.fern,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = _clients[i];
          return _ClientTile(
            client: c,
            avatarColor: _avatarColor(c.pan),
            kycColor: _kycColor(c.kycStatus),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CrmClientDetailScreen(
                      ownerEmail: widget.ownerEmail, client: c),
                ),
              );
              _load();
            },
          );
        },
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<CrmClient> clients;
  const _SummaryStrip({required this.clients});

  @override
  Widget build(BuildContext context) {
    final total = clients.length;
    final kycDone = clients
        .where((c) =>
            c.kycStatus.toUpperCase() == 'KYC_VALIDATED' ||
            c.kycStatus.toUpperCase() == 'KYC_REGISTERED')
        .length;
    final pending = total - kycDone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(child: _statChip('Total', '$total', Brand.gold)),
          const SizedBox(width: 8),
          Expanded(child: _statChip('KYC done', '$kycDone', Brand.green)),
          const SizedBox(width: 8),
          Expanded(child: _statChip('Pending', '$pending', Brand.red)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Brand.fern.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Brand.mint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  final CrmClient client;
  final Color avatarColor;
  final Color kycColor;
  final VoidCallback onTap;

  const _ClientTile({
    required this.client,
    required this.avatarColor,
    required this.kycColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.fern.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Brand.gold.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: avatarColor.withValues(alpha: 0.25),
                child: Text(
                  client.initials,
                  style:
                      TextStyle(color: avatarColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName,
                      style: const TextStyle(
                          color: Brand.paper,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.pan,
                      style: const TextStyle(
                          color: Brand.mint, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kycColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kycColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  client.kycStatus.replaceAll('_', ' '),
                  style: TextStyle(
                      color: kycColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Brand.mint),
            ],
          ),
        ),
      ),
    );
  }
}
