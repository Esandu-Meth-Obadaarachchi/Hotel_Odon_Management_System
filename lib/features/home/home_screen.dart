import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/bookings/room_selection_screen.dart';
import 'package:odon_booking/features/rooms/room_config_screen.dart';
import 'package:odon_booking/features/bookings/view_bookings_screen.dart';
import 'package:odon_booking/features/bookings/widgets/booking_flags.dart';
import 'package:odon_booking/features/auth/login_screen.dart';
import 'package:odon_booking/features/inventory/add_inventory_item_screen.dart';
import 'package:odon_booking/features/financials/calculate_profit_page.dart';
import 'package:odon_booking/features/invoices/generate_invoice_screen.dart';
import 'package:odon_booking/features/financials/expenses_screen.dart';
import 'package:odon_booking/features/guests/guests_list_screen.dart';
import 'package:odon_booking/features/settings/user_access_screen.dart';
import 'package:odon_booking/features/auth/auth_gate.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

// ── Package meta ──────────────────────────────────────────────────────────────

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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiService _apiService = ApiService();

  // The room overview goes stale while the screen sits open (e.g. the manager
  // adds bookings from another device), so re-pull quietly on this interval.
  static const _autoRefreshInterval = Duration(seconds: 30);

  late TabController _tabController;
  int _dayOffset = 0; // 0 = today, 1 = tomorrow

  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _roomConfig  = [];
  bool _loading = true;
  String? _error;

  Timer? _autoRefreshTimer;
  bool _refreshing = false;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _dayOffset = _tabController.index);
        }
      });
    _fetchData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  // ── Auto refresh ────────────────────────────────────────────────────────────

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(_autoRefreshInterval, (_) => _fetchData(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back from the background: refresh now, then resume the ticker.
      _fetchData(silent: true);
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autoRefreshTimer?.cancel();
    }
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  DateTime get _selectedDay {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + _dayOffset);
  }

  // [silent] keeps the current data on screen while refetching — used by the
  // auto refresh so the overview updates without a spinner or scroll jump.
  Future<void> _fetchData({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) {
      setState(() { _loading = true; _error = null; });
    } else {
      setState(() {});
    }
    try {
      final bookings = await _apiService.fetchBookings(DateTime.now());
      final config   = await _apiService.fetchRoomConfig();
      if (!mounted) return;
      setState(() {
        _allBookings = bookings;
        _roomConfig  = List<Map<String, dynamic>>.from(
          (config['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
        );
        _loading = false;
        _error = null;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      // On a silent refresh keep whatever is already on screen; only flag it.
      setState(() { _loading = false; _error = e.toString(); });
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
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

  /// Guests arriving early on [_selectedDay] and guests leaving late from it,
  /// so the rooms and the kitchen can be ready for them.
  List<Map<String, dynamic>> get _earlyArrivals => _allBookings.where((b) {
        final ci = DateTime.tryParse(b['checkIn']?.toString() ?? '');
        return b['earlyCheckIn'] == true && ci != null && _sameDay(ci, _selectedDay);
      }).toList();

  List<Map<String, dynamic>> get _lateDepartures => _allBookings.where((b) {
        final co = DateTime.tryParse(b['checkOut']?.toString() ?? '');
        return b['lateCheckOut'] == true && co != null && _sameDay(co, _selectedDay);
      }).toList();

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

  /// Two-column dashboard once there is room for it (desktop / large tablet).
  bool _isWide(double w) => w >= 900;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = _isWide(MediaQuery.sizeOf(context).width);
    return Scaffold(
      extendBody: true,
      // Phones reach the actions from the bottom bar instead of a tile grid.
      bottomNavigationBar: wide ? null : _bottomBar(),
      body: AnimatedSwitcher(
        duration: AppMotion.base,
        switchInCurve: AppMotion.ease,
        child: _loading
            ? const LoadingView(key: ValueKey('loading'), label: 'Loading the house…')
            : RefreshIndicator(
                key: const ValueKey('content'),
                onRefresh: _fetchData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    _appBar(),
                    SliverToBoxAdapter(
                      child: PageBody(child: wide ? _wideBody() : _narrowBody()),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _narrowBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(),
          const SizedBox(height: AppSpace.lg),
          _dayToggleBox(),
          if (_error != null) ...[const SizedBox(height: AppSpace.md), _errorBanner()],
          const SizedBox(height: AppSpace.lg),
          _statsCard(),
          const SizedBox(height: AppSpace.lg),
          _roomMap(wrapTiles: false),
          const SizedBox(height: AppSpace.lg),
          _mealSection(),
          _timingSection(),
          // Clears the floating bottom bar.
          SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
        ],
      );

  /// Desktop: greeting + day switch share a line, then the room board (wide
  /// column) sits beside meals, timings and navigation.
  Widget _wideBody() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _intro()),
              const SizedBox(width: AppSpace.xl),
              SizedBox(width: 280, child: _dayToggleBox()),
            ],
          ),
          if (_error != null) ...[const SizedBox(height: AppSpace.lg), _errorBanner()],
          const SizedBox(height: AppSpace.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _statsCard(),
                  const SizedBox(height: AppSpace.lg),
                  _roomMap(wrapTiles: true),
                ]),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                flex: 2,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _quickActions(),
                  const SizedBox(height: AppSpace.lg),
                  _mealSection(),
                  _timingSection(),
                ]),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xxl),
        ],
      );

  // ── App bar ───────────────────────────────────────────────────────────────

  Widget _appBar() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      shape: const Border(),
      titleSpacing: 0,
      flexibleSpace: const Frosted(
        border: Border(bottom: BorderSide(color: AppColors.hairline, width: 0.5)),
        child: SizedBox.expand(),
      ),
      title: PageBody(
        alignment: Alignment.center,
        child: Row(
          children: [
            const BrandSeal(size: 38),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('The Odon', style: AppText.headline.copyWith(fontSize: 17)),
                  const SizedBox(height: 1),
                  Row(children: [
                    AnimatedContainer(
                      duration: AppMotion.base,
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _error != null
                            ? AppColors.danger
                            : (_refreshing ? AppColors.warning : AppColors.success),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_freshnessLabel(),
                          overflow: TextOverflow.ellipsis,
                          style: AppText.footnote.copyWith(fontSize: 12)),
                    ),
                  ]),
                ],
              ),
            ),
            _refreshBtn(),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout_rounded, size: 21),
              onPressed: () => Navigator.pushAndRemoveUntil(
                  context, MaterialPageRoute(builder: (_) => LoginScreen()), (_) => false),
            ),
          ],
        ),
      ),
    );
  }

  // Tells the user how stale the numbers are, so a quiet refresh is visible.
  String _freshnessLabel() {
    if (_refreshing) return 'Updating…';
    if (_error != null) return 'Offline · showing last data';
    if (_lastUpdated == null) return 'Not updated yet';
    final mins = DateTime.now().difference(_lastUpdated!).inMinutes;
    if (mins < 1) return 'Updated just now';
    if (mins == 1) return 'Updated 1 min ago';
    return 'Updated $mins mins ago';
  }

  Widget _refreshBtn() {
    if (_refreshing) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return IconButton(
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh_rounded, size: 22),
      onPressed: _fetchData,
    );
  }

  // ── Greeting ──────────────────────────────────────────────────────────────

  Widget _intro() {
    final now = DateTime.now();
    final hour = now.hour;
    final part = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final first = CurrentUser.current?.name.trim().split(' ').first ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('EEEE d MMMM').format(now).toUpperCase(), style: AppText.eyebrow),
          const SizedBox(height: 6),
          Text(first.isEmpty ? part : '$part, $first', style: AppText.largeTitle),
        ],
      ),
    );
  }

  // ── Day toggle ───────────────────────────────────────────────────────────

  Widget _dayToggleBox() => SegmentedTabs(
        controller: _tabController,
        labels: const ['Today', 'Tomorrow'],
      );

  String get _dayWord => _dayOffset == 0 ? 'today' : 'tomorrow';

  // ── Error banner ─────────────────────────────────────────────────────────

  Widget _errorBanner() => InlineBanner(
        'Couldn\'t reach the server. Showing the last data we had.',
        tone: BannerTone.danger,
        actionLabel: 'Retry',
        onAction: _fetchData,
      );

  // ── Occupancy ────────────────────────────────────────────────────────────

  Widget _statsCard() {
    final total = _roomConfig.where((r) => r['isBlocked'] != true).length;
    final occ = _occupiedCount;
    final ratio = total == 0 ? 0.0 : occ / total;
    return MetricStrip(
      [
        Metric('$occ', 'Occupied', caption: 'of $total rooms'),
        Metric('${_availableRooms.clamp(0, 99)}', 'Available', caption: 'to sell $_dayWord'),
        Metric('$_totalGuests', 'Guests', caption: 'in house'),
      ],
      footer: Row(children: [
        Expanded(child: ProportionBar(ratio)),
        const SizedBox(width: AppSpace.md),
        Text('${(ratio * 100).round()}% occupancy',
            style: AppText.footnote.copyWith(color: AppColors.ink2, fontSize: 12)),
      ]),
    );
  }

  // ── Room map ─────────────────────────────────────────────────────────────

  Widget _roomMap({required bool wrapTiles}) {
    final ground = _roomConfig.where((r) => r['floor'] == 'Ground').toList();
    final upper = _roomConfig.where((r) => r['floor'] == 'Upper').toList();

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: SectionHeader('Rooms',
              subtitle: 'Who is in each room $_dayWord',
              padding: const EdgeInsets.only(bottom: AppSpace.lg)),
        ),
        if (ground.isNotEmpty) ...[
          _floorLabel('Ground floor'),
          _floorRow(ground, wrapTiles),
          const SizedBox(height: AppSpace.lg),
        ],
        if (upper.isNotEmpty) ...[
          _floorLabel('Upper floor'),
          _floorRow(upper, wrapTiles),
          const SizedBox(height: AppSpace.lg),
        ],
        // The legend lives on the board instead of behind a dialog.
        const Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
          child: Divider(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
          child: Wrap(spacing: 14, runSpacing: 8, children: [
            ...AppColors.packages.entries.map((e) => LegendDot(e.value, e.key)),
            const LegendDot(AppColors.hairlineStrong, 'Available', outlined: true),
            const LegendDot(AppColors.blocked, 'Blocked'),
          ]),
        ),
      ]),
    );
  }

  Widget _floorLabel(String label) => Eyebrow(label,
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm));

  Widget _floorRow(List<Map<String, dynamic>> rooms, bool wrapTiles) {
    Widget tileFor(Map<String, dynamic> room) =>
        _roomTile(room, _infoForRoom(room['roomNumber'] as String));

    // Desktop has the width to show every room at once — wrap instead of
    // hiding rooms behind a horizontal scroll that needs a mouse drag.
    if (wrapTiles) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rooms.map((r) => SizedBox(height: 112, child: tileFor(r))).toList(),
        ),
      );
    }

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => tileFor(rooms[i]),
      ),
    );
  }

  Widget _roomTile(Map<String, dynamic> room, Map<String, dynamic>? info) {
    final roomNum = (room['roomNumber'] as String).padLeft(3, '0');
    final isBlocked = room['isBlocked'] == true;
    final baseType = room['baseType'] as String? ?? 'Double';

    late Color bg;
    late Color fg;
    Color border = Colors.transparent;
    String? pkgAbbr;
    String? guest;
    String? roomType;
    int? pax;

    if (isBlocked) {
      bg = AppColors.blocked;
      fg = Colors.white;
    } else if (info != null) {
      final b = info['booking'] as Map<String, dynamic>;
      final r = info['room'] as Map<String, dynamic>;
      final pkg = b['package'] as String? ?? '';
      bg = AppColors.forPackage(pkg);
      fg = Colors.white;
      pkgAbbr = _pkgAbbrev[pkg] ?? pkg;
      guest = (b['guestName'] as String? ?? 'Guest').split(' ').first;
      roomType = r['roomType'] as String? ?? baseType;
      pax = r['pax'] as int? ?? 0;
    } else {
      bg = AppColors.surface;
      fg = AppColors.ink;
      border = AppColors.hairlineStrong;
    }

    final occupied = info != null && !isBlocked;
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.ease,
      width: 92,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
        boxShadow: occupied
            ? [BoxShadow(color: bg.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(roomNum, style: AppText.number(14, color: fg)),
            if (pkgAbbr != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(pkgAbbr,
                    style: AppText.eyebrow.copyWith(
                        fontSize: 9, color: Colors.white, letterSpacing: 0.4)),
              ),
            if (isBlocked) Icon(Icons.lock_rounded, color: fg.withValues(alpha: 0.7), size: 13),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isBlocked)
              Text('Manager',
                  style: AppText.footnote.copyWith(fontSize: 12, color: fg.withValues(alpha: 0.8)))
            else if (info != null) ...[
              Text(guest ?? '',
                  style: AppText.bodyStrong.copyWith(fontSize: 13, color: fg, height: 1.2),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
              const SizedBox(height: 2),
              Text('${_shortType(roomType ?? '')} · $pax pax',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.footnote.copyWith(
                      fontSize: 11, color: fg.withValues(alpha: 0.82), height: 1.2)),
            ] else ...[
              Text(baseType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink2)),
              Text('Free',
                  style: AppText.footnote.copyWith(
                      fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
            ],
          ]),
        ],
      ),
    );
  }

  String _shortType(String t) => const {
        'Family Plus': 'Fam+',
        'Family': 'Family',
        'Triple': 'Triple',
        'Double': 'Double',
      }[t] ?? t;

  // ── Meal section ──────────────────────────────────────────────────────────

  Widget _mealSection() {
    final m = _meals;
    final pkgCounts = <String, int>{
      for (final pkg in AppColors.packages.keys)
        pkg: _active.where((b) => b['package'] == pkg).length,
    }..removeWhere((_, v) => v == 0);

    Widget cell(String label, int pax, IconData icon, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: AppText.footnote.copyWith(color: AppColors.ink2)),
            ]),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: AppMotion.base,
              child: Text('$pax',
                  key: ValueKey('$label$pax'), style: AppText.number(28)),
            ),
            Text('covers', style: AppText.footnote.copyWith(fontSize: 12)),
          ]),
        );

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader('Meals', subtitle: 'Kitchen covers for $_dayWord'),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cell('Breakfast', m['breakfast']!, Icons.wb_twilight_rounded, AppColors.breakfast),
            const VerticalDivider(width: 24),
            cell('Lunch', m['lunch']!, Icons.light_mode_rounded, AppColors.lunch),
            const VerticalDivider(width: 24),
            cell('Dinner', m['dinner']!, Icons.nightlight_round, AppColors.dinner),
          ]),
        ),
        if (pkgCounts.isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          const Divider(),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: pkgCounts.entries.map((e) {
              final color = AppColors.forPackage(e.key);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(e.key, style: AppText.footnote.copyWith(color: AppColors.ink2)),
                  const SizedBox(width: 6),
                  Text('${e.value}', style: AppText.number(13)),
                ]),
              );
            }).toList(),
          ),
        ],
      ]),
    );
  }

  // ── Early check-in / late check-out ───────────────────────────────────────

  Widget _timingSection() {
    final early = _earlyArrivals;
    final late = _lateDepartures;
    if (early.isEmpty && late.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader('Early arrivals & late departures',
              subtitle: 'Have these rooms and meals ready',
              padding: const EdgeInsets.only(bottom: AppSpace.sm)),
          ...early.map((b) => _timingRow(b, 'Early check-in',
              formatStayTime(b['earlyCheckInTime']), AppColors.success, Icons.login_rounded)),
          ...late.map((b) => _timingRow(b, 'Late check-out',
              formatStayTime(b['lateCheckOutTime']), AppColors.warning, Icons.logout_rounded)),
        ]),
      ),
    );
  }

  Widget _timingRow(
      Map<String, dynamic> b, String label, String? time, Color color, IconData icon) {
    final rooms = b['rooms'] as List?;
    final roomText = (rooms != null && rooms.isNotEmpty)
        ? rooms.map((r) => r['roomNumber'].toString()).join(', ')
        : (b['roomNumber']?.toString() ?? '');
    final guest = (b['guestName'] as String?)?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        IconWell(icon, color: color, size: 36),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(guest.isEmpty ? 'Guest' : guest,
                overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(fontSize: 14)),
            Text('$label${roomText.isEmpty ? '' : ' · Room $roomText'}',
                overflow: TextOverflow.ellipsis, style: AppText.footnote),
          ]),
        ),
        const SizedBox(width: 8),
        StatusPill(time ?? 'Time not set', color: time == null ? AppColors.ink3 : color),
      ]),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────

  /// The ones the front desk uses all day — these get the bottom bar slots.
  static final _newBooking =
      _QuickAction('New booking', Icons.add_rounded, () => RoomSelectionScreen());

  static final List<_QuickAction> _primaryActions = [
    _QuickAction('Bookings', Icons.calendar_month_outlined, () => ViewBookingsScreen()),
    _QuickAction('Invoice', Icons.receipt_long_outlined, () => GenerateInvoiceScreen()),
    _QuickAction('Inventory', Icons.inventory_2_outlined, () => AddInventoryItemScreen()),
  ];

  /// Everything else — behind "More" on phones, in the list on desktop.
  static final List<_QuickAction> _moreActions = [
    _QuickAction('Guests', Icons.people_alt_outlined, () => const GuestsListScreen()),
    _QuickAction('Profit', Icons.insights_rounded, () => CalculateProfitPage()),
    _QuickAction('Expenses & salaries', Icons.account_balance_wallet_outlined,
        () => ExpensesAndSalaryScreen()),
    _QuickAction('Room setup', Icons.meeting_room_outlined, () => RoomConfigScreen()),
  ];

  /// Managing who can sign in is owner-only, so this tile is added at build
  /// time rather than living in the static list. The backend enforces the same
  /// rule — hiding it here is convenience, not the control.
  static final _userAccessAction = _QuickAction(
      'User access', Icons.admin_panel_settings_outlined, () => const UserAccessScreen());

  List<_QuickAction> get _visibleMoreActions => [
        ..._moreActions,
        if (CurrentUser.current?.isAdmin == true) _userAccessAction,
      ];

  // Refreshes on return, so anything booked/edited there shows up right away
  // instead of waiting for the next auto-refresh tick.
  Future<void> _open(_QuickAction a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => a.builder()));
    if (mounted) await _fetchData(silent: true);
  }

  Widget _quickActions() {
    final actions = [..._primaryActions, ..._visibleMoreActions];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        onPressed: () => _open(_newBooking),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('New booking'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: AppSpace.md),
      _actionList(actions, dense: false),
    ]);
  }

  /// Grouped list in one card, Settings-style: icon well, label, chevron.
  Widget _actionList(List<_QuickAction> actions,
      {required bool dense, VoidCallback? beforeOpen}) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      if (i > 0) {
        rows.add(const Padding(
            padding: EdgeInsets.only(left: 64), child: Divider(height: 1)));
      }
      rows.add(Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            beforeOpen?.call();
            _open(a);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
            child: Row(children: [
              IconWell(a.icon, size: 36),
              const SizedBox(width: 14),
              Expanded(child: Text(a.label, style: AppText.bodyStrong.copyWith(fontSize: 15))),
              const Icon(Icons.chevron_right_rounded, color: AppColors.ink4, size: 22),
            ]),
          ),
        ),
      ));
    }
    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SurfaceCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: rows)),
    );
  }

  // ── Bottom action bar (phones) ─────────────────────────────────────────────

  Widget _bottomBar() => Frosted(
        tint: AppColors.surface,
        opacity: 0.86,
        border: const Border(top: BorderSide(color: AppColors.hairline, width: 0.5)),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _bottomBarItem(_primaryActions[0]),
                _bottomBarItem(_primaryActions[1]),
                // The everyday job sits in the middle of the thumb's reach.
                Expanded(
                  child: Center(
                    child: Pressable(
                      onTap: () => _open(_newBooking),
                      pressedScale: 0.92,
                      semanticLabel: 'New booking',
                      child: Container(
                        width: 54,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33121614), blurRadius: 12, offset: Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
                _bottomBarItem(_primaryActions[2]),
                _bottomBarItem(_QuickAction('More', Icons.grid_view_rounded, () => const SizedBox()),
                    onTap: _showMoreSheet),
              ],
            ),
          ),
        ),
      );

  Widget _bottomBarItem(_QuickAction a, {VoidCallback? onTap}) => Expanded(
        child: Pressable(
          onTap: onTap ?? () => _open(a),
          pressedScale: 0.9,
          semanticLabel: a.label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(a.icon, color: AppColors.ink, size: 23),
              const SizedBox(height: 4),
              Text(a.label,
                  style: AppText.footnote.copyWith(
                      fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );

  void _showMoreSheet() => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.canvas,
        builder: (sheetCtx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('More', style: AppText.title),
                ),
                _actionList(_visibleMoreActions,
                    dense: true, beforeOpen: () => Navigator.pop(sheetCtx)),
              ],
            ),
          ),
        ),
      );
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Widget Function() builder;
  const _QuickAction(this.label, this.icon, this.builder);
}
