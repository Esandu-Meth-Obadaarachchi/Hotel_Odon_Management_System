import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';

class EditInventoryItemScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const EditInventoryItemScreen({Key? key, required this.item})
      : super(key: key);

  @override
  _EditInventoryItemScreenState createState() =>
      _EditInventoryItemScreenState();
}

class _EditInventoryItemScreenState extends State<EditInventoryItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _addQuantityController = TextEditingController();
  final TextEditingController _removeQuantityController =
      TextEditingController();
  DateTime? _purchasedDate;
  final ApiService _apiService = ApiService();

  int currentQuantity = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize with existing item data
    _itemNameController.text = widget.item['item_name'] ?? '';
    currentQuantity = widget.item['quantity'] ?? 0;
    _quantityController.text = currentQuantity.toString();

    // Parse the purchased date
    if (widget.item['purchasedDate'] != null) {
      try {
        _purchasedDate = DateTime.parse(widget.item['purchasedDate']);
      } catch (e) {
        _purchasedDate = DateTime.now();
      }
    }
  }

  void _addQuantity() {
    final addAmount = int.tryParse(_addQuantityController.text.trim()) ?? 0;
    if (addAmount > 0) {
      setState(() {
        currentQuantity += addAmount;
        _quantityController.text = currentQuantity.toString();
      });
      _addQuantityController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $addAmount items')),
      );
    }
  }

  void _removeQuantity() {
    final removeAmount =
        int.tryParse(_removeQuantityController.text.trim()) ?? 0;
    if (removeAmount > 0) {
      if (removeAmount <= currentQuantity) {
        setState(() {
          currentQuantity -= removeAmount;
          _quantityController.text = currentQuantity.toString();
        });
        _removeQuantityController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $removeAmount items')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cannot remove more items than available')),
        );
      }
    }
  }

  void _updateItem() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final updatedItem = {
        'item_name': _itemNameController.text.trim(),
        'quantity': currentQuantity,
        'purchasedDate': _purchasedDate?.toIso8601String(),
      };

      try {
        await _apiService.updateInventoryItem(widget.item['_id'], updatedItem);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item updated successfully!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update item: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _deleteItem() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
            'Are you sure you want to delete "${_itemNameController.text}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _apiService.deleteInventoryItem(widget.item['_id']);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item deleted successfully!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete item: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit item'),
        actions: [
          IconButton(
            tooltip: 'Delete item',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _isLoading ? null : _deleteItem,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        child: PageBody(
          maxWidth: AppLayout.maxForm,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current quantity — the number this screen is about.
                SurfaceCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('In stock', style: AppText.footnote),
                              const SizedBox(height: 4),
                              AnimatedSwitcher(
                                duration: AppMotion.base,
                                child: Text('$currentQuantity',
                                    key: ValueKey(currentQuantity),
                                    style: AppText.number(40)),
                              ),
                            ]),
                      ),
                      const IconWell(Icons.inventory_2_outlined, size: 48),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      TextFormField(
                        controller: _itemNameController,
                        decoration: fieldDecoration('Item name',
                            icon: Icons.label_outline_rounded),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter the item name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _quantityController,
                        decoration: fieldDecoration('Set total quantity',
                            icon: Icons.numbers_rounded,
                            helper: 'Or adjust with add / remove below'),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final newQuantity = int.tryParse(value) ?? 0;
                          setState(() {
                            currentQuantity = newQuantity;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter the quantity';
                          }
                          if (int.tryParse(value) == null ||
                              int.parse(value) < 0) {
                            return 'Enter a valid quantity';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: Text(_purchasedDate == null
                            ? 'Select purchase date'
                            : 'Bought ${DateFormat('d MMM yyyy').format(_purchasedDate!)}'),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.ink4),
                        onTap: () async {
                          final selectedDate = await showDatePicker(
                            context: context,
                            initialDate: _purchasedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (selectedDate != null) {
                            setState(() {
                              _purchasedDate = selectedDate;
                            });
                          }
                        },
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                        child: _adjustCard('Add', _addQuantityController,
                            Icons.add_rounded, _addQuantity)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _adjustCard('Remove', _removeQuantityController,
                            Icons.remove_rounded, _removeQuantity)),
                  ],
                ),
                const SizedBox(height: 28),

                FilledButton(
                  onPressed: _isLoading ? null : _updateItem,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Small card with a quantity field and its action, for quick stock moves.
  Widget _adjustCard(String verb, TextEditingController controller,
      IconData icon, VoidCallback onPressed) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: controller,
            decoration: fieldDecoration('$verb qty'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(verb),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    _addQuantityController.dispose();
    _removeQuantityController.dispose();
    super.dispose();
  }
}
