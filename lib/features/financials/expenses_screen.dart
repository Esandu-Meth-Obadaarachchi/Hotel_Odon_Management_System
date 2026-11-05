import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:flutter/services.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'ViewEditSalariesExpensesScreen.dart';
import 'package:odon_booking/shared/services/image_processor_service.dart';
import 'package:odon_booking/shared/widgets/data_confirmation_dialog.dart';
import 'bulk_import.dart';

class ExpensesAndSalaryScreen extends StatefulWidget {
  @override
  _ExpensesAndSalaryScreenState createState() => _ExpensesAndSalaryScreenState();
}

class _ExpensesAndSalaryScreenState extends State<ExpensesAndSalaryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Expenses & salaries'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ViewEditSalariesExpensesScreen()),
            ),
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: const Text('Records'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppLayout.maxForm),
                child: SegmentedTabs(
                  controller: _tabController,
                  labels: const ['Salaries', 'Expenses'],
                  icons: const [Icons.people_alt_outlined, Icons.receipt_long_outlined],
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [SalaryTab(), ExpensesTab()],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALARY TAB
// ─────────────────────────────────────────────────────────────────────────────

class SalaryTab extends StatefulWidget {
  @override
  _SalaryTabState createState() => _SalaryTabState();
}

class _SalaryTabState extends State<SalaryTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedType = 'OT';

  String _selectedMonth = DateTime.now().month.toString();
  String _selectedYear = DateTime.now().year.toString();
  int _selectedDay = DateTime.now().day;

  final List<String> _salaryTypes = ['OT', 'Monthly', 'Weekly', 'Commission'];
  final ApiService _apiService = ApiService();
  final ImageProcessorService _imageProcessor = ImageProcessorService();

  final List<String> _months = ['1','2','3','4','5','6','7','8','9','10','11','12'];
  final List<String> _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];
  final List<String> _years = ['2023','2024','2025','2026','2027'];

  List<int> get _daysInMonth {
    final month = int.parse(_selectedMonth);
    final year  = int.parse(_selectedYear);
    return List.generate(DateTime(year, month + 1, 0).day, (i) => i + 1);
  }

  void _validateSelectedDay() {
    final maxDays = _daysInMonth.length;
    if (_selectedDay > maxDays) _selectedDay = maxDays;
  }

  DateTime get _selectedDate =>
      DateTime(int.parse(_selectedYear), int.parse(_selectedMonth), _selectedDay);

  void _submitSalary() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _apiService.addSalary({
          'employeeName': _nameController.text,
          'salaryType': _selectedType,
          'amount': double.parse(_amountController.text),
          'date': _selectedDate.toIso8601String(),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Salary record added'),
          ),
        );
        _clearForm();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _saveBatchSalaries(List<Map<String, dynamic>> salaries) async {
    for (var s in salaries) await _apiService.addSalary(s);
  }

  Future<void> _saveBatchExpenses(List<Map<String, dynamic>> expenses) async {
    for (var e in expenses) await _apiService.addExpense(e);
  }

  void _processImageWithAI() async {
    try {
      final extractedData = await _imageProcessor.processImage(context);
      if (extractedData.isNotEmpty) {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => DataConfirmationDialog(data: extractedData),
        );
        if (result != null) {
          final salaryData  = result['salaryData']  as List<Map<String, dynamic>>? ?? [];
          final expenseData = result['expenseData'] as List<Map<String, dynamic>>? ?? [];
          if (salaryData.isNotEmpty)  await _saveBatchSalaries(salaryData);
          if (expenseData.isNotEmpty) await _saveBatchExpenses(expenseData);
          if (salaryData.isNotEmpty || expenseData.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Added ${salaryData.length} salary + ${expenseData.length} expense entries',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No financial data found in the image'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  void _importFromPastedJson() async {
    try {
      final items = await showBulkImportPasteDialog(context);
      if (items == null || items.isEmpty) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => DataConfirmationDialog(data: items),
      );
      if (result != null) {
        final salaryData  = result['salaryData']  as List<Map<String, dynamic>>? ?? [];
        final expenseData = result['expenseData'] as List<Map<String, dynamic>>? ?? [];
        if (salaryData.isNotEmpty)  await _saveBatchSalaries(salaryData);
        if (expenseData.isNotEmpty) await _saveBatchExpenses(expenseData);
        if (salaryData.isNotEmpty || expenseData.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added ${salaryData.length} salary + ${expenseData.length} expense entries',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  void _clearForm() {
    _nameController.clear();
    _amountController.clear();
    setState(() {
      _selectedType  = 'OT';
      _selectedMonth = DateTime.now().month.toString();
      _selectedYear  = DateTime.now().year.toString();
      _selectedDay   = DateTime.now().day;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 16, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scan banner
          _ScanBanner(onScan: _processImageWithAI, label: 'Scan salary sheet from photo'),
          const SizedBox(height: 10),

          // Paste-JSON banner
          _PasteBanner(onPaste: _importFromPastedJson, label: 'Paste month JSON from Claude'),
          const SizedBox(height: 20),

          // Section label
          _sectionLabel('Add a salary'),
          const SizedBox(height: 10),

          // Form card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Date row
                    _DateSelector(
                      months: _months,
                      monthNames: _monthNames,
                      years: _years,
                      selectedMonth: _selectedMonth,
                      selectedYear: _selectedYear,
                      selectedDay: _selectedDay,
                      daysInMonth: _daysInMonth,
                      onMonthChanged: (v) => setState(() {
                        _selectedMonth = v!;
                        _validateSelectedDay();
                      }),
                      onYearChanged: (v) => setState(() {
                        _selectedYear = v!;
                        _validateSelectedDay();
                      }),
                      onDayChanged: (v) => setState(() => _selectedDay = v!),
                      selectedDate: _selectedDate,
                    ),
                    const SizedBox(height: 16),

                    // Employee name
                    _indigoField(
                      controller: _nameController,
                      label: 'Employee Name',
                      icon: Icons.person_outline_rounded,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Enter employee name' : null,
                    ),
                    const SizedBox(height: 14),

                    // Type dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: _indigoDecoration('Salary Type', Icons.category_outlined),
                      items: _salaryTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    _indigoField(
                      controller: _amountController,
                      label: 'Amount (LKR)',
                      icon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter amount';
                        if (double.tryParse(v) == null) return 'Invalid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),

                    FilledButton(
                      onPressed: _submitSalary,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text('Add salary record'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPENSES TAB
// ─────────────────────────────────────────────────────────────────────────────

class ExpensesTab extends StatefulWidget {
  @override
  _ExpensesTabState createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<ExpensesTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController     = TextEditingController();
  final _amountController   = TextEditingController();
  final _reasonController   = TextEditingController();
  String _selectedCategory  = 'Food';
  DateTime _selectedDate    = DateTime.now();
  final ApiService _apiService = ApiService();
  final ImageProcessorService _imageProcessor = ImageProcessorService();

  List<String> _expenseNameSuggestions = [];
  final FocusNode _nameFieldFocusNode = FocusNode();
  OverlayEntry? _overlayEntry;

  final List<String> _expenseCategories = [
    'Food','Utilities','Maintenance','Supplies',
    'Transportation','Marketing','Equipment','Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadExpenseNames();
    _nameController.addListener(_onNameFieldChanged);
    _nameFieldFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameFieldChanged);
    _nameFieldFocusNode.removeListener(_onFocusChanged);
    _nameController.dispose();
    _amountController.dispose();
    _reasonController.dispose();
    _nameFieldFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  Future<void> _loadExpenseNames() async {
    try {
      final expenses = await _apiService.fetchExpenses();
      final uniqueNames = <String>{};
      for (var e in expenses) {
        if (e['expenseName'] != null && e['expenseName'].toString().trim().isNotEmpty) {
          uniqueNames.add(e['expenseName'].toString().trim());
        }
      }
      setState(() => _expenseNameSuggestions = uniqueNames.toList()..sort());
    } catch (_) {}
  }

  void _onNameFieldChanged() {
    final query = _nameController.text.toLowerCase();
    if (query.isNotEmpty && _nameFieldFocusNode.hasFocus) {
      final filtered = _expenseNameSuggestions
          .where((n) => n.toLowerCase().contains(query))
          .take(5)
          .toList();
      if (filtered.isNotEmpty) {
        _showSuggestionsOverlay(filtered);
      } else {
        _removeOverlay();
      }
    } else {
      _removeOverlay();
    }
  }

  void _onFocusChanged() {
    if (!_nameFieldFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), _removeOverlay);
    } else if (_nameController.text.isNotEmpty) {
      _onNameFieldChanged();
    }
  }

  void _showSuggestionsOverlay(List<String> suggestions) {
    _removeOverlay();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final ctx = _nameFieldFocusNode.context;
    if (ctx == null) return;
    final rb  = ctx.findRenderObject() as RenderBox?;
    if (rb == null) return;
    final pos  = rb.localToGlobal(Offset.zero, ancestor: overlay);
    final size = rb.size;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: pos.dx,
        top: pos.dy + size.height + 4,
        width: size.width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.hairline),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (_, index) {
                final s = suggestions[index];
                return InkWell(
                  onTap: () {
                    _nameController.text = s;
                    _nameController.selection = TextSelection.fromPosition(
                        TextPosition(offset: s.length));
                    _removeOverlay();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: index < suggestions.length - 1
                          ? Border(bottom: BorderSide(color: AppColors.sunken))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 16, color: AppColors.ink3),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _submitExpense() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _apiService.addExpense({
          'expenseName': _nameController.text,
          'category': _selectedCategory,
          'amount': double.parse(_amountController.text),
          'date': _selectedDate.toIso8601String(),
          'reason': _reasonController.text,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Expense record added'),
          ),
        );
        _loadExpenseNames();
        _clearForm();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _saveBatchSalaries(List<Map<String, dynamic>> salaries) async {
    for (var s in salaries) await _apiService.addSalary(s);
  }

  Future<void> _saveBatchExpenses(List<Map<String, dynamic>> expenses) async {
    for (var e in expenses) await _apiService.addExpense(e);
  }

  void _processImageWithAI() async {
    try {
      final extractedData = await _imageProcessor.processImage(context);
      if (extractedData.isNotEmpty) {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => DataConfirmationDialog(data: extractedData),
        );
        if (result != null) {
          final salaryData  = result['salaryData']  as List<Map<String, dynamic>>? ?? [];
          final expenseData = result['expenseData'] as List<Map<String, dynamic>>? ?? [];
          if (salaryData.isNotEmpty)  await _saveBatchSalaries(salaryData);
          if (expenseData.isNotEmpty) await _saveBatchExpenses(expenseData);
          if (salaryData.isNotEmpty || expenseData.isNotEmpty) {
            _loadExpenseNames();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Added ${salaryData.length} salary + ${expenseData.length} expense entries',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No financial data found in the image'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  void _importFromPastedJson() async {
    try {
      final items = await showBulkImportPasteDialog(context);
      if (items == null || items.isEmpty) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => DataConfirmationDialog(data: items),
      );
      if (result != null) {
        final salaryData  = result['salaryData']  as List<Map<String, dynamic>>? ?? [];
        final expenseData = result['expenseData'] as List<Map<String, dynamic>>? ?? [];
        if (salaryData.isNotEmpty)  await _saveBatchSalaries(salaryData);
        if (expenseData.isNotEmpty) await _saveBatchExpenses(expenseData);
        if (salaryData.isNotEmpty || expenseData.isNotEmpty) {
          _loadExpenseNames();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Added ${salaryData.length} salary + ${expenseData.length} expense entries',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  void _clearForm() {
    _nameController.clear();
    _amountController.clear();
    _reasonController.clear();
    setState(() {
      _selectedCategory = 'Food';
      _selectedDate     = DateTime.now();
    });
    _removeOverlay();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.ink,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 16, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scan banner
          _ScanBanner(onScan: _processImageWithAI, label: 'Scan expense receipt from photo'),
          const SizedBox(height: 10),

          // Paste-JSON banner
          _PasteBanner(onPaste: _importFromPastedJson, label: 'Paste month JSON from Claude'),
          const SizedBox(height: 20),

          _sectionLabel('Add an expense'),
          const SizedBox(height: 10),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Expense name with autocomplete
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFieldFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Expense Name',
                        hintText: 'Type to see suggestions',
                        prefixIcon: const Icon(Icons.receipt_outlined, size: 20),
                        suffixIcon: _nameController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18, color: AppColors.ink4),
                                onPressed: () {
                                  _nameController.clear();
                                  _removeOverlay();
                                },
                              )
                            : null,
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Enter expense name' : null,
                    ),
                    const SizedBox(height: 14),

                    // Category
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: _indigoDecoration('Category', Icons.label_outline_rounded),
                      items: _expenseCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategory = v!),
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    _indigoField(
                      controller: _amountController,
                      label: 'Amount (LKR)',
                      icon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter amount';
                        if (double.tryParse(v) == null) return 'Invalid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Date picker
                    GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, color: AppColors.ink3, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                              style: const TextStyle(fontSize: 15),
                            ),
                            const Spacer(),
                            Text('Tap to change', style: TextStyle(fontSize: 12, color: AppColors.ink4)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Reason
                    _indigoField(
                      controller: _reasonController,
                      label: 'Reason / Description (optional)',
                      icon: Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 22),

                    FilledButton(
                      onPressed: _submitExpense,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text('Add expense record'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _ScanBanner extends StatelessWidget {
  final VoidCallback onScan;
  final String label;
  const _ScanBanner({required this.onScan, required this.label});

  @override
  Widget build(BuildContext context) => _ImportRow(
        icon: Icons.document_scanner_outlined,
        label: label,
        action: 'Scan',
        onTap: onScan,
      );
}

class _PasteBanner extends StatelessWidget {
  final VoidCallback onPaste;
  final String label;
  const _PasteBanner({required this.onPaste, required this.label});

  @override
  Widget build(BuildContext context) => _ImportRow(
        icon: Icons.content_paste_rounded,
        label: label,
        action: 'Paste',
        onTap: onPaste,
      );
}

/// A shortcut for filling the form from somewhere else (photo, clipboard).
class _ImportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String action;
  final VoidCallback onTap;
  const _ImportRow({required this.icon, required this.label, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          IconWell(icon, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppText.bodyStrong.copyWith(fontSize: 14))),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(minimumSize: const Size(72, 38)),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  final List<String> months, monthNames, years;
  final String selectedMonth, selectedYear;
  final int selectedDay;
  final List<int> daysInMonth;
  final ValueChanged<String?> onMonthChanged, onYearChanged;
  final ValueChanged<int?> onDayChanged;
  final DateTime selectedDate;

  const _DateSelector({
    required this.months,
    required this.monthNames,
    required this.years,
    required this.selectedMonth,
    required this.selectedYear,
    required this.selectedDay,
    required this.daysInMonth,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onDayChanged,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.ink3),
            const SizedBox(width: 6),
            Text(
              '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
              style: AppText.bodyStrong.copyWith(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Month — takes most space
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: selectedMonth,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Month',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: months
                    .map((m) => DropdownMenuItem(value: m, child: Text(monthNames[int.parse(m) - 1])))
                    .toList(),
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 8),
            // Year
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: selectedYear,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Year',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                onChanged: onYearChanged,
              ),
            ),
            const SizedBox(width: 8),
            // Day
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<int>(
                value: selectedDay,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Day',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                items: daysInMonth
                    .map((d) => DropdownMenuItem(value: d, child: Text(d.toString())))
                    .toList(),
                onChanged: onDayChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: AppText.eyebrow),
    );

InputDecoration _indigoDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
    );

Widget _indigoField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int maxLines = 1,
}) =>
    TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: _indigoDecoration(label, icon),
      validator: validator,
    );
