import 'package:flutter/material.dart';
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
  DateTime? _selectedDay;
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

      for (final booking in bookings) {
        final checkInDate = DateTime.parse(booking['checkIn']);
        final checkOutDate = DateTime.parse(booking['checkOut']);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'View Bookings',
          style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FutureBookingsScreen())),
            icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
            label: const Text('Upcoming', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Collapsible: month summary + calendar
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _calendarExpanded
                ? Column(
                    children: [
                      _buildMonthSummary(),
                      _buildCalendar(),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Toggle strip
          GestureDetector(
            onTap: () => setState(() => _calendarExpanded = !_calendarExpanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              color: Colors.indigo.shade50,
              child: Icon(
                _calendarExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.indigo,
                size: 22,
              ),
            ),
          ),

          // Selected day header
          if (_selectedDay != null) _buildDayHeader(),

          // Booking list
          Expanded(child: _buildBookingList()),

          // Bottom action row
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildMonthSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Room-Nights This Month', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text('$_totalRoomNightsForMonth', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              _buildSummaryButton('Past', Icons.history, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastBookingsScreen()))),
              const SizedBox(width: 8),
              _buildSummaryButton('Upcoming', Icons.upcoming, () => Navigator.push(context, MaterialPageRoute(builder: (_) => FutureBookingsScreen()))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
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
        headerStyle: const HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          formatButtonShowsNext: false,
        ),
        calendarStyle: const CalendarStyle(
          todayDecoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
          selectedDecoration: BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
          markerDecoration: BoxDecoration(),
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
            return _buildCalendarDay(day, roomCount, isSelected: true, isToday: false);
          },
        ),
      ),
    );
  }

  Widget _buildCalendarDay(DateTime day, int roomCount, {required bool isSelected, required bool isToday}) {
    Color bgColor = Colors.transparent;
    Color textColor = Colors.black87;
    if (isSelected) { bgColor = Colors.indigo; textColor = Colors.white; }
    else if (isToday) { bgColor = Colors.orange; textColor = Colors.white; }

    return Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                '${day.day}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
              ),
            ),
            if (roomCount > 0)
              Positioned(
                bottom: -5,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    '$roomCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1.2),
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
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${day.day} ${months[day.month - 1]} ${day.year}';
    final roomsOnDay = _roomCountForDay(_getEventsForDay(day));
    final bookingsOnDay = _bookingsForSelectedDay.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.indigo, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 15)),
          const Spacer(),
          if (bookingsOnDay > 0) ...[
            _pill('$bookingsOnDay booking${bookingsOnDay > 1 ? 's' : ''}', Colors.indigo.shade100, Colors.indigo),
            const SizedBox(width: 6),
            _pill('$roomsOnDay room${roomsOnDay > 1 ? 's' : ''}', Colors.red.shade100, Colors.red.shade700),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildBookingList() {
    if (_bookingsForSelectedDay.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _selectedDay == null ? 'Tap a date to view bookings' : 'No bookings on this day',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _bookingsForSelectedDay.length,
      itemBuilder: (context, index) => _buildBookingCard(_bookingsForSelectedDay[index]),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final guestName = booking['guestName'] as String? ?? '';
    final guestPhone = booking['guestPhone'] as String? ?? '';
    final package = booking['package'] as String? ?? 'N/A';
    final extraDetails = (booking['extraDetails'] as String?)?.trim() ?? '';
    final numOfNights = booking['num_of_nights']?.toString() ?? 'N/A';
    final total = booking['total'] as String? ?? '';
    final advance = booking['advance'] as String? ?? '';

    final checkIn = booking['checkIn'] != null ? DateTime.parse(booking['checkIn']) : null;
    final checkOut = booking['checkOut'] != null ? DateTime.parse(booking['checkOut']) : null;

    final stayStatus = _stayStatus(checkIn, checkOut);

    final needDriver = booking['needDriver'] == true;
    final isNewFormat = booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty;
    final rooms = isNewFormat
        ? List<Map<String, dynamic>>.from((booking['rooms'] as List).map((r) => Map<String, dynamic>.from(r)))
        : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: guest info ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guestName.isNotEmpty ? guestName : 'Guest',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      if (guestPhone.isNotEmpty)
                        Text(guestPhone, style: TextStyle(fontSize: 13, color: Colors.indigo.shade400)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Share invoice',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 16),
                  ),
                  onPressed: () => shareBookingInvoice(context, booking),
                ),
                IconButton(
                  tooltip: 'Edit booking',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.indigo,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                  ),
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
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Which night of the stay this day is ──────────────────────
                if (stayStatus != null) ...[
                  stayStatus,
                  const SizedBox(height: 10),
                ],

                // ── Rooms ────────────────────────────────────────────────────
                if (isNewFormat) ...[
                  const Text('Rooms', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: rooms.map((r) => _buildRoomChip(r)).toList(),
                  ),
                ] else ...[
                  // Legacy single-room booking
                  Row(
                    children: [
                      _buildRoomChip({
                        'roomNumber': booking['roomNumber'] ?? 'N/A',
                        'roomType': booking['roomType'] ?? 'N/A',
                        'pax': _paxForType(booking['roomType'] as String? ?? ''),
                      }),
                    ],
                  ),
                ],

                if (needDriver) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drive_eta, size: 15, color: Colors.amber.shade800),
                        const SizedBox(width: 6),
                        Text(
                          'Driver Room Required',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // ── Stay details ─────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(child: _detailItem(Icons.card_giftcard, 'Package', package, Colors.purple)),
                    Expanded(child: _detailItem(Icons.nights_stay, 'Nights', numOfNights, Colors.indigo)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _detailItem(Icons.login, 'Check-in', _fmtDate(checkIn), Colors.green)),
                    Expanded(child: _detailItem(Icons.logout, 'Check-out', _fmtDate(checkOut), Colors.red)),
                  ],
                ),

                // ── Financial ────────────────────────────────────────────────
                if (total.isNotEmpty || advance.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (total.isNotEmpty)
                        Expanded(child: _detailItem(Icons.monetization_on, 'Total', 'LKR $total', Colors.teal)),
                      if (advance.isNotEmpty)
                        Expanded(child: _detailItem(Icons.payments, 'Advance', 'LKR $advance', Colors.orange)),
                    ],
                  ),
                ],

                // ── Extra details ─────────────────────────────────────────────
                if (extraDetails.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            extraDetails,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
    final label = isCheckIn ? 'Check-in' : 'Staying over';
    final color = isCheckIn ? Colors.green.shade700 : Colors.blue.shade700;
    final icon = isCheckIn ? Icons.login : Icons.hotel;
    final nightLabel = nights.length == 1
        ? '1 night'
        : 'Night ${index + 1} of ${nights.length}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          Text('·', style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.6))),
          const SizedBox(width: 6),
          Text(nightLabel, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _buildRoomChip(Map<String, dynamic> room) {
    final roomNum = (room['roomNumber'] ?? 'N/A').toString();
    final roomType = (room['roomType'] ?? 'N/A').toString();
    final pax = room['pax'] as int? ?? _paxForType(roomType);

    Color chipColor;
    switch (roomType) {
      case 'Family Plus': chipColor = Colors.deepOrange; break;
      case 'Family':      chipColor = Colors.orange.shade700; break;
      case 'Triple':      chipColor = Colors.teal; break;
      case 'Double':      chipColor = Colors.indigo; break;
      default:            chipColor = Colors.grey; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            roomNum.padLeft(3, '0'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: chipColor),
          ),
          Text(roomType, style: TextStyle(fontSize: 10, color: chipColor, fontWeight: FontWeight.w600)),
          Text('${pax}pax', style: TextStyle(fontSize: 10, color: chipColor.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _detailItem(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SelectedDayBookingsScreen(
                selectedDay: _selectedDay ?? _focusedDay,
                bookings: _bookingsForSelectedDay,
              ),
            ),
          ),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text("View Full Day Details", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  int _paxForType(String type) {
    switch (type) {
      case 'Double': return 2;
      case 'Triple': return 3;
      case 'Family': return 4;
      case 'Family Plus': return 5;
      default: return 0;
    }
  }
}
