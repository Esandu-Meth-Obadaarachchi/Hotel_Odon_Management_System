import 'package:flutter/material.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/features/guests/widgets/guest_name_autocomplete.dart';

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

  // Legacy fields (old single-room bookings)
  late TextEditingController roomNumberController;
  late TextEditingController roomTypeController;

  // New: per-room list (new multi-room bookings)
  late List<Map<String, dynamic>> _rooms;
  late bool _isNewFormat;

  String _balanceMethod = '';
  String _balanceDisplay = 'N/A';
  String? _mealStart;
  bool _needDriver = false;

  static const _roomTypes = ['Double', 'Triple', 'Family', 'Family Plus'];
  static const _packages = ['Full Board', 'Half Board', 'Room Only', 'BnB', 'Dinner Only'];
  static const _mealStarts = ['Lunch', 'Dinner'];

  @override
  void initState() {
    super.initState();
    final b = widget.booking;

    _isNewFormat = b['rooms'] != null && (b['rooms'] as List).isNotEmpty;
    _rooms = _isNewFormat
        ? List<Map<String, dynamic>>.from(
            (b['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
          )
        : [];

    roomNumberController = TextEditingController(text: b['roomNumber'] as String? ?? '');
    roomTypeController = TextEditingController(text: b['roomType'] as String? ?? '');
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
    roomNumberController.dispose();
    roomTypeController.dispose();
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
    if (_isNewFormat) {
      if (packageTypeController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')),
        );
        return;
      }
    } else {
      if (roomNumberController.text.isEmpty ||
          roomTypeController.text.isEmpty ||
          packageTypeController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')),
        );
        return;
      }
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
      // Legacy fields
      if (!_isNewFormat) 'roomNumber': roomNumberController.text,
      if (!_isNewFormat) 'roomType': roomTypeController.text,
      // New fields
      if (_isNewFormat) 'rooms': _rooms,
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

            // Rooms section — new format shows per-room type editors, legacy shows text fields
            if (_isNewFormat) ...[
              const Text('Rooms', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 8),
              ..._rooms.asMap().entries.map((entry) => _buildRoomRow(entry.key, entry.value)),
              const SizedBox(height: 15),
            ] else ...[
              _buildField('Room Number', roomNumberController, icon: Icons.hotel),
              const SizedBox(height: 15),
              _buildField('Room Type', roomTypeController, icon: Icons.room_preferences),
              const SizedBox(height: 15),
            ],

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

  Widget _buildRoomRow(int index, Map<String, dynamic> room) {
    final currentType = room['roomType'] as String? ?? 'Double';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  (room['roomNumber'] ?? '').toString().padLeft(3, '0'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _roomTypes.contains(currentType) ? currentType : null,
                decoration: InputDecoration(
                  labelText: 'Room Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _roomTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _rooms[index]['roomType'] = v;
                      _rooms[index]['pax'] = _paxForType(v);
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_paxForType(currentType)}pax',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  int _paxForType(String type) {
    switch (type) {
      case 'Double': return 2;
      case 'Triple': return 3;
      case 'Family': return 4;
      case 'Family Plus': return 5;
      default: return 2;
    }
  }

  /// Combined capacity of this booking's rooms, across both the new per-room
  /// list and the legacy single-room fields. Used only as the fallback for a
  /// booking that predates the stored head count.
  int get _roomCapacity {
    if (_isNewFormat) {
      return _rooms.fold<int>(0, (sum, r) {
        final pax = r['pax'];
        return sum +
            (pax is num && pax > 0
                ? pax.toInt()
                : _paxForType((r['roomType'] ?? '').toString()));
      });
    }
    return _paxForType(roomTypeController.text);
  }

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
