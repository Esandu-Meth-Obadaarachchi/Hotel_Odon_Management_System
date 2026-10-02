import 'package:flutter/material.dart';

/// Yes/no extras on a booking that the staff need to prepare for, shown as
/// badges on the booking cards. The driver room keeps its own badge.

/// One badge per flag set on [booking]. Renders nothing when none are set.
class BookingFlagBadges extends StatelessWidget {
  final Map<String, dynamic> booking;

  const BookingFlagBadges({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (booking['needKiriPidu'] == true)
        _badge(Icons.rice_bowl_rounded, 'Kiri Pidu Required', Colors.teal),
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
