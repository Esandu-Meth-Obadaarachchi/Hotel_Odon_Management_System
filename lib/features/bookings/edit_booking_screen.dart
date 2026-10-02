import 'package:flutter/material.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/guests/widgets/guest_name_autocomplete.dart';
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

    totalController.addListener(_recalcBalance);
    advanceController.addListener(_recalcBalance);
    _recalcBalance();

    _loadRooms();
  }

  late final List<Map<String, dynamic>> _initialRooms;

  DateTime get _checkIn => DateTime.parse(widget.booking['checkIn'].toString());
  DateTime get _checkOut => DateTime.parse(widget.booking['checkOut'].toString());

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

    final updatedBooking = {
      'num_of_nights': widget.booking['num_of_nights'],
      'package': packageTypeController.text,
      'extraDetails': extraDetailsController.text,
      'checkIn': widget.booking['checkIn'],
      'checkOut': widget.booking['checkOut'],
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
