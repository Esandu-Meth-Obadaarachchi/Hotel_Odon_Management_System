import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/features/bookings/widgets/booking_card.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'edit_booking_screen.dart';

class FutureBookingsScreen extends StatefulWidget {
  @override
  _FutureBookingsScreenState createState() => _FutureBookingsScreenState();
}

class _FutureBookingsScreenState extends State<FutureBookingsScreen> {
  List<Map<String, dynamic>> _futureBookings = [];
  bool _loading = true;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchFutureBookings();
  }

  Future<void> _fetchFutureBookings() async {
    setState(() => _loading = true);
    try {
      final currentDate = DateTime.now();
      final bookings = await _apiService.fetchFutureBookings(currentDate);
      // Records with an unreadable check-in are dropped rather than allowed to
      // throw and blank the whole list.
      DateTime? ci(Map<String, dynamic> b) =>
          DateTime.tryParse(b['checkIn']?.toString() ?? '');
      final filtered = bookings.where((b) {
        final d = ci(b);
        return d != null && d.isAfter(currentDate);
      }).toList()
        ..sort((a, b) => ci(a)!.compareTo(ci(b)!));
      setState(() {
        _futureBookings = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchFutureBookings,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const LargeTitleSliverAppBar(
              title: 'Upcoming',
              subtitle: 'Arrivals from tomorrow onwards',
              maxWidth: AppLayout.maxForm,
            ),
            if (_loading)
              const SliverFillRemaining(child: LoadingView())
            else if (_futureBookings.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Nothing booked ahead',
                  message: 'New bookings will appear here. Pull down to refresh.',
                ),
              )
            else ...[
              _summary([
                Metric('${_futureBookings.length}', 'Bookings'),
                Metric('${_roomsIn(_futureBookings)}', 'Rooms'),
              ]),
              _list(_futureBookings, _card),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> booking) {
    final checkIn = DateTime.tryParse(booking['checkIn']?.toString() ?? '');
    // Whole calendar days, so "tomorrow" doesn't depend on the time of day.
    final now = DateTime.now();
    final local = checkIn?.toLocal();
    final daysUntil = local == null
        ? null
        : DateTime(local.year, local.month, local.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
    final soon = daysUntil != null && daysUntil <= 3;

    return BookingCard(
      booking: booking,
      badge: daysUntil == null || daysUntil < 0
          ? null
          : StatusPill(
              daysUntil == 0
                  ? 'Today'
                  : daysUntil == 1
                      ? 'Tomorrow'
                      : 'In $daysUntil days',
              color: soon ? AppColors.warning : AppColors.ink2,
            ),
      actions: [
        CardIconButton(
          Icons.edit_outlined,
          tooltip: 'Edit booking',
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditBookingScreen(
                  booking: booking,
                  selectedDay: checkIn ?? DateTime.now(),
                ),
              ),
            );
            if (result == true) _fetchFutureBookings();
          },
        ),
      ],
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
