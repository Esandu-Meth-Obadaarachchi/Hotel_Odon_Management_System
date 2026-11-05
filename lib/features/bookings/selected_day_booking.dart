import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/features/bookings/widgets/booking_card.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'edit_booking_screen.dart';

class SelectedDayBookingsScreen extends StatefulWidget {
  final DateTime selectedDay;
  final List<Map<String, dynamic>> bookings;

  const SelectedDayBookingsScreen({
    Key? key,
    required this.selectedDay,
    required this.bookings,
  }) : super(key: key);

  @override
  _SelectedDayBookingsScreenState createState() =>
      _SelectedDayBookingsScreenState();
}

class _SelectedDayBookingsScreenState
    extends State<SelectedDayBookingsScreen> {
  late List<Map<String, dynamic>> _bookings;
  final _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _bookings = List.from(widget.bookings);
  }

  Future<void> _refresh() async {
    try {
      final fetched = await _apiService.fetchBookings(widget.selectedDay);
      setState(() {
        // Match the calendar screen: a booking counts for every night it
        // occupies, not only its check-in day.
        final day = DateTime(widget.selectedDay.year, widget.selectedDay.month,
            widget.selectedDay.day);
        _bookings = fetched.where((b) {
          final ci = DateTime.tryParse(b['checkIn']?.toString() ?? '');
          final co = DateTime.tryParse(b['checkOut']?.toString() ?? '');
          if (ci == null || co == null) return false; // unreadable dates
          final start = DateTime(ci.year, ci.month, ci.day);
          final end = DateTime(co.year, co.month, co.day);
          if (!end.isAfter(start)) return day == start;
          return !day.isBefore(start) && day.isBefore(end);
        }).toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEEE d MMMM').format(widget.selectedDay);
    final guests = _bookings.fold<int>(0, (sum, b) {
      final rooms = b['rooms'] as List?;
      if (rooms != null && rooms.isNotEmpty) {
        return sum + rooms.fold<int>(0, (s, r) => s + ((r['pax'] as int?) ?? 0));
      }
      return sum;
    });

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            LargeTitleSliverAppBar(
              title: dayLabel,
              subtitle: 'Everyone staying this night',
              maxWidth: AppLayout.maxForm,
            ),
            _summary([
              Metric('${_bookings.length}', 'Bookings'),
              Metric('${_roomsIn(_bookings)}', 'Rooms'),
              if (guests > 0) Metric('$guests', 'Guests'),
            ]),
            if (_bookings.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No one is staying',
                  message: 'There are no bookings for this night.',
                ),
              )
            else
              _list(_bookings, (booking) => BookingCard(
                    booking: booking,
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
                                selectedDay: widget.selectedDay,
                              ),
                            ),
                          );
                          if (result == true) _refresh();
                        },
                      ),
                    ],
                  )),
          ],
        ),
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
