import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/features/bookings/widgets/booking_card.dart';
import 'package:intl/intl.dart';
import 'package:month_picker_dialog/month_picker_dialog.dart';
import 'package:odon_booking/core/api/api_service.dart';

class PastBookingsScreen extends StatefulWidget {
  @override
  _PastBookingsScreenState createState() => _PastBookingsScreenState();
}

class _PastBookingsScreenState extends State<PastBookingsScreen> {
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchBookingsForMonth(_selectedMonth);
  }

  Future<void> _fetchBookingsForMonth(DateTime month) async {
    setState(() => _loading = true);
    try {
      final all = await _apiService.fetchBookingsForMonth(month);
      setState(() {
        // Unreadable dates are dropped rather than allowed to throw.
        DateTime? ci(Map<String, dynamic> b) =>
            DateTime.tryParse(b['checkIn']?.toString() ?? '');
        _bookings = all.where((b) {
          final d = ci(b);
          return d != null && d.year == month.year && d.month == month.month;
        }).toList()
          ..sort((a, b) => ci(a)!.compareTo(ci(b)!));
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _pickMonth(BuildContext context) {
    showMonthPicker(context: context, initialDate: _selectedMonth)
        .then((picked) {
      if (picked != null) {
        setState(() => _selectedMonth = picked);
        _fetchBookingsForMonth(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final totalNights = _bookings.fold<int>(0, (sum, b) => sum + ((b['num_of_nights'] as int?) ?? 0));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          LargeTitleSliverAppBar(
            title: 'Past bookings',
            subtitle: monthLabel,
            maxWidth: AppLayout.maxForm,
            actions: [
              TextButton.icon(
                onPressed: () => _pickMonth(context),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Month'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(child: LoadingView())
          else if (_bookings.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No bookings in $monthLabel',
                message: 'Pick another month to look further back.',
                actionLabel: 'Change month',
                onAction: () => _pickMonth(context),
              ),
            )
          else ...[
            _summary([
              Metric('${_bookings.length}', 'Bookings'),
              Metric('${_roomsIn(_bookings)}', 'Rooms'),
              Metric('$totalNights', 'Nights'),
            ]),
            _list(_bookings, (b) {
              final ci = DateTime.tryParse(b['checkIn']?.toString() ?? '');
              return BookingCard(
                booking: b,
                badge: ci == null ? null : StatusPill(DateFormat('d MMM').format(ci)),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, Widget Function(Map<String, dynamic>) card) =>
      SliverPadding(
        padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 12, bottom: 32),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => card(items[i]),
        ),
      );

  Widget _summary(List<Metric> metrics) => SliverPadding(
        padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 4),
        sliver: SliverToBoxAdapter(child: MetricStrip(metrics, valueSize: 24)),
      );

  int _roomsIn(List<Map<String, dynamic>> list) => list.fold<int>(0, (sum, b) {
        final rooms = b['rooms'] as List?;
        return sum + (rooms != null && rooms.isNotEmpty ? rooms.length : 1);
      });
}
