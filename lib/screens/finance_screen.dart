// finance_screen.dart
//
// Three tabs: Daily Spending (with categories), Loans & Debt, Pending Dues.
// Written with plain Material widgets + Theme colors so it drops in cleanly -
// swap in your shared Brand/AppColors constants for visual consistency with
// the rest of the app if you have one (matches the same note as tax_screen.dart).

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, required this.userEmail});

  final String userEmail;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Tracker'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Spending'),
            Tab(text: 'Loans & Debt'),
            Tab(text: 'Pending Dues'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SpendingTab(userEmail: widget.userEmail),
          _LoansTab(userEmail: widget.userEmail),
          _PendingTab(userEmail: widget.userEmail),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 1 — DAILY SPENDING
// =============================================================================
class _SpendingTab extends StatefulWidget {
  const _SpendingTab({required this.userEmail});
  final String userEmail;

  @override
  State<_SpendingTab> createState() => _SpendingTabState();
}

class _SpendingTabState extends State<_SpendingTab> {
  Map<String, dynamic>? _summary;
  List<dynamic> _expenses = [];
  List<String> _categories = [];
  bool _loading = true;
  String? _error;
  String _selectedMonth = _currentMonth();

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

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
      final results = await Future.wait([
        ApiService.getExpenseSummary(widget.userEmail, month: _selectedMonth),
        ApiService.getExpenses(widget.userEmail, month: _selectedMonth),
        ApiService.getCategories(widget.userEmail),
      ]);
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _expenses = results[1] as List<dynamic>;
        _categories = results[2] as List<String>;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showAddExpenseSheet() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? category = _categories.isNotEmpty ? _categories.first : null;
    DateTime expenseDate = DateTime.now();
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add Expense',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    ..._categories.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c))),
                    const DropdownMenuItem(
                        value: '__new__', child: Text('+ Add new category')),
                  ],
                  onChanged: (v) async {
                    if (v == '__new__') {
                      final newCat = await _promptNewCategory(ctx);
                      if (newCat != null && newCat.isNotEmpty) {
                        await ApiService.addCategory(widget.userEmail, newCat);
                        setSheetState(() {
                          _categories.add(newCat);
                          category = newCat;
                        });
                      }
                    } else {
                      setSheetState(() => category = v);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(
                      '${expenseDate.year}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: expenseDate,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setSheetState(() => expenseDate = picked);
                    }
                  },
                ),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amt = double.tryParse(amountCtrl.text.trim());
                          if (amt == null || amt <= 0 || category == null) {
                            setSheetState(
                                () => error = 'Enter a valid amount and category');
                            return;
                          }
                          setSheetState(() => saving = true);
                          try {
                            await ApiService.addExpense(
                              widget.userEmail,
                              amount: amt,
                              category: category!,
                              description: descCtrl.text.trim().isEmpty
                                  ? null
                                  : descCtrl.text.trim(),
                              expenseDate:
                                  '${expenseDate.year}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}',
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                          } catch (e) {
                            setSheetState(() => error = e.toString());
                          } finally {
                            setSheetState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Expense'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<String?> _promptNewCategory(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'e.g. Pet Care')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseSheet,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (_summary != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total spent (${_summary!['month']}): ₹${_summary!['total_spent']}',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Average daily spend: ₹${_summary!['average_daily_spend']}'),
                              Text('Transactions: ${_summary!['transaction_count']}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('By Category',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...(_summary!['category_breakdown'] as List<dynamic>)
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(c['category']),
                                        Text('₹${c['amount']} (${c['percent']}%)'),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                        value: (c['percent'] as num) / 100),
                                  ],
                                ),
                              )),
                      const SizedBox(height: 16),
                    ],
                    const Text('Recent Transactions',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._expenses.map((e) => Dismissible(
                          key: ValueKey(e['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              child: const Icon(Icons.delete, color: Colors.white)),
                          onDismissed: (_) async {
                            await ApiService.deleteExpense(
                                widget.userEmail, e['id'] as int);
                          },
                          child: Card(
                            child: ListTile(
                              title: Text(e['category']),
                              subtitle: Text(e['description'] ?? e['expense_date']),
                              trailing: Text('₹${e['amount']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        )),
                  ],
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// TAB 2 — LOANS & DEBT
// =============================================================================
class _LoansTab extends StatefulWidget {
  const _LoansTab({required this.userEmail});
  final String userEmail;

  @override
  State<_LoansTab> createState() => _LoansTabState();
}

class _LoansTabState extends State<_LoansTab> {
  Map<String, dynamic>? _data;
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
      final data = await ApiService.getLoans(widget.userEmail);
      setState(() => _data = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showAddLoanSheet() async {
    final nameCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final tenureCtrl = TextEditingController();
    String loanType = 'PERSONAL';
    DateTime startDate = DateTime.now();
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add Loan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Loan name', hintText: 'e.g. Home Loan - SBI'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: loanType,
                  decoration: const InputDecoration(labelText: 'Loan type'),
                  items: const [
                    DropdownMenuItem(value: 'PERSONAL', child: Text('Personal')),
                    DropdownMenuItem(value: 'HOME', child: Text('Home')),
                    DropdownMenuItem(value: 'CAR', child: Text('Car')),
                    DropdownMenuItem(value: 'EDUCATION', child: Text('Education')),
                    DropdownMenuItem(value: 'CREDIT_CARD', child: Text('Credit Card')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: (v) => setSheetState(() => loanType = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: principalCtrl,
                  decoration: const InputDecoration(labelText: 'Principal amount (₹)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rateCtrl,
                  decoration: const InputDecoration(labelText: 'Annual interest rate (%)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tenureCtrl,
                  decoration: const InputDecoration(labelText: 'Tenure (months)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  subtitle: Text(
                      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: startDate,
                      firstDate: DateTime(2010),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setSheetState(() => startDate = picked);
                  },
                ),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final principal = double.tryParse(principalCtrl.text.trim());
                          final rate = double.tryParse(rateCtrl.text.trim());
                          final tenure = int.tryParse(tenureCtrl.text.trim());
                          if (nameCtrl.text.trim().isEmpty ||
                              principal == null || principal <= 0 ||
                              rate == null || rate < 0 ||
                              tenure == null || tenure <= 0) {
                            setSheetState(() => error = 'Fill in all fields with valid numbers');
                            return;
                          }
                          setSheetState(() => saving = true);
                          try {
                            await ApiService.addLoan(
                              widget.userEmail,
                              loanName: nameCtrl.text.trim(),
                              loanType: loanType,
                              principal: principal,
                              annualInterestRate: rate,
                              tenureMonths: tenure,
                              startDate:
                                  '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                          } catch (e) {
                            setSheetState(() => error = e.toString());
                          } finally {
                            setSheetState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Loan'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLoanSheet,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (_data != null) ...[
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Total Outstanding Debt: ₹${_data!['total_outstanding_debt']}',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Monthly EMI total: ₹${_data!['total_monthly_emi']}'),
                              Text('Active loans: ${_data!['active_loan_count']}  ·  Paid off: ${_data!['paid_off_count']}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...(_data!['loans'] as List<dynamic>).map((loan) {
                        final progress = (loan['months_elapsed'] as num) /
                            (loan['tenure_months'] as num).clamp(1, double.infinity);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(loan['loan_name'],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 15)),
                                    if (loan['is_paid_off'] == true)
                                      const Chip(label: Text('Paid off')),
                                  ],
                                ),
                                Text('${loan['loan_type']} · ${loan['annual_interest_rate']}% p.a.',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 8),
                                Text('EMI: ₹${loan['emi']}/month'),
                                Text('Outstanding: ₹${loan['outstanding_balance']}'),
                                Text('${loan['months_remaining']} months remaining'),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(value: progress.toDouble()),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// TAB 3 — PENDING DUES
// =============================================================================
class _PendingTab extends StatefulWidget {
  const _PendingTab({required this.userEmail});
  final String userEmail;

  @override
  State<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<_PendingTab> {
  List<dynamic> _pending = [];
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
      final data = await ApiService.getPendingPayments(widget.userEmail);
      setState(() => _pending = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  double get _totalPending =>
      _pending.fold(0.0, (sum, p) => sum + (p['amount'] as num).toDouble());

  Future<void> _showAddDueSheet() async {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    DateTime dueDate = DateTime.now();
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add Pending Due',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Description', hintText: 'e.g. Electricity bill'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Category (optional)'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                      '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dueDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setSheetState(() => dueDate = picked);
                  },
                ),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amt = double.tryParse(amountCtrl.text.trim());
                          if (descCtrl.text.trim().isEmpty || amt == null || amt <= 0) {
                            setSheetState(
                                () => error = 'Enter a valid description and amount');
                            return;
                          }
                          setSheetState(() => saving = true);
                          try {
                            await ApiService.addPendingPayment(
                              widget.userEmail,
                              description: descCtrl.text.trim(),
                              amount: amt,
                              dueDate:
                                  '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
                              category: categoryCtrl.text.trim().isEmpty
                                  ? null
                                  : categoryCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                          } catch (e) {
                            setSheetState(() => error = e.toString());
                          } finally {
                            setSheetState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Due'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDueSheet,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            'Total Pending: ₹${_totalPending.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._pending.map((p) => Card(
                          child: ListTile(
                            title: Text(p['description']),
                            subtitle: Text(
                                'Due ${p['due_date']}${p['category'] != null ? ' · ${p['category']}' : ''}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('₹${p['amount']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Colors.green),
                                  tooltip: 'Mark as paid',
                                  onPressed: () async {
                                    await ApiService.markPaymentPaid(
                                        widget.userEmail, p['id'] as int);
                                    _load();
                                  },
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
              ),
      ),
    );
  }
}
