import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/guests/widgets/guest_name_autocomplete.dart';

class RoomSelectionScreen extends StatefulWidget {
  /// Optional prefill data (e.g. coming from the Generate Invoice screen).
  /// Recognised keys: guestName, guestPhone (String); checkIn, checkOut
  /// (DateTime); package, mealStart (String); total, advance, extraDetails
  /// (String); needDriver (bool).
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

  List<Map<String, dynamic>> _roomConfig = [];
  bool _configLoading = true;

  String? _mealStart;
  bool _needDriver = false;

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

  String _getRoomType(Map<String, dynamic> roomCfg) {
    final baseType = roomCfg['baseType'] as String;
    final hasExtra = _extraBedRooms.contains(roomCfg['roomNumber'] as String);
    if (baseType == 'Family') return hasExtra ? 'Family Plus' : 'Family';
    return hasExtra ? 'Triple' : 'Double';
  }

  int _getPax(String roomType) {
    switch (roomType) {
      case 'Double': return 2;
      case 'Triple': return 3;
      case 'Family': return 4;
      case 'Family Plus': return 5;
      default: return 2;
    }
  }

  Future<void> _selectCheckInDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.indigo, onPrimary: Colors.white),
        ),
        child: child!,
      ),
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.indigo, onPrimary: Colors.white),
        ),
        child: child!,
      ),
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
      final booked = <String>{};
      for (final booking in bookings) {
        final bookingCheckIn = DateTime.parse(booking['checkIn']);
        final bookingCheckOut = DateTime.parse(booking['checkOut']);
        final normBI = DateTime(bookingCheckIn.year, bookingCheckIn.month, bookingCheckIn.day);
        final normBO = DateTime(bookingCheckOut.year, bookingCheckOut.month, bookingCheckOut.day);
        final normCI = DateTime(_checkInDate!.year, _checkInDate!.month, _checkInDate!.day);
        final normCO = DateTime(_checkOutDate!.year, _checkOutDate!.month, _checkOutDate!.day);

        bool overlaps = normCI.isBefore(normBO) && normCO.isAfter(normBI);
        if (normCI.isAtSameMomentAs(normBO)) overlaps = false;

        if (overlaps) {
          if (booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty) {
            for (final r in booking['rooms'] as List) {
              booked.add(r['roomNumber'].toString());
            }
          } else if (booking['roomNumber'] != null) {
            booked.add(booking['roomNumber'].toString());
          }
        }
      }
      setState(() => _bookedRooms = booked);
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

    List<dynamic> inventoryItems;
    try {
      inventoryItems = await _apiService.fetchInventoryItems();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch inventory: $e')),
      );
      return;
    }

    bool hasInventoryIssue = false;
    for (final key in totalDeductions.keys) {
      final item = inventoryItems.firstWhere(
        (i) => i['item_name'].toString().toLowerCase() == key,
        orElse: () => null,
      );
      if (item == null || (item['quantity'] ?? 0) < totalDeductions[key]!) {
        hasInventoryIssue = true;
      }
    }

    for (final key in totalDeductions.keys) {
      final item = inventoryItems.firstWhere(
        (i) => i['item_name'].toString().toLowerCase() == key,
        orElse: () => null,
      );
      if (item != null) {
        final updated = (item['quantity'] ?? 0) - totalDeductions[key]!;
        if (updated >= 0) {
          try {
            await _apiService.updateInventoryItem(item['_id'], {
              'item_name': item['item_name'],
              'quantity': updated,
            });
          } catch (_) {}
        }
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
    };

    print('[DEBUG] Saving booking, needDriver=$_needDriver');
    try {
      await _apiService.addBooking(newBooking);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save booking')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hasInventoryIssue
            ? 'Booking saved! Check inventory levels.'
            : 'Booking saved and inventory updated.'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    });
  }

  // ─── Room card ───────────────────────────────────────────────────────────────

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final roomNum = room['roomNumber'] as String;
    final baseType = room['baseType'] as String;
    final isBlocked = room['isBlocked'] == true;
    final isBooked = _bookedRooms.contains(roomNum);
    final isSelected = _selectedRooms.contains(roomNum);
    final hasExtra = _extraBedRooms.contains(roomNum);

    final roomType = isSelected ? _getRoomType(room) : baseType;
    final pax = _getPax(roomType);

    Color bgColor;
    Color textColor = const Color(0xFF1E293B);

    if (isBlocked) {
      bgColor = Colors.grey.shade300;
      textColor = Colors.grey.shade600;
    } else if (isBooked) {
      bgColor = Colors.red.shade400;
      textColor = Colors.white;
    } else if (isSelected && hasExtra) {
      bgColor = Colors.orange.shade400;
      textColor = Colors.white;
    } else if (isSelected) {
      bgColor = Colors.green.shade500;
      textColor = Colors.white;
    } else {
      bgColor = Colors.white;
    }

    return GestureDetector(
      onTap: (isBlocked || isBooked)
          ? null
          : () {
              setState(() {
                if (_selectedRooms.contains(roomNum)) {
                  _selectedRooms.remove(roomNum);
                  _extraBedRooms.remove(roomNum);
                } else {
                  _selectedRooms.add(roomNum);
                }
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (hasExtra ? Colors.orange.shade700 : Colors.green.shade700)
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      roomNum.padLeft(3, '0'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBlocked
                          ? 'Blocked'
                          : isBooked
                              ? 'Booked'
                              : (isSelected ? roomType : baseType),
                      style: TextStyle(
                        fontSize: 9,
                        color: textColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 1),
                      Text(
                        '${pax}pax',
                        style: TextStyle(
                          fontSize: 9,
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isSelected && !isBlocked && !isBooked)
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_extraBedRooms.contains(roomNum)) {
                        _extraBedRooms.remove(roomNum);
                      } else {
                        _extraBedRooms.add(roomNum);
                      }
                    });
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: hasExtra ? Colors.white : Colors.white.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasExtra ? Colors.orange.shade700 : Colors.green.shade700,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 13,
                      color: hasExtra ? Colors.orange.shade700 : Colors.green.shade700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorSection(String floor) {
    final rooms = _roomConfig.where((r) => r['floor'] == floor).toList();
    if (rooms.isEmpty) return const SizedBox.shrink();

    final isGround = floor == 'Ground';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Floor header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isGround ? Colors.indigo.shade50 : Colors.purple.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(
                  color: isGround ? Colors.indigo.shade100 : Colors.purple.shade100,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isGround ? Colors.indigo : Colors.purple,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$floor Floor',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isGround ? Colors.indigo.shade700 : Colors.purple.shade700,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rooms.length} rooms',
                  style: TextStyle(
                    fontSize: 11,
                    color: isGround ? Colors.indigo.shade400 : Colors.purple.shade400,
                  ),
                ),
              ],
            ),
          ),
          // Room grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: rooms.length,
              itemBuilder: (context, index) => _buildRoomCard(rooms[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSummary() {
    if (_selectedRooms.isEmpty) return const SizedBox.shrink();

    final roomList = _selectedRooms.map((roomNum) {
      final cfg = _roomConfig.firstWhere((r) => r['roomNumber'] == roomNum, orElse: () => {});
      final type = cfg.isNotEmpty ? _getRoomType(cfg) : 'Unknown';
      return MapEntry(roomNum, type);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.green.shade200)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_selectedRooms.length} room${_selectedRooms.length > 1 ? 's' : ''} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: roomList.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        'Room ${entry.key.padLeft(3, '0')} · ${entry.value}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 12, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tap + on a selected room to add an extra bed',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: _configLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : CustomScrollView(
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
                      'New Booking',
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
                            Icons.hotel_rounded,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Prefilled-from-invoice banner ─────────────────
                        if (widget.prefill != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded,
                                    size: 18, color: Colors.amber.shade800),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Details prefilled from the invoice. Just select the room(s) below and save.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Guest details ─────────────────────────────────
                        _sectionLabel('Guest Details'),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
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
                        _sectionLabel('Stay Dates'),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
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
                                            color: Colors.grey.shade200,
                                          ),
                                          Icon(Icons.arrow_forward_rounded,
                                              size: 16, color: Colors.grey.shade400),
                                          Container(
                                            width: 1,
                                            height: 30,
                                            color: Colors.grey.shade200,
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.nights_stay_outlined,
                                            size: 14, color: Colors.indigo.shade600),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$_numOfNights night${_numOfNights > 1 ? 's' : ''}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.indigo.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Package ───────────────────────────────────────
                        _sectionLabel('Package'),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _indigoDropdown(
                                  label: 'Select Package',
                                  value: _packageType,
                                  icon: Icons.restaurant_menu_rounded,
                                  items: ['Full Board', 'Half Board', 'Room Only', 'BnB', 'Dinner Only'],
                                  onChanged: (v) => setState(() {
                                    _packageType = v;
                                    if (v != 'Full Board' && v != 'Half Board') _mealStart = null;
                                  }),
                                ),
                                if (_packageType == 'Full Board' || _packageType == 'Half Board') ...[
                                  const SizedBox(height: 12),
                                  _indigoDropdown(
                                    label: 'First Meal on Arrival',
                                    value: _mealStart,
                                    icon: Icons.restaurant_rounded,
                                    items: ['Lunch', 'Dinner'],
                                    onChanged: (v) => setState(() => _mealStart = v),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Room selection ────────────────────────────────
                        _sectionLabel('Select Rooms'),
                        const SizedBox(height: 10),
                        _buildFloorSection('Ground'),
                        const SizedBox(height: 10),
                        _buildFloorSection('Upper'),
                        const SizedBox(height: 12),

                        // Legend
                        _buildLegend(),
                        const SizedBox(height: 12),

                        // Selected summary
                        _buildSelectedSummary(),
                        if (_selectedRooms.isNotEmpty) const SizedBox(height: 20),

                        // ── Options ───────────────────────────────────────
                        _sectionLabel('Options'),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _needDriver = !_needDriver),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: _needDriver
                                          ? Colors.amber.shade50
                                          : Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.directions_car_rounded,
                                      color: _needDriver
                                          ? Colors.amber.shade700
                                          : Colors.grey.shade400,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Requires Driver Room',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          'Reserve a room for driver',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Transform.scale(
                                    scale: 0.9,
                                    child: Switch(
                                      value: _needDriver,
                                      activeColor: Colors.amber.shade700,
                                      onChanged: (v) => setState(() => _needDriver = v),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Financial details ─────────────────────────────
                        _sectionLabel('Financial Details'),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
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
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _saveBooking,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.check_rounded, size: 20),
                              label: const Text(
                                'Save Booking',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: hasDate ? Colors.indigo.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasDate ? Colors.indigo.shade200 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasDate ? Colors.indigo.shade500 : Colors.grey.shade500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: hasDate ? Colors.indigo.shade600 : Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    date != null ? DateFormat('d MMM yyyy').format(date) : 'Tap to set',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasDate ? Colors.indigo.shade800 : Colors.grey.shade400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _legendChip(Colors.white, Colors.grey.shade400, 'Available'),
        _legendChip(Colors.green.shade500, Colors.green.shade500, 'Selected'),
        _legendChip(Colors.orange.shade400, Colors.orange.shade400, '+Extra bed'),
        _legendChip(Colors.red.shade400, Colors.red.shade400, 'Booked'),
        _legendChip(Colors.grey.shade300, Colors.grey.shade300, 'Blocked'),
      ],
    );
  }

  Widget _legendChip(Color fill, Color border, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _indigoField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.indigo.shade400, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _indigoDropdown({
    required String label,
    required String? value,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.indigo.shade400, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: items.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
      onChanged: onChanged,
    );
  }
}

Widget _sectionLabel(String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 1.1,
      ),
    );
