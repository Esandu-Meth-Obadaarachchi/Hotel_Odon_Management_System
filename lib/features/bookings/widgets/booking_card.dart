import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/features/bookings/head_count.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

import 'booking_flags.dart';
import 'extra_charges.dart';

/// One booking, laid out the same way on every list (calendar day, upcoming,
/// past, full-day details). Screens add their own [badge], [actions],
/// [status] line and [footer]; the body is shared so the four lists can't
/// drift apart.
class BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final Widget? badge;
  final List<Widget> actions;
  final Widget? status;
  final Widget? footer;

  const BookingCard({
    super.key,
    required this.booking,
    this.badge,
    this.actions = const [],
    this.status,
    this.footer,
  });

  static String fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('EEE d MMM').format(d);

  @override
  Widget build(BuildContext context) {
    final guestName = (booking['guestName'] as String? ?? '').trim();
    final guestPhone = booking['guestPhone'] as String? ?? '';
    final package = booking['package'] as String? ?? '';
    final extraDetails = (booking['extraDetails'] as String?)?.trim() ?? '';
    final charges = extraChargesOf(booking);
    final nights = booking['num_of_nights'];
    final total = (booking['total'] ?? '').toString();
    final advance = (booking['advance'] ?? '').toString();
    final needDriver = booking['needDriver'] == true;
    final heads = headCountOf(booking);

    final checkIn = DateTime.tryParse(booking['checkIn']?.toString() ?? '');
    final checkOut = DateTime.tryParse(booking['checkOut']?.toString() ?? '');

    final isNewFormat = booking['rooms'] is List && (booking['rooms'] as List).isNotEmpty;
    final rooms = isNewFormat
        ? List<Map<String, dynamic>>.from(
            (booking['rooms'] as List).map((r) => Map<String, dynamic>.from(r)))
        : [
            {
              'roomNumber': booking['roomNumber'] ?? '—',
              'roomType': booking['roomType'] ?? '',
              'pax': paxForRoomType(booking['roomType'] as String? ?? ''),
            }
          ];

    final guestsLabel = [
      '${heads.adults} adult${heads.adults == 1 ? '' : 's'}',
      if (heads.kids > 0) '${heads.kids} kid${heads.kids == 1 ? '' : 's'}',
    ].join(' · ');

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Guest ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
          child: Row(children: [
            InitialsAvatar(guestName.isEmpty ? 'Guest' : guestName, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(guestName.isEmpty ? 'Guest' : guestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline),
                const SizedBox(height: 2),
                Text(guestPhone.isEmpty ? guestsLabel : '$guestPhone · $guestsLabel',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.footnote),
              ]),
            ),
            if (badge != null) ...[const SizedBox(width: 8), badge!],
            for (final a in actions) ...[const SizedBox(width: 6), a],
          ]),
        ),

        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(alignment: Alignment.centerLeft, child: status!),
          ),

        // ── Stay ────────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: AppRadius.control,
          ),
          child: Row(children: [
            Expanded(child: _endpoint('Check-in', fmtDate(checkIn))),
            Column(children: [
              const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.ink3),
              if (nights != null)
                Text('$nights night${nights.toString() == '1' ? '' : 's'}',
                    style: AppText.footnote.copyWith(fontSize: 11)),
            ]),
            Expanded(child: _endpoint('Check-out', fmtDate(checkOut), end: true)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (package.isNotEmpty)
              StatusPill(package, color: AppColors.forPackage(package), solid: true),
            ...rooms.map(_roomChip),
          ]),
        ),

        if (needDriver || booking['needKiriPidu'] == true ||
            booking['earlyCheckIn'] == true || booking['lateCheckOut'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              BookingFlagBadges(booking: booking),
              if (needDriver)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: StatusPill('Driver room', color: AppColors.warning, icon: Icons.drive_eta_rounded),
                ),
            ]),
          ),

        // ── Money ───────────────────────────────────────────────────────────
        if (total.isNotEmpty || advance.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: Divider()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              if (total.isNotEmpty) Expanded(child: _money('Total', total, strong: true)),
              if (advance.isNotEmpty) Expanded(child: _money('Advance', advance)),
            ]),
          ),
        ],

        if (charges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ExtraChargesSummary(charges: charges),
          ),

        if (extraDetails.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.sticky_note_2_outlined, size: 15, color: AppColors.ink3),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(extraDetails, style: AppText.callout)),
            ]),
          ),

        if (footer != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: footer!),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _endpoint(String label, String date, {bool end = false}) => Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppText.eyebrow.copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          Text(date, style: AppText.bodyStrong.copyWith(fontSize: 14)),
        ],
      );

  Widget _money(String label, String value, {bool strong = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.footnote),
          const SizedBox(height: 2),
          Text(_lkr(value),
              style: AppText.number(strong ? 17 : 15,
                  weight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: strong ? AppColors.ink : AppColors.ink2)),
        ],
      );

  /// "19000.00" → "LKR 19,000"; leaves anything non-numeric as typed.
  static String _lkr(String raw) {
    final n = double.tryParse(raw.replaceAll(',', '').trim());
    if (n == null) return 'LKR $raw';
    return formatLkr(n);
  }

  Widget _roomChip(Map<String, dynamic> room) {
    final num = (room['roomNumber'] ?? '—').toString();
    final type = (room['roomType'] ?? '').toString();
    final pax = room['pax'] as int? ?? paxForRoomType(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(num.padLeft(3, '0'), style: AppText.number(13)),
        if (type.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text('$type · $pax', style: AppText.footnote.copyWith(fontSize: 12, color: AppColors.ink2)),
        ],
      ]),
    );
  }
}
