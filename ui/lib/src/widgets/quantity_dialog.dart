import 'package:better_idle/src/widgets/item_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logic/logic.dart';

/// A dialog that lets the user select a quantity.
///
/// Used for debug add-items and similar cases where the user needs to
/// pick a quantity without any cost/affordability constraints.
class QuantityDialog extends StatelessWidget {
  const QuantityDialog({
    required this.item,
    this.maxQuantity = 99999,
    super.key,
  });

  final Item item;
  final int maxQuantity;

  static const _presets = [1, 10, 100, 1000, 10000];

  @override
  Widget build(BuildContext context) {
    final availablePresets = _presets.where((q) => q <= maxQuantity).toList();

    return AlertDialog(
      title: Row(
        children: [
          ItemImage(item: item, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('Add ${item.name}')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('How many?'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final qty in availablePresets)
                _QuantityButton(
                  label: _formatQuantity(qty),
                  onPressed: () => Navigator.of(context).pop(qty),
                ),
              if (maxQuantity > 0 &&
                  (availablePresets.isEmpty ||
                      maxQuantity != availablePresets.last))
                _QuantityButton(
                  label: 'Max (${_formatQuantity(maxQuantity)})',
                  onPressed: () => Navigator.of(context).pop(maxQuantity),
                ),
              _QuantityButton(
                label: 'Custom',
                onPressed: () => _showCustomQuantityDialog(context),
                outlined: true,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _formatQuantity(int qty) {
    if (qty >= 1000) {
      return '${qty ~/ 1000}k';
    }
    return '$qty';
  }

  void _showCustomQuantityDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: InputDecoration(hintText: 'Max: $maxQuantity'),
          onSubmitted: (value) {
            final qty = int.tryParse(value);
            if (qty != null && qty > 0 && qty <= maxQuantity) {
              Navigator.of(dialogContext).pop(qty);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(controller.text);
              if (qty != null && qty > 0 && qty <= maxQuantity) {
                Navigator.of(dialogContext).pop(qty);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((qty) {
      if (qty != null && context.mounted) {
        Navigator.of(context).pop(qty);
      }
    });
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

/// Shows a quantity selection dialog and returns the selected quantity.
///
/// Returns null if the user cancels.
Future<int?> showQuantityDialog(
  BuildContext context,
  Item item, {
  int maxQuantity = 99999,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => QuantityDialog(item: item, maxQuantity: maxQuantity),
  );
}
