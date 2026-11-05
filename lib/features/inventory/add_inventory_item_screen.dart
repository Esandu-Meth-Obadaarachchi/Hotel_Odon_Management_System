import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/features/home/home_screen.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'edit_inventory_item_screen.dart';

class AddInventoryItemScreen extends StatefulWidget {
  @override
  _AddInventoryItemScreenState createState() => _AddInventoryItemScreenState();
}

class _AddInventoryItemScreenState extends State<AddInventoryItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  DateTime? _purchasedDate;
  final ApiService _apiService = ApiService();
  late Future<List<dynamic>> _inventoryItems;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _inventoryItems = _apiService.fetchInventoryItems();
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors above')),
      );
      return;
    }
    if (_purchasedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a purchase date'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService().addInventory({
        'item_name': _itemNameController.text.trim(),
        'quantity': int.tryParse(_quantityController.text.trim()) ?? 0,
        'purchasedDate': _purchasedDate!.toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Item added successfully'),
        ),
      );
      _itemNameController.clear();
      _quantityController.clear();
      setState(() {
        _purchasedDate = null;
        _submitting = false;
        _inventoryItems = _apiService.fetchInventoryItems();
      });
    } catch (e) {
      setState(() => _submitting = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ───────────────────────────────────────────
          const LargeTitleSliverAppBar(
            title: 'Inventory',
            subtitle: 'Guest supplies in stock',
          ),

          SliverToBoxAdapter(
            child: PageBody(
              padding: EdgeInsets.fromLTRB(
                  AppLayout.gutter(context), 8, AppLayout.gutter(context), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Standard items note ──────────────────────────────
                  const InlineBanner(
                    'Standard items: soap, conditioner, body lotion, shampoo, brush kit.',
                  ),
                  const SizedBox(height: 20),

                  // ── Add item form ────────────────────────────────────
                  _sectionLabel('Add an item'),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Item name
                            TextFormField(
                              controller: _itemNameController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: 'Item Name',
                                prefixIcon: const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 20),
                              ),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Enter item name'
                                  : null,
                            ),
                            const SizedBox(height: 14),

                            // Quantity
                            TextFormField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                prefixIcon:
                                    const Icon(Icons.numbers_rounded, size: 20),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty)
                                  return 'Enter quantity';
                                final n = int.tryParse(v);
                                if (n == null || n <= 0)
                                  return 'Enter a valid quantity';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // Date picker
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime.now(),
                                  builder: (ctx, child) => Theme(
                                    data: Theme.of(ctx).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: AppColors.ink,
                                        onPrimary: Colors.white,
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null)
                                  setState(() => _purchasedDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 15),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: AppRadius.control,
                                  border: Border.all(
                                    color: _purchasedDate == null
                                        ? AppColors.hairlineStrong
                                        : AppColors.ink,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      color: _purchasedDate == null
                                          ? AppColors.ink4
                                          : AppColors.ink3,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _purchasedDate == null
                                            ? 'Select purchase date'
                                            : DateFormat('d MMM yyyy')
                                                .format(_purchasedDate!),
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: _purchasedDate == null
                                              ? AppColors.ink3
                                              : AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Tap to pick',
                                      style: TextStyle(
                                          fontSize: 12, color: AppColors.ink4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            FilledButton(
                              onPressed: _submitting ? null : _submitForm,
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52)),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text('Add item'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Inventory list ───────────────────────────────────
                  _sectionLabel('In stock'),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),

          // ── Inventory grid ──────────────────────────────────────────
          FutureBuilder<List<dynamic>>(
            future: _inventoryItems,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Couldn\'t load stock',
                    message: 'Check the connection and open this page again.',
                  ),
                );
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Nothing in stock yet',
                    message: 'Items you add above will show here.',
                  ),
                );
              }
              return SliverPadding(
                padding: AppLayout.sliverPadding(context, bottom: 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 156,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => _buildInventoryCard(
                        items[index] as Map<String, dynamic>),
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryCard(Map<String, dynamic> item) {
    final quantity = item['quantity'] as int? ?? 0;
    final isLow = quantity <= 3;
    final purchased =
        DateTime.tryParse(item['purchasedDate']?.toString() ?? '');

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      borderColor: isLow ? AppColors.warningLine : AppColors.hairline,
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => EditInventoryItemScreen(item: item)),
        );
        if (result == true) {
          setState(() => _inventoryItems = _apiService.fetchInventoryItems());
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item['item_name'] ?? 'Unnamed',
                  style:
                      AppText.bodyStrong.copyWith(fontSize: 14, height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.ink4),
            ],
          ),
          const Spacer(),
          Text('$quantity',
              style: AppText.number(32,
                  color: isLow ? AppColors.warning : AppColors.ink)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  purchased == null
                      ? 'No date'
                      : 'Bought ${DateFormat('d MMM').format(purchased)}',
                  style: AppText.footnote.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLow) const StatusPill('Low', color: AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text.toUpperCase(), style: AppText.eyebrow),
    );
