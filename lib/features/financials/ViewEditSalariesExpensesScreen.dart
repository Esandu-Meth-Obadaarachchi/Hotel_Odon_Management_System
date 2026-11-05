import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:flutter/services.dart';
import 'package:odon_booking/core/api/api_service.dart';

class ViewEditSalariesExpensesScreen extends StatefulWidget {
  @override
  _ViewEditSalariesExpensesScreenState createState() =>
      _ViewEditSalariesExpensesScreenState();
}

class _ViewEditSalariesExpensesScreenState
    extends State<ViewEditSalariesExpensesScreen> {
  String _selectedType     = 'Salaries';
  String _selectedMonth    = DateTime.now().month.toString();
  String _selectedYear     = DateTime.now().year.toString();
  String _selectedCategory = 'All';
  String _searchQuery      = '';

  List<Map<String, dynamic>> _records         = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  bool _isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();

  final List<String> _months = [
    '1','2','3','4','5','6','7','8','9','10','11','12'
  ];
  final List<String> _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];
  final List<String> _years = ['2023','2024','2025','2026','2027'];
  final List<String> _salaryTypes     = ['OT','Monthly','Weekly','Commission'];
  final List<String> _expenseCategories = [
    'Food','Utilities','Maintenance','Supplies',
    'Transportation','Marketing','Equipment','Other',
  ];

  List<String> get _currentCategoryOptions {
    return ['All', ...(_selectedType == 'Salaries' ? _salaryTypes : _expenseCategories)];
  }

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final selectedDate =
          DateTime(int.parse(_selectedYear), int.parse(_selectedMonth));
      final fetched = _selectedType == 'Salaries'
          ? await _apiService.fetchSalariesForMonth(selectedDate)
          : await _apiService.fetchExpensesForMonth(selectedDate);
      setState(() {
        _records = fetched;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_records);
    if (_selectedCategory != 'All') {
      filtered = filtered.where((r) {
        return _selectedType == 'Salaries'
            ? r['salaryType'] == _selectedCategory
            : r['category'] == _selectedCategory;
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((r) {
        final name = _selectedType == 'Salaries'
            ? (r['employeeName'] ?? '').toLowerCase()
            : (r['expenseName']  ?? '').toLowerCase();
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    setState(() => _filteredRecords = filtered);
  }

  double _calculateTotal() => _filteredRecords.fold(0.0, (sum, r) {
        final a = r['amount'];
        if (a is int)    return sum + a.toDouble();
        if (a is double) return sum + a;
        if (a is String) return sum + (double.tryParse(a) ?? 0.0);
        return sum;
      });

  Future<void> _deleteRecord(String id) async {
    try {
      if (_selectedType == 'Salaries') {
        await _apiService.deleteSalary(id);
      } else {
        await _apiService.deleteExpense(id);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Record deleted'),
        ),
      );
      _loadRecords();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  void _showEditDialog(Map<String, dynamic> record) {
    if (_selectedType == 'Salaries') {
      _showEditSalaryDialog(record);
    } else {
      _showEditExpenseDialog(record);
    }
  }

  void _showEditSalaryDialog(Map<String, dynamic> salary) {
    final nameCtrl   = TextEditingController(text: salary['employeeName']);
    final amountCtrl = TextEditingController(text: salary['amount'].toString());
    String type      = salary['salaryType'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Salary', style: TextStyle( fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(nameCtrl, 'Employee Name', Icons.person_outline),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: _dialogDeco('Salary Type', Icons.category_outlined),
                  items: _salaryTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setS(() => type = v!),
                ),
                const SizedBox(height: 14),
                _dialogField(amountCtrl, 'Amount (LKR)', Icons.payments_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                try {
                  await _apiService.updateSalary(salary['_id'], {
                    'employeeName': nameCtrl.text,
                    'salaryType': type,
                    'amount': double.parse(amountCtrl.text),
                    'date': salary['date'],
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Updated'), backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating),
                  );
                  _loadRecords();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditExpenseDialog(Map<String, dynamic> expense) {
    final nameCtrl   = TextEditingController(text: expense['expenseName']);
    final amountCtrl = TextEditingController(text: expense['amount'].toString());
    final reasonCtrl = TextEditingController(text: expense['reason'] ?? '');
    String category  = expense['category'];
    DateTime date    = DateTime.parse(expense['date']);

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Expense', style: TextStyle( fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(nameCtrl, 'Expense Name', Icons.receipt_outlined),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: _dialogDeco('Category', Icons.label_outline),
                  items: _expenseCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setS(() => category = v!),
                ),
                const SizedBox(height: 14),
                _dialogField(amountCtrl, 'Amount (LKR)', Icons.payments_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setS(() => date = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.hairlineStrong),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, color: AppColors.ink3, size: 18),
                        const SizedBox(width: 10),
                        Text('${date.day}/${date.month}/${date.year}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _dialogField(reasonCtrl, 'Reason / Description', Icons.notes_rounded, maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                try {
                  await _apiService.updateExpense(expense['_id'], {
                    'expenseName': nameCtrl.text,
                    'category': category,
                    'amount': double.parse(amountCtrl.text),
                    'date': date.toIso8601String(),
                    'reason': reasonCtrl.text,
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Updated'), backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating),
                  );
                  _loadRecords();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadRecords,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PageBody(
        maxWidth: AppLayout.maxForm,
        child: Column(
        children: [
          // ── Filter Panel ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                // Type + category row
                Row(
                  children: [
                    Expanded(child: _compactDropdown<String>(
                      value: _selectedType,
                      items: ['Salaries', 'Expenses'],
                      itemLabel: (v) => v,
                      icon: Icons.swap_horiz_rounded,
                      onChanged: (v) {
                        setState(() {
                          _selectedType = v!;
                          _selectedCategory = 'All';
                        });
                        _loadRecords();
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _compactDropdown<String>(
                      value: _selectedCategory,
                      items: _currentCategoryOptions,
                      itemLabel: (v) => v == 'All' ? 'All types' : v,
                      icon: Icons.filter_list_rounded,
                      onChanged: (v) {
                        setState(() => _selectedCategory = v!);
                        _applyFilters();
                      },
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                // Month + Year row
                Row(
                  children: [
                    Expanded(flex: 3, child: _compactDropdown<String>(
                      value: _selectedMonth,
                      items: _months,
                      itemLabel: (v) => _monthNames[int.parse(v) - 1],
                      icon: Icons.calendar_month_outlined,
                      onChanged: (v) {
                        setState(() => _selectedMonth = v!);
                        _loadRecords();
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _compactDropdown<String>(
                      value: _selectedYear,
                      items: _years,
                      itemLabel: (v) => v,
                      icon: Icons.event_note_outlined,
                      onChanged: (v) {
                        setState(() => _selectedYear = v!);
                        _loadRecords();
                      },
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                // Search
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _selectedType == 'Salaries'
                        ? 'Search by employee name…'
                        : 'Search by expense name…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              _applyFilters();
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),

          // ── Total ────────────────────────────────────────────────────────
          if (!_isLoading && _filteredRecords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SurfaceCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_buildFilterDescription(), style: AppText.bodyStrong.copyWith(fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            '${_monthNames[int.parse(_selectedMonth) - 1]} $_selectedYear · '
                            '${_filteredRecords.length} record${_filteredRecords.length != 1 ? 's' : ''}',
                            style: AppText.footnote,
                          ),
                        ],
                      ),
                    ),
                    FittedBox(
                      child: Text(formatMoney(_calculateTotal()), style: AppText.number(22)),
                    ),
                  ],
                ),
              ),
            ),

          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _filteredRecords.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
                        itemCount: _filteredRecords.length,
                        itemBuilder: (_, i) {
                          final r = _filteredRecords[i];
                          return _selectedType == 'Salaries'
                              ? _SalaryCard(salary: r, onEdit: () => _showEditDialog(r), onDelete: () => _confirmDelete(r['_id']))
                              : _ExpenseCard(expense: r, onEdit: () => _showEditDialog(r), onDelete: () => _confirmDelete(r['_id']));
                        },
                      ),
          ),
        ],
      ),
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this record?'),
        content: const Text('It will be removed from the totals. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              Navigator.pop(context);
              _deleteRecord(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _searchQuery.isNotEmpty || _selectedCategory != 'All';
    return SingleChildScrollView(
      child: EmptyState(
        icon: _selectedType == 'Salaries' ? Icons.people_outline : Icons.receipt_long_outlined,
        title: _buildEmptyStateMessage(),
        message: '${_monthNames[int.parse(_selectedMonth) - 1]} $_selectedYear',
        actionLabel: filtered ? 'Clear filters' : null,
        onAction: filtered
            ? () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategory = 'All';
                });
                _applyFilters();
              }
            : null,
      ),
    );
  }

  String _buildFilterDescription() {
    if (_searchQuery.isNotEmpty && _selectedCategory != 'All') return 'Filtered Total';
    if (_searchQuery.isNotEmpty) return 'Search Results';
    if (_selectedCategory != 'All') return '$_selectedCategory Total';
    return 'Total ${_selectedType}';
  }

  String _buildEmptyStateMessage() {
    if (_searchQuery.isNotEmpty) return 'No search results';
    if (_selectedCategory != 'All') return 'No $_selectedCategory found';
    return 'No ${_selectedType.toLowerCase()} found';
  }

  Widget _compactDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required IconData icon,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18, color: AppColors.ink3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        isDense: true,
      ),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(itemLabel(i), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECORD CARDS
// ─────────────────────────────────────────────────────────────────────────────

class _SalaryCard extends StatelessWidget {
  final Map<String, dynamic> salary;
  final VoidCallback onEdit, onDelete;
  const _SalaryCard({required this.salary, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(salary['date'] ?? salary['createdAt']);
    final amount = double.tryParse(salary['amount'].toString()) ?? 0.0;
    return _RecordRow(
      title: salary['employeeName'] ?? 'Unknown employee',
      tag: (salary['salaryType'] ?? '').toString(),
      date: date,
      amount: amount,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Map<String, dynamic> expense;
  final VoidCallback onEdit, onDelete;
  const _ExpenseCard({required this.expense, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(expense['date']);
    final amount = double.tryParse(expense['amount'].toString()) ?? 0.0;
    return _RecordRow(
      title: expense['expenseName'] ?? 'Unknown expense',
      tag: (expense['category'] ?? '').toString(),
      date: date,
      amount: amount,
      note: expense['reason']?.toString() ?? '',
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

String formatMoney(double v) => 'LKR ${NumberFormat('#,##0.##').format(v)}';

class _RecordRow extends StatelessWidget {
  final String title, tag;
  final DateTime date;
  final double amount;
  final String note;
  final VoidCallback onEdit, onDelete;

  const _RecordRow({
    required this.title,
    required this.tag,
    required this.date,
    required this.amount,
    this.note = '',
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        shadow: false,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    [if (tag.isNotEmpty) tag, DateFormat('d MMM yyyy').format(date)].join(' · '),
                    style: AppText.footnote,
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(note, style: AppText.footnote.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            Text(formatMoney(amount), style: AppText.number(15)),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.ink3, size: 20),
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

TextField _dialogField(
  TextEditingController ctrl,
  String label,
  IconData icon, {
  TextInputType? keyboardType,
  int maxLines = 1,
}) =>
    TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _dialogDeco(label, icon),
    );

InputDecoration _dialogDeco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
    );
