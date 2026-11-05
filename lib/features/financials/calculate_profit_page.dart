import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/ai_insights/ai_insights_page.dart';

class CalculateProfitPage extends StatefulWidget {
  @override
  _CalculateProfitPageState createState() => _CalculateProfitPageState();
}

class _CalculateProfitPageState extends State<CalculateProfitPage> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate   = DateTime.now();

  List<Map<String, dynamic>> _bookingsForSelectedRange = [];
  List<Map<String, dynamic>> _expensesForSelectedRange = [];
  List<Map<String, dynamic>> _salariesForSelectedRange = [];

  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  double totalRevenue     = 0;
  double totalAdvance     = 0;
  double totalBalance     = 0;
  double totalBankBalance = 0;
  double totalCashBalance = 0;
  double totalExpenses    = 0;
  double totalSalaries    = 0;
  double totalProfit      = 0;

  @override
  void initState() {
    super.initState();
    _fetchAllDataForDateRange(_startDate, _endDate);
  }

  Future<void> _fetchAllDataForDateRange(DateTime start, DateTime end) async {
    setState(() => _isLoading = true);
    try {
      final months     = _getMonthsInRange(start, end);
      final allBookings = <Map<String, dynamic>>[];
      final allExpenses = <Map<String, dynamic>>[];
      final allSalaries = <Map<String, dynamic>>[];

      for (final month in months) {
        final futures = await Future.wait([
          _apiService.fetchBookingsForMonth(month),
          _apiService.fetchExpensesForMonth(month),
          _apiService.fetchSalariesForMonth(month),
        ]);
        allBookings.addAll(futures[0]);
        allExpenses.addAll(futures[1]);
        allSalaries.addAll(futures[2]);
      }

      setState(() {
        _bookingsForSelectedRange = allBookings.where((b) {
          final d = DateTime.parse(b['checkIn']);
          return !d.isBefore(start) && !d.isAfter(end);
        }).toList();
        _expensesForSelectedRange = allExpenses.where((e) {
          if (e['date'] == null) return false;
          final d = DateTime.parse(e['date']);
          return !d.isBefore(start) && !d.isAfter(end);
        }).toList();
        _salariesForSelectedRange = allSalaries.where((s) {
          if (s['date'] == null) return false;
          final d = DateTime.parse(s['date']);
          return !d.isBefore(start) && !d.isAfter(end);
        }).toList();

        _calculateTotals();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to fetch data. Please try again.')),
      );
    }
  }

  List<DateTime> _getMonthsInRange(DateTime start, DateTime end) {
    final months   = <DateTime>[];
    var current    = DateTime(start.year, start.month);
    final endMonth = DateTime(end.year, end.month);
    while (!current.isAfter(endMonth)) {
      months.add(current);
      current = DateTime(current.year, current.month + 1);
    }
    return months;
  }

  void _calculateTotals() {
    totalRevenue = totalAdvance = totalBalance =
        totalBankBalance = totalCashBalance = totalExpenses = totalSalaries = 0;

    for (final b in _bookingsForSelectedRange) {
      final t  = double.tryParse(b['total'].toString())   ?? 0;
      final a  = double.tryParse(b['advance'].toString()) ?? 0;
      final bm = b['balanceMethod'];
      totalRevenue += t;
      totalAdvance += a;
      totalBalance += (t - a);
      if (bm == 'Bank') totalBankBalance += (t - a);
      if (bm == 'Cash') totalCashBalance += (t - a);
    }
    for (final e in _expensesForSelectedRange) {
      totalExpenses += double.tryParse(e['amount'].toString()) ?? 0;
    }
    for (final s in _salariesForSelectedRange) {
      totalSalaries += double.tryParse(s['amount'].toString()) ?? 0;
    }
    totalProfit = totalRevenue - totalExpenses - totalSalaries;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
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
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate   = picked.end;
      });
      _fetchAllDataForDateRange(_startDate, _endDate);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${_monthAbbr[d.month - 1]} ${d.year}';

  String _fmtLkr(double v) {
    final abs = v.abs();
    if (abs >= 1000000) {
      return 'LKR ${(abs / 1000000).toStringAsFixed(2)}M';
    }
    return 'LKR ${abs.toStringAsFixed(2)}';
  }

  static const _monthAbbr = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final days = _endDate.difference(_startDate).inDays + 1;
    final isProfit = totalProfit >= 0;
    final resultColor = isProfit ? AppColors.success : AppColors.danger;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit'),
        actions: [
          TextButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: const Text('Range'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const LoadingView(label: 'Adding up the numbers…')
          : SingleChildScrollView(
              padding: const EdgeInsets.only(top: 16, bottom: 32),
              child: PageBody(
                maxWidth: AppLayout.maxForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Range ─────────────────────────────────────────────
                    Pressable(
                      onTap: _selectDateRange,
                      pressedScale: 0.98,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadius.control,
                          border: Border.all(color: AppColors.hairlineStrong),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.ink3),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${_fmtDate(_startDate)}  –  ${_fmtDate(_endDate)}',
                                  style: AppText.bodyStrong.copyWith(fontSize: 14)),
                            ),
                            StatusPill('$days day${days != 1 ? 's' : ''}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Net result ────────────────────────────────────────
                    SurfaceCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isProfit ? 'NET PROFIT' : 'NET LOSS',
                              style: AppText.eyebrow.copyWith(color: resultColor)),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(_fmtLkr(totalProfit), style: AppText.number(40, color: resultColor)),
                          ),
                          const SizedBox(height: 14),
                          Wrap(spacing: 16, runSpacing: 6, children: [
                            _countBadge(Icons.hotel_outlined, _bookingsForSelectedRange.length, 'bookings'),
                            _countBadge(Icons.receipt_outlined, _expensesForSelectedRange.length, 'expenses'),
                            _countBadge(Icons.people_outline_rounded, _salariesForSelectedRange.length, 'salaries'),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Statement ─────────────────────────────────────────
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ledgerSectionHeader('INCOME'),
                          _ledgerRow(label: 'Booking revenue', amount: totalRevenue, bold: true),
                          _ledgerRow(label: 'Advance collected', amount: totalAdvance, indent: 1),
                          _ledgerRow(label: 'Balance due', amount: totalBalance, indent: 1),
                          if (totalBankBalance > 0)
                            _ledgerRow(label: 'by bank transfer', amount: totalBankBalance, indent: 2, small: true),
                          if (totalCashBalance > 0)
                            _ledgerRow(label: 'in cash', amount: totalCashBalance, indent: 2, small: true),
                          _ledgerDivider(),
                          _ledgerSectionHeader('OUTGOINGS'),
                          _ledgerRow(label: 'Expenses', amount: totalExpenses, bold: true, negate: true),
                          _ledgerRow(label: 'Salaries', amount: totalSalaries, bold: true, negate: true),
                          _ledgerDivider(thick: true),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                            child: Row(
                              children: [
                                Text('Net', style: AppText.headline),
                                const Spacer(),
                                Text('${isProfit ? '' : '−'}${_fmtLkr(totalProfit)}',
                                    style: AppText.number(18, color: resultColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AiInsightsPage(
                            selectedMonth: _startDate,
                            rangeEnd: _endDate,
                            totalRevenue: totalRevenue,
                            totalExpenses: totalExpenses,
                            totalSalaries: totalSalaries,
                            totalProfit: totalProfit,
                            bookings: _bookingsForSelectedRange,
                            expenses: _expensesForSelectedRange,
                            salaries: _salariesForSelectedRange,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Business insights'),
                    ),
                    const SizedBox(height: 28),

                    // ── Detail ────────────────────────────────────────────
                    DefaultTabController(
                      length: 3,
                      child: Builder(
                        builder: (ctx) => Column(
                          children: [
                            SegmentedTabs(
                              controller: DefaultTabController.of(ctx),
                              labels: [
                                'Bookings ${_bookingsForSelectedRange.length}',
                                'Expenses ${_expensesForSelectedRange.length}',
                                'Salaries ${_salariesForSelectedRange.length}',
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 360,
                              child: TabBarView(
                                children: [
                                  _buildBookingsList(),
                                  _buildList(_expensesForSelectedRange, isExpense: true),
                                  _buildList(_salariesForSelectedRange, isExpense: false),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Ledger components ──────────────────────────────────────────────────────

  Widget _ledgerSectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(label, style: AppText.eyebrow.copyWith(fontSize: 10)),
      );

  Widget _ledgerDivider({bool thick = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Divider(color: thick ? AppColors.hairlineStrong : AppColors.hairline),
      );

  Widget _ledgerRow({
    required String label,
    required double amount,
    int indent = 0,
    bool bold = false,
    bool small = false,
    bool negate = false,
  }) {
    final leftPad = 20.0 + indent * 16.0;
    final size = small ? 13.0 : 14.5;
    return Padding(
      padding: EdgeInsets.fromLTRB(leftPad, 6, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: bold
                    ? AppText.bodyStrong.copyWith(fontSize: size)
                    : AppText.callout.copyWith(fontSize: size, color: AppColors.ink3)),
          ),
          Text(
            '${negate ? '−' : ''}${_fmtLkr(amount)}',
            style: AppText.number(size,
                weight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? AppColors.ink : AppColors.ink2),
          ),
        ],
      ),
    );
  }

  Widget _countBadge(IconData icon, int count, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.ink3),
          const SizedBox(width: 5),
          Text('$count $label', style: AppText.footnote.copyWith(color: AppColors.ink2)),
        ],
      );

  // ── Detail list builders ───────────────────────────────────────────────────

  Widget _rows(int count, Widget Function(int) row) => SingleChildScrollView(
        child: SurfaceCard(
          shadow: false,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider()),
              row(i),
            ],
          ]),
        ),
      );

  Widget _row(String title, String sub, double amount) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong.copyWith(fontSize: 14), overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty) Text(sub, style: AppText.footnote.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Text(_fmtLkr(amount), style: AppText.number(14)),
          ],
        ),
      );

  Widget _buildBookingsList() {
    if (_bookingsForSelectedRange.isEmpty) {
      return _emptyState(Icons.event_busy_outlined, 'No bookings in this range');
    }
    return _rows(_bookingsForSelectedRange.length, (i) {
      final booking = _bookingsForSelectedRange[i];
      final isNew = booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty;
      final roomLabel = isNew
          ? (booking['rooms'] as List).cast<Map<String, dynamic>>().map((r) => '${r['roomNumber']}').join(', ')
          : '${booking['roomNumber'] ?? '?'}';
      final guest = (booking['guestName'] ?? '').toString().trim();
      final total = double.tryParse(booking['total'].toString()) ?? 0;
      return _row(guest.isEmpty ? 'Room $roomLabel' : guest,
          '${(booking['package'] ?? '').toString()} · Room $roomLabel', total);
    });
  }

  Widget _buildList(List<Map<String, dynamic>> items, {required bool isExpense}) {
    if (items.isEmpty) {
      return _emptyState(
        isExpense ? Icons.receipt_long_outlined : Icons.people_outline,
        isExpense ? 'No expenses in this range' : 'No salaries in this range',
      );
    }
    return _rows(items.length, (i) {
      final item = items[i];
      final amount = double.tryParse(item['amount'].toString()) ?? 0;
      final name = isExpense ? (item['expenseName'] ?? '–') : (item['employeeName'] ?? '–');
      final sub = isExpense ? (item['category'] ?? '') : (item['salaryType'] ?? '');
      return _row(name.toString(), sub.toString(), amount);
    });
  }

  Widget _emptyState(IconData icon, String label) => EmptyState(icon: icon, title: label);
}
