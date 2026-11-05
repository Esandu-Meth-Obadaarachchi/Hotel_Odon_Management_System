import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/features/bookings/widgets/booking_card.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/invoices/booking_invoice.dart';
import 'edit_booking_screen.dart';
import 'future_bookings_screen.dart';
import 'past_bookings_screen.dart';
import 'selected_day_booking.dart';

class ViewBookingsScreen extends StatefulWidget {
  @override
  _ViewBookingsScreenState createState() => _ViewBookingsScreenState();
}

class _ViewBookingsScreenState extends State<ViewBookingsScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  // Opens on today so the day's guests are visible without a tap.
  DateTime? _selectedDay = DateTime.now();
  List<Map<String, dynamic>> _bookingsForSelectedDay = [];
  Map<DateTime, List> _events = {};
  int _totalRoomNightsForMonth = 0;
  bool _calendarExpanded = true;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchMonthEvents();
  }

  // Returns the number of rooms in a booking (handles old + new format)
  int _roomCount(Map<String, dynamic> booking) {
    if (booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty) {
      return (booking['rooms'] as List).length;
    }
    return 1;
  }

  // Returns room count across all events on a day
  int _roomCountForDay(List events) {
    int total = 0;
    for (final b in events) {
      total += _roomCount(b as Map<String, dynamic>);
    }
    return total;
  }

  void _updateSelectedDayBookings(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    _bookingsForSelectedDay = List<Map<String, dynamic>>.from(
      (_events[key] ?? []).map((b) => Map<String, dynamic>.from(b as Map)),
    );
  }

  // Every night a booking occupies: check-in night through the night before
  // check-out. A 14th → 16th stay occupies the 14th and the 15th.
  List<DateTime> _nightsOf(DateTime checkIn, DateTime checkOut) {
    final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final end = DateTime(checkOut.year, checkOut.month, checkOut.day);

    // Day-use / bad data (check-out on or before check-in): still show it once.
    if (!end.isAfter(start)) return [start];

    final nights = <DateTime>[];
    for (var i = 0; ; i++) {
      final night = DateTime(start.year, start.month, start.day + i);
      if (!night.isBefore(end)) break;
      nights.add(night);
    }
    return nights;
  }

  Future<void> _fetchMonthEvents() async {
    try {
      final bookings = await _apiService.fetchBookingsForMonth(_focusedDay);
      final Map<DateTime, List> events = {};
      int totalRoomNights = 0;

      int skipped = 0;

      for (final booking in bookings) {
        // A record with a missing or malformed date must not take the whole
        // calendar down with it — skip it and carry on.
        final checkInDate = DateTime.tryParse(booking['checkIn']?.toString() ?? '');
        final checkOutDate = DateTime.tryParse(booking['checkOut']?.toString() ?? '');
        if (checkInDate == null || checkOutDate == null) {
          skipped++;
          continue;
        }

        final rooms = _roomCount(booking);
        final nights = _nightsOf(checkInDate, checkOutDate);

        if (checkInDate.month == _focusedDay.month && checkInDate.year == _focusedDay.year) {
          totalRoomNights += nights.length * rooms;
        }

        // A booking belongs to every night it occupies, not just its check-in
        // day — otherwise a multi-night stay looks like a free day mid-stay.
        for (final night in nights) {
          if (night.month != _focusedDay.month || night.year != _focusedDay.year) continue;
          events[night] = [...(events[night] ?? []), booking];
        }
      }

      if (skipped > 0) {
        print('Skipped $skipped booking(s) with an unreadable check-in/out date');
      }

      setState(() {
        _events = events;
        _totalRoomNightsForMonth = totalRoomNights;
        if (_selectedDay != null) _updateSelectedDayBookings(_selectedDay!);
      });
    } catch (e) {
      print('Failed to fetch month events: $e');
    }
  }

  List _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final wide = AppLayout.isWide(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastBookingsScreen())),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('Past'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FutureBookingsScreen())),
            icon: const Icon(Icons.upcoming_outlined, size: 18),
            label: const Text('Upcoming'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide ? _wideBody() : _narrowBody(),
    );
  }

  /// Desktop: calendar in a fixed column on the left, the day's bookings on
  /// the right — no collapsing needed when there is room for both.
  Widget _wideBody() {
    return PageBody(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 420,
            child: ListView(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              children: [
                _buildMonthSummary(),
                const SizedBox(height: 12),
                _buildCalendar(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                if (_selectedDay != null) _buildDayHeader(),
                Expanded(child: _buildBookingList()),
                if (_selectedDay != null) _buildBottomActions(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrowBody() {
    return Column(
      children: [
        // Collapsible: month summary + calendar
        AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.ease,
          alignment: Alignment.topCenter,
          child: _calendarExpanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      _buildMonthSummary(),
                      const SizedBox(height: 12),
                      _buildCalendar(),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),

        // Toggle strip
        Pressable(
          onTap: () => setState(() => _calendarExpanded = !_calendarExpanded),
          pressedScale: 1,
          semanticLabel: _calendarExpanded ? 'Hide calendar' : 'Show calendar',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_calendarExpanded ? 'Hide calendar' : 'Show calendar',
                    style: AppText.footnote.copyWith(color: AppColors.ink2)),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: _calendarExpanded ? 0.5 : 0,
                  duration: AppMotion.base,
                  curve: AppMotion.ease,
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.ink2, size: 20),
                ),
              ],
            ),
          ),
        ),

        if (_selectedDay != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDayHeader(),
          ),

        Expanded(child: _buildBookingList()),

        if (_selectedDay != null) _buildBottomActions(),
      ],
    );
  }

  Widget _buildMonthSummary() {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room-nights in ${DateFormat('MMMM').format(_focusedDay)}', style: AppText.footnote),
                const SizedBox(height: 4),
                Text('$_totalRoomNightsForMonth', style: AppText.number(28)),
              ],
            ),
          ),
          const IconWell(Icons.nights_stay_outlined, size: 40),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
            _updateSelectedDayBookings(selectedDay);
          });
        },
        onFormatChanged: (format) => setState(() => _calendarFormat = format),
        onPageChanged: (focusedDay) {
          setState(() => _focusedDay = focusedDay);
          _fetchMonthEvents();
        },
        eventLoader: _getEventsForDay,
        rowHeight: 48,
        daysOfWeekHeight: 28,
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          formatButtonShowsNext: false,
          titleTextStyle: AppText.headline,
          leftChevronIcon: const Icon(Icons.chevron_left_rounded, color: AppColors.ink),
          rightChevronIcon: const Icon(Icons.chevron_right_rounded, color: AppColors.ink),
          formatButtonTextStyle: AppText.footnote.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
          formatButtonDecoration: BoxDecoration(
            border: Border.all(color: AppColors.hairlineStrong),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: AppText.eyebrow.copyWith(fontSize: 10),
          weekendStyle: AppText.eyebrow.copyWith(fontSize: 10),
        ),
        calendarStyle: const CalendarStyle(
          markerDecoration: BoxDecoration(),
          outsideDaysVisible: false,
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            final events = _getEventsForDay(day);
            final roomCount = _roomCountForDay(events);
            return _buildCalendarDay(day, roomCount, isSelected: false, isToday: false);
          },
          todayBuilder: (context, day, focusedDay) {
            final events = _getEventsForDay(day);
            final roomCount = _roomCountForDay(events);
            return _buildCalendarDay(day, roomCount, isSelected: false, isToday: true);
          },
          selectedBuilder: (context, day, focusedDay) {
            final events = _getEventsForDay(day);
            final roomCount = _roomCountForDay(events);
            return _buildCalendarDay(day, roomCount, isSelected: true, isToday: isSameDay(day, DateTime.now()));
          },
        ),
      ),
    );
  }

  Widget _buildCalendarDay(DateTime day, int roomCount, {required bool isSelected, required bool isToday}) {
    final bg = isSelected ? AppColors.ink : Colors.transparent;
    final fg = isSelected ? Colors.white : AppColors.ink;

    return Center(
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: AppMotion.fast,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: isToday && !isSelected ? Border.all(color: AppColors.ink, width: 1.5) : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${day.day}',
                style: AppText.number(14, weight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500, color: fg),
              ),
            ),
            if (roomCount > 0)
              Positioned(
                bottom: -4,
                right: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.halfBoard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text(
                    '$roomCount',
                    textAlign: TextAlign.center,
                    style: AppText.number(9.5, color: Colors.white).copyWith(height: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader() {
    final day = _selectedDay!;
    final roomsOnDay = _roomCountForDay(_getEventsForDay(day));
    final bookingsOnDay = _bookingsForSelectedDay.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(DateFormat('EEEE d MMMM').format(day), style: AppText.title.copyWith(fontSize: 18)),
          ),
          if (bookingsOnDay > 0) ...[
            StatusPill('$bookingsOnDay booking${bookingsOnDay > 1 ? 's' : ''}'),
            const SizedBox(width: 6),
            StatusPill('$roomsOnDay room${roomsOnDay > 1 ? 's' : ''}', color: AppColors.halfBoard),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingList() {
    if (_bookingsForSelectedDay.isEmpty) {
      return SingleChildScrollView(
        child: EmptyState(
          icon: _selectedDay == null ? Icons.touch_app_outlined : Icons.event_available_outlined,
          title: _selectedDay == null ? 'Pick a date' : 'No one is staying',
          message: _selectedDay == null
              ? 'Tap a day on the calendar to see who is staying.'
              : 'There are no bookings for this night.',
        ),
      );
    }

    final wide = AppLayout.isWide(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(wide ? 0 : 16, 4, wide ? 0 : 16, 16),
      itemCount: _bookingsForSelectedDay.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildBookingCard(_bookingsForSelectedDay[index]),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final checkIn = DateTime.tryParse(booking['checkIn']?.toString() ?? '');
    final checkOut = DateTime.tryParse(booking['checkOut']?.toString() ?? '');

    return BookingCard(
      booking: booking,
      status: _stayStatus(checkIn, checkOut),
      footer: _auditLine(booking),
      actions: [
        CardIconButton(
          Icons.ios_share_rounded,
          tooltip: 'Share invoice',
          onPressed: () => shareBookingInvoice(context, booking),
        ),
        CardIconButton(
          Icons.edit_outlined,
          tooltip: 'Edit booking',
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditBookingScreen(
                  booking: booking,
                  selectedDay: _selectedDay ?? _focusedDay,
                ),
              ),
            );
            if (result == true) await _fetchMonthEvents();
          },
        ),
      ],
    );
  }

  /// "Added by dad · Edited by esandu, 14 Aug" — from the server-stamped
  /// fields. Returns null for records created before the audit trail existed.
  Widget? _auditLine(Map<String, dynamic> booking) {
    final createdBy = (booking['createdBy'] as String?)?.trim() ?? '';
    final updatedBy = (booking['updatedBy'] as String?)?.trim() ?? '';
    if (createdBy.isEmpty && updatedBy.isEmpty) return null;

    String who(String email, String name) {
      final n = name.trim();
      if (n.isNotEmpty) return n.split(' ').first;
      return email.split('@').first;
    }

    final parts = <String>[];
    if (createdBy.isNotEmpty) {
      parts.add('Added by ${who(createdBy, booking['createdByName'] as String? ?? '')}');
    }
    // Only worth showing the editor when it is a genuine later edit.
    final updatedAt = DateTime.tryParse(booking['updatedAt'] as String? ?? '');
    final createdAt = DateTime.tryParse(booking['createdAt'] as String? ?? '') ??
        _createdFromId(booking['_id']);
    final wasEdited = updatedAt != null &&
        (createdAt == null || updatedAt.difference(createdAt).inSeconds > 5);
    if (updatedBy.isNotEmpty && wasEdited) {
      final label = who(updatedBy, booking['updatedByName'] as String? ?? '');
      parts.add('edited by $label ${_fmtDate(updatedAt)}');
    }
    if (parts.isEmpty) return null;

    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 13, color: AppColors.ink4),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// When a record was created, read from its Mongo ObjectId: the first 8 hex
  /// characters are the creation time in seconds. Covers bookings saved before
  /// createdAt was stored, which otherwise all looked edited.
  DateTime? _createdFromId(dynamic id) {
    final hex = id?.toString() ?? '';
    if (hex.length < 8) return null;
    final seconds = int.tryParse(hex.substring(0, 8), radix: 16);
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  // Shows whether the selected day is the check-in night or a later night of
  // the same stay, e.g. "Staying over · Night 2 of 2".
  Widget? _stayStatus(DateTime? checkIn, DateTime? checkOut) {
    final selected = _selectedDay;
    if (selected == null || checkIn == null || checkOut == null) return null;

    final nights = _nightsOf(checkIn, checkOut);
    final day = DateTime(selected.year, selected.month, selected.day);
    final index = nights.indexWhere((n) => isSameDay(n, day));
    if (index < 0) return null;

    final isCheckIn = index == 0;
    final nightLabel = nights.length == 1
        ? '1 night'
        : 'Night ${index + 1} of ${nights.length}';
    return StatusPill(
      '${isCheckIn ? 'Arrives' : 'Staying over'} · $nightLabel',
      color: isCheckIn ? AppColors.success : AppColors.info,
      icon: isCheckIn ? Icons.login_rounded : Icons.bedtime_outlined,
    );
  }

  Widget _buildBottomActions() {
    final wide = AppLayout.isWide(context);
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 0 : 16, 10, wide ? 0 : 16, 12),
      decoration: wide
          ? null
          : const BoxDecoration(
              color: AppColors.canvas,
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SelectedDayBookingsScreen(
                  selectedDay: _selectedDay ?? _focusedDay,
                  bookings: _bookingsForSelectedDay,
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_full_rounded, size: 18),
            label: const Text('Open full day'),
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'N/A';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }


}
