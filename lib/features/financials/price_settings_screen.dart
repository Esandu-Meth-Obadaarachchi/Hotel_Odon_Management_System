import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/core/api/api_service.dart';

class PriceSettingsScreen extends StatefulWidget {
  @override
  _PriceSettingsScreenState createState() => _PriceSettingsScreenState();
}

class _PriceSettingsScreenState extends State<PriceSettingsScreen> {
  final _apiService = ApiService();

  static const List<String> _packages = [
    'Full Board',
    'Half Board',
    'Bed and Breakfast',
    'Room Only',
    'Room + Dinner',
  ];

  static const List<String> _roomTypes = [
    'Single',
    'Double',
    'Triple',
    'Family',
    'Family Plus',
  ];

  // Package accent colors — distinct, not all indigo
  static const Map<String, Color> _packageColors = {
    'Full Board':        AppColors.fullBoard,
    'Half Board':        AppColors.halfBoard,
    'Bed and Breakfast': AppColors.bnb,
    'Room Only':         AppColors.roomOnly,
    'Room + Dinner':     AppColors.dinnerOnly,
  };

  static const Map<String, IconData> _packageIcons = {
    'Full Board':        Icons.restaurant_menu_rounded,
    'Half Board':        Icons.dining_rounded,
    'Bed and Breakfast': Icons.free_breakfast_rounded,
    'Room Only':         Icons.hotel_rounded,
    'Room + Dinner':     Icons.dinner_dining_rounded,
  };

  static const Map<String, String> _packageAbbr = {
    'Full Board':        'FB',
    'Half Board':        'HB',
    'Bed and Breakfast': 'B&B',
    'Room Only':         'RO',
    'Room + Dinner':     'RD',
  };

  late Map<String, Map<String, TextEditingController>> _controllers;
  late TextEditingController _driverRoomController;

  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (var pkg in _packages)
        pkg: {for (var room in _roomTypes) room: TextEditingController()},
    };
    _driverRoomController = TextEditingController();
    _fetchPrices();
  }

  @override
  void dispose() {
    for (var pkg in _controllers.values) {
      for (var c in pkg.values) c.dispose();
    }
    _driverRoomController.dispose();
    super.dispose();
  }

  Future<void> _fetchPrices() async {
    try {
      final data     = await _apiService.fetchPrices();
      final packages = data['packages'] as Map<String, dynamic>;
      for (var pkg in _packages) {
        final rooms = packages[pkg] as Map<String, dynamic>? ?? {};
        for (var room in _roomTypes) {
          final price = (rooms[room] as num?)?.toDouble() ?? 0.0;
          _controllers[pkg]![room]!.text = price.toStringAsFixed(2);
        }
      }
      _driverRoomController.text =
          ((data['driverRoomPrice'] as num?)?.toDouble() ?? 2500.0)
              .toStringAsFixed(2);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load prices: $e'),
        ),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _savePrices() async {
    setState(() => _saving = true);
    try {
      final packages = <String, Map<String, double>>{
        for (var pkg in _packages)
          pkg: {
            for (var room in _roomTypes)
              room: double.tryParse(_controllers[pkg]![room]!.text) ?? 0.0,
          },
      };
      final driverPrice = double.tryParse(_driverRoomController.text) ?? 2500.0;
      await _apiService.updatePrices(packages, driverPrice);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Prices saved'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room prices'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton.icon(
                  onPressed: _savePrices,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save'),
                ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 16, bottom: 32),
              children: [
                // Header note
                const InlineBanner('Prices are per night in LKR. Changes apply to new invoices.'),
                const SizedBox(height: 16),

                // Driver room
                _buildDriverCard(),
                const SizedBox(height: 20),

                // Column headers
                _buildColumnHeaders(),
                const SizedBox(height: 8),

                // Package rows
                ..._packages.map((pkg) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPackageRow(pkg),
                    )),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildDriverCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const IconWell(Icons.directions_car_rounded, size: 38),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver room',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    'Per night',
                    style: TextStyle(fontSize: 12, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: TextFormField(
                controller: _driverRoomController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: AppText.number(14),
                decoration: InputDecoration(
                  prefixText: 'LKR ',
                  prefixStyle: TextStyle(fontSize: 12, color: AppColors.ink3),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 110),
          ..._roomTypes.map(
            (room) => Expanded(
              child: Text(
                room,
                textAlign: TextAlign.center,
                style: AppText.eyebrow.copyWith(fontSize: 10, letterSpacing: 0.4),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageRow(String package) {
    final color = _packageColors[package] ?? AppColors.ink;
    final icon  = _packageIcons[package] ?? Icons.hotel_rounded;
    final abbr  = _packageAbbr[package] ?? package;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Package label — fixed 110px
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      abbr,
                      style: AppText.bodyStrong.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Price fields
            ..._roomTypes.map(
              (room) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TextFormField(
                    controller: _controllers[package]![room],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: AppText.number(13, weight: FontWeight.w500),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
