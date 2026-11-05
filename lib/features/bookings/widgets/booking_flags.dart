import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

/// Yes/no extras on a booking that the staff need to prepare for, shown as
/// badges on the booking cards. The driver room keeps its own badge.

/// Turns a stored "HH:mm" time into "10:30 AM". Returns null when no time
/// was recorded.
String? formatStayTime(dynamic hhmm) {
  final t = parseStayTime(hhmm);
  if (t == null) return null;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
}

TimeOfDay? parseStayTime(dynamic hhmm) {
  final parts = (hhmm ?? '').toString().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// "HH:mm", the format the booking stores times in.
String stayTimeToString(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Optional time picker row: "Time (optional) [10:30 AM] ×". [value] and
/// [onChanged] use the stored "HH:mm" string, null when not set.
class OptionalTimeField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String hint;

  const OptionalTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'Time (optional)',
  });

  @override
  Widget build(BuildContext context) {
    final label = formatStayTime(value);
    return Row(
      children: [
        const Icon(Icons.access_time_rounded, size: 16, color: AppColors.ink3),
        const SizedBox(width: 6),
        Text(hint, style: AppText.callout),
        const Spacer(),
        OutlinedButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: parseStayTime(value) ?? TimeOfDay.now(),
            );
            if (picked != null) onChanged(stayTimeToString(picked));
          },
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(64, 38),
          ),
          child: Text(label ?? 'Set time'),
        ),
        if (label != null)
          IconButton(
            tooltip: 'Clear time',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink3),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

/// One badge per flag set on [booking]. Renders nothing when none are set.
class BookingFlagBadges extends StatelessWidget {
  final Map<String, dynamic> booking;

  const BookingFlagBadges({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (booking['needKiriPidu'] == true)
        _badge(Icons.rice_bowl_rounded, 'Kiri pidu', AppColors.roomOnly),
      if (booking['earlyCheckIn'] == true)
        _badge(
          Icons.schedule_rounded,
          'Early check-in · ${formatStayTime(booking['earlyCheckInTime']) ?? 'time not set'}',
          AppColors.success,
        ),
      if (booking['lateCheckOut'] == true)
        _badge(
          Icons.more_time_rounded,
          'Late check-out · ${formatStayTime(booking['lateCheckOutTime']) ?? 'time not set'}',
          AppColors.warning,
        ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 6, children: badges),
    );
  }

  Widget _badge(IconData icon, String label, Color color) =>
      StatusPill(label, color: color, icon: icon);
}

/// Option card with an icon, title, subtitle and switch, matching the
/// "Requires Driver Room" card on Add Booking. [child] shows under the row
/// while the switch is on.
class OptionToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final MaterialColor color;
  final ValueChanged<bool> onChanged;
  final Widget? child;

  const OptionToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color.shade700;
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.ease,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: value ? AppColors.ink : AppColors.hairline),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadius.card,
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  IconWell(icon, size: 38, color: value ? accent : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.bodyStrong.copyWith(fontSize: 14)),
                        Text(subtitle, style: AppText.footnote),
                      ],
                    ),
                  ),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.ease,
            child: value && child != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
