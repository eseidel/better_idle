import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/item_image.dart';

/// A widget that displays an item count with icon and name.
///
/// Example: `100 [icon] Lobster`
class ItemCountRow extends StatelessWidget {
  const ItemCountRow({
    required this.item,
    required this.count,
    this.countColor,
    super.key,
  });

  /// The item to display.
  final Item item;

  /// The count of items.
  final int count;

  /// Optional color for the count text.
  final Color? countColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            approximateCountString(count),
            style: countColor != null ? TextStyle(color: countColor) : null,
          ),
          const SizedBox(width: 4),
          ItemImage(item: item, size: 16),
          const SizedBox(width: 4),
          Flexible(child: Text(item.name)),
        ],
      ),
    );
  }
}
