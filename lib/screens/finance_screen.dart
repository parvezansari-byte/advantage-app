// finance_screen.dart
//
// Three tabs: Daily Spending (with categories), Loans & Debt, Pending Dues.
// Styled with the app's Brand palette (see main.dart) for visual consistency
// with the rest of the app.

import 'package:flutter/material.dart';
import '../main.dart';
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
      backgroundColor: Brand.vault,
      appBar: AppBar(
        backgroundColor: Brand.vault,
        title: const Text('Finance Tracker',
            style: TextStyle(color: Brand.gold)),
        iconTheme: const IconThemeData(color: Brand.gold),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Brand.gold,
          unselectedLabelColor: Brand.mint,
          indicatorColor: Brand.gold,
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
// Shared styling helpers
// =============================================================================

/// Standard card surface used throughout this screen: the app's mid-tone
/// green, with a soft gold-tinted border so cards read clearly against the
/// dark vault background.
BoxDecoration _cardDecoration({Color? accent}) => BoxDecoration(
      color: Brand.fern,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (accent ?? Brand.gold).withValues(alpha: 0.35),
        width: 1,
      ),
    );

const _titleStyle = TextStyle(
    color: Brand.paper, fontWeight: FontWeight.bold, fontSize: 15);
const _bodyStyle = TextStyle(color: Brand.paper, fontSize: 14);
const _mutedStyle = TextStyle(color: Brand.mint, fontSize: 12);
const _amountStyle = TextStyle(
    color: Brand.gold, fontWeight: FontWeight.bold, fontSize: 15);
const _errorStyle = TextStyle(color: Brand.red, fontSize: 13);

