import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';

/// Allowed salary types (must match the Salary form + edit dialog dropdowns).
const List<String> kSalaryTypes = ['OT', 'Monthly', 'Weekly', 'Commission'];

/// Allowed expense categories (must match the Expense form + edit dialog dropdowns).
const List<String> kExpenseCategories = [
  'Food', 'Utilities', 'Maintenance', 'Supplies',
  'Transportation', 'Marketing', 'Equipment', 'Other',
];

/// Parses the JSON a user pastes (the format the Claude prompt produces) into
/// the item-map list that [DataConfirmationDialog] consumes for review.
///
/// Accepts either:
///   { "salaries": [ ... ], "expenses": [ ... ] }
/// or a bare list of items each carrying a `type` / recognisable fields.
///
/// Categories are clamped to the allowed sets so the edit dialog's dropdowns
/// never receive an out-of-range value. Throws [FormatException] with a
/// user-friendly message on bad input.
List<Map<String, dynamic>> parseBulkImportJson(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    throw const FormatException('Nothing pasted. Paste the JSON from Claude first.');
  }

  // Strip ``` / ```json code fences Claude chat often wraps the output in.
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    text = text.trim();
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const FormatException(
      "That doesn't look like valid JSON. Copy the whole block Claude gave "
      'you, including the outer { } brackets.',
    );
  }

  final items = <Map<String, dynamic>>[];

  void addSalary(Map m) {
    final name = (m['employeeName'] ?? m['name'] ?? '').toString().trim();
    final amount = _parseAmount(m['amount']);
    if (name.isEmpty && amount == null) return;
    var type = (m['salaryType'] ?? m['type'] ?? 'Monthly').toString().trim();
    if (!kSalaryTypes.contains(type)) type = 'Monthly';
    items.add({
      'itemName': name,
      'suggestedType': 'salary',
      'suggestedCategory': type,
      'amount': amount,
      'date': _parseDate(m['date']),
      'description': (m['reason'] ?? m['description'] ?? '').toString(),
    });
  }

  void addExpense(Map m) {
    final name = (m['expenseName'] ?? m['name'] ?? '').toString().trim();
    final amount = _parseAmount(m['amount']);
    if (name.isEmpty && amount == null) return;
    var cat = (m['category'] ?? 'Other').toString().trim();
    if (!kExpenseCategories.contains(cat)) cat = 'Other';
    items.add({
      'itemName': name,
      'suggestedType': 'expense',
      'suggestedCategory': cat,
      'amount': amount,
      'date': _parseDate(m['date']),
      'description': (m['reason'] ?? m['description'] ?? '').toString(),
    });
  }

  if (decoded is Map) {
    final salaries = decoded['salaries'];
    final expenses = decoded['expenses'];
    if (salaries == null && expenses == null) {
      _classifyAndAdd(decoded, addSalary, addExpense); // single bare item
    } else {
      if (salaries is List) {
        for (final s in salaries) {
          if (s is Map) addSalary(s);
        }
      }
      if (expenses is List) {
        for (final e in expenses) {
          if (e is Map) addExpense(e);
        }
      }
    }
  } else if (decoded is List) {
    for (final el in decoded) {
      if (el is Map) _classifyAndAdd(el, addSalary, addExpense);
    }
  } else {
    throw const FormatException(
      'Unexpected JSON shape. Expected an object with "salaries" and "expenses".',
    );
  }

  if (items.isEmpty) {
    throw const FormatException('No salary or expense entries found in that JSON.');
  }
  return items;
}

void _classifyAndAdd(
  Map m,
  void Function(Map) addSalary,
  void Function(Map) addExpense,
) {
  final t = (m['type'] ?? '').toString().toLowerCase();
  if (t == 'salary' || m.containsKey('employeeName') || m.containsKey('salaryType')) {
    addSalary(m);
  } else {
    addExpense(m);
  }
}

double? _parseAmount(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final cleaned = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String _parseDate(dynamic v) {
  if (v != null) {
    final parsed = DateTime.tryParse(v.toString().trim());
    if (parsed != null) return parsed.toIso8601String();
  }
  return DateTime.now().toIso8601String();
}

/// Shows the paste-JSON dialog. Returns the normalised item list ready for
/// [DataConfirmationDialog], or `null` if the user cancelled.
Future<List<Map<String, dynamic>>?> showBulkImportPasteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text(
              'Paste JSON from Claude',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paste the JSON block Claude gave you for the month, then '
                    'review the entries before saving.',
                    style: TextStyle(fontSize: 13, color: AppColors.ink3),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '{ "salaries": [...], "expenses": [...] }',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(color: AppColors.danger, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  try {
                    final items = parseBulkImportJson(controller.text);
                    Navigator.pop(ctx, items);
                  } on FormatException catch (e) {
                    setState(() => error = e.message);
                  }
                },
                child: const Text('Parse & Review'),
              ),
            ],
          );
        },
      );
    },
  );
}
