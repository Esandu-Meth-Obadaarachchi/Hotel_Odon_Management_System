import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
      backgroundColor: const Color(0xFFF5F6FA),
      body: RefreshIndicator(
        onRefresh: _fetchFutureBookings,
        color: Colors.indigo,
        child: CustomScrollView(
          slivers: [
            // Gradient header
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              backgroundColor: Colors.indigo,
              iconTheme: const IconThemeData(color: Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                title: const Text(
                  'Upcoming Bookings',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Icon(
                        Icons.upcoming_rounded,
                        size: 56,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.indigo),
                ),
              )
            else if (_futureBookings.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available_rounded,
                          size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'No upcoming bookings',
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pull down to refresh',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Stats banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _statsBanner(),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildBookingCard(_futureBookings[i]),
                    childCount: _futureBookings.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statsBanner() {
    final totalRooms = _futureBookings.fold<int>(0, (sum, b) {
      final rooms = b['rooms'] as List?;
      return sum + (rooms != null && rooms.isNotEmpty ? rooms.length : 1);
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _statPill(Icons.upcoming_rounded,
              '${_futureBookings.length} booking${_futureBookings.length != 1 ? 's' : ''}'),
          const SizedBox(width: 10),
          _statPill(Icons.hotel_rounded,
              '$totalRooms room${totalRooms != 1 ? 's' : ''}'),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }

  // ─── Booking card (matches view_bookings_screen style) ───────────────────

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final guestName = booking['guestName'] as String? ?? '';
    final guestPhone = booking['guestPhone'] as String? ?? '';
    final package = booking['package'] as String? ?? 'N/A';
    final extraDetails = (booking['extraDetails'] as String?)?.trim() ?? '';
    final numOfNights = booking['num_of_nights']?.toString() ?? 'N/A';
    final total = booking['total'] as String? ?? '';
    final advance = booking['advance'] as String? ?? '';
    final needDriver = booking['needDriver'] == true;

    final checkIn =
        booking['checkIn'] != null ? DateTime.parse(booking['checkIn']) : null;
    final checkOut = booking['checkOut'] != null
        ? DateTime.parse(booking['checkOut'])
        : null;

    final isNewFormat =
        booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty;
    final rooms = isNewFormat
        ? List<Map<String, dynamic>>.from(
            (booking['rooms'] as List).map((r) => Map<String, dynamic>.from(r)))
        : <Map<String, dynamic>>[];

    // Days until check-in
    final daysUntil = checkIn != null
        ? checkIn.difference(DateTime.now()).inDays
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
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
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guestName.isNotEmpty ? guestName : 'Guest',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      if (guestPhone.isNotEmpty)
                        Text(guestPhone,
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.indigo.shade400)),
                    ],
                  ),
                ),
                // Countdown chip
                if (daysUntil != null && daysUntil >= 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: daysUntil <= 3
                          ? Colors.orange.shade100
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: daysUntil <= 3
                            ? Colors.orange.shade300
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      daysUntil == 0
                          ? 'Today'
                          : '${daysUntil}d away',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: daysUntil <= 3
                            ? Colors.orange.shade800
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // Edit button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.indigo,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit,
                        color: Colors.white, size: 16),
                  ),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditBookingScreen(
                          booking: booking,
                          selectedDay:
                              checkIn ?? DateTime.now(),
                        ),
                      ),
                    );
                    if (result == true) _fetchFutureBookings();
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
                // Rooms
                if (isNewFormat) ...[
                  const Text('Rooms',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: rooms.map(_buildRoomChip).toList(),
                  ),
                ] else ...[
                  Row(children: [
                    _buildRoomChip({
                      'roomNumber': booking['roomNumber'] ?? 'N/A',
                      'roomType': booking['roomType'] ?? 'N/A',
                      'pax':
                          _paxForType(booking['roomType'] as String? ?? ''),
                    }),
                  ]),
                ],

                if (needDriver) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drive_eta,
                            size: 15, color: Colors.amber.shade800),
                        const SizedBox(width: 6),
                        Text(
                          'Driver Room Required',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                        child: _detailItem(Icons.card_giftcard_rounded,
                            'Package', package, Colors.purple)),
                    Expanded(
                        child: _detailItem(Icons.nights_stay_rounded,
                            'Nights', numOfNights, Colors.indigo)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _detailItem(Icons.login_rounded, 'Check-in',
                            _fmtDate(checkIn), Colors.green)),
                    Expanded(
                        child: _detailItem(Icons.logout_rounded, 'Check-out',
                            _fmtDate(checkOut), Colors.red)),
                  ],
                ),

                if (total.isNotEmpty || advance.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (total.isNotEmpty)
                        Expanded(
                            child: _detailItem(
                                Icons.monetization_on_rounded,
                                'Total',
                                'LKR $total',
                                Colors.teal)),
                      if (advance.isNotEmpty)
                        Expanded(
                            child: _detailItem(Icons.payments_rounded,
                                'Advance', 'LKR $advance', Colors.orange)),
                    ],
                  ),
                ],

                if (extraDetails.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            extraDetails,
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700),
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
        border:
            Border.all(color: chipColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(roomNum.padLeft(3, '0'),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: chipColor)),
          Text(roomType,
              style: TextStyle(
                  fontSize: 10,
                  color: chipColor,
                  fontWeight: FontWeight.w600)),
          Text('${pax}pax',
              style: TextStyle(
                  fontSize: 10,
                  color: chipColor.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _detailItem(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'N/A';
    return DateFormat('d MMM yyyy').format(d);
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
