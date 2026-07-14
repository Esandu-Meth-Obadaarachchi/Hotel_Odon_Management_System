import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'package:odon_booking/core/utils/file_saver.dart' as file_saver;
import 'invoice.dart' as invoice;

/// Maps the booking system's package names to the price-config / invoice
/// package keys.
const _pkgPriceKey = {
  'Full Board': 'Full Board',
  'Half Board': 'Half Board',
  'Room Only': 'Room Only',
  'BnB': 'Bed and Breakfast',
  'Dinner Only': 'Room + Dinner',
};

int _paxForType(String type) {
  switch (type) {
    case 'Single':
      return 1;
    case 'Double':
      return 2;
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

const String _fixedNotes =
    '- Once you arrive to check in, please produce the NIC of the person under whose name the booking was made.\n'
    '- If you need a driver\'s room, please inform on the same day you make the reservation\n'
    '- If you need any extra meal please inform the previous day\n'
    '- Meals brought from outside will not be allowed to have inside the rooms or restaurant\n'
    '- Swimming Pool will be unavailable after 8.00pm';

String _combinedNotes(String? extra) {
  var s = (extra ?? '').trim();
  if (s.isNotEmpty) s += '\n\n';
  s += 'PLEASE NOTE THAT:\n$_fixedNotes';
  return s;
}

/// Builds an invoice PDF directly from an existing booking record and then
/// shows a dialog to share / open it. Reconstructs a price breakdown from the
/// current room prices; the booking's stored `total` is treated as the final
/// amount and any difference from the room subtotal is shown as a discount
/// (or an adjustment charge if the total is higher).
Future<void> shareBookingInvoice(
  BuildContext context,
  Map<String, dynamic> booking,
) async {
  final navigator = Navigator.of(context);

  // Loading spinner while we fetch prices + build the PDF.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: Colors.indigo),
    ),
  );

  try {
    // ── Fetch current prices ────────────────────────────────────────────────
    Map<String, Map<String, double>> prices = {};
    double driverRoomPrice = 2500.0;
    try {
      final data = await ApiService().fetchPrices();
      final packages = data['packages'] as Map<String, dynamic>;
      prices = packages.map(
        (pkg, rooms) => MapEntry(
          pkg,
          (rooms as Map<String, dynamic>).map(
            (room, price) => MapEntry(room, (price as num).toDouble()),
          ),
        ),
      );
      driverRoomPrice = (data['driverRoomPrice'] as num).toDouble();
    } catch (_) {
      // Fall back to zero-priced breakdown if prices can't be fetched.
    }

    // ── Read booking fields ─────────────────────────────────────────────────
    final guestName = booking['guestName'] as String? ?? '';
    final guestPhone = (booking['guestPhone'] as String?)?.trim();
    final package = booking['package'] as String? ?? 'Room Only';
    final priceKey = _pkgPriceKey[package] ?? package;
    final mealStart = booking['mealStart'] as String?;
    final needDriver = booking['needDriver'] == true;

    final checkInDate = DateTime.parse(booking['checkIn']);
    final checkOutDate = DateTime.parse(booking['checkOut']);
    final rawNights = booking['num_of_nights'];
    final nights = (rawNights is num)
        ? rawNights.toInt()
        : (rawNights is String ? int.tryParse(rawNights) : null) ??
            checkOutDate.difference(checkInDate).inDays;

    // ── Rooms (new + legacy formats) ────────────────────────────────────────
    final isNewFormat =
        booking['rooms'] != null && (booking['rooms'] as List).isNotEmpty;
    final List<Map<String, dynamic>> rooms = isNewFormat
        ? List<Map<String, dynamic>>.from(
            (booking['rooms'] as List).map((r) => Map<String, dynamic>.from(r)))
        : [
            {
              'roomNumber': booking['roomNumber'],
              'roomType': booking['roomType'] ?? 'Double',
              'pax': _paxForType(booking['roomType'] as String? ?? 'Double'),
            }
          ];

    // Group rooms by type for the invoice line items.
    final Map<String, int> typeCounts = {};
    int numGuests = 0;
    for (final r in rooms) {
      final t = (r['roomType'] ?? 'Double').toString();
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
      numGuests += (r['pax'] as int?) ?? _paxForType(t);
    }

    final Map<String, Map<String, dynamic>> priceBreakdown = {};
    double rawSubtotal = 0;
    typeCounts.forEach((type, qty) {
      final unit = prices[priceKey]?[type] ?? 0.0;
      final line = unit * qty * nights;
      rawSubtotal += line;
      priceBreakdown['$type - $package'] = {
        'quantity': qty,
        'nights': nights,
        'unitPrice': unit,
        'totalPrice': line,
      };
    });
    if (needDriver) {
      final line = driverRoomPrice * nights;
      rawSubtotal += line;
      priceBreakdown['Driver Room'] = {
        'quantity': 1,
        'nights': nights,
        'unitPrice': driverRoomPrice,
        'totalPrice': line,
      };
    }

    final roomStr = [
      ...typeCounts.entries.map((e) => '${e.value}x ${e.key}'),
      if (needDriver) '1x Driver Room',
    ].join(', ');

    // ── Financials ──────────────────────────────────────────────────────────
    final fmt = NumberFormat('#,##0.00');
    final finalTotal = double.tryParse(
            (booking['total'] as String? ?? '').replaceAll(',', '').trim()) ??
        rawSubtotal;
    final advance = double.tryParse(
            (booking['advance'] as String? ?? '').replaceAll(',', '').trim()) ??
        0.0;

    double discount = 0;
    final List<invoice.ExtraCharge> extras = [];
    if (rawSubtotal > finalTotal) {
      discount = rawSubtotal - finalTotal;
    } else if (finalTotal > rawSubtotal) {
      extras.add(invoice.ExtraCharge(
          reason: 'Adjustment', amount: finalTotal - rawSubtotal));
    }
    final balance = finalTotal - advance;

    final startMeal =
        (package == 'Full Board' || package == 'Half Board') ? mealStart : null;

    final dateFmt = DateFormat('yyyy-MM-dd');

    final pdfUrl = await invoice.generateInvoice(
      guestName: guestName,
      guestPhone: (guestPhone != null && guestPhone.isNotEmpty) ? guestPhone : null,
      checkIn: dateFmt.format(checkInDate),
      checkOut: dateFmt.format(checkOutDate),
      numGuests: numGuests,
      room: roomStr,
      packageDetails: package,
      startMeal: startMeal,
      totalAmount: fmt.format(rawSubtotal),
      standardDiscount: fmt.format(discount),
      additionalDiscount: fmt.format(0),
      extraCharges: extras,
      finalAmount: fmt.format(finalTotal),
      advanceAmount: fmt.format(advance),
      balanceAmount: fmt.format(balance),
      priceBreakdown: priceBreakdown,
      specialNotes: _combinedNotes(booking['extraDetails'] as String?),
    );

    final summary = _buildWhatsAppSummary(
      guestName: guestName,
      checkIn: checkInDate,
      checkOut: checkOutDate,
      nights: nights,
      package: package,
      typeCounts: typeCounts,
      needDriver: needDriver,
      finalTotal: finalTotal,
      advance: advance,
      balance: balance,
      fmt: fmt,
    );

    navigator.pop(); // close spinner
    if (!context.mounted) return;
    _showShareDialog(context, summary, pdfUrl);
  } catch (e) {
    navigator.pop(); // close spinner
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to generate invoice: $e'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

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

String _buildWhatsAppSummary({
  required String guestName,
  required DateTime checkIn,
  required DateTime checkOut,
  required int nights,
  required String package,
  required Map<String, int> typeCounts,
  required bool needDriver,
  required double finalTotal,
  required double advance,
  required double balance,
  required NumberFormat fmt,
}) {
  final dateLine = nights == 1
      ? _ordinalDate(checkIn)
      : '${_ordinalDate(checkIn)} - ${_ordinalDate(checkOut)}';

  final roomLines = <String>[];
  typeCounts.forEach((type, qty) {
    final label = qty == 1 ? '$type room' : '$type rooms';
    roomLines.add('$qty $label');
  });
  if (needDriver) roomLines.add('1 Driver room');

  final buffer = StringBuffer();
  buffer.writeln('Dear sir,');
  buffer.writeln('Pls check whether the following details are correct.');
  buffer.writeln('Name : $guestName');
  buffer.writeln('Date : $dateLine');
  buffer.writeln('$nights ${nights == 1 ? "night" : "nights"}');
  buffer.writeln('Package : $package');
  for (final line in roomLines) {
    buffer.writeln(line);
  }
  buffer.writeln('Total : LKR ${fmt.format(finalTotal)}');
  buffer.writeln('Advance : LKR ${fmt.format(advance)}');
  buffer.writeln('Remaining : LKR ${fmt.format(balance)}');
  return buffer.toString().trimRight();
}

void _showShareDialog(BuildContext context, String message, String? pdfUrl) {
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
                        if (!ok && context.mounted) {
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
                  const SizedBox(height: 16),
                ],
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
                      if (!context.mounted) return;
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
