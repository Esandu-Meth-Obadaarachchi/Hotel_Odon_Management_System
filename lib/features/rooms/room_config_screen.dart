import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/core/api/api_service.dart';

class RoomConfigScreen extends StatefulWidget {
  @override
  _RoomConfigScreenState createState() => _RoomConfigScreenState();
}

class _RoomConfigScreenState extends State<RoomConfigScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchConfig();
  }

  Future<void> _fetchConfig() async {
    try {
      final config = await _apiService.fetchRoomConfig();
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(
          (config['rooms'] as List).map((r) => Map<String, dynamic>.from(r)),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load room config: $e')),
      );
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await _apiService.updateRoomConfig(_rooms);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room configuration saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groundRooms = _rooms.where((r) => r['floor'] == 'Ground').toList();
    final upperRooms = _rooms.where((r) => r['floor'] == 'Upper').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Room setup'),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: _saveConfig, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const LoadingView()
          : SingleChildScrollView(
              padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 16, bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLegend(),
                  if (groundRooms.isNotEmpty) ...[
                    _buildFloorHeader('Ground floor'),
                    _buildFloor(groundRooms),
                  ],
                  if (upperRooms.isNotEmpty) ...[
                    _buildFloorHeader('Upper floor'),
                    _buildFloor(upperRooms),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLegend() => const InlineBanner(
        'Double sleeps 2 (3 with an extra bed). Family sleeps 4 (5 with an extra bed). '
        'Blocked rooms can\'t be picked for new bookings.',
      );

  Widget _buildFloorHeader(String label) => FormSectionLabel(label);

  Widget _buildFloor(List<Map<String, dynamic>> rooms) => SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (var i = 0; i < rooms.length; i++) ...[
            if (i > 0) const Padding(padding: EdgeInsets.only(left: 76), child: Divider()),
            _buildRoomRow(rooms[i]),
          ],
        ]),
      );

  Widget _buildRoomRow(Map<String, dynamic> room) {
    final index = _rooms.indexWhere((r) => r['roomNumber'] == room['roomNumber']);
    final isBlocked = room['isBlocked'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isBlocked ? AppColors.blocked : AppColors.sunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    room['roomNumber'].toString().padLeft(3, '0'),
                    style: AppText.number(14, color: isBlocked ? Colors.white : AppColors.ink),
                  ),
                  if (isBlocked) const Icon(Icons.lock_rounded, size: 11, color: Colors.white70),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ChoiceChipGroup(
              items: const ['Double', 'Family'],
              value: room['baseType'] as String?,
              onChanged: (val) {
                if (val != null && index >= 0) {
                  setState(() => _rooms[index]['baseType'] = val);
                }
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: isBlocked,
                trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? AppColors.blocked : AppColors.hairlineStrong),
                onChanged: (val) {
                  if (index >= 0) setState(() => _rooms[index]['isBlocked'] = val);
                },
              ),
              Text('Blocked', style: AppText.footnote.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
