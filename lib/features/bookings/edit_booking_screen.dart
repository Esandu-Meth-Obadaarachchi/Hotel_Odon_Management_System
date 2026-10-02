import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/guests/widgets/guest_name_autocomplete.dart';
import 'widgets/extra_charges.dart';
import 'widgets/room_picker.dart';

class EditBookingScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final DateTime selectedDay;

  EditBookingScreen({required this.booking, required this.selectedDay});

  @override
  _EditBookingScreenState createState() => _EditBookingScreenState();
}

class _EditBookingScreenState extends State<EditBookingScreen> {
  final ApiService _apiService = ApiService();

  late TextEditingController packageTypeController;
  late TextEditingController extraDetailsController;
  late TextEditingController totalController;
  late TextEditingController advanceController;
  late TextEditingController guestNameController;
  late TextEditingController guestPhoneController;
  late TextEditingController adultsController;
  late TextEditingController kidsController;

  // Room selection, picked on the same grid as Add Booking. Legacy
  // single-room bookings load into it too and are saved back in the
  // multi-room format.
  List<Map<String, dynamic>> _roomConfig = [];
  bool _configLoading = true;
  final Set<String> _selectedRooms = {};
  final Set<String> _extraBedRooms = {};
  Set<String> _bookedRooms = {};

  /// Rooms on the booking that are missing from the room config (renamed or
  /// removed since). They are kept as they were so an edit never drops them.
  final Map<String, Map<String, dynamic>> _unlistedRooms = {};

  String _balanceMethod = '';
  String _balanceDisplay = 'N/A';
  String? _mealStart;
  bool _needDriver = false;
  List<Map<String, dynamic>> _extraCharges = [];

  static const _packages = ['Full Board', 'Half Board', 'Room Only', 'BnB', 'Dinner Only'];
  static const _mealStarts = ['Lunch', 'Dinner'];

  @override
  void initState() {
    super.initState();
    final b = widget.booking;

    final isNewFormat = b['rooms'] is List && (b['rooms'] as List).isNotEmpty;
    final List<Map<String, dynamic>> initialRooms = isNewFormat
        ? (b['rooms'] as List).map((r) => Map<String, dynamic>.from(r)).toList()
        : [
            if ((b['roomNumber'] ?? '').toString().trim().isNotEmpty)
              {
                'roomNumber': b['roomNumber'].toString().trim(),
                'roomType': b['roomType'] ?? 'Double',
              },
          ];
    for (final r in initialRooms) {
      final roomNum = r['roomNumber'].toString();
      _selectedRooms.add(roomNum);
      if (hasExtraBed((r['roomType'] ?? '').toString())) _extraBedRooms.add(roomNum);
    }
    _initialRooms = initialRooms;

    // Stored as UTC midnight, so the UTC calendar day is the booked day.
    final ci = DateTime.tryParse(b['checkIn']?.toString() ?? '') ?? widget.selectedDay;
    final co = DateTime.tryParse(b['checkOut']?.toString() ?? '') ??
        ci.add(const Duration(days: 1));
    _checkIn = DateTime(ci.year, ci.month, ci.day);
    _checkOut = DateTime(co.year, co.month, co.day);
    packageTypeController = TextEditingController(text: b['package'] as String? ?? '');
    extraDetailsController = TextEditingController(text: b['extraDetails'] as String? ?? '');
    totalController = TextEditingController(text: b['total'] as String? ?? '');
    advanceController = TextEditingController(text: b['advance'] as String? ?? '');
    guestNameController = TextEditingController(text: b['guestName'] as String? ?? '');
    guestPhoneController = TextEditingController(text: b['guestPhone'] as String? ?? '');

    // Bookings saved before the head count existed have neither field. Adults
    // falls back to the rooms' capacity so the box is never blank; kids has no
    // sensible default other than zero.
    final storedAdults = b['numAdults'];
    adultsController = TextEditingController(
      text: (storedAdults is num && storedAdults > 0)
          ? storedAdults.toInt().toString()
          : _roomCapacity.toString(),
    );
    final storedKids = b['numKids'];
    kidsController = TextEditingController(
      text: (storedKids is num && storedKids > 0) ? storedKids.toInt().toString() : '0',
    );

    _balanceMethod = b['balanceMethod'] as String? ?? '';
    final savedMealStart = b['mealStart'] as String?;
    _mealStart = (savedMealStart == 'Lunch' || savedMealStart == 'Dinner') ? savedMealStart : null;
    _needDriver = b['needDriver'] == true;
    _extraCharges = extraChargesOf(b);

    totalController.addListener(_recalcBalance);
    advanceController.addListener(_recalcBalance);
    _recalcBalance();

    _loadRooms();
  }

