import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:flutter/services.dart';

class DataConfirmationDialog extends StatefulWidget {
  final List<Map<String, dynamic>> data;

  const DataConfirmationDialog({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  _DataConfirmationDialogState createState() => _DataConfirmationDialogState();
}

class _DataConfirmationDialogState extends State<DataConfirmationDialog> {
  late List<DataItem> items;
  List<bool> selectedItems = [];

  @override
  void initState() {
    super.initState();
    items = widget.data.map((data) => DataItem.fromMap(data)).toList();
    selectedItems = List.filled(items.length, true); // All selected by default
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Check what was read',
      ),
      content: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Text(
              'AI extracted ${items.length} item${items.length > 1 ? 's' : ''}. Review, categorize, and edit if needed:',
              style: TextStyle(fontSize: 14, color: AppColors.ink3),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: selectedItems[index],
                                onChanged: (value) {
                                  setState(() {
                                    selectedItems[index] = value ?? false;
                                  });
                                },
                                                              ),
                              Expanded(
                                child: Text(
                                  items[index].itemName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppColors.ink2),
                                onPressed: () => _editItem(index),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          _buildItemDetails(index),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _getSelectedCount() > 0 ? _confirmData : null,
          child: Text('Add ${_getSelectedCount()} Item${_getSelectedCount() > 1 ? 's' : ''}'),
        ),
      ],
    );
  }

  Widget _buildItemDetails(int index) {
    final item = items[index];

    return Column(
      children: [
        _buildDetailRow('Type', item.itemType),
        _buildDetailRow('Category', item.category),
        _buildDetailRow('Amount', '\$${item.amount?.toStringAsFixed(2) ?? '0.00'}'),
        _buildEditableDateRow(index), // New editable date row
        if (item.description?.isNotEmpty == true)
          _buildDetailRow('Description', item.description!),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.ink3,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: value == 'Salary' ? AppColors.successSoft : AppColors.infoSoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value == 'Salary' ? AppColors.successLine : AppColors.infoLine,
                  width: 1,
                ),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: value == 'Salary' ? AppColors.success : AppColors.info,
                  fontWeight: label == 'Type' ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableDateRow(int index) {
    final item = items[index];
    final formattedDate = _formatDate(item.date);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              'Date:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.ink3,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _editDate(index),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.warningLine,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 6),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.edit,
                      size: 14,
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }

  int _getSelectedCount() {
    return selectedItems.where((selected) => selected).length;
  }

  Future<void> _editDate(int index) async {
    final currentDate = items[index].date ?? DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );

    if (selectedDate != null && selectedDate != currentDate) {
      setState(() {
        items[index] = DataItem(
          itemName: items[index].itemName,
          amount: items[index].amount,
          date: selectedDate,
          itemType: items[index].itemType,
          category: items[index].category,
          description: items[index].description,
        );
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Date updated successfully!'),
            ],
          ),
          duration: Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  void _editItem(int index) {
    showDialog(
      context: context,
      builder: (context) => _EditItemDialog(
        item: items[index],
        onSave: (editedItem) {
          setState(() {
            items[index] = editedItem;
          });
        },
      ),
    );
  }

  void _confirmData() {
    final salaryData = <Map<String, dynamic>>[];
    final expenseData = <Map<String, dynamic>>[];

    for (int i = 0; i < items.length; i++) {
      if (selectedItems[i]) {
        final itemMap = items[i].toMap();
        if (items[i].itemType.toLowerCase() == 'salary') {
          salaryData.add(itemMap);
        } else {
          expenseData.add(itemMap);
        }
      }
    }

    // Return both salary and expense data
    Navigator.pop(context, {
      'salaryData': salaryData,
      'expenseData': expenseData,
    });
  }
}

class _EditItemDialog extends StatefulWidget {
  final DataItem item;
  final Function(DataItem) onSave;

  const _EditItemDialog({
    required this.item,
    required this.onSave,
  });

  @override
  _EditItemDialogState createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late TextEditingController nameController;
  late TextEditingController amountController;
  late TextEditingController descriptionController;
  late String selectedType;
  late String selectedCategory;
  late DateTime selectedDate;

  final List<String> itemTypes = ['Salary', 'Expense'];
  final List<String> salaryCategories = ['OT', 'Monthly', 'Weekly', 'Commission'];
  final List<String> expenseCategories = [
    'Food', 'Utilities', 'Maintenance', 'Supplies',
    'Transportation', 'Marketing', 'Equipment', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.item.itemName);
    amountController = TextEditingController(text: widget.item.amount?.toString() ?? '');
    descriptionController = TextEditingController(text: widget.item.description ?? '');
    selectedType = widget.item.itemType;
    selectedCategory = widget.item.category;
    selectedDate = widget.item.date ?? DateTime.now();
  }

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Item Type Dropdown
            DropdownButtonFormField<String>(
              value: selectedType,
              decoration: InputDecoration(
                labelText: 'Item Type',
                prefixIcon: Icon(
                  selectedType == 'Salary' ? Icons.person : Icons.receipt),
              ),
              items: itemTypes.map((type) => DropdownMenuItem(
                value: type,
                child: Text(type),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  selectedType = value!;
                  // Reset category when type changes
                  if (selectedType == 'Salary') {
                    selectedCategory = salaryCategories.contains(selectedCategory)
                        ? selectedCategory
                        : salaryCategories.first;
                  } else {
                    selectedCategory = expenseCategories.contains(selectedCategory)
                        ? selectedCategory
                        : expenseCategories.first;
                  }
                });
              },
            ),
            SizedBox(height: 16),

            // Item Name
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: selectedType == 'Salary' ? 'Employee Name' : 'Expense Name',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            SizedBox(height: 16),

            // Category Dropdown (changes based on type)
            DropdownButtonFormField<String>(
              value: selectedCategory,
              decoration: InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category),
              ),
              items: (selectedType == 'Salary' ? salaryCategories : expenseCategories)
                  .map((category) => DropdownMenuItem(
                value: category,
                child: Text(category),
              )).toList(),
              onChanged: (value) => setState(() => selectedCategory = value!),
            ),
            SizedBox(height: 16),

            // Amount
            TextField(
              controller: amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            SizedBox(height: 16),

            // Enhanced Date Field with Calendar Icon
            GestureDetector(
              onTap: _selectDate,
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.hairlineStrong),
                  borderRadius: AppRadius.control,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, color: AppColors.ink3),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.ink3,
                          ),
                        ),
                        Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Spacer(),
                    Icon(Icons.edit, color: AppColors.ink3, size: 18),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Description
            TextField(
              controller: descriptionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description/Notes',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveChanges,
          child: Text('Save'),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _saveChanges() {
    final editedItem = DataItem(
      itemName: nameController.text,
      amount: double.tryParse(amountController.text) ?? 0.0,
      date: selectedDate,
      itemType: selectedType,
      category: selectedCategory,
      description: descriptionController.text,
    );

    widget.onSave(editedItem);
    Navigator.pop(context);
  }
}

