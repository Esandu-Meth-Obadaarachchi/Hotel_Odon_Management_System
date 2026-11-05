import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'invoice.dart' as invoice;
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/core/utils/file_saver.dart' as file_saver;
import 'package:odon_booking/features/financials/price_settings_screen.dart';
import 'package:odon_booking/features/bookings/room_selection_screen.dart';
import 'package:odon_booking/features/bookings/widgets/booking_flags.dart';

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
  final TextEditingController _adultsController = TextEditingController();
  final TextEditingController _kidsController = TextEditingController();

  /// True once the adults box has been typed into. From then on the room
  /// selection stops overwriting it.
  bool _adultsEdited = false;

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

  // Not priced on the invoice; carried into the booking when it is added.
  bool _needKiriPidu = false;
  bool _earlyCheckIn = false;
  String? _earlyCheckInTime; // "HH:mm", optional
  bool _lateCheckOut = false;
  String? _lateCheckOutTime; // "HH:mm", optional
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

  /// Combined capacity of the rooms on the invoice. This is where the adults
  /// box starts, because the rooms quoted are what imply the head count.
  int get _autoAdults {
    int total = 0;
    for (var room in _selectedRooms) {
      total += _roomCapacity[room.type]! * room.quantity;
    }
    return total;
  }

  int get _adultsEntered =>
      int.tryParse(_adultsController.text.trim()) ?? _autoAdults;

  int get _kidsEntered => int.tryParse(_kidsController.text.trim()) ?? 0;

  /// Follows the room selection until the user types their own number.
  /// Call inside setState, after the rooms have changed.
  void _syncAdults() {
    if (_adultsEdited) return;
    final auto = _autoAdults;
    _adultsController.text = auto == 0 ? '' : auto.toString();
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
    _syncAdults(); // seed the adults box from the default room
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
    _adultsController.dispose();
    _kidsController.dispose();
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
    _syncAdults();
    _calculateTotal();
  });

  void _removeRoom(int index) {
    if (_selectedRooms.length > 1) {
      setState(() {
        _selectedRooms.removeAt(index);
        _syncAdults();
        _calculateTotal();
      });
    }
  }

  void _updateRoomType(int index, String type) => setState(() {
    _selectedRooms[index].type = type;
    _syncAdults();
    _calculateTotal();
  });

  void _updateRoomQuantity(int index, int quantity) => setState(() {
    _selectedRooms[index].quantity = quantity;
    _syncAdults();
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
          colorScheme: const ColorScheme.light(primary: AppColors.ink, onPrimary: Colors.white),
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
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            LargeTitleSliverAppBar(
              title: 'Invoice',
              subtitle: 'Quote a stay and share the PDF',
              maxWidth: AppLayout.maxForm,
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Edit room prices',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PriceSettingsScreen()),
                    );
                    _fetchPrices();
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),

            SliverToBoxAdapter(
              child: PageBody(
                maxWidth: AppLayout.maxForm,
                padding: EdgeInsets.fromLTRB(AppLayout.gutter(context), 8, AppLayout.gutter(context), 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Guest details ───────────────────────────────────
                    _sectionLabel('Guest'),
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
                    _sectionLabel('Stay'),
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
                                child: const Icon(Icons.arrow_forward_rounded,
                                    size: 16, color: AppColors.ink3),
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
                                  label: _kidsEntered > 0
                                      ? '$_adultsEntered adults + $_kidsEntered kids'
                                      : '$_adultsEntered guests',
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
                                      color: AppColors.sunken,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Room ${index + 1}', style: AppText.bodyStrong.copyWith(fontSize: 14)),
                                  const Spacer(),
                                  if (_selectedRooms.length > 1)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _removeRoom(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.sunken,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.delete_outline_rounded,
                                            color: AppColors.ink2, size: 16),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                value: room.type,
                                decoration: InputDecoration(
                                  labelText: 'Room Type',
                                  prefixIcon: const Icon(Icons.hotel_rounded, size: 20),
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
                                    style: AppText.callout,
                                  ),
                                  const Spacer(),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.hairlineStrong),
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
                                            style: AppText.number(16),
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
                      style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                      onPressed: _addRoom,
                    ),
                    const SizedBox(height: 12),

                    // ── Head count ──────────────────────────────────────
                    _sectionLabel('Guests'),
                    const SizedBox(height: 10),
                    _buildHeadCount(),
                    const SizedBox(height: 20),

                    // ── Package & Options ───────────────────────────────
                    _sectionLabel('Meal plan & options'),
                    const SizedBox(height: 10),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChoiceChipGroup(
                            items: const ['Room Only', 'Bed and Breakfast', 'Half Board', 'Full Board', 'Room + Dinner'],
                            value: _packageType,
                            dotColor: (p) => AppColors.forPackage(const {
                                  'Bed and Breakfast': 'BnB',
                                  'Room + Dinner': 'Dinner Only',
                                }[p] ?? p),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _packageType = v;
                                _updateDayPackages();
                              });
                            },
                          ),
                          if (_packageType == 'Full Board' ||
                              _packageType == 'Half Board') ...[
                            const SizedBox(height: 16),
                            Text('First meal on arrival', style: AppText.footnote.copyWith(color: AppColors.ink2)),
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
                                              ? AppColors.ink
                                              : AppColors.surface,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.ink
                                                : AppColors.hairlineStrong,
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
                                                  : AppColors.ink,
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
                          const SizedBox(height: 16),
                          // Driver room toggle
                          _toggleRow(
                            icon: Icons.directions_car_rounded,
                            iconColor: AppColors.warning,
                            iconBg: AppColors.warningSoft,
                            title: 'Driver room',
                            subtitle:
                                'LKR ${fmt.format(_driverRoomPrice)}/night',
                            value: _includeDriverRoom,
                            onChanged: (v) => setState(() {
                              _includeDriverRoom = v;
                              _calculateTotal();
                            }),
                          ),
                          const SizedBox(height: 8),
                          _toggleRow(
                            icon: Icons.rice_bowl_rounded,
                            iconColor: AppColors.roomOnly,
                            iconBg: AppColors.infoSoft,
                            title: 'Kiri pidu',
                            subtitle: 'Prepare kiri pidu for this booking',
                            value: _needKiriPidu,
                            onChanged: (v) => setState(() => _needKiriPidu = v),
                          ),
                          const SizedBox(height: 8),
                          _toggleRow(
                            icon: Icons.schedule_rounded,
                            iconColor: AppColors.success,
                            iconBg: AppColors.successSoft,
                            title: 'Early check-in',
                            subtitle: 'Arriving before 2:00 PM',
                            value: _earlyCheckIn,
                            onChanged: (v) => setState(() => _earlyCheckIn = v),
                          ),
                          if (_earlyCheckIn)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                              child: OptionalTimeField(
                                value: _earlyCheckInTime,
                                hint: 'Arrival time (optional)',
                                onChanged: (t) => setState(() => _earlyCheckInTime = t),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _toggleRow(
                            icon: Icons.more_time_rounded,
                            iconColor: AppColors.warning,
                            iconBg: AppColors.warningSoft,
                            title: 'Late check-out',
                            subtitle: 'Leaving after 11:00 AM',
                            value: _lateCheckOut,
                            onChanged: (v) => setState(() => _lateCheckOut = v),
                          ),
                          if (_lateCheckOut)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                              child: OptionalTimeField(
                                value: _lateCheckOutTime,
                                hint: 'Departure time (optional)',
                                onChanged: (t) => setState(() => _lateCheckOutTime = t),
                              ),
                            ),
                          const SizedBox(height: 8),
                          // Day customization toggle
                          _toggleRow(
                            icon: Icons.calendar_month_rounded,
                            iconColor: AppColors.roomOnly,
                            iconBg: AppColors.infoSoft,
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
                    _sectionLabel('Extra charges'),
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
                                  child: const Icon(Icons.delete_outline_rounded,
                                      color: AppColors.ink3, size: 20),
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
                      style: TextButton.styleFrom(foregroundColor: AppColors.ink),
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
                    FilledButton.icon(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          _generateInvoice();
                        }
                      },
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      label: const Text('Generate invoice'),
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
    final netColor = _totalAmount >= 0 ? AppColors.ink : AppColors.danger;

    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Summary', style: AppText.headline),
              const Spacer(),
              StatusPill('$nights night${nights == 1 ? '' : 's'}', icon: Icons.nights_stay_outlined),
            ],
          ),
          const SizedBox(height: 14),
          ..._selectedRooms.map((room) => _summaryRow('${room.quantity} × ${room.type} room', '')),
          if (_includeDriverRoom) _summaryRow('1 × Driver room', ''),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          _summaryRow('Subtotal', 'LKR ${fmt.format(subtotal)}', bold: true),
          if (_discount > 0)
            _summaryRow('Standard discount', '− LKR ${fmt.format(_discount)}'),
          if (_additionalDiscount > 0)
            _summaryRow('Additional discount', '− LKR ${fmt.format(_additionalDiscount)}'),
          if (_totalExtraCharges > 0)
            _summaryRow('Extra charges', '+ LKR ${fmt.format(_totalExtraCharges)}'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: AppColors.canvas, borderRadius: AppRadius.control),
            child: Row(
              children: [
                Text('Total', style: AppText.bodyStrong),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('LKR ${fmt.format(_totalAmount)}', style: AppText.number(22, color: netColor)),
                  ),
                ),
              ],
            ),
          ),
          if (_advanceAmount > 0) ...[
            const SizedBox(height: 10),
            _summaryRow('Advance paid', 'LKR ${fmt.format(_advanceAmount)}', valueColor: AppColors.success),
            _summaryRow('Balance due', 'LKR ${fmt.format(_remainingBalance)}', bold: true),
          ],
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
      padding: EdgeInsets.only(left: indent * 16.0, top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: bold ? AppText.bodyStrong.copyWith(fontSize: 14) : AppText.callout),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: AppText.number(14,
                  weight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: valueColor ?? (bold ? AppColors.ink : AppColors.ink2)),
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
                  style: AppText.bodyStrong.copyWith(fontSize: 13),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  dayStr,
                  style: AppText.footnote,
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

  /// Adults + kids. Adults is prefilled from the rooms quoted above and stays
  /// in step with them until it is typed into; kids is always manual, because
  /// children never enter into which room gets quoted.
  Widget _buildHeadCount() {
    final auto = _autoAdults;
    final kids = _kidsEntered;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  controller: _adultsController,
                  label: 'Adults (Pax)',
                  icon: Icons.person_outline_rounded,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _adultsEdited = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
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
                    'Rooms quoted fit $auto adults',
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
                    'Adults comes from the rooms above; edit it if the party differs. '
                    'Kids are counted separately and shown on the invoice.',
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
    );
  }

  Widget _card({required Widget child}) {
    return Card(
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
      decoration: fieldDecoration(label, icon: icon),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    bool isRequired = false,
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
              hasDate ? DateFormat('EEE d MMM').format(date) : 'Select date',
              style: hasDate ? AppText.bodyStrong : AppText.body.copyWith(color: AppColors.ink4),
              overflow: TextOverflow.ellipsis,
            ),
            if (hasDate)
              Text(DateFormat('yyyy').format(date), style: AppText.footnote.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _infoPill({required IconData icon, required String label}) =>
      StatusPill(label, icon: icon);

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
      borderRadius: AppRadius.control,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.control,
          border: Border.all(color: value ? AppColors.ink : AppColors.hairline),
        ),
        child: Row(
          children: [
            IconWell(icon, size: 34, color: value ? iconColor : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong.copyWith(fontSize: 14)),
                  Text(subtitle, style: AppText.footnote.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
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
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: onTap != null ? AppColors.ink : AppColors.ink4),
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
      numGuests: _adultsEntered,
      numKids: _kidsEntered,
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
      'needKiriPidu': _needKiriPidu,
      'earlyCheckIn': _earlyCheckIn,
      'earlyCheckInTime': _earlyCheckIn ? _earlyCheckInTime : null,
      'lateCheckOut': _lateCheckOut,
      'lateCheckOutTime': _lateCheckOut ? _lateCheckOutTime : null,
      'extraDetails': _specialNotesController.text,
      'numAdults': _adultsEntered,
      'numKids': _kidsEntered,
      // Already counted in the total above; the booking keeps the breakdown.
      'extraCharges': _extraCharges
          .where((c) => c.reason.trim().isNotEmpty || c.amount != 0)
          .map((c) => {'reason': c.reason.trim(), 'amount': c.amount})
          .toList(),
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
    // Spelling the kids out here is what lets the guest correct it before
    // arrival, rather than it being argued about at the desk.
    if (_kidsEntered > 0) {
      buffer.writeln(
        '${_adultsEntered} ${_adultsEntered == 1 ? "adult" : "adults"} '
        'and ${_kidsEntered} ${_kidsEntered == 1 ? "kid" : "kids"}',
      );
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
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 8),
              const Text('Invoice ready'),
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
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () async {
                          final ok = await file_saver.sharePdfLast();
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Sharing is not supported in this browser. Use Open PDF instead.',
                                ),
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
                          minimumSize: const Size.fromHeight(48),
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
                      label: const Text('Add as booking'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
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
                    style: AppText.eyebrow,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: AppRadius.control,
                      border: Border.all(color: AppColors.hairline),
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
                      label: const Text('Copy message'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: message));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Message copied to clipboard'),
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

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: AppText.eyebrow),
    );
