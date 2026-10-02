import 'package:flutter_test/flutter_test.dart';
import 'package:odon_booking/features/bookings/widgets/booking_flags.dart';
import 'package:odon_booking/features/bookings/widgets/extra_charges.dart';
import 'package:odon_booking/features/bookings/widgets/room_picker.dart';

void main() {
  group('bookedRoomsBetween', () {
    final bookings = <Map<String, dynamic>>[
      {
        '_id': 'a',
        'checkIn': '2026-10-10T00:00:00.000Z',
        'checkOut': '2026-10-12T00:00:00.000Z',
        'rooms': [
          {'roomNumber': '101'},
          {'roomNumber': '102'},
        ],
      },
      {
        '_id': 'b',
        'checkIn': '2026-10-12T00:00:00.000Z',
        'checkOut': '2026-10-13T00:00:00.000Z',
        'roomNumber': '5',
      },
    ];

    test('finds rooms on overlapping nights', () {
      expect(
        bookedRoomsBetween(bookings, DateTime(2026, 10, 11), DateTime(2026, 10, 13)),
        {'101', '102', '5'},
      );
    });

    test('check-out day does not clash with a new check-in', () {
      expect(
        bookedRoomsBetween(bookings, DateTime(2026, 10, 13), DateTime(2026, 10, 14)),
        isEmpty,
      );
    });

    test('skips the booking being edited', () {
      expect(
        bookedRoomsBetween(bookings, DateTime(2026, 10, 10), DateTime(2026, 10, 13),
            excludeId: 'a'),
        {'5'},
      );
    });
  });

  test('effectiveRoomType follows the extra bed', () {
    expect(effectiveRoomType({'baseType': 'Double'}, extraBed: true), 'Triple');
    expect(effectiveRoomType({'baseType': 'Family'}, extraBed: true), 'Family Plus');
    expect(effectiveRoomType({'baseType': 'Family'}, extraBed: false), 'Family');
  });

  group('extra charges', () {
    test('reads stored charges and ignores junk', () {
      final charges = extraChargesOf({
        'extraCharges': [
          {'reason': 'Extra dinner', 'amount': 1500},
          {'reason': 'Late check-out', 'amount': '2000'},
          'junk',
        ],
      });
      expect(charges.length, 2);
      expect(sumExtraCharges(charges), 3500);
      expect(extraChargesOf({}), isEmpty);
    });

    test('total moves by the change in charges', () {
      expect(adjustTotalForCharges('20000', 0, 1500), '21500');
      expect(adjustTotalForCharges('21500.00', 1500, 500), '20500');
      expect(adjustTotalForCharges('', 0, 1500), '');
    });
  });

  test('stay times format and validate', () {
    expect(formatStayTime('09:30'), '9:30 AM');
    expect(formatStayTime('15:05'), '3:05 PM');
    expect(formatStayTime(null), isNull);
    expect(formatStayTime('25:00'), isNull);
  });
}