class DataItem {
  final String itemName;
  final double? amount;
  final DateTime? date;
  final String itemType; // 'Salary' or 'Expense'
  final String category;
  final String? description;

  DataItem({
    required this.itemName,
    this.amount,
    this.date,
    required this.itemType,
    required this.category,
    this.description,
  });

  factory DataItem.fromMap(Map<String, dynamic> map) {
    final suggestedType = map['suggestedType']?.toString().toLowerCase() ?? 'expense';
    return DataItem(
      itemName: map['itemName']?.toString() ?? '',
      amount: map['amount'] is double
          ? map['amount']
          : double.tryParse(map['amount']?.toString() ?? '0'),
      date: map['date'] != null
          ? DateTime.tryParse(map['date']) ?? DateTime.now()
          : DateTime.now(),
      itemType: suggestedType == 'salary' ? 'Salary' : 'Expense',
      category: map['suggestedCategory']?.toString() ?? 'Other',
      description: map['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    if (itemType == 'Salary') {
      // Convert to salary format
      return {
        'employeeName': itemName,
        'salaryType': category,
        'amount': amount,
        'date': date?.toIso8601String(),
      };
    } else {
      // Convert to expense format
      return {
        'expenseName': itemName,
        'category': category,
        'amount': amount,
        'date': date?.toIso8601String(),
        'reason': description,
      };
    }
  }
}