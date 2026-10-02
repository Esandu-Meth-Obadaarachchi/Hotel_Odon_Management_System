import 'package:flutter/material.dart';

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

    Color bgColor;
    Color textColor = const Color(0xFF1E293B);

    if (isBlocked && !isSelected) {
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

    final canTap = isSelected || (!isBlocked && !isBooked);

    return GestureDetector(
      onTap: canTap ? () => onToggleRoom(roomNum) : null,
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
                      isSelected
                          ? roomType
                          : isBlocked
                              ? 'Blocked'
                              : isBooked
                                  ? 'Booked'
                                  : baseType,
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
            if (isSelected)
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: () => onToggleExtraBed(roomNum),
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
    final rooms = roomConfig.where((r) => r['floor'] == floor).toList();
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
}
