import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';

/// Shows a dialog displaying the possible contents of an openable item.
void showOpenableContentsDialog(BuildContext context, Item item) {
  showDialog<void>(
    context: context,
    builder: (context) => OpenableContentsDialog(item: item),
  );
}

/// A dialog that displays the possible contents of an openable item.
class OpenableContentsDialog extends StatelessWidget {
  const OpenableContentsDialog({required this.item, super.key});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final items = context.state.registries.items;
    final dropTable = item.dropTable;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ItemImage(item: item, size: 48),
          const SizedBox(height: 8),
          Text(item.name),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Possible contents:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (dropTable != null)
              ...dropTable.entries
                  .sorted((a, b) => b.weight.compareTo(a.weight))
                  .map((entry) {
                    final entryItem = items.byId(entry.itemID);
                    return _DropRow(
                      prefix: _formatQuantity(
                        entry.minQuantity,
                        entry.maxQuantity,
                      ),
                      icon: ItemImage(item: entryItem, size: 20),
                      name: entryItem.name,
                    );
                  }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatQuantity(int min, int max) {
    if (min == max) {
      return '$min x';
    }
    return 'Up to $max x';
  }
}

class _DropRow extends StatelessWidget {
  const _DropRow({
    required this.prefix,
    required this.icon,
    required this.name,
  });

  final String prefix;
  final Widget icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          Text(prefix),
          const SizedBox(width: 4),
          icon,
          const SizedBox(width: 4),
          Expanded(child: Text(name)),
        ],
      ),
    );
  }
}
