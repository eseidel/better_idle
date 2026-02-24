import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that displays the drops for a thieving NPC.
class ThievingDropsDialog extends StatelessWidget {
  const ThievingDropsDialog({required this.action, super.key});

  final ThievingAction action;

  @override
  Widget build(BuildContext context) {
    final items = context.state.registries.items;

    return AlertDialog(
      title: Row(
        children: [
          if (action.media != null) ...[
            CachedImage(assetPath: action.media),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(action.name)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // GP section
            const Text('GP:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _DropRow(
              prefix: '1 - ${action.maxGold}',
              icon: CachedImage(assetPath: Currency.gp.assetPath, size: 20),
              name: Currency.gp.abbreviation,
            ),
            const SizedBox(height: 16),

            // Common Drops section
            const Text(
              'Common Drops:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (action.dropTable != null)
              _buildDropTable(items, action.dropTable!)
            else
              const Text(
                'None',
                style: TextStyle(color: Style.textColorSecondary),
              ),
            const SizedBox(height: 16),

            // Rare Drops section
            const Text(
              'Rare Drops:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (action.uniqueDrop != null)
              _DropRow(
                prefix: '${action.uniqueDrop!.count} x',
                icon: ItemImage(
                  item: items.byId(action.uniqueDrop!.itemId),
                  size: 20,
                ),
                name: items.byId(action.uniqueDrop!.itemId).name,
              )
            else
              const Text(
                'None',
                style: TextStyle(color: Style.textColorSecondary),
              ),
            const SizedBox(height: 16),

            // Area Unique Drops section
            const Text(
              'Area Unique Drops:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (action.area.uniqueDrops.isNotEmpty)
              ...action.area.uniqueDrops.map(
                (drop) => _DropRow(
                  prefix: '${drop.count} x',
                  icon: ItemImage(item: items.byId(drop.itemId), size: 20),
                  name: items.byId(drop.itemId).name,
                ),
              )
            else
              const Text(
                'None',
                style: TextStyle(color: Style.textColorSecondary),
              ),
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

  Widget _buildDropTable(ItemRegistry items, Droppable dropTable) {
    if (dropTable is! DropChance) {
      return const Text(
        'Unknown loot format',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    final innerTable = dropTable.child;
    if (innerTable is! DropTable) {
      return const Text(
        'Unknown loot format',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    // Sort entries by weight descending (most common first)
    final sortedEntries = List<DropTableEntry>.from(innerTable.entries)
      ..sort((a, b) => b.weight.compareTo(a.weight));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedEntries.map((entry) {
        final item = items.byId(entry.itemID);
        return _DropRow(
          prefix: _formatQuantity(entry.minQuantity, entry.maxQuantity),
          icon: ItemImage(item: item, size: 20),
          name: item.name,
        );
      }).toList(),
    );
  }

  String _formatQuantity(int min, int max) {
    if (min == max) {
      return '$min x';
    }
    return '$min - $max x';
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
