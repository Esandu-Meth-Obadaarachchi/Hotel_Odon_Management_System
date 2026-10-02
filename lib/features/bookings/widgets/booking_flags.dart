import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
        Icon(Icons.access_time_rounded, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(hint, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
            foregroundColor: Colors.indigo,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label ?? 'Set time'),
        ),
        if (label != null)
          IconButton(
            tooltip: 'Clear time',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade500),
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
        _badge(Icons.rice_bowl_rounded, 'Kiri Pidu Required', Colors.teal),
      if (booking['earlyCheckIn'] == true)
        _badge(
          Icons.schedule_rounded,
          'Early Check-in · ${formatStayTime(booking['earlyCheckInTime']) ?? 'time not set'}',
          Colors.green,
        ),
      if (booking['lateCheckOut'] == true)
        _badge(
          Icons.more_time_rounded,
          'Late Check-out · ${formatStayTime(booking['lateCheckOutTime']) ?? 'time not set'}',
          Colors.deepOrange,
        ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 6, children: badges),
    );
  }

  Widget _badge(IconData icon, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color.shade800),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade900),
          ),
        ],
      ),
    );
  }
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
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: value ? color.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: value ? color.shade700 : Colors.grey.shade400, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: value,
                      activeThumbColor: color.shade700,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (value && child != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: child,
            ),
        ],
      ),
    );
  }
}
