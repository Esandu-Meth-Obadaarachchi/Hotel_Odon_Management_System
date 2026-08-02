import 'package:flutter/material.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/bookings/room_selection_screen.dart';
import 'package:odon_booking/features/rooms/room_config_screen.dart';
import 'package:odon_booking/features/bookings/view_bookings_screen.dart';
import 'package:odon_booking/features/auth/login_screen.dart';
import 'package:odon_booking/features/inventory/add_inventory_item_screen.dart';
import 'package:odon_booking/features/financials/calculate_profit_page.dart';
import 'package:odon_booking/features/invoices/generate_invoice_screen.dart';
import 'package:odon_booking/features/financials/expenses_screen.dart';
import 'package:odon_booking/features/guests/guests_list_screen.dart';

// ── Package meta ──────────────────────────────────────────────────────────────

const _pkgColor = {
  'Full Board':  Color(0xFF16A34A),
  'Half Board':  Color(0xFF2563EB),
  'BnB':         Color(0xFF7C3AED),
  'Room Only':   Color(0xFF0891B2),
  'Dinner Only': Color(0xFFEA580C),
};

const _pkgAbbrev = {
  'Full Board':  'FB',
  'Half Board':  'HB',
  'BnB':         'B&B',
  'Room Only':   'RO',
  'Dinner Only': 'DO',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  late TabController _tabController;
  int _dayOffset = 0; // 0 = today, 1 = tomorrow

  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _roomConfig  = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _dayOffset = _tabController.index);
        }
      });
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  DateTime get _selectedDay {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + _dayOffset);
  }

  Future<void> _fetchData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final bookings = await _apiService.fetchBookings(DateTime.now());
      final config   = await _apiService.fetchRoomConfig();
      setState(() {
        _allBookings = bookings;
        _roomConfig  = List<Map<String, dynamic>>.from(
          (config['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Computed helpers ─────────────────────────────────────────────────────────

  bool _activeThatDay(Map<String, dynamic> b, DateTime day) {
    try {
      final ci = DateTime.parse(b['checkIn']);
      final co = DateTime.parse(b['checkOut']);
      final d  = DateTime(day.year, day.month, day.day);
      final ni = DateTime(ci.year, ci.month, ci.day);
      final no = DateTime(co.year, co.month, co.day);
      return !d.isBefore(ni) && d.isBefore(no);
    } catch (_) { return false; }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _active =>
      _allBookings.where((b) => _activeThatDay(b, _selectedDay)).toList();

  // Returns { booking, room } for the given room number, or null if free
  Map<String, dynamic>? _infoForRoom(String roomNum) {
    for (final b in _active) {
      final rooms = b['rooms'] as List?;
      if (rooms != null && rooms.isNotEmpty) {
        for (final r in rooms) {
          if (r['roomNumber'].toString() == roomNum) {
            return {'booking': b, 'room': Map<String, dynamic>.from(r)};
          }
        }
      } else if (b['roomNumber']?.toString() == roomNum) {
        return {
          'booking': b,
          'room': {
            'roomNumber': roomNum,
            'roomType': b['roomType'] ?? '',
            'pax': _paxForType(b['roomType'] as String? ?? ''),
          },
        };
      }
    }
    return null;
  }

  int _paxForType(String t) {
    switch (t) {
      case 'Triple':      return 3;
      case 'Family':      return 4;
      case 'Family Plus': return 5;
      default:            return 2;
    }
  }

  int _bookingPax(Map<String, dynamic> b) {
    final rooms = b['rooms'] as List?;
    if (rooms != null && rooms.isNotEmpty) {
      return rooms.fold<int>(0, (s, r) => s + (r['pax'] as int? ?? 0));
    }
    return _paxForType(b['roomType'] as String? ?? '');
  }

  // Bookings checking out on [day] — their checkout morning breakfast still needs prep.
  List<Map<String, dynamic>> _checkingOutOn(DateTime day) {
    return _allBookings.where((b) {
      try {
        final co = DateTime.parse(b['checkOut']);
        return _sameDay(co, day);
      } catch (_) { return false; }
    }).toList();
  }

  Map<String, int> get _meals {
    int breakfast = 0, lunch = 0, dinner = 0;

    // Guests staying on _selectedDay (checkIn <= day < checkOut)
    for (final b in _active) {
      final pax        = _bookingPax(b);
      final pkg        = b['package'] as String? ?? '';
      final mealStart  = b['mealStart'] as String? ?? 'Lunch';
      final ci         = DateTime.tryParse(b['checkIn'] ?? '');
      final isFirstDay = ci != null && _sameDay(ci, _selectedDay);

      switch (pkg) {
        case 'BnB':
          if (!isFirstDay) breakfast += pax;
          break;
        case 'Full Board':
          if (isFirstDay) {
            if (mealStart == 'Lunch') { lunch += pax; dinner += pax; }
            else                      { dinner += pax; }
          } else {
            breakfast += pax; lunch += pax; dinner += pax;
          }
          break;
        case 'Half Board':
          if (isFirstDay) {
            if (mealStart == 'Lunch') { lunch += pax; dinner += pax; }
            else                      { dinner += pax; }
          } else {
            breakfast += pax; dinner += pax;
          }
          break;
        case 'Dinner Only':
          dinner += pax;
          break;
      }
    }

    // Guests checking OUT on _selectedDay — they still need breakfast that morning.
    for (final b in _checkingOutOn(_selectedDay)) {
      final pkg = b['package'] as String? ?? '';
      if (pkg == 'Full Board' || pkg == 'Half Board' || pkg == 'BnB') {
        breakfast += _bookingPax(b);
      }
    }

    return {'breakfast': breakfast, 'lunch': lunch, 'dinner': dinner};
  }

  int get _occupiedCount {
    final seen = <String>{};
    for (final b in _active) {
      final rooms = b['rooms'] as List?;
      if (rooms != null && rooms.isNotEmpty) {
        for (final r in rooms) seen.add(r['roomNumber'].toString());
      } else if (b['roomNumber'] != null) {
        seen.add(b['roomNumber'].toString());
      }
    }
    return seen.length;
  }

  int get _totalGuests => _active.fold<int>(0, (s, b) => s + _bookingPax(b));
  int get _availableRooms =>
      _roomConfig.where((r) => r['isBlocked'] != true).length - _occupiedCount;

  // ── Layout ────────────────────────────────────────────────────────────────

  /// Widest the dashboard content is allowed to get on large screens.
  static const double _maxContentWidth = 1240;

  /// Two-column dashboard once there is room for it (desktop / large tablet).
  bool _isWide(double w) => w >= 900;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = _isWide(constraints.maxWidth);
                  return CustomScrollView(
                    slivers: [
                      _appBar(),
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                            child: wide ? _wideBody() : _narrowBody(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _narrowBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dayToggle(),
          if (_error != null) _errorBanner(),
          _statsRow(),
          _roomMap(wrapTiles: false),
          _mealSection(),
          _quickActions(),
          const SizedBox(height: 24),
        ],
      );

  /// Desktop: toggle + stats span the full width, then room map (wide column)
  /// sits beside meals + quick actions so nothing is stretched edge-to-edge.
  Widget _wideBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) _errorBanner(),
          // Toggle and stats share one line — three full-width stat cards on a
          // desktop monitor would otherwise be absurdly wide and mostly empty.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _dayToggleBox()),
                  const SizedBox(width: 16),
                  ..._statCards(),
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _roomMap(wrapTiles: true)),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mealSection(),
                    _quickActions(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      );

  // ── App bar ───────────────────────────────────────────────────────────────

  Widget _appBar() {
    final now = DateTime.now();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${now.day} ${months[now.month - 1]} ${now.year}';

    return SliverAppBar(
      expandedHeight: 90,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF4F46E5),
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.hotel, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('ODON Hotel',
                          style: TextStyle(color: Colors.white, fontSize: 20,
                              fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                      Text(dateStr,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                    ],
                  ),
                  const Spacer(),
                  _iconBtn(Icons.refresh, _fetchData),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.logout, () => Navigator.pushAndRemoveUntil(
                    context, MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 19),
    ),
  );

  // ── Day toggle ───────────────────────────────────────────────────────────

  Widget _dayToggle() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: _dayToggleBox(),
      );

  Widget _dayToggleBox() {
    return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF4F46E5),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          padding: const EdgeInsets.all(4),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.today, size: 15), SizedBox(width: 6), Text('Today'),
            ])),
            Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.event, size: 15), SizedBox(width: 6), Text('Tomorrow'),
            ])),
          ],
        ),
      );
  }

  // ── Error banner ─────────────────────────────────────────────────────────

  Widget _errorBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(children: [
      Icon(Icons.warning_rounded, color: Colors.red.shade400, size: 18),
      const SizedBox(width: 8),
      const Expanded(child: Text('Could not load data. Pull down to retry.',
          style: TextStyle(fontSize: 13, color: Colors.red))),
    ]),
  );

  // ── Stats row ────────────────────────────────────────────────────────────

  Widget _statsRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: _statCards()),
      );

  List<Widget> _statCards() => [
        _statCard('$_occupiedCount', 'Occupied', Icons.bed_rounded, const Color(0xFF4F46E5)),
        const SizedBox(width: 10),
        _statCard('${_availableRooms.clamp(0, 99)}', 'Available',
            Icons.door_back_door_rounded, const Color(0xFF16A34A)),
        const SizedBox(width: 10),
        _statCard('$_totalGuests', 'Guests', Icons.people_rounded, const Color(0xFF0891B2)),
      ];

  Widget _statCard(String value, String label, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
      ]),
    ),
  );

  // ── Room map ─────────────────────────────────────────────────────────────

  Widget _roomMap({required bool wrapTiles}) {
    final ground = _roomConfig.where((r) => r['floor'] == 'Ground').toList();
    final upper  = _roomConfig.where((r) => r['floor'] == 'Upper').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              const Icon(Icons.hotel_rounded, color: Color(0xFF4F46E5), size: 18),
              const SizedBox(width: 8),
              const Text('Room Overview',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const Spacer(),
              GestureDetector(
                onTap: _showLegend,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                  child: const Row(children: [
                    Icon(Icons.info_outline, size: 13, color: Color(0xFF64748B)),
                    SizedBox(width: 4),
                    Text('Legend', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ]),
                ),
              ),
            ]),
          ),
          if (ground.isNotEmpty) ...[
            _floorLabel('Ground Floor'),
            _floorRow(ground, wrapTiles),
            const SizedBox(height: 4),
          ],
          if (upper.isNotEmpty) ...[
            _floorLabel('Upper Floor'),
            _floorRow(upper, wrapTiles),
          ],
          const SizedBox(height: 14),
        ]),
      ),
    );
  }

  void _showLegend() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Color Legend'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ..._pkgColor.entries.map((e) => _legendRow(e.value, e.key)),
        _legendRow(const Color(0xFFCBD5E1), 'Available'),
        _legendRow(const Color(0xFF475569), 'Blocked'),
      ]),
      actions: [TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      )],
    ),
  );

  Widget _legendRow(Color c, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(width: 16, height: 16,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13)),
    ]),
  );

  Widget _floorLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 0, 6),
    child: Text(label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8),
            letterSpacing: 0.5)),
  );

  Widget _floorRow(List<Map<String, dynamic>> rooms, bool wrapTiles) {
    Widget tileFor(Map<String, dynamic> room) =>
        _roomTile(room, _infoForRoom(room['roomNumber'] as String));

    // Desktop has the width to show every room at once — wrap instead of
    // hiding rooms behind a horizontal scroll that needs a mouse drag.
    if (wrapTiles) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rooms.map((r) => SizedBox(height: 120, child: tileFor(r))).toList(),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: rooms.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: tileFor(rooms[i]),
        ),
      ),
    );
  }

  Widget _roomTile(Map<String, dynamic> room, Map<String, dynamic>? info) {
    final roomNum   = (room['roomNumber'] as String).padLeft(3, '0');
    final isBlocked = room['isBlocked'] == true;
    final baseType  = room['baseType'] as String? ?? 'Double';

    late Color tileColor;
    late Color textColor;
    String? pkgAbbr;
    String? guest;
    String? roomType;
    int?    pax;

    if (isBlocked) {
      tileColor = const Color(0xFF475569);
      textColor = Colors.white;
    } else if (info != null) {
      final b   = info['booking'] as Map<String, dynamic>;
      final r   = info['room']    as Map<String, dynamic>;
      final pkg = b['package'] as String? ?? '';
      tileColor = _pkgColor[pkg] ?? const Color(0xFF64748B);
      textColor = Colors.white;
      pkgAbbr   = _pkgAbbrev[pkg] ?? pkg;
      guest     = (b['guestName'] as String? ?? 'Guest').split(' ').first;
      roomType  = r['roomType'] as String? ?? baseType;
      pax       = r['pax'] as int? ?? 0;
    } else {
      tileColor = const Color(0xFFE2E8F0);
      textColor = const Color(0xFF94A3B8);
    }

    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: info != null ? 0.14 : 0.05),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top row: room number + badge
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(roomNum,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
              if (pkgAbbr != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(pkgAbbr,
                      style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              if (isBlocked)
                Icon(Icons.lock_rounded, color: textColor.withValues(alpha: 0.7), size: 11),
            ]),
            // Bottom info block
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isBlocked)
                Text('Manager', style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.8)))
              else if (info != null) ...[
                Text(guest ?? '',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 2),
                Text(_shortType(roomType ?? ''),
                    style: TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.85))),
                const SizedBox(height: 1),
                Row(children: [
                  Icon(Icons.person, size: 9, color: textColor.withValues(alpha: 0.8)),
                  const SizedBox(width: 2),
                  Text('${pax}pax', style: TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.8))),
                ]),
              ] else ...[
                Text(baseType, style: TextStyle(fontSize: 10, color: textColor)),
                Text('Free', style: TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.65))),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  String _shortType(String t) => const {
    'Family Plus': 'Fam+',
    'Family':      'Family',
    'Triple':      'Triple',
    'Double':      'Double',
  }[t] ?? t;

  // ── Meal section ──────────────────────────────────────────────────────────

  Widget _mealSection() {
    final m = _meals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(Icons.restaurant_menu_rounded, color: Color(0xFF4F46E5), size: 18),
              SizedBox(width: 8),
              Text('Meal Count', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(children: [
              _mealCard('Breakfast', m['breakfast']!, Icons.wb_sunny_rounded,    const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              _mealCard('Lunch',     m['lunch']!,     Icons.restaurant_rounded,  const Color(0xFF16A34A)),
              const SizedBox(width: 8),
              _mealCard('Dinner',    m['dinner']!,    Icons.dinner_dining_rounded, const Color(0xFF7C3AED)),
            ]),
          ),
          // Package breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Wrap(spacing: 6, runSpacing: 6, children: _pkgColor.keys.map((pkg) {
              final count = _active.where((b) => b['package'] == pkg).length;
              if (count == 0) return const SizedBox.shrink();
              final color = _pkgColor[pkg]!;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text('${_pkgAbbrev[pkg]} × $count',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              );
            }).toList()),
          ),
        ]),
      ),
    );
  }

  Widget _mealCard(String label, int pax, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text('$pax', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text('pax', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.75))),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            textAlign: TextAlign.center),
      ]),
    ),
  );

  // ── Quick actions ─────────────────────────────────────────────────────────

  Widget _quickActions() {
    final actions = <_QuickAction>[
      _QuickAction('New Booking', Icons.add_circle_rounded, const Color(0xFF4F46E5),
          () => RoomSelectionScreen()),
      _QuickAction('Bookings', Icons.calendar_month_rounded, const Color(0xFF16A34A),
          () => ViewBookingsScreen()),
      _QuickAction('Guests', Icons.people_alt_rounded, const Color(0xFFDB2777),
          () => const GuestsListScreen()),
      _QuickAction('Inventory', Icons.inventory_2_rounded, const Color(0xFFF59E0B),
          () => AddInventoryItemScreen()),
      _QuickAction('Profit', Icons.analytics_rounded, const Color(0xFF8B5CF6),
          () => CalculateProfitPage()),
      _QuickAction('Invoice', Icons.receipt_long_rounded, const Color(0xFFEF4444),
          () => GenerateInvoiceScreen()),
      _QuickAction('Expenses', Icons.attach_money_rounded, const Color(0xFF0891B2),
          () => ExpensesAndSalaryScreen()),
      _QuickAction('Room Config', Icons.meeting_room_rounded, const Color(0xFF475569),
          () => RoomConfigScreen()),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick Actions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          const gap = 10.0;
          // Aim for ~100px tiles, capped at 4 columns so the 8 actions stay in a
          // tidy block instead of stretching into one long row on desktop.
          final cols = ((c.maxWidth + gap) / 100).floor().clamp(2, 4);
          final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: actions
                .map((a) => SizedBox(width: tileW, height: 96, child: _actionTile(a)))
                .toList(),
          );
        }),
      ]),
    );
  }

  Widget _actionTile(_QuickAction a) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => a.builder())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(a.icon, color: a.color, size: 23),
              ),
              const SizedBox(height: 8),
              Text(a.label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155),
                      height: 1.1),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function() builder;
  const _QuickAction(this.label, this.icon, this.color, this.builder);
}
