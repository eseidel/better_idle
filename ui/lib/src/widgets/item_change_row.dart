import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A widget that displays an item change with count, icon, and name.
///
/// Example: `+85 [icon] Normal Logs` or `-10 [icon] Trout`
/// The count is colored green for gains and red for losses.
class ItemChangeRow extends StatelessWidget {
  const ItemChangeRow({
    required this.item,
    required this.count,
    this.suffix = '',
    super.key,
  });

  /// The item to display.
  final Item item;

  /// The count of items gained (positive) or lost (negative).
  final int count;

  /// Optional suffix to append (e.g., " (100 / hr)").
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final countText = signedCountString(count);
    final countColor = count > 0 ? Style.successColor : Style.errorColor;

    // Simple pluralization: add 's' if count is not 1 or -1
    final absCount = count.abs();
    final itemName = absCount == 1 ? item.name : _pluralize(item.name);

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(countText, style: TextStyle(color: countColor)),
          const SizedBox(width: 4),
          ItemImage(item: item, size: 16),
          const SizedBox(width: 4),
          Flexible(child: Text('$itemName$suffix')),
        ],
      ),
    );
  }

  /// Simple pluralization for item names.
  String _pluralize(String name) {
    // Most item names in Melvor are already plural (e.g., "Normal Logs")
    // or don't need pluralization, so we just return the name as-is.
    return name;
  }
}
