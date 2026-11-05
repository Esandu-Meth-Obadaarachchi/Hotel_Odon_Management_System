import 'dart:async';
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/core/api/api_service.dart';

/// Drop-in TextField for guest name with autocomplete suggestions backed by
/// the Guest database. Selecting a suggestion fills both the name and phone
/// controllers so the rest of the booking form keeps working unchanged.
class GuestNameAutocomplete extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final String label;

  /// Decoration applied to the inner TextField. If null, a borderless
  /// labelled decoration is used.
  final InputDecoration? inputDecoration;

  /// Decoration applied to the Container wrapping the TextField. If null,
  /// a flat white card with shadow is used (matches room_selection_screen).
  final BoxDecoration? wrapperDecoration;

  /// Optional padding for the wrapping container.
  final EdgeInsetsGeometry wrapperPadding;

  const GuestNameAutocomplete({
    super.key,
    required this.nameController,
    required this.phoneController,
    this.label = 'Guest Name',
    this.inputDecoration,
    this.wrapperDecoration,
    this.wrapperPadding = EdgeInsets.zero,
  });

  @override
  State<GuestNameAutocomplete> createState() => _GuestNameAutocompleteState();
}

class _GuestNameAutocompleteState extends State<GuestNameAutocomplete> {
  final ApiService _api = ApiService();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<Iterable<Map<String, dynamic>>> _search(String input) async {
    final q = input.trim();
    if (q.length < 2) return const [];
    // Debounce: wait briefly, then bail if the user has kept typing.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (widget.nameController.text.trim() != q) return const [];
    try {
      return await _api.searchGuests(q);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: widget.nameController,
      focusNode: _focusNode,
      optionsBuilder: (v) => _search(v.text),
      displayStringForOption: (g) => (g['name'] ?? '').toString(),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final field = TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: widget.inputDecoration ??
              fieldDecoration(widget.label, icon: Icons.person_outline_rounded),
        );
        return Container(
          padding: widget.wrapperPadding,
          decoration: widget.wrapperDecoration ?? const BoxDecoration(),
          child: field,
        );
      },
      onSelected: (guest) {
        final phone = (guest['phone'] ?? '').toString();
        if (phone.isNotEmpty) widget.phoneController.text = phone;
        FocusScope.of(context).unfocus();
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            shadowColor: const Color(0x33121614),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.control,
              side: const BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final g = options.elementAt(i);
                  final name = (g['name'] ?? '').toString();
                  final phone = (g['phone'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: InitialsAvatar(name, size: 34),
                    title: Text(name,
                        style: AppText.bodyStrong.copyWith(fontSize: 14)),
                    subtitle: Text(phone, style: AppText.footnote),
                    onTap: () => onSelected(g),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
