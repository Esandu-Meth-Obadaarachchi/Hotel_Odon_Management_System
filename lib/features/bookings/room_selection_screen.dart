import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/guests/widgets/guest_name_autocomplete.dart';
import 'widgets/booking_flags.dart';
import 'widgets/extra_charges.dart';
import 'widgets/room_picker.dart';

class RoomSelectionScreen extends StatefulWidget {
  /// Optional prefill data (e.g. coming from the Generate Invoice screen).
  /// Recognised keys: guestName, guestPhone (String); checkIn, checkOut
  /// (DateTime); package, mealStart (String); total, advance, extraDetails
  /// (String); needDriver, needKiriPidu, earlyCheckIn, lateCheckOut (bool);
  /// earlyCheckInTime, lateCheckOutTime ("HH:mm" String); numAdults, numKids
  /// (int); extraCharges (List of {reason, amount}).
  final Map<String, dynamic>? prefill;

  RoomSelectionScreen({this.prefill});

  @override
  _RoomSelectionScreenState createState() => _RoomSelectionScreenState();
}

class _RoomSelectionScreenState extends State<RoomSelectionScreen> {
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  String? _packageType;
  final TextEditingController _guestNameController = TextEditingController();
  final TextEditingController _guestPhoneController = TextEditingController();
  final TextEditingController _extraDetailsController = TextEditingController();
  final TextEditingController _totalCostController = TextEditingController();
  final TextEditingController _advanceAmountController = TextEditingController();
  final TextEditingController _adultsController = TextEditingController();
  final TextEditingController _kidsController = TextEditingController();

  /// True once the adults box has been typed into. From then on the room
  /// selection stops overwriting it — the user knows something the room type
  /// does not.
  bool _adultsEdited = false;

  List<Map<String, dynamic>> _roomConfig = [];
  bool _configLoading = true;

  String? _mealStart;
  bool _needDriver = false;
  bool _needKiriPidu = false;
  bool _earlyCheckIn = false;
  String? _earlyCheckInTime; // "HH:mm", optional
  bool _lateCheckOut = false;
  String? _lateCheckOutTime; // "HH:mm", optional

  List<Map<String, dynamic>> _extraCharges = [];
  final GlobalKey<ExtraChargesEditorState> _chargesKey = GlobalKey();

  Set<String> _selectedRooms = {};
  Set<String> _extraBedRooms = {};
  Set<String> _bookedRooms = {};

