import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Extra charges on a booking: a list of `{reason, amount}` pairs, such as an
/// extra dinner or a late check-out fee. The booking's `total` already
/// includes them; the list records what the money was for.

/// Reads the charges stored on a booking. Bookings saved before the field
/// existed return an empty list.
List<Map<String, dynamic>> extraChargesOf(Map<String, dynamic> booking) {
  final raw = booking['extraCharges'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((c) => {
            'reason': (c['reason'] ?? '').toString(),
            'amount': (c['amount'] is num)
                ? (c['amount'] as num).toDouble()
                : double.tryParse(c['amount']?.toString() ?? '') ?? 0.0,
          })
      .toList();
}

double sumExtraCharges(List<Map<String, dynamic>> charges) =>
    charges.fold(0.0, (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0));

final _lkr = NumberFormat('#,##0.##');

/// Formats a charge amount the way the cards show money ("LKR 1,500").
String formatLkr(double amount) => 'LKR ${_lkr.format(amount)}';

/// Rows of reason + amount with an "Add extra charge" button. Calls
/// [onChanged] with the cleaned list (blank rows left out) on every edit.
class ExtraChargesEditor extends StatefulWidget {
  final List<Map<String, dynamic>> initialCharges;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  const ExtraChargesEditor({
    super.key,
    required this.initialCharges,
    required this.onChanged,
  });

  @override
  State<ExtraChargesEditor> createState() => ExtraChargesEditorState();
}

class ExtraChargesEditorState extends State<ExtraChargesEditor> {
  final List<_ChargeRow> _rows = [];

  @override
  void initState() {
    super.initState();
    for (final c in widget.initialCharges) {
      _rows.add(_ChargeRow(
        reason: (c['reason'] ?? '').toString(),
        amount: _amountText((c['amount'] as num?)?.toDouble() ?? 0),
      ));
    }
  }

  /// Replaces every row, e.g. when the parent form is reset.
  void reset([List<Map<String, dynamic>> charges = const []]) {
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows
        ..clear()
        ..addAll(charges.map((c) => _ChargeRow(
              reason: (c['reason'] ?? '').toString(),
              amount: _amountText((c['amount'] as num?)?.toDouble() ?? 0),
            )));
    });
  }

  String _amountText(double v) =>
      v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2));

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get charges => _rows
      .map((r) => {
            'reason': r.reason.text.trim(),
            'amount': double.tryParse(r.amount.text.replaceAll(',', '').trim()) ?? 0.0,
          })
      .where((c) => (c['reason'] as String).isNotEmpty || (c['amount'] as double) != 0)
      .toList();

  void _notify() => widget.onChanged(charges);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: row.reason,
                    onChanged: (_) => _notify(),
                    decoration: _decoration('Reason', Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _notify(),
                    decoration: _decoration('Price (LKR)', Icons.payments_outlined),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove charge',
                  icon: Icon(Icons.close_rounded, color: Colors.red.shade400, size: 20),
                  onPressed: () {
                    setState(() => _rows.removeAt(i).dispose());
                    _notify();
                  },
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () => setState(() => _rows.add(_ChargeRow())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add extra charge'),
          style: TextButton.styleFrom(foregroundColor: Colors.indigo),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: Icon(icon, color: Colors.indigo.shade400, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.indigo, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      );
}

class _ChargeRow {
  final TextEditingController reason;
  final TextEditingController amount;

  _ChargeRow({String reason = '', String amount = ''})
      : reason = TextEditingController(text: reason),
        amount = TextEditingController(text: amount);

  void dispose() {
    reason.dispose();
    amount.dispose();
  }
}

/// Moves [totalText] by the change in the charges' sum, so adding a LKR 1,500
/// charge adds LKR 1,500 to the total. A blank total is left blank: the user
/// has not priced the stay yet.
String adjustTotalForCharges(String totalText, double oldSum, double newSum) {
  final delta = newSum - oldSum;
  final current = double.tryParse(totalText.replaceAll(',', '').trim());
  if (delta == 0 || current == null) return totalText;
  final next = current + delta;
  return next == next.roundToDouble() ? next.toInt().toString() : next.toStringAsFixed(2);
}

/// Read-only list of a booking's extra charges for the booking cards.
class ExtraChargesSummary extends StatelessWidget {
  final List<Map<String, dynamic>> charges;

  const ExtraChargesSummary({super.key, required this.charges});

  @override
  Widget build(BuildContext context) {
    if (charges.isEmpty) return const SizedBox.shrink();
    final color = Colors.deepPurple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_card_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text('Extra Charges',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              const Spacer(),
              Text(formatLkr(sumExtraCharges(charges)),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ...charges.map((c) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (c['reason'] as String).isEmpty ? 'Extra charge' : c['reason'] as String,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ),
                    Text(formatLkr((c['amount'] as num).toDouble()),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
