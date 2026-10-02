/// How many adults and kids are on a booking.
///
/// Adults are implied by the rooms — a Double seats 2, a Family 4 — so that
/// capacity is what the booking screens prefill and what these helpers fall
/// back to for records saved before the head count was stored. Kids are only
/// ever entered by hand: nothing about a room implies them, which is exactly
/// why they are worth tracking separately.
library;

/// Adult capacity of a room type. Anything unrecognised is treated as a Double,
/// matching what the room cards show.
int paxForRoomType(String type) {
  switch (type) {
    case 'Single':
      return 1;
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

/// Combined capacity of a booking's rooms, across both the per-room `rooms`
/// list and the legacy single-room fields.
int roomCapacityOf(Map<String, dynamic> booking) {
  final rooms = booking['rooms'];
  if (rooms is List && rooms.isNotEmpty) {
    return rooms.fold<int>(0, (sum, r) {
      if (r is! Map) return sum;
      final pax = r['pax'];
      return sum +
          (pax is num && pax > 0
              ? pax.toInt()
              : paxForRoomType((r['roomType'] ?? '').toString()));
    });
  }
  return paxForRoomType((booking['roomType'] ?? '').toString());
}

/// The head count to display for a booking.
({int adults, int kids}) headCountOf(Map<String, dynamic> booking) {
  final storedAdults = booking['numAdults'];
  final storedKids = booking['numKids'];
  return (
    adults: (storedAdults is num && storedAdults > 0)
        ? storedAdults.toInt()
        : roomCapacityOf(booking),
    kids: (storedKids is num && storedKids > 0) ? storedKids.toInt() : 0,
  );
}