  int _numOfNights = 0;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchRoomConfig();
    _applyPrefill();
  }

  void _applyPrefill() {
    final p = widget.prefill;
    if (p == null) return;

    _guestNameController.text = (p['guestName'] as String?) ?? '';
    _guestPhoneController.text = (p['guestPhone'] as String?) ?? '';
    if (p['total'] != null) _totalCostController.text = p['total'].toString();
    if (p['advance'] != null) _advanceAmountController.text = p['advance'].toString();
    if (p['extraDetails'] != null) {
      _extraDetailsController.text = p['extraDetails'].toString();
    }

    const validPackages = ['Full Board', 'Half Board', 'Room Only', 'BnB', 'Dinner Only'];
    final pkg = p['package'] as String?;
    if (pkg != null && validPackages.contains(pkg)) {
      _packageType = pkg;
      if (pkg == 'Full Board' || pkg == 'Half Board') {
        final meal = p['mealStart'] as String?;
        if (meal == 'Lunch' || meal == 'Dinner') _mealStart = meal;
      }
    }

    _needDriver = p['needDriver'] == true;
    _needKiriPidu = p['needKiriPidu'] == true;
    _earlyCheckIn = p['earlyCheckIn'] == true;
    if (_earlyCheckIn && parseStayTime(p['earlyCheckInTime']) != null) {
      _earlyCheckInTime = p['earlyCheckInTime'].toString();
    }
    _lateCheckOut = p['lateCheckOut'] == true;
    if (_lateCheckOut && parseStayTime(p['lateCheckOutTime']) != null) {
      _lateCheckOutTime = p['lateCheckOutTime'].toString();
    }

    // The invoice total already includes these, so they carry over as-is.
    _extraCharges = extraChargesOf(p);

    // The invoice already asked for the head count, so carry it over rather
    // than making the front desk key it in twice. An adults figure that came
    // from the invoice counts as user-entered: the rooms picked here must not
    // overwrite it.
    final adults = p['numAdults'];
    if (adults is int && adults > 0) {
      _adultsController.text = adults.toString();
      _adultsEdited = true;
    }
    final kids = p['numKids'];
    if (kids is int && kids > 0) _kidsController.text = kids.toString();

    final ci = p['checkIn'];
    final co = p['checkOut'];
    if (ci is DateTime && co is DateTime) {
      _checkInDate = ci;
      _checkOutDate = co;
      _numOfNights = co.difference(ci).inDays;
      _fetchBookingsForDateRange();
    }
  }

  Future<void> _fetchRoomConfig() async {
    try {
      final config = await _apiService.fetchRoomConfig();
      setState(() {
        _roomConfig = List<Map<String, dynamic>>.from(
          (config['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
        );
        _configLoading = false;
      });
    } catch (e) {
      setState(() => _configLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load room config: $e')),
      );
    }
  }

  String _getRoomType(Map<String, dynamic> roomCfg) => effectiveRoomType(
        roomCfg,
        extraBed: _extraBedRooms.contains(roomCfg['roomNumber'] as String),
      );

  int _getPax(String roomType) => paxForType(roomType);

  /// Combined capacity of the rooms currently selected. This is the number the
  /// adults box starts from, because the room chosen is what implies the head
  /// count — a Family room means four adults unless told otherwise.
  int get _autoAdults => _selectedRooms.fold<int>(0, (sum, roomNum) {
        final cfg = _roomConfig.firstWhere(
          (r) => r['roomNumber'] == roomNum,
          orElse: () => {},
        );
        return sum + (cfg.isEmpty ? 0 : _getPax(_getRoomType(cfg)));
      });

  /// Follows the room selection until the user types their own number.
  /// Call inside setState, after the selection has changed.
  void _syncAdults() {
    if (_adultsEdited) return;
    final auto = _autoAdults;
    _adultsController.text = auto == 0 ? '' : auto.toString();
  }

  int get _adultsEntered =>
      int.tryParse(_adultsController.text.trim()) ?? _autoAdults;

  int get _kidsEntered => int.tryParse(_kidsController.text.trim()) ?? 0;

  Future<void> _selectCheckInDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _checkInDate) {
      setState(() {
        _checkInDate = picked;
        _checkOutDate = picked.add(const Duration(days: 1));
      });
      _calculateNumOfNights();
      _fetchBookingsForDateRange();
    }
  }

  Future<void> _selectCheckOutDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _checkInDate ?? DateTime.now(),
      firstDate: _checkInDate ?? DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _checkOutDate) {
      setState(() => _checkOutDate = picked);
      if (_checkInDate != null) {
        _calculateNumOfNights();
        _fetchBookingsForDateRange();
      }
    }
  }

  void _calculateNumOfNights() {
    if (_checkInDate != null && _checkOutDate != null) {
      setState(() {
        _numOfNights = _checkOutDate!.difference(_checkInDate!).inDays;
      });
    }
  }

  Future<void> _fetchBookingsForDateRange() async {
    if (_checkInDate == null || _checkOutDate == null) return;
    try {
      final bookings = await _apiService.fetchBookingsForDateRange(_checkInDate!, _checkOutDate!);
      final booked = bookedRoomsBetween(bookings, _checkInDate!, _checkOutDate!);
      // Rooms picked before the dates changed may now be taken.
      final clashing = _selectedRooms.intersection(booked);
      setState(() {
        _bookedRooms = booked;
        _selectedRooms.removeAll(clashing);
        _extraBedRooms.removeAll(clashing);
        _syncAdults();
      });
      if (clashing.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Room${clashing.length > 1 ? 's' : ''} ${clashing.join(', ')} '
              '${clashing.length > 1 ? 'are' : 'is'} booked on these dates and '
              '${clashing.length > 1 ? 'were' : 'was'} unselected. Please pick again.',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to fetch existing bookings')),
      );
    }
  }

  Map<String, int> _getInventoryItemsForType(String roomType) {
    switch (roomType) {
      case 'Double':
        return {
          'soap': 1, 'conditioner': 1, 'body lotion': 1, 'shampoo': 1,
          'shower gel': 1, 'dental kit': 1, 'white sugar sachets': 2,
          'milk creamer sachets': 2, 'black tea sachets': 2, 'nescafe sachet': 2,
        };
      case 'Triple':
        return {
          'soap': 1, 'conditioner': 1, 'body lotion': 1, 'shampoo': 1,
          'shower gel': 1, 'dental kit': 2, 'white sugar sachets': 3,
          'milk creamer sachets': 3, 'black tea sachets': 3, 'nescafe sachet': 3,
        };
      case 'Family':
        return {
          'soap': 1, 'conditioner': 1, 'body lotion': 1, 'shampoo': 1,
          'shower gel': 1, 'dental kit': 2, 'white sugar sachets': 4,
          'milk creamer sachets': 4, 'black tea sachets': 4, 'nescafe sachet': 4,
        };
      case 'Family Plus':
        return {
          'soap': 1, 'conditioner': 1, 'body lotion': 1, 'shampoo': 1,
          'shower gel': 1, 'dental kit': 2, 'white sugar sachets': 5,
          'milk creamer sachets': 5, 'black tea sachets': 5, 'nescafe sachet': 5,
        };
      default:
        return {};
    }
  }

  /// Takes the amenities for the booked rooms out of stock. The item updates
  /// are independent, so they go out together instead of one after another.
  /// Returns true when stock is short or the inventory could not be updated.
  Future<bool> _deductInventory(Map<String, int> totalDeductions) async {
    final List<dynamic> inventoryItems;
    try {
      inventoryItems = await _apiService.fetchInventoryItems();
    } catch (_) {
      return true;
    }

    bool hasInventoryIssue = false;
    final updates = <Future<void>>[];
    for (final entry in totalDeductions.entries) {
      final item = inventoryItems.firstWhere(
        (i) => i['item_name'].toString().toLowerCase() == entry.key,
        orElse: () => null,
      );
      if (item == null) {
        hasInventoryIssue = true;
        continue;
      }
      final updated = (item['quantity'] ?? 0) - entry.value;
      if (updated < 0) {
        hasInventoryIssue = true;
        continue;
      }
      updates.add(_apiService
          .updateInventoryItem(item['_id'], {
            'item_name': item['item_name'],
            'quantity': updated,
          })
          .catchError((_) {
            hasInventoryIssue = true;
          }));
    }
    await Future.wait(updates);
    return hasInventoryIssue;
  }

  Future<void> _saveBooking() async {
    if (_checkInDate == null ||
        _checkOutDate == null ||
        _packageType == null ||
        _selectedRooms.isEmpty ||
        _guestNameController.text.trim().isEmpty ||
        _guestPhoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields including guest name and phone')),
      );
      return;
    }

    final roomsData = _selectedRooms.map((roomNum) {
      final cfg = _roomConfig.firstWhere((r) => r['roomNumber'] == roomNum, orElse: () => {});
      final roomType = cfg.isNotEmpty ? _getRoomType(cfg) : 'Double';
      return {
        'roomNumber': roomNum,
        'roomType': roomType,
        'pax': _getPax(roomType),
      };
    }).toList();

    final Map<String, int> totalDeductions = {};
    for (final roomData in roomsData) {
      final items = _getInventoryItemsForType(roomData['roomType'] as String);
      for (final key in items.keys) {
        totalDeductions[key] = (totalDeductions[key] ?? 0) + items[key]!;
      }
    }

    final normalizedCheckIn = DateTime.utc(_checkInDate!.year, _checkInDate!.month, _checkInDate!.day);
    final normalizedCheckOut = DateTime.utc(_checkOutDate!.year, _checkOutDate!.month, _checkOutDate!.day);

    final newBooking = {
      'rooms': roomsData,
      'package': _packageType!,
      if (_mealStart != null) 'mealStart': _mealStart,
      'extraDetails': _extraDetailsController.text,
      'checkIn': normalizedCheckIn.toIso8601String(),
      'checkOut': normalizedCheckOut.toIso8601String(),
      'num_of_nights': _numOfNights,
      'total': _totalCostController.text,
      'advance': _advanceAmountController.text,
      'guestName': _guestNameController.text,
      'guestPhone': _guestPhoneController.text,
      'needDriver': _needDriver,
      'needKiriPidu': _needKiriPidu,
      'earlyCheckIn': _earlyCheckIn,
      'earlyCheckInTime': _earlyCheckIn ? _earlyCheckInTime : null,
      'lateCheckOut': _lateCheckOut,
      'lateCheckOutTime': _lateCheckOut ? _lateCheckOutTime : null,
      'numAdults': _adultsEntered,
      'numKids': _kidsEntered,
      'extraCharges': _extraCharges,
    };

    // The booking is saved first: if it fails, no stock has been taken for
    // a stay that does not exist.
    try {
      await _apiService.addBooking(newBooking);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save booking')),
      );
      return;
    }

    final hasInventoryIssue = await _deductInventory(totalDeductions);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hasInventoryIssue
            ? 'Booking saved! Check inventory levels.'
            : 'Booking saved and inventory updated.'),
      ),
    );
    _resetBooking();
  }

  void _resetBooking() {
    setState(() {
      _packageType = null;
      _mealStart = null;
      _extraDetailsController.clear();
      _advanceAmountController.clear();
      _totalCostController.clear();
      _guestNameController.clear();
      _guestPhoneController.clear();
      _selectedRooms.clear();
      _extraBedRooms.clear();
      _bookedRooms.clear();
      _checkInDate = null;
      _checkOutDate = null;
      _numOfNights = 0;
      _needDriver = false;
      _needKiriPidu = false;
      _earlyCheckIn = false;
      _earlyCheckInTime = null;
      _lateCheckOut = false;
      _lateCheckOutTime = null;
      _extraCharges = [];
      _chargesKey.currentState?.reset();
      _adultsController.clear();
      _kidsController.clear();
      _adultsEdited = false;
    });
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _extraDetailsController.dispose();
    _totalCostController.dispose();
    _advanceAmountController.dispose();
    _adultsController.dispose();
    _kidsController.dispose();
    super.dispose();
  }

  Widget _buildSelectedSummary() {
    if (_selectedRooms.isEmpty) return const SizedBox.shrink();

    final roomList = _selectedRooms.map((roomNum) {
      final cfg = _roomConfig.firstWhere((r) => r['roomNumber'] == roomNum, orElse: () => {});
      final type = cfg.isNotEmpty ? _getRoomType(cfg) : 'Unknown';
      return MapEntry(roomNum, type);
    }).toList();

    return SurfaceCard(
      shadow: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.ink, size: 18),
              const SizedBox(width: 8),
              Text(
                '${_selectedRooms.length} room${_selectedRooms.length > 1 ? 's' : ''} selected',
                style: AppText.bodyStrong.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: roomList.map((entry) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(entry.key.padLeft(3, '0'), style: AppText.number(13)),
                  const SizedBox(width: 6),
                  Text(entry.value, style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink2)),
                ]),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text('Tap + on a selected room to add an extra bed.', style: AppText.footnote.copyWith(fontSize: 12)),
        ],
      ),
    );
  }

  /// Adults + kids. Adults is prefilled from the rooms picked above and stays
  /// in step with them until it is typed into; kids is always manual, because
  /// children never enter into which room gets booked.
  Widget _buildHeadCount() {
    final auto = _autoAdults;
    final kids = _kidsEntered;

    return Card(
child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _indigoField(
                    controller: _adultsController,
                    label: 'Adults (Pax)',
                    icon: Icons.person_outline_rounded,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _adultsEdited = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _indigoField(
                    controller: _kidsController,
                    label: 'Kids',
                    icon: Icons.child_care_rounded,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_adultsEdited && auto > 0 && _adultsEntered != auto)
              // The rooms say one thing and the box says another. That is
              // allowed — it is the whole point of the field — but the gap is
              // worth showing, along with a one-tap way back.
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rooms selected fit $auto adults',
                      style: AppText.footnote.copyWith(color: AppColors.warning),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() {
                      _adultsEdited = false;
                      _syncAdults();
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Reset',
                        style: AppText.footnote.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.ink3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      auto == 0
                          ? 'Adults fills in once rooms are selected. Kids are never counted when picking a room — record them here.'
                          : 'Adults comes from the rooms selected; edit it if the party differs. Kids are tracked separately.',
                      style: AppText.footnote,
                    ),
                  ),
                ],
              ),
            if (kids > 0) ...[
              const SizedBox(height: 10),
              StatusPill(
                'Party of ${_adultsEntered + kids} · '
                '$_adultsEntered adult${_adultsEntered == 1 ? '' : 's'}, '
                '$kids kid${kids == 1 ? '' : 's'}',
                icon: Icons.groups_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _configLoading
          ? const LoadingView()
          : CustomScrollView(
              slivers: [
                const LargeTitleSliverAppBar(
                  title: 'New booking',
                  subtitle: 'Guest, dates, plan and rooms',
                  maxWidth: AppLayout.maxForm,
                ),

                SliverToBoxAdapter(
                  child: PageBody(
                    maxWidth: AppLayout.maxForm,
                    padding: EdgeInsets.fromLTRB(AppLayout.gutter(context), 8, AppLayout.gutter(context), 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Prefilled-from-invoice banner ─────────────────
                        if (widget.prefill != null) ...[
                          const InlineBanner(
                            'Details copied from the invoice. Pick the room(s) below and save.',
                            tone: BannerTone.info,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Guest details ─────────────────────────────────
                        _sectionLabel('Guest'),
                        const SizedBox(height: 10),
                        Card(
child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                GuestNameAutocomplete(
                                  nameController: _guestNameController,
                                  phoneController: _guestPhoneController,
                                ),
                                const SizedBox(height: 12),
                                _indigoField(
                                  controller: _guestPhoneController,
                                  label: 'Phone Number',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Stay dates ────────────────────────────────────
                        _sectionLabel('Stay'),
                        const SizedBox(height: 10),
                        Card(
child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _dateTile(
                                      label: 'Check-In',
                                      date: _checkInDate,
                                      onTap: () => _selectCheckInDate(context),
                                    )),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 1,
                                            height: 30,
                                            color: AppColors.hairline,
                                          ),
                                          Icon(Icons.arrow_forward_rounded,
                                              size: 16, color: AppColors.ink3),
                                          Container(
                                            width: 1,
                                            height: 30,
                                            color: AppColors.hairline,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(child: _dateTile(
                                      label: 'Check-Out',
                                      date: _checkOutDate,
                                      onTap: () => _selectCheckOutDate(context),
                                    )),
                                  ],
                                ),
                                if (_numOfNights > 0) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: StatusPill(
                                      '$_numOfNights night${_numOfNights > 1 ? 's' : ''}',
                                      icon: Icons.nights_stay_outlined,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Package ───────────────────────────────────────
                        _sectionLabel('Meal plan'),
                        const SizedBox(height: 10),
                        Card(
child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ChoiceChipGroup(
                                  items: const ['Full Board', 'Half Board', 'Room Only', 'BnB', 'Dinner Only'],
                                  value: _packageType,
                                  dotColor: AppColors.forPackage,
                                  onChanged: (v) => setState(() {
                                    _packageType = v;
                                    if (v != 'Full Board' && v != 'Half Board') _mealStart = null;
                                  }),
                                ),
                                AnimatedSize(
                                  duration: AppMotion.base,
                                  curve: AppMotion.ease,
                                  alignment: Alignment.topLeft,
                                  child: (_packageType == 'Full Board' || _packageType == 'Half Board')
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('First meal on arrival', style: AppText.footnote.copyWith(color: AppColors.ink2)),
                                              const SizedBox(height: 8),
                                              ChoiceChipGroup(
                                                items: const ['Lunch', 'Dinner'],
                                                value: _mealStart,
                                                onChanged: (v) => setState(() => _mealStart = v),
                                              ),
                                            ],
                                          ),
                                        )
                                      : const SizedBox(width: double.infinity),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Room selection ────────────────────────────────
                        _sectionLabel('Rooms'),
                        const SizedBox(height: 10),
                        RoomPicker(
                          roomConfig: _roomConfig,
                          selectedRooms: _selectedRooms,
                          extraBedRooms: _extraBedRooms,
                          bookedRooms: _bookedRooms,
                          onToggleRoom: (roomNum) => setState(() {
                            if (_selectedRooms.contains(roomNum)) {
                              _selectedRooms.remove(roomNum);
                              _extraBedRooms.remove(roomNum);
                            } else {
                              _selectedRooms.add(roomNum);
                            }
                            _syncAdults();
                          }),
                          onToggleExtraBed: (roomNum) => setState(() {
                            if (!_extraBedRooms.remove(roomNum)) _extraBedRooms.add(roomNum);
                            _syncAdults();
                          }),
                        ),
                        const SizedBox(height: 12),

                        // Selected summary
                        _buildSelectedSummary(),
                        if (_selectedRooms.isNotEmpty) const SizedBox(height: 20),

                        // ── Head count ────────────────────────────────────
                        _sectionLabel('Guests'),
                        const SizedBox(height: 10),
                        _buildHeadCount(),
                        const SizedBox(height: 20),

                        // ── Options ───────────────────────────────────────
                        _sectionLabel('Options'),
                        const SizedBox(height: 10),
                        OptionToggleCard(
                          icon: Icons.directions_car_rounded,
                          title: 'Driver room',
                          subtitle: 'Keep a room for the driver',
                          value: _needDriver,
                          color: AppColors.warning,
                          onChanged: (v) => setState(() => _needDriver = v),
                        ),
                        const SizedBox(height: 10),
                        OptionToggleCard(
                          icon: Icons.rice_bowl_rounded,
                          title: 'Kiri pidu',
                          subtitle: 'Prepare kiri pidu for this booking',
                          value: _needKiriPidu,
                          color: AppColors.roomOnly,
                          onChanged: (v) => setState(() => _needKiriPidu = v),
                        ),
                        const SizedBox(height: 10),
                        OptionToggleCard(
                          icon: Icons.schedule_rounded,
                          title: 'Early check-in',
                          subtitle: 'Arriving before 2:00 PM',
                          value: _earlyCheckIn,
                          color: AppColors.success,
                          onChanged: (v) => setState(() => _earlyCheckIn = v),
                          child: OptionalTimeField(
                            value: _earlyCheckInTime,
                            hint: 'Arrival time (optional)',
                            onChanged: (t) => setState(() => _earlyCheckInTime = t),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OptionToggleCard(
                          icon: Icons.more_time_rounded,
                          title: 'Late check-out',
                          subtitle: 'Leaving after 11:00 AM',
                          value: _lateCheckOut,
                          color: AppColors.warning,
                          onChanged: (v) => setState(() => _lateCheckOut = v),
                          child: OptionalTimeField(
                            value: _lateCheckOutTime,
                            hint: 'Departure time (optional)',
                            onChanged: (t) => setState(() => _lateCheckOutTime = t),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Financial details ─────────────────────────────
                        _sectionLabel('Payment'),
                        const SizedBox(height: 10),
                        Card(
child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _indigoField(
                                  controller: _totalCostController,
                                  label: 'Total Cost (LKR)',
                                  icon: Icons.receipt_long_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                                const SizedBox(height: 12),
                                _indigoField(
                                  controller: _advanceAmountController,
                                  label: 'Advance Amount (LKR)',
                                  icon: Icons.payments_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Extra charges (added to the total)',
                                    style: AppText.footnote.copyWith(color: AppColors.ink2, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ExtraChargesEditor(
                                  key: _chargesKey,
                                  initialCharges: _extraCharges,
                                  onChanged: (charges) => setState(() {
                                    _totalCostController.text = adjustTotalForCharges(
                                      _totalCostController.text,
                                      sumExtraCharges(_extraCharges),
                                      sumExtraCharges(charges),
                                    );
                                    _extraCharges = charges;
                                  }),
                                ),
                                const SizedBox(height: 12),
                                _indigoField(
                                  controller: _extraDetailsController,
                                  label: 'Extra Details / Notes',
                                  icon: Icons.notes_rounded,
                                  maxLines: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Save button ───────────────────────────────────
                        FilledButton.icon(
                          onPressed: _saveBooking,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Save booking'),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final hasDate = date != null;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasDate ? AppColors.surface : AppColors.canvas,
          borderRadius: AppRadius.control,
          border: Border.all(color: hasDate ? AppColors.ink : AppColors.hairlineStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 10)),
            const SizedBox(height: 6),
            Text(
              date != null ? DateFormat('EEE d MMM').format(date) : 'Select date',
              style: hasDate
                  ? AppText.bodyStrong
                  : AppText.body.copyWith(color: AppColors.ink4),
              overflow: TextOverflow.ellipsis,
            ),
            if (date != null)
              Text(DateFormat('yyyy').format(date), style: AppText.footnote.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _indigoField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: fieldDecoration(label, icon: icon),
    );
  }
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: AppText.eyebrow),
    );
