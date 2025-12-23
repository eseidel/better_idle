import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Compact inline display of input items with icons and counts.
/// Shows: [item1 icon] 15 [item2 icon] 10
class InputItemsRow extends StatelessWidget {
  const InputItemsRow({required this.items, super.key});

  final Map<MelvorId, int> items;

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
          ItemImage(item: state.registries.items.byId(entry.key), size: 16),
          const SizedBox(width: 2),
          Text('${entry.value}'),
        ],
      ],
    );
  }
}
