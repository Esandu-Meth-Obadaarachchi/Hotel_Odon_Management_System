import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/bookings/edit_booking_screen.dart';

class GuestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> guest;

  const GuestDetailScreen({super.key, required this.guest});

  @override
  State<GuestDetailScreen> createState() => _GuestDetailScreenState();
}

class _GuestDetailScreenState extends State<GuestDetailScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;

  String get _phone => (widget.guest['phone'] ?? '').toString();
  String get _name => (widget.guest['name'] ?? 'Guest').toString();

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _api.fetchGuestBookings(_phone);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Stats ────────────────────────────────────────────────────────────
  int _roomCount(Map<String, dynamic> b) {
    final rooms = b['rooms'];
    if (rooms is List && rooms.isNotEmpty) return rooms.length;
    return 1;
  }

  int get _totalRoomNights {
    return _bookings.fold<int>(0, (sum, b) {
      final n = (b['num_of_nights'] as num?)?.toInt() ?? 0;
      return sum + n * _roomCount(b);
    });
  }

  double get _totalRevenue {
    return _bookings.fold<double>(0, (sum, b) {
      final raw = b['total']?.toString() ?? '';
      final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
      return sum + (double.tryParse(cleaned) ?? 0);
    });
  }

  DateTime? get _lastVisit {
    DateTime? latest;
    for (final b in _bookings) {
      final ci = b['checkIn'] != null
          ? DateTime.tryParse(b['checkIn'].toString())
          : null;
      if (ci != null && (latest == null || ci.isAfter(latest))) latest = ci;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest')),
      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: ListView(
          padding: const EdgeInsets.only(top: 20, bottom: 32),
          children: [
            PageBody(
              maxWidth: AppLayout.maxForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 20),
                  _buildStatsRow(),
                  const SizedBox(height: 28),
                  _buildHistoryHeader(),
                  const SizedBox(height: 10),
                  ..._buildHistoryBody(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Row(
      children: [
        InitialsAvatar(_name, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name,
                  style: AppText.largeTitle.copyWith(fontSize: 26),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                [
                  if (_phone.isNotEmpty) _phone,
                  if (_lastVisit != null)
                    'Last visit ${DateFormat('d MMM yyyy').format(_lastVisit!)}',
                ].join(' · '),
                style: AppText.callout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return MetricStrip([
      Metric('${_bookings.length}', 'Bookings'),
      Metric('$_totalRoomNights', 'Room-nights'),
      Metric(NumberFormat.compact().format(_totalRevenue), 'Revenue',
          caption: 'LKR'),
    ], valueSize: 24);
  }

  Widget _buildHistoryHeader() {
    return Row(
      children: [
        Text('STAYS', style: AppText.eyebrow),
        const Spacer(),
        if (_bookings.isNotEmpty)
          Text('${_bookings.length} total',
              style: AppText.footnote.copyWith(fontSize: 12)),
      ],
    );
  }

  List<Widget> _buildHistoryBody() {
    if (_loading) {
      return const [
        Padding(
            padding: EdgeInsets.symmetric(vertical: 40), child: LoadingView())
      ];
    }
    if (_error != null) {
      return [
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load stays',
          message: 'Pull down to try again.',
          actionLabel: 'Retry',
          onAction: _loadBookings,
        ),
      ];
    }
    if (_bookings.isEmpty) {
      return const [
        EmptyState(icon: Icons.event_busy_outlined, title: 'No stays yet')
      ];
    }
    return [
      SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < _bookings.length; i++) ...[
            if (i > 0)
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider()),
            _buildBookingCard(_bookings[i]),
          ],
        ]),
      ),
    ];
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final ci = booking['checkIn'] != null
        ? DateTime.tryParse(booking['checkIn'].toString())
        : null;
    final co = booking['checkOut'] != null
        ? DateTime.tryParse(booking['checkOut'].toString())
        : null;
    final pkg = (booking['package'] ?? '').toString();
    final nights = (booking['num_of_nights'] as num?)?.toInt() ?? 0;
    final total = (booking['total'] ?? '').toString();
    final rooms = booking['rooms'];
    final isNew = rooms is List && rooms.isNotEmpty;
    final roomText = isNew
        ? rooms
            .map((r) => (r['roomNumber'] ?? '').toString().padLeft(3, '0'))
            .join(', ')
        : (booking['roomNumber'] ?? '?').toString();
    final totalNum = double.tryParse(total.replaceAll(RegExp(r'[^0-9.]'), ''));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditBookingScreen(
                booking: booking,
                selectedDay: ci ?? DateTime.now(),
              ),
            ),
          );
          if (result == true) _loadBookings();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.forPackage(pkg),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ci != null && co != null
                          ? '${DateFormat('d MMM').format(ci)} – ${DateFormat('d MMM yyyy').format(co)}'
                          : 'Dates unavailable',
                      style: AppText.bodyStrong.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pkg.isEmpty ? 'No plan' : pkg} · $nights night${nights == 1 ? '' : 's'} · Room $roomText',
                      style: AppText.footnote,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (total.isNotEmpty)
                Text(
                  totalNum == null
                      ? total
                      : NumberFormat('#,##0').format(totalNum),
                  style: AppText.number(14),
                ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
            ],
          ),
        ),
      ),
    );
  }
}
