import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Compact inline display of input items with icons and counts.
/// Shows: [item1 icon] 15 [item2 icon] 10
class InputItemsRow extends StatelessWidget {
  const InputItemsRow({required this.items, this.onItemTap, super.key});

  final Map<MelvorId, int> items;

  /// Optional callback when an item is tapped.
  final void Function(Item item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    if (items.isEmpty) {
      return const Text(
        'No inputs',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, entry) in items.entries.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          _buildItemCell(
            context,
            state.registries.items.byId(entry.key),
            entry.value,
          ),
        ],
      ],
    );
  }

  Widget _buildItemCell(BuildContext context, Item item, int count) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ItemImage(item: item, size: 16),
        const SizedBox(width: 2),
        Text('$count'),
      ],
    );

    if (onItemTap != null) {
      return GestureDetector(onTap: () => onItemTap!(item), child: content);
    }
    return content;
  }
}
