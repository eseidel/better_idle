import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that displays the drops for a combat monster.
class MonsterDropsDialog extends StatelessWidget {
  const MonsterDropsDialog({required this.monster, super.key});

  final CombatAction monster;

  @override
  Widget build(BuildContext context) {
    final items = context.state.registries.items;

    final media = monster.media;
    return AlertDialog(
      title: Row(
        children: [
          if (media != null) ...[
            CachedImage(assetPath: media),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(monster.name)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Always Drops section
            const Text(
              'Always Drops:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // GP drop
            if (monster.minGpDrop > 0 || monster.maxGpDrop > 0)
              _DropRow(
                prefix: _formatGpRange(monster.minGpDrop, monster.maxGpDrop),
                icon: CachedImage(assetPath: Currency.gp.assetPath, size: 20),
                name: Currency.gp.abbreviation,
              ),

            // Bones drop
            if (monster.bones != null)
              _DropRow(
                prefix: '${monster.bones!.quantity}x',
                icon: ItemImage(
                  item: items.byId(monster.bones!.itemId),
                  size: 20,
                ),
                name: monster.bones!.itemId.name,
              ),

            if (monster.minGpDrop == 0 &&
                monster.maxGpDrop == 0 &&
                monster.bones == null)
              const Text(
                'Nothing',
                style: TextStyle(color: Style.textColorSecondary),
              ),

            const SizedBox(height: 16),

            // Possible Extra Drops section
            const Text(
              'Possible Extra Drops:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (monster.lootTable != null)
              _buildLootTable(context, monster.lootTable!)
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

  String _formatGpRange(int min, int max) {
    if (min == max) {
      return '$min';
    }
    return '$min - $max';
  }

  Widget _buildLootTable(BuildContext context, Droppable lootTable) {
    final items = context.state.registries.items;

    // The lootTable is a DropChance wrapping a DropTable
    if (lootTable is! DropChance) {
      return const Text(
        'Unknown loot format',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    final dropChance = lootTable;
    final innerTable = dropChance.child;

    if (innerTable is! DropTable) {
      return const Text(
        'Unknown loot format',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    final table = innerTable;

    // Sort entries by weight descending (most common first)
    final sortedEntries = List<DropTableEntry>.from(table.entries)
      ..sort((a, b) => b.weight.compareTo(a.weight));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedEntries.map((entry) {
        final item = items.byId(entry.itemID);

        return _DropRow(
          prefix: _formatQuantityPrefix(entry.minQuantity, entry.maxQuantity),
          icon: ItemImage(item: item, size: 20),
          name: item.name,
        );
      }).toList(),
    );
  }

  String _formatQuantityPrefix(int min, int max) {
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
