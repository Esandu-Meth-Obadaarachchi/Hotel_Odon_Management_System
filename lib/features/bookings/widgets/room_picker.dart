import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

/// Room grid shared by Add Booking and Edit Booking, so both screens pick
/// rooms the same way: tap a card to select it, tap the `+` badge on a
/// selected card to add an extra bed.
///
/// The widget holds no state. The parent owns the three sets and rebuilds it
/// through the two callbacks.

/// Effective room type for a configured room, given whether it has an extra bed.
String effectiveRoomType(Map<String, dynamic> roomCfg, {required bool extraBed}) {
  final baseType = roomCfg['baseType'] as String? ?? 'Double';
  if (baseType == 'Family') return extraBed ? 'Family Plus' : 'Family';
  return extraBed ? 'Triple' : 'Double';
}

/// Adult capacity of a room type, as shown on the cards ("4pax").
int paxForType(String roomType) {
  switch (roomType) {
    case 'Triple':
      return 3;
    case 'Family':
      return 4;
    case 'Family Plus':
      return 5;
    default:
      return 2;
  }
}

/// True when a stored room type means the room has an extra bed in it.
bool hasExtraBed(String roomType) =>
    roomType == 'Triple' || roomType == 'Family Plus';

/// Room numbers already taken by [bookings] for any night between [checkIn]
/// and [checkOut]. Pass [excludeId] when editing, so a booking never clashes
/// with itself.
Set<String> bookedRoomsBetween(
  List<Map<String, dynamic>> bookings,
  DateTime checkIn,
  DateTime checkOut, {
  String? excludeId,
}) {
  final ci = DateTime(checkIn.year, checkIn.month, checkIn.day);
  final co = DateTime(checkOut.year, checkOut.month, checkOut.day);
  final booked = <String>{};

  for (final booking in bookings) {
    if (excludeId != null && booking['_id'] == excludeId) continue;
    final bi = DateTime.tryParse(booking['checkIn']?.toString() ?? '');
    final bo = DateTime.tryParse(booking['checkOut']?.toString() ?? '');
    if (bi == null || bo == null) continue;
    final normBI = DateTime(bi.year, bi.month, bi.day);
    final normBO = DateTime(bo.year, bo.month, bo.day);

    // Check-out morning and check-in afternoon share a day without clashing.
    final overlaps = ci.isBefore(normBO) && co.isAfter(normBI);
    if (!overlaps) continue;

    final rooms = booking['rooms'];
    if (rooms is List && rooms.isNotEmpty) {
      for (final r in rooms) {
        booked.add(r['roomNumber'].toString());
      }
    } else if (booking['roomNumber'] != null) {
      booked.add(booking['roomNumber'].toString());
    }
  }
  return booked;
}

class RoomPicker extends StatelessWidget {
  final List<Map<String, dynamic>> roomConfig;
  final Set<String> selectedRooms;
  final Set<String> extraBedRooms;
  final Set<String> bookedRooms;
  final ValueChanged<String> onToggleRoom;
  final ValueChanged<String> onToggleExtraBed;

  const RoomPicker({
    super.key,
    required this.roomConfig,
    required this.selectedRooms,
    required this.extraBedRooms,
    required this.bookedRooms,
    required this.onToggleRoom,
    required this.onToggleExtraBed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFloorSection('Ground'),
        const SizedBox(height: 10),
        _buildFloorSection('Upper'),
        const SizedBox(height: 12),
        _buildLegend(),
      ],
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room) {
    final roomNum = room['roomNumber'] as String;
    final baseType = room['baseType'] as String;
    final isBlocked = room['isBlocked'] == true;
    final isSelected = selectedRooms.contains(roomNum);
    // A room the booking already holds stays selectable even if it is blocked
    // now, otherwise an edit could never keep it.
    final isBooked = bookedRooms.contains(roomNum) && !isSelected;
    final hasExtra = extraBedRooms.contains(roomNum);

    final roomType = isSelected ? effectiveRoomType(room, extraBed: hasExtra) : baseType;
    final pax = paxForType(roomType);

    // Selected rooms take the ink fill used for every selection in the app;
    // an extra bed adds amber so it can't be missed at the desk.
    Color bgColor = AppColors.surface;
    Color textColor = AppColors.ink;
    Color borderColor = AppColors.hairlineStrong;

    if (isBlocked && !isSelected) {
      bgColor = AppColors.sunken;
      textColor = AppColors.ink4;
      borderColor = AppColors.sunken;
    } else if (isBooked) {
      bgColor = AppColors.tint(AppColors.danger, 0.07);
      textColor = AppColors.danger;
      borderColor = AppColors.tint(AppColors.danger, 0.25);
    } else if (isSelected && hasExtra) {
      bgColor = AppColors.warning;
      textColor = Colors.white;
      borderColor = AppColors.warning;
    } else if (isSelected) {
      bgColor = AppColors.ink;
      textColor = Colors.white;
      borderColor = AppColors.ink;
    }

    final canTap = isSelected || (!isBlocked && !isBooked);

    return Pressable(
      onTap: canTap ? () => onToggleRoom(roomNum) : null,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.ease,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor),
          boxShadow: isSelected
              ? [BoxShadow(color: bgColor.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(roomNum.padLeft(3, '0'), style: AppText.number(17, color: textColor)),
                    const SizedBox(height: 3),
                    Text(
                      isSelected
                          ? roomType
                          : isBlocked
                              ? 'Blocked'
                              : isBooked
                                  ? 'Booked'
                                  : baseType,
                      style: AppText.footnote.copyWith(
                        fontSize: 10,
                        height: 1.2,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isSelected)
                      Text(
                        '$pax pax',
                        style: AppText.footnote.copyWith(
                            fontSize: 10, height: 1.2, color: textColor.withValues(alpha: 0.7)),
                      ),
                  ],
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Tooltip(
                  message: hasExtra ? 'Remove extra bed' : 'Add extra bed',
                  child: GestureDetector(
                    onTap: () => onToggleExtraBed(roomNum),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: hasExtra ? Colors.white : Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasExtra ? Icons.remove_rounded : Icons.add_rounded,
                        size: 14,
                        color: hasExtra ? AppColors.warning : Colors.white,
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

  Widget _buildFloorSection(String floor) {
    final rooms = roomConfig.where((r) => r['floor'] == floor).toList();
    if (rooms.isEmpty) return const SizedBox.shrink();

    return SurfaceCard(
      padding: EdgeInsets.zero,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Row(
              children: [
                Text('$floor floor'.toUpperCase(), style: AppText.eyebrow),
                const Spacer(),
                Text('${rooms.length} rooms', style: AppText.footnote.copyWith(fontSize: 12)),
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

  Widget _buildLegend() {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _legendChip(AppColors.surface, AppColors.hairlineStrong, 'Available'),
        _legendChip(AppColors.ink, AppColors.ink, 'Selected'),
        _legendChip(AppColors.warning, AppColors.warning, 'Extra bed'),
        _legendChip(AppColors.tint(AppColors.danger, 0.1), AppColors.tint(AppColors.danger, 0.4), 'Booked'),
        _legendChip(AppColors.sunken, AppColors.sunken, 'Blocked'),
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
        const SizedBox(width: 6),
        Text(label, style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink2)),
      ],
    );
  }
}
