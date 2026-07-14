import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'invoice.dart' as invoice;
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/core/utils/file_saver.dart' as file_saver;
import 'package:odon_booking/features/financials/price_settings_screen.dart';
import 'package:odon_booking/features/bookings/room_selection_screen.dart';

class Room {
  String type;
  int quantity;
  Room(this.type, this.quantity);
}

class ExtraCharge {
  String reason;
  double amount;
  ExtraCharge({required this.reason, required this.amount});
}

class GenerateInvoiceScreen extends StatefulWidget {
  @override
  _GenerateInvoiceScreenState createState() => _GenerateInvoiceScreenState();
}

class _GenerateInvoiceScreenState extends State<GenerateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nicController = TextEditingController();
  final TextEditingController _checkInController = TextEditingController();
  final TextEditingController _checkOutController = TextEditingController();
  final TextEditingController _additionalDiscountController = TextEditingController();
  final TextEditingController _specialNotesController = TextEditingController();
  final TextEditingController _advanceAmountController = TextEditingController();

  DateTime? _checkInDate;
  DateTime? _checkOutDate;

  String _packageType = 'Full Board';
  String _startMeal = 'Lunch';
  bool _customizePackages = false;
  List<String> _dayPackages = [];
  double _totalAmount = 0.0;
  double _discount = 0.0;
  double _additionalDiscount = 0.0;
  double _discountPerRoom = 1000.0;
  bool _includeDriverRoom = false;
  double _driverRoomPrice = 2500.0;

  List<ExtraCharge> _extraCharges = [];
  List<Room> _selectedRooms = [];

  Map<String, Map<String, double>> _roomPrices = {
    'Full Board':        {'Single': 15250, 'Double': 22500, 'Triple': 28750, 'Family': 35000, 'Family Plus': 42250},
    'Half Board':        {'Single': 13250, 'Double': 18500, 'Triple': 22750, 'Family': 27000, 'Family Plus': 32250},
    'Bed and Breakfast': {'Single': 11250, 'Double': 14500, 'Triple': 16750, 'Family': 19000, 'Family Plus': 22250},
    'Room Only':         {'Single': 10000, 'Double': 12000, 'Triple': 13000, 'Family': 14000, 'Family Plus': 16000},
    'Room + Dinner':     {'Single': 14000, 'Double': 15000, 'Triple': 18000, 'Family': 21000, 'Family Plus': 24000},
  };

  final Map<String, int> _roomCapacity = {
    'Single': 1, 'Double': 2, 'Triple': 3, 'Family': 4, 'Family Plus': 5,
  };

  int get _totalGuests {
    int total = 0;
    for (var room in _selectedRooms) {
      total += _roomCapacity[room.type]! * room.quantity;
    }
    return total;
  }

  int get _totalRoomNights {
    if (_checkInDate == null || _checkOutDate == null) return 0;
    int nights = _checkOutDate!.difference(_checkInDate!).inDays;
    int total = 0;
    for (var room in _selectedRooms) {
      total += room.quantity * nights;
    }
    return total;
  }

  double get _driverRoomTotal {
    if (!_includeDriverRoom || _checkInDate == null || _checkOutDate == null) return 0.0;
    int nights = _checkOutDate!.difference(_checkInDate!).inDays;
    return _driverRoomPrice * nights;
  }

  double get _totalExtraCharges =>
      _extraCharges.fold(0.0, (sum, charge) => sum + charge.amount);

  double get _advanceAmount =>
      double.tryParse(_advanceAmountController.text) ?? 0.0;

  double get _remainingBalance => _totalAmount - _advanceAmount;

  @override
  void initState() {
    super.initState();
    _selectedRooms.add(Room('Double', 1));
    _extraCharges.add(ExtraCharge(reason: '', amount: 0.0));
    _fetchPrices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nicController.dispose();
    _checkInController.dispose();
    _checkOutController.dispose();
    _additionalDiscountController.dispose();
    _specialNotesController.dispose();
    _advanceAmountController.dispose();
    super.dispose();
  }

  Future<void> _fetchPrices() async {
    try {
      final data = await ApiService().fetchPrices();
      final packages = data['packages'] as Map<String, dynamic>;
      setState(() {
        _roomPrices = packages.map(
          (pkg, rooms) => MapEntry(
            pkg,
            (rooms as Map<String, dynamic>).map(
              (room, price) => MapEntry(room, (price as num).toDouble()),
            ),
          ),
        );
        _driverRoomPrice = (data['driverRoomPrice'] as num).toDouble();
      });
      _calculateTotal();
    } catch (_) {}
  }

  void _updateDayPackages() {
    if (_checkInDate != null && _checkOutDate != null) {
      int days = _checkOutDate!.difference(_checkInDate!).inDays;
      _dayPackages = List.filled(days, _packageType);
      _calculateTotal();
    }
  }

  void _calculateTotal() {
    if (_checkInDate == null || _checkOutDate == null) return;
    int days = _checkOutDate!.difference(_checkInDate!).inDays;
    double roomTotal = 0.0;

    for (var room in _selectedRooms) {
      if (_customizePackages) {
        for (int i = 0; i < days; i++) {
          String pkg = i < _dayPackages.length ? _dayPackages[i] : _packageType;
          roomTotal += (_roomPrices[pkg]?[room.type] ?? 0.0) * room.quantity;
        }
      } else {
        roomTotal += days * (_roomPrices[_packageType]?[room.type] ?? 0.0) * room.quantity;
      }
    }

    double subtotal = roomTotal + _driverRoomTotal;
    _discount = _discountPerRoom * _totalRoomNights;
    _additionalDiscount = double.tryParse(_additionalDiscountController.text) ?? 0.0;

    setState(() {
      _totalAmount = subtotal - _discount - _additionalDiscount + _totalExtraCharges;
    });
  }

  void _addRoom() => setState(() {
    _selectedRooms.add(Room('Double', 1));
    _calculateTotal();
  });

  void _removeRoom(int index) {
    if (_selectedRooms.length > 1) {
      setState(() {
        _selectedRooms.removeAt(index);
        _calculateTotal();
      });
    }
  }

  void _updateRoomType(int index, String type) => setState(() {
    _selectedRooms[index].type = type;
    _calculateTotal();
  });

  void _updateRoomQuantity(int index, int quantity) => setState(() {
    _selectedRooms[index].quantity = quantity;
    _calculateTotal();
  });

  void _addExtraCharge() => setState(() {
    _extraCharges.add(ExtraCharge(reason: '', amount: 0.0));
  });

  void _removeExtraCharge(int index) {
    setState(() {
      if (_extraCharges.length > 1) {
        _extraCharges.removeAt(index);
      } else {
        _extraCharges[0] = ExtraCharge(reason: '', amount: 0.0);
      }
      _calculateTotal();
    });
  }

  void _updateExtraChargeReason(int index, String reason) =>
      setState(() => _extraCharges[index].reason = reason);

  void _updateExtraChargeAmount(int index, String amountStr) => setState(() {
    _extraCharges[index].amount = double.tryParse(amountStr) ?? 0.0;
    _calculateTotal();
  });

  Future<void> _selectDate(BuildContext context, bool isCheckIn) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn
          ? DateTime.now()
          : (_checkInDate ?? DateTime.now().add(const Duration(days: 1))),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.indigo, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = picked;
          _checkInController.text = DateFormat('yyyy-MM-dd').format(picked);
          _checkOutDate = _checkInDate!.add(const Duration(days: 1));
          _checkOutController.text = DateFormat('yyyy-MM-dd').format(_checkOutDate!);
        } else {
          _checkOutDate = picked;
          _checkOutController.text = DateFormat('yyyy-MM-dd').format(picked);
        }
        _updateDayPackages();
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Form(
        key: _formKey,
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
                  'Generate Invoice',
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
                        Icons.receipt_long_rounded,
                        size: 56,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: Colors.white),
                  tooltip: 'Edit Room Prices',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PriceSettingsScreen()),
                    );
                    _fetchPrices();
                  },
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Guest details ───────────────────────────────────
                    _sectionLabel('Guest Details'),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _field(
                            controller: _nameController,
                            label: 'Guest Name',
                            icon: Icons.person_outline_rounded,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter guest name' : null,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _phoneController,
                            label: 'Phone Number (Optional)',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _nicController,
                            label: 'NIC (Optional)',
                            icon: Icons.badge_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Stay dates ──────────────────────────────────────
                    _sectionLabel('Stay Dates'),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _dateTile(
                                label: 'Check-In',
                                date: _checkInDate,
                                onTap: () => _selectDate(context, true),
                                isRequired: true,
                              )),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: Colors.grey.shade400),
                              ),
                              Expanded(child: _dateTile(
                                label: 'Check-Out',
                                date: _checkOutDate,
                                onTap: () => _selectDate(context, false),
                                isRequired: true,
                              )),
                            ],
                          ),
                          if (_checkInDate != null && _checkOutDate != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _infoPill(
                                  icon: Icons.nights_stay_outlined,
                                  label: '${_checkOutDate!.difference(_checkInDate!).inDays} nights',
                                ),
                                const SizedBox(width: 8),
                                _infoPill(
                                  icon: Icons.people_outline_rounded,
                                  label: '$_totalGuests guests',
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Rooms ───────────────────────────────────────────
                    _sectionLabel('Rooms'),
                    const SizedBox(height: 10),
                    ..._selectedRooms.asMap().entries.map((entry) {
                      final index = entry.key;
                      final room = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _card(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.indigo.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Room ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_selectedRooms.length > 1)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _removeRoom(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.delete_outline_rounded,
                                            color: Colors.red.shade400, size: 16),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                value: room.type,
                                decoration: InputDecoration(
                                  labelText: 'Room Type',
                                  prefixIcon: Icon(Icons.hotel_rounded,
                                      color: Colors.indigo.shade400, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Colors.indigo, width: 2),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                items: ['Single', 'Double', 'Triple', 'Family', 'Family Plus']
                                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) _updateRoomType(index, v);
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    'Quantity',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _qtyButton(
                                          icon: Icons.remove_rounded,
                                          onTap: room.quantity > 1
                                              ? () => _updateRoomQuantity(
                                                  index, room.quantity - 1)
                                              : null,
                                        ),
                                        SizedBox(
                                          width: 36,
                                          child: Text(
                                            '${room.quantity}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        _qtyButton(
                                          icon: Icons.add_rounded,
                                          onTap: () =>
                                              _updateRoomQuantity(index, room.quantity + 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Another Room'),
                      style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                      onPressed: _addRoom,
                    ),
                    const SizedBox(height: 12),

                    // ── Package & Options ───────────────────────────────
                    _sectionLabel('Package & Options'),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _packageType,
                            decoration: InputDecoration(
                              labelText: 'Package',
                              prefixIcon: Icon(Icons.restaurant_menu_rounded,
                                  color: Colors.indigo.shade400, size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Colors.indigo, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            items: ['Room Only', 'Bed and Breakfast', 'Half Board',
                                    'Full Board', 'Room + Dinner']
                                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _packageType = v!;
                                _updateDayPackages();
                              });
                            },
                          ),
                          if (_packageType == 'Full Board' ||
                              _packageType == 'Half Board') ...[
                            const SizedBox(height: 16),
                            Text(
                              'FIRST MEAL ON ARRIVAL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: ['Lunch', 'Dinner'].map((meal) {
                                final selected = _startMeal == meal;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        right: meal == 'Lunch' ? 6 : 0,
                                        left: meal == 'Dinner' ? 6 : 0),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _startMeal = meal),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? Colors.indigo
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? Colors.indigo
                                                : Colors.grey.shade200,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            meal,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: selected
                                                  ? Colors.white
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // Driver room toggle
                          _toggleRow(
                            icon: Icons.directions_car_rounded,
                            iconColor: Colors.amber.shade700,
                            iconBg: Colors.amber.shade50,
                            title: 'Driver Room',
                            subtitle:
                                'LKR ${fmt.format(_driverRoomPrice)}/night',
                            value: _includeDriverRoom,
                            onChanged: (v) => setState(() {
                              _includeDriverRoom = v;
                              _calculateTotal();
                            }),
                          ),
                          const SizedBox(height: 8),
                          // Day customization toggle
                          _toggleRow(
                            icon: Icons.calendar_month_rounded,
                            iconColor: Colors.teal.shade700,
                            iconBg: Colors.teal.shade50,
                            title: 'Custom per-day packages',
                            subtitle: 'Different package for each night',
                            value: _customizePackages,
                            onChanged: (v) => setState(() {
                              _customizePackages = v;
                              _updateDayPackages();
                            }),
                          ),
                          if (_customizePackages &&
                              _checkInDate != null &&
                              _checkOutDate != null) ...[
                            const SizedBox(height: 12),
                            _buildDayPackageOptions(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Extra charges ───────────────────────────────────
                    _sectionLabel('Extra Charges'),
                    const SizedBox(height: 10),
                    ..._extraCharges.asMap().entries.map((entry) {
                      final index = entry.key;
                      final charge = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _card(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: charge.reason,
                                  decoration: InputDecoration(
                                    labelText: 'Reason',
                                    hintText: 'e.g. Airport Transfer',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide:
                                          BorderSide(color: Colors.grey.shade200),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Colors.indigo, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    isDense: true,
                                  ),
                                  onChanged: (v) => _updateExtraChargeReason(index, v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: charge.amount > 0
                                      ? charge.amount.toString()
                                      : '',
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'LKR',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide:
                                          BorderSide(color: Colors.grey.shade200),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Colors.indigo, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    isDense: true,
                                  ),
                                  onChanged: (v) =>
                                      _updateExtraChargeAmount(index, v),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _removeExtraCharge(index),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(Icons.delete_outline_rounded,
                                      color: Colors.red.shade400, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    TextButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Extra Charge'),
                      style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                      onPressed: _addExtraCharge,
                    ),
                    const SizedBox(height: 12),

                    // ── Payment ─────────────────────────────────────────
                    _sectionLabel('Payment'),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        children: [
                          _field(
                            controller: _additionalDiscountController,
                            label: 'Additional Discount (LKR)',
                            icon: Icons.discount_outlined,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _calculateTotal(),
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _advanceAmountController,
                            label: 'Advance Payment (LKR)',
                            icon: Icons.payments_outlined,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _field(
                            controller: _specialNotesController,
                            label: 'Special Notes',
                            icon: Icons.notes_rounded,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Summary card ────────────────────────────────────
                    if (_checkInDate != null && _checkOutDate != null)
                      _buildSummaryCard(fmt),
                    const SizedBox(height: 28),

                    // ── Generate button ─────────────────────────────────
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
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              _generateInvoice();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                          label: const Text(
                            'Generate Invoice',
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
      ),
    );
  }

  Widget _buildSummaryCard(NumberFormat fmt) {
    final nights = _checkOutDate!.difference(_checkInDate!).inDays;
    final subtotal = _totalAmount + _discount + _additionalDiscount - _totalExtraCharges;
    final netColor = _totalAmount >= 0 ? const Color(0xFF16A34A) : Colors.red;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Colors.indigo.shade100)),
            ),
            child: Row(
              children: [
                Icon(Icons.summarize_rounded, color: Colors.indigo.shade600, size: 16),
                const SizedBox(width: 8),
                Text(
                  'INVOICE SUMMARY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                _infoPill(
                  icon: Icons.nights_stay_outlined,
                  label: '$nights nights',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Room details
                ..._selectedRooms.map((room) => _summaryRow(
                  '${room.quantity}× ${room.type} Room',
                  '',
                  indent: 0,
                )),
                if (_includeDriverRoom)
                  _summaryRow('1× Driver Room', '', indent: 0),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 4),
                _summaryRow(
                  'Subtotal',
                  'LKR ${fmt.format(subtotal)}',
                  bold: true,
                ),
                if (_discount > 0)
                  _summaryRow(
                    'Standard Discount',
                    '− LKR ${fmt.format(_discount)}',
                    valueColor: Colors.red.shade600,
                  ),
                if (_additionalDiscount > 0)
                  _summaryRow(
                    'Additional Discount',
                    '− LKR ${fmt.format(_additionalDiscount)}',
                    valueColor: Colors.red.shade600,
                  ),
                if (_totalExtraCharges > 0)
                  _summaryRow(
                    'Extra Charges',
                    '+ LKR ${fmt.format(_totalExtraCharges)}',
                    valueColor: Colors.blue.shade600,
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: netColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: netColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const Spacer(),
                      FittedBox(
                        child: Text(
                          'LKR ${fmt.format(_totalAmount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: netColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_advanceAmount > 0) ...[
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Advance Paid',
                    'LKR ${fmt.format(_advanceAmount)}',
                    valueColor: Colors.green.shade600,
                  ),
                  _summaryRow(
                    'Balance Due',
                    'LKR ${fmt.format(_remainingBalance)}',
                    bold: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    int indent = 0,
    bool bold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent * 16.0, top: 3, bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                color: bold ? Colors.black87 : Colors.grey.shade700,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? (bold ? Colors.black87 : Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayPackageOptions() {
    if (_checkInDate == null || _checkOutDate == null) return const SizedBox.shrink();
    int days = _checkOutDate!.difference(_checkInDate!).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(days, (i) {
        if (_dayPackages.length <= i) _dayPackages.add(_packageType);
        final day = _checkInDate!.add(Duration(days: i));
        final dayStr = DateFormat('EEE, d MMM').format(day);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 60,
                child: Text(
                  'Day ${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dayStr,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              Expanded(
                flex: 3,
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  value: _dayPackages[i],
                  items: ['Room Only', 'Bed and Breakfast', 'Half Board', 'Full Board', 'Room + Dinner']
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v, style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _dayPackages[i] = v!;
                    _calculateTotal();
                  }),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
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

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    bool isRequired = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: date != null ? Colors.indigo.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null ? Colors.indigo.shade200 : Colors.grey.shade200,
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
                color: date != null ? Colors.indigo.shade500 : Colors.grey.shade500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: date != null ? Colors.indigo.shade600 : Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    date != null
                        ? DateFormat('d MMM yyyy').format(date)
                        : 'Tap to set',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: date != null
                          ? Colors.indigo.shade800
                          : Colors.grey.shade400,
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

  Widget _infoPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.indigo.shade600),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.indigo.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? iconBg.withValues(alpha: 0.5) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? iconColor.withValues(alpha: 0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: value,
                activeColor: iconColor,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18,
            color: onTap != null ? Colors.indigo : Colors.grey.shade300),
      ),
    );
  }

  void _generateInvoice() async {
    if (_checkInDate == null || _checkOutDate == null) return;

    String packageDetails = _customizePackages
        ? 'Custom package with varying meal plans'
        : _packageType;

    String roomDetails = _selectedRooms.map((r) => '${r.quantity}x ${r.type}').join(', ');
    if (_includeDriverRoom) roomDetails += ', 1x Driver Room';

    String? startMealForInvoice;
    if (!_customizePackages &&
        (_packageType == 'Full Board' || _packageType == 'Half Board')) {
      startMealForInvoice = _startMeal;
    }

    Map<String, Map<String, dynamic>> priceBreakdown = {};
    if (_checkInDate != null && _checkOutDate != null) {
      int nights = _checkOutDate!.difference(_checkInDate!).inDays;
      for (var room in _selectedRooms) {
        String key = '${room.type} - ${_customizePackages ? "Custom" : _packageType}';
        double roomPrice = 0;
        if (_customizePackages) {
          for (int i = 0; i < nights && i < _dayPackages.length; i++) {
            roomPrice += _roomPrices[_dayPackages[i]]![room.type]! * room.quantity;
          }
        } else {
          roomPrice = _roomPrices[_packageType]![room.type]! * room.quantity * nights;
        }
        priceBreakdown[key] = {
          'quantity': room.quantity,
          'nights': nights,
          'unitPrice': _roomPrices[_packageType]![room.type],
          'totalPrice': roomPrice,
        };
      }
      if (_includeDriverRoom) {
        priceBreakdown['Driver Room'] = {
          'quantity': 1,
          'nights': nights,
          'unitPrice': _driverRoomPrice,
          'totalPrice': _driverRoomPrice * nights,
        };
      }
    }

    const String fixedNotes =
        '- Once you arrive to check in, please produce the NIC of the person under whose name the booking was made.\n'
        '- If you need a driver\'s room, please inform on the same day you make the reservation\n'
        '- If you need any extra meal please inform the previous day\n'
        '- Meals brought from outside will not be allowed to have inside the rooms or restaurant\n'
        '- Swimming Pool will be unavailable after 8.00pm';

    String combinedNotes = _specialNotesController.text;
    if (combinedNotes.isNotEmpty) combinedNotes += '\n\n';
    combinedNotes += 'PLEASE NOTE THAT:\n$fixedNotes';

    final fmt = NumberFormat('#,##0.00');

    final pdfUrl = await invoice.generateInvoice(
      guestName: _nameController.text,
      guestPhone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
      checkIn: _checkInController.text,
      checkOut: _checkOutController.text,
      numGuests: _totalGuests,
      room: roomDetails,
      packageDetails: packageDetails,
      startMeal: startMealForInvoice,
      totalAmount: fmt.format(_totalAmount + _discount + _additionalDiscount - _totalExtraCharges),
      standardDiscount: fmt.format(_discount),
      additionalDiscount: fmt.format(_additionalDiscount),
      extraCharges: _extraCharges
          .where((c) => c.reason.isNotEmpty && c.amount > 0)
          .map((c) => invoice.ExtraCharge(reason: c.reason, amount: c.amount))
          .toList(),
      finalAmount: fmt.format(_totalAmount),
      advanceAmount: fmt.format(_advanceAmount),
      balanceAmount: fmt.format(_remainingBalance),
      priceBreakdown: priceBreakdown,
      specialNotes: combinedNotes,
    );

    if (!mounted) return;

    final summaryMessage = _buildWhatsAppSummary(fmt);
    _showInvoiceReadyDialog(summaryMessage, pdfUrl);
  }

  /// Maps the invoice's package names to the booking system's package names
  /// and returns a prefill map consumed by [RoomSelectionScreen].
  Map<String, dynamic> _buildBookingPrefill() {
    const pkgMap = {
      'Full Board': 'Full Board',
      'Half Board': 'Half Board',
      'Room Only': 'Room Only',
      'Bed and Breakfast': 'BnB',
      'Room + Dinner': 'Dinner Only',
    };

    final mappedPackage = _customizePackages ? null : pkgMap[_packageType];
    final startMeal = (!_customizePackages &&
            (_packageType == 'Full Board' || _packageType == 'Half Board'))
        ? _startMeal
        : null;

    return {
      'guestName': _nameController.text,
      'guestPhone': _phoneController.text,
      'checkIn': _checkInDate,
      'checkOut': _checkOutDate,
      'package': mappedPackage,
      'mealStart': startMeal,
      'total': _totalAmount.toStringAsFixed(2),
      'advance': _advanceAmount.toStringAsFixed(2),
      'needDriver': _includeDriverRoom,
      'extraDetails': _specialNotesController.text,
    };
  }

  String _buildWhatsAppSummary(NumberFormat fmt) {
    final nights = _checkOutDate!.difference(_checkInDate!).inDays;

    String dateLine;
    if (nights == 1) {
      dateLine = _ordinalDate(_checkInDate!);
    } else {
      dateLine = '${_ordinalDate(_checkInDate!)} - ${_ordinalDate(_checkOutDate!)}';
    }

    final roomLines = <String>[];
    for (final r in _selectedRooms) {
      final label = r.quantity == 1 ? '${r.type} room' : '${r.type} rooms';
      roomLines.add('${r.quantity} $label');
    }
    if (_includeDriverRoom) roomLines.add('1 Driver room');

    final buffer = StringBuffer();
    buffer.writeln('Dear sir,');
    buffer.writeln('Pls check whether the following details are correct.');
    buffer.writeln('Name : ${_nameController.text}');
    if (_nicController.text.trim().isNotEmpty) {
      buffer.writeln('NIC : ${_nicController.text.trim()}');
    }
    buffer.writeln('Date : $dateLine');
    buffer.writeln('$nights ${nights == 1 ? "night" : "nights"}');
    buffer.writeln('Package : $packageDetails');
    for (final line in roomLines) {
      buffer.writeln(line);
    }
    buffer.writeln('Total : LKR ${fmt.format(_totalAmount)}');
    buffer.writeln('Advance : LKR ${fmt.format(_advanceAmount)}');
    buffer.writeln('Remaining : LKR ${fmt.format(_remainingBalance)}');
    return buffer.toString().trimRight();
  }

  String get packageDetails => _customizePackages
      ? 'Custom package with varying meal plans'
      : _packageType;

  String _ordinalDate(DateTime d) {
    final day = d.day;
    final suffix = (day >= 11 && day <= 13)
        ? 'th'
        : (day % 10 == 1)
            ? 'st'
            : (day % 10 == 2)
                ? 'nd'
                : (day % 10 == 3)
                    ? 'rd'
                    : 'th';
    return '$day$suffix ${DateFormat('MMMM').format(d)}';
  }

  void _showInvoiceReadyDialog(String message, String? pdfUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Text('Invoice Ready'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pdfUrl != null && kIsWeb) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Share PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          final ok = await file_saver.sharePdfLast();
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Sharing is not supported in this browser. Use Open PDF instead.',
                                ),
                                backgroundColor: Colors.orange.shade700,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (pdfUrl != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: const Text('Open PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => file_saver.openPdfUrl(pdfUrl),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Add this invoice to the booking system
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.hotel_rounded, size: 18),
                      label: const Text('Add Booking to System'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RoomSelectionScreen(prefill: _buildBookingPrefill()),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'WHATSAPP MESSAGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: SelectableText(
                      message,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Message'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: message));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Message copied to clipboard'),
                            backgroundColor: Colors.green.shade600,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