  late final List<Map<String, dynamic>> _initialRooms;

  late DateTime _checkIn;
  late DateTime _checkOut;

  int get _numOfNights => _checkOut.difference(_checkIn).inDays;

  Future<void> _loadRooms() async {
    try {
      final config = await _apiService.fetchRoomConfig();
      final rooms = List<Map<String, dynamic>>.from(
        (config['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
      );
      final known = rooms.map((r) => r['roomNumber'].toString()).toSet();
      setState(() {
        _roomConfig = rooms;
        for (final r in _initialRooms) {
          final roomNum = r['roomNumber'].toString();
          if (!known.contains(roomNum)) _unlistedRooms[roomNum] = r;
        }
        _configLoading = false;
      });
    } catch (e) {
      setState(() => _configLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load room config: $e')),
        );
      }
    }
    await _refreshBookedRooms();
  }

  /// Rooms other bookings hold on this booking's dates.
  Future<Set<String>> _fetchBookedRooms(DateTime checkIn, DateTime checkOut) async {
    final bookings = await _apiService.fetchBookingsForDateRange(checkIn, checkOut);
    return bookedRoomsBetween(
      bookings,
      checkIn,
      checkOut,
      excludeId: widget.booking['_id'] as String?,
    );
  }

  Future<void> _refreshBookedRooms() async {
    try {
      final booked = await _fetchBookedRooms(_checkIn, _checkOut);
      if (mounted) setState(() => _bookedRooms = booked);
    } catch (_) {
      // The grid still works without it; save re-checks availability anyway.
    }
  }

  Future<void> _pickDate({required bool isCheckIn}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? _checkIn : _checkOut,
      firstDate: isCheckIn ? DateTime(2020) : _checkIn.add(const Duration(days: 1)),
      lastDate: DateTime(2030, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.indigo, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    setState(() {
      if (isCheckIn) {
        // Keep the stay length when only the arrival moves.
        final nights = _numOfNights > 0 ? _numOfNights : 1;
        _checkIn = picked;
        _checkOut = picked.add(Duration(days: nights));
      } else {
        _checkOut = picked;
      }
    });
    await _checkRoomsStillFree();
  }

  /// Re-reads what other bookings hold on the current dates and drops any
  /// selected room that is now taken. Returns false when rooms were dropped
  /// or availability could not be checked.
  Future<bool> _checkRoomsStillFree() async {
    final Set<String> booked;
    try {
      booked = await _fetchBookedRooms(_checkIn, _checkOut);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check room availability: $e')),
        );
      }
      return false;
    }
    if (!mounted) return false;

    final clashing = _selectedRooms.intersection(booked);
    setState(() {
      _bookedRooms = booked;
      _selectedRooms.removeAll(clashing);
      _extraBedRooms.removeAll(clashing);
      for (final r in clashing) {
        _unlistedRooms.remove(r);
      }
    });
    if (clashing.isEmpty) return true;

    final names = clashing.map((r) => r.padLeft(3, '0')).join(', ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rooms not available'),
        content: Text(
          'Room${clashing.length > 1 ? 's' : ''} $names '
          '${clashing.length > 1 ? 'are' : 'is'} already booked between '
          '${_fmt(_checkIn)} and ${_fmt(_checkOut)}.\n\n'
          '${clashing.length > 1 ? 'They have' : 'It has'} been removed from this booking. '
          'Please pick replacement rooms before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Reselect rooms'),
          ),
        ],
      ),
    );
    return false;
  }

  String _fmt(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// Rooms as they will be saved: one entry per selected room, typed from the
  /// room config plus the extra-bed toggle.
  List<Map<String, dynamic>> get _roomsData {
    final list = <Map<String, dynamic>>[];
    for (final roomNum in _selectedRooms) {
      final cfg = _roomConfig.firstWhere(
        (r) => r['roomNumber'].toString() == roomNum,
        orElse: () => <String, dynamic>{},
      );
      if (cfg.isEmpty) {
        final kept = _unlistedRooms[roomNum] ??
            _initialRooms.firstWhere(
              (r) => r['roomNumber'].toString() == roomNum,
              orElse: () => {'roomNumber': roomNum, 'roomType': 'Double'},
            );
        final type = (kept['roomType'] ?? 'Double').toString();
        list.add({'roomNumber': roomNum, 'roomType': type, 'pax': paxForType(type)});
        continue;
      }
      final type = effectiveRoomType(cfg, extraBed: _extraBedRooms.contains(roomNum));
      list.add({'roomNumber': roomNum, 'roomType': type, 'pax': paxForType(type)});
    }
    return list;
  }

  @override
  void dispose() {
    totalController.removeListener(_recalcBalance);
    advanceController.removeListener(_recalcBalance);
    totalController.dispose();
    advanceController.dispose();
    packageTypeController.dispose();
    extraDetailsController.dispose();
    guestNameController.dispose();
    guestPhoneController.dispose();
    adultsController.dispose();
    kidsController.dispose();
    super.dispose();
  }

  void _recalcBalance() {
    final total = int.tryParse(totalController.text) ?? 0;
    final advance = int.tryParse(advanceController.text) ?? 0;
    setState(() => _balanceDisplay = (total - advance).toString());
  }

  Future<void> _save() async {
    if (packageTypeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }
    if (_selectedRooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one room')),
      );
      return;
    }
    if (!_checkOut.isAfter(_checkIn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-out must be after check-in')),
      );
      return;
    }
    // Someone may have booked one of these rooms since the screen opened.
    if (!await _checkRoomsStillFree()) return;
    if (!mounted) return;

    final updatedBooking = {
      'num_of_nights': _numOfNights,
      'package': packageTypeController.text,
      'extraDetails': extraDetailsController.text,
      'checkIn': DateTime.utc(_checkIn.year, _checkIn.month, _checkIn.day).toIso8601String(),
      'checkOut': DateTime.utc(_checkOut.year, _checkOut.month, _checkOut.day).toIso8601String(),
      'total': totalController.text,
      'advance': advanceController.text,
      'balanceMethod': _balanceMethod.isEmpty ? null : _balanceMethod,
      'guestName': guestNameController.text,
      'guestPhone': guestPhoneController.text,
      'needDriver': _needDriver,
      // Always sent: the PUT replaces the whole document, so omitting these
      // would wipe the head count off any booking that gets edited.
      'numAdults': int.tryParse(adultsController.text.trim()) ?? _roomCapacity,
      'numKids': int.tryParse(kidsController.text.trim()) ?? 0,
      if (_mealStart != null) 'mealStart': _mealStart,
      'rooms': _roomsData,
      'extraCharges': _extraCharges,
      // Clears the old single-room fields so a converted legacy booking is
      // read in the multi-room format everywhere.
      'roomNumber': null,
      'roomType': null,
    };

    try {
      final id = widget.booking['_id'] as String?;
      if (id == null) throw Exception('Booking ID missing');
      await _apiService.updateBooking(id, updatedBooking);
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update booking: $e')),
      );
    }
  }

  Future<void> _delete() async {
    try {
      final id = widget.booking['_id'] as String?;
      if (id == null) throw Exception('Booking ID missing');
      await _apiService.deleteBooking(id);
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete booking: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Booking',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Booking Details',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 20),

            GuestNameAutocomplete(
              nameController: guestNameController,
              phoneController: guestPhoneController,
              wrapperDecoration: const BoxDecoration(),
              wrapperPadding: EdgeInsets.zero,
              inputDecoration: InputDecoration(
                labelText: 'Guest Name',
                prefixIcon: const Icon(Icons.person, color: Colors.indigo),
                labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.indigo, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 15),
            _buildField('Guest Phone', guestPhoneController, icon: Icons.phone),
            const SizedBox(height: 15),

            // Stay dates — changing them re-checks the selected rooms
            const Text('Stay Dates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _dateTile('Check-In', _checkIn, () => _pickDate(isCheckIn: true))),
                const SizedBox(width: 10),
                Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 10),
                Expanded(child: _dateTile('Check-Out', _checkOut, () => _pickDate(isCheckIn: false))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$_numOfNights night${_numOfNights == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo.shade700),
            ),
            const SizedBox(height: 15),

            // Rooms — same grid as Add Booking
            const Text('Rooms', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 8),
            if (_configLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: Colors.indigo)),
              )
            else
              RoomPicker(
                roomConfig: _roomConfig,
                selectedRooms: _selectedRooms,
                extraBedRooms: _extraBedRooms,
                bookedRooms: _bookedRooms,
                onToggleRoom: (roomNum) => setState(() {
                  if (!_selectedRooms.remove(roomNum)) {
                    _selectedRooms.add(roomNum);
                  } else {
                    _extraBedRooms.remove(roomNum);
                    _unlistedRooms.remove(roomNum);
                  }
                }),
                onToggleExtraBed: (roomNum) => setState(() {
                  if (!_extraBedRooms.remove(roomNum)) _extraBedRooms.add(roomNum);
                }),
              ),
            const SizedBox(height: 10),
            _buildSelectedRoomsSummary(),
            const SizedBox(height: 15),

            // Head count — adults defaults to the rooms' capacity, kids are
            // recorded by hand because they never affect the room chosen.
            const Text('Head Count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildField('Adults (Pax)', adultsController,
                      icon: Icons.person_outline, keyboardType: TextInputType.number),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField('Kids', kidsController,
                      icon: Icons.child_care, keyboardType: TextInputType.number),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Package dropdown
            _buildDropdown(
              label: 'Package Type',
              value: _packages.contains(packageTypeController.text) ? packageTypeController.text : null,
              items: _packages,
              icon: Icons.card_giftcard,
              onChanged: (v) => setState(() {
                packageTypeController.text = v ?? '';
                if (v != 'Full Board' && v != 'Half Board') _mealStart = null;
              }),
            ),
            if (packageTypeController.text == 'Full Board' || packageTypeController.text == 'Half Board') ...[
              const SizedBox(height: 15),
              _buildDropdown(
                label: 'First Meal on Arrival',
                value: _mealStarts.contains(_mealStart) ? _mealStart : null,
                items: _mealStarts,
                icon: Icons.restaurant,
                onChanged: (v) => setState(() => _mealStart = v),
              ),
            ],
            const SizedBox(height: 15),

            _buildField('Extra Details', extraDetailsController, icon: Icons.notes, maxLines: 3),
            const SizedBox(height: 20),
            const Text('Extra Charges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 4),
            Text('Changes here update the Total Cost below.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            ExtraChargesEditor(
              initialCharges: _extraCharges,
              onChanged: (charges) => setState(() {
                totalController.text = adjustTotalForCharges(
                  totalController.text,
                  sumExtraCharges(_extraCharges),
                  sumExtraCharges(charges),
                );
                _extraCharges = charges;
              }),
            ),
            const SizedBox(height: 15),
            _buildField('Total Cost', totalController, icon: Icons.monetization_on),
            const SizedBox(height: 20),
            _buildField('Advance', advanceController, icon: Icons.attach_money),
            const SizedBox(height: 20),

            Text(
              ' Balance : $_balanceDisplay',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
            ),
            const SizedBox(height: 20),

            const Text(
              'Balance Payment Method:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _balanceMethod == 'Bank',
                  onChanged: (v) => setState(() => _balanceMethod = v == true ? 'Bank' : ''),
                  activeColor: Colors.indigo,
                ),
                const Text('Bank', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 20),
                Checkbox(
                  value: _balanceMethod == 'Cash',
                  onChanged: (v) => setState(() => _balanceMethod = v == true ? 'Cash' : ''),
                  activeColor: Colors.indigo,
                ),
                const Text('Cash', style: TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _needDriver,
                  activeColor: Colors.indigo,
                  onChanged: (v) => setState(() => _needDriver = v ?? false),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.drive_eta, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text('Requires Driver Room', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 30),

            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    onPressed: _delete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.delete, color: Colors.white),
                    label: const Text('Delete', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.indigo.shade600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _fmt(date),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo.shade800),
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

  Widget _buildSelectedRoomsSummary() {
    final rooms = _roomsData;
    if (rooms.isEmpty) {
      return Text(
        'No rooms selected. Tap a room to add it.',
        style: TextStyle(fontSize: 12, color: Colors.red.shade400),
      );
    }
    final unlisted = rooms.where((r) => _unlistedRooms.containsKey(r['roomNumber'])).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: rooms.map((r) {
            final isUnlisted = _unlistedRooms.containsKey(r['roomNumber']);
            return InputChip(
              label: Text(
                'Room ${r['roomNumber'].toString().padLeft(3, '0')} · ${r['roomType']} · ${r['pax']}pax',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800),
              ),
              backgroundColor: Colors.green.shade50,
              side: BorderSide(color: Colors.green.shade300),
              // Unlisted rooms are not on the grid, so this is the only way
              // to drop them.
              onDeleted: isUnlisted
                  ? () => setState(() {
                        _selectedRooms.remove(r['roomNumber']);
                        _unlistedRooms.remove(r['roomNumber']);
                      })
                  : null,
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          unlisted.isEmpty
              ? 'Tap + on a selected room to add an extra bed'
              : 'Rooms not in the current room setup are kept as they were.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  /// Combined capacity of this booking's rooms, across both the new per-room
  /// list and the legacy single-room fields. Used only as the fallback for a
  /// booking that predates the stored head count.
  int get _roomCapacity => _initialRooms.fold<int>(0, (sum, r) {
        final pax = r['pax'];
        return sum +
            (pax is num && pax > 0
                ? pax.toInt()
                : paxForType((r['roomType'] ?? '').toString()));
      });

  Widget _buildField(String label, TextEditingController controller,
      {IconData? icon, int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: Colors.indigo) : null,
        labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.indigo),
        labelStyle: const TextStyle(fontSize: 14, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: items.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
      onChanged: onChanged,
    );
  }
}