InputDecoration _fieldDecoration(String label, {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Brand.mint),
      hintStyle: TextStyle(color: Brand.mint.withValues(alpha: 0.5)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Brand.mint.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Brand.gold, width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
      backgroundColor: Brand.gold,
      foregroundColor: Brand.vault,
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    );

/// Wraps a bottom-sheet form body with the app's dark surface, gold heading
/// and consistent padding, so every "Add X" sheet in this screen matches.
Widget _sheetShell({
  required BuildContext ctx,
  required String title,
  required List<Widget> children,
}) {
  return Container(
    decoration: const BoxDecoration(
      color: Brand.fern,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    padding: EdgeInsets.only(
      left: 20, right: 20, top: 20,
      bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Brand.gold)),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return _sheetShell(
            ctx: ctx,
            title: 'Add Expense',
            children: [
              TextField(
                controller: amountCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Amount (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Category'),
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
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Description (optional)'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date', style: _bodyStyle),
                subtitle: Text(
                    '${expenseDate.year}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}',
                    style: _mutedStyle),
                trailing: const Icon(Icons.calendar_today, color: Brand.gold),
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
                Text(error!, style: _errorStyle),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
                style: _primaryButtonStyle,
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault))
                    : const Text('Save Expense'),
              ),
            ],
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
        backgroundColor: Brand.fern,
        title: const Text('New Category', style: TextStyle(color: Brand.gold)),
        content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Brand.paper),
            decoration: _fieldDecoration('', hint: 'e.g. Pet Care')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Brand.mint))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Add', style: TextStyle(color: Brand.gold))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseSheet,
        backgroundColor: Brand.gold,
        foregroundColor: Brand.vault,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Brand.gold))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: _errorStyle),
                    if (_summary != null) ...[
                      Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Total spent (${_summary!['month']})',
                                style: _mutedStyle),
                            const SizedBox(height: 2),
                            Text('₹${_summary!['total_spent']}',
                                style: const TextStyle(
                                    color: Brand.gold,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text(
                                'Average daily spend: ₹${_summary!['average_daily_spend']}',
                                style: _bodyStyle),
                            Text('Transactions: ${_summary!['transaction_count']}',
                                style: _bodyStyle),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('By Category',
                          style: TextStyle(
                              color: Brand.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 10),
                      ...(_summary!['category_breakdown'] as List<dynamic>)
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(c['category'], style: _bodyStyle),
                                        Text('₹${c['amount']} (${c['percent']}%)',
                                            style: const TextStyle(
                                                color: Brand.mint,
                                                fontSize: 13)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: (c['percent'] as num) / 100,
                                        minHeight: 6,
                                        backgroundColor:
                                            Brand.mint.withValues(alpha: 0.15),
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                Brand.gold),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      const SizedBox(height: 8),
                    ],
                    const Text('Recent Transactions',
                        style: TextStyle(
                            color: Brand.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    if (_expenses.isEmpty)
                      Text('No transactions yet.',
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.6))),
                    ..._expenses.map((e) => Dismissible(
                          key: ValueKey(e['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                              decoration: BoxDecoration(
                                  color: Brand.red,
                                  borderRadius: BorderRadius.circular(14)),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              margin: const EdgeInsets.only(bottom: 10),
                              child: const Icon(Icons.delete,
                                  color: Brand.paper)),
                          onDismissed: (_) async {
                            await ApiService.deleteExpense(
                                widget.userEmail, e['id'] as int);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: _cardDecoration(),
                            child: ListTile(
                              title: Text(e['category'], style: _titleStyle),
                              subtitle: Text(
                                  e['description'] ?? e['expense_date'],
                                  style: _mutedStyle),
                              trailing: Text('₹${e['amount']}',
                                  style: _amountStyle),
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return _sheetShell(
            ctx: ctx,
            title: 'Add Loan',
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration:
                    _fieldDecoration('Loan name', hint: 'e.g. Home Loan - SBI'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: loanType,
                dropdownColor: Brand.fern,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Loan type'),
                items: const [
                  DropdownMenuItem(value: 'PERSONAL', child: Text('Personal')),
                  DropdownMenuItem(value: 'HOME', child: Text('Home')),
                  DropdownMenuItem(value: 'CAR', child: Text('Car')),
                  DropdownMenuItem(
                      value: 'EDUCATION', child: Text('Education')),
                  DropdownMenuItem(
                      value: 'CREDIT_CARD', child: Text('Credit Card')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                ],
                onChanged: (v) => setSheetState(() => loanType = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: principalCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Principal amount (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Annual interest rate (%)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tenureCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Tenure (months)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date', style: _bodyStyle),
                subtitle: Text(
                    '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                    style: _mutedStyle),
                trailing: const Icon(Icons.calendar_today, color: Brand.gold),
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
                Text(error!, style: _errorStyle),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
                style: _primaryButtonStyle,
                onPressed: saving
                    ? null
                    : () async {
                        final principal =
                            double.tryParse(principalCtrl.text.trim());
                        final rate = double.tryParse(rateCtrl.text.trim());
                        final tenure = int.tryParse(tenureCtrl.text.trim());
                        if (nameCtrl.text.trim().isEmpty ||
                            principal == null || principal <= 0 ||
                            rate == null || rate < 0 ||
                            tenure == null || tenure <= 0) {
                          setSheetState(() =>
                              error = 'Fill in all fields with valid numbers');
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault))
                    : const Text('Save Loan'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLoanSheet,
        backgroundColor: Brand.gold,
        foregroundColor: Brand.vault,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Brand.gold))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: _errorStyle),
                    if (_data != null) ...[
                      Container(
                        decoration: _cardDecoration(accent: Brand.red),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Outstanding Debt',
                                style: _mutedStyle),
                            const SizedBox(height: 2),
                            Text('₹${_data!['total_outstanding_debt']}',
                                style: const TextStyle(
                                    color: Brand.red,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Text(
                                'Monthly EMI total: ₹${_data!['total_monthly_emi']}',
                                style: _bodyStyle),
                            Text(
                                'Active loans: ${_data!['active_loan_count']}  ·  Paid off: ${_data!['paid_off_count']}',
                                style: _bodyStyle),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if ((_data!['loans'] as List).isEmpty)
                        Text('No loans added yet.',
                            style: TextStyle(
                                color: Brand.mint.withValues(alpha: 0.6))),
                      ...(_data!['loans'] as List<dynamic>).map((loan) {
                        final progress = (loan['months_elapsed'] as num) /
                            (loan['tenure_months'] as num)
                                .clamp(1, double.infinity);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: _cardDecoration(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(loan['loan_name'],
                                        style: _titleStyle),
                                  ),
                                  if (loan['is_paid_off'] == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Brand.green,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Text('Paid off',
                                          style: TextStyle(
                                              color: Brand.paper,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                  '${loan['loan_type']} · ${loan['annual_interest_rate']}% p.a.',
                                  style: _mutedStyle),
                              const SizedBox(height: 10),
                              Text('EMI: ₹${loan['emi']}/month',
                                  style: _bodyStyle),
                              Text(
                                  'Outstanding: ₹${loan['outstanding_balance']}',
                                  style: _bodyStyle),
                              Text('${loan['months_remaining']} months remaining',
                                  style: _mutedStyle),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress.toDouble().clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor:
                                      Brand.mint.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation(
                                      loan['is_paid_off'] == true
                                          ? Brand.green
                                          : Brand.gold),
                                ),
                              ),
                            ],
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return _sheetShell(
            ctx: ctx,
            title: 'Add Pending Due',
            children: [
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Description',
                    hint: 'e.g. Electricity bill'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Amount (₹)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                style: const TextStyle(color: Brand.paper),
                decoration: _fieldDecoration('Category (optional)'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date', style: _bodyStyle),
                subtitle: Text(
                    '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
                    style: _mutedStyle),
                trailing: const Icon(Icons.calendar_today, color: Brand.gold),
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
                Text(error!, style: _errorStyle),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              FilledButton(
                style: _primaryButtonStyle,
                onPressed: saving
                    ? null
                    : () async {
                        final amt = double.tryParse(amountCtrl.text.trim());
                        if (descCtrl.text.trim().isEmpty ||
                            amt == null || amt <= 0) {
                          setSheetState(() =>
                              error = 'Enter a valid description and amount');
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.vault))
                    : const Text('Save Due'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.vault,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDueSheet,
        backgroundColor: Brand.gold,
        foregroundColor: Brand.vault,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Brand.gold,
        backgroundColor: Brand.fern,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Brand.gold))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Text(_error!, style: _errorStyle),
                    Container(
                      decoration: _cardDecoration(accent: Brand.gold),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Pending', style: _mutedStyle),
                          const SizedBox(height: 2),
                          Text('₹${_totalPending.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Brand.gold,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_pending.isEmpty)
                      Text('Nothing pending — you\'re all caught up.',
                          style: TextStyle(
                              color: Brand.mint.withValues(alpha: 0.6))),
                    ..._pending.map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: _cardDecoration(),
                          child: ListTile(
                            title: Text(p['description'], style: _titleStyle),
                            subtitle: Text(
                                'Due ${p['due_date']}${p['category'] != null ? ' · ${p['category']}' : ''}',
                                style: _mutedStyle),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('₹${p['amount']}', style: _amountStyle),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Brand.green),
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
