import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// Represents an item that can be opened to receive drops from a table.
@immutable
class Openable {
  const Openable({required this.itemName, required this.drops});

  /// The name of the item that can be opened.
  final String itemName;

  /// The drop table for this openable. Uses weighted selection.
  final List<Droppable> drops;

  /// Gets the Item this openable represents.
  Item get item => itemRegistry.byName(itemName);

  /// Opens this item once and returns the resulting drop.
  /// Returns null only if all drops have rates < 1.0 and none triggered.
  ItemStack? open(Random random) {
    // Select from weighted drop table
    final totalWeight = drops.fold<double>(0, (sum, d) => sum + d.rate);
    var roll = random.nextDouble() * totalWeight;

    for (final drop in drops) {
      roll -= drop.rate;
      if (roll <= 0) {
        // This drop was selected, now roll it (ignoring its rate since we
        // already used the rate as weight for selection)
        // Create a temporary drop with rate 1.0 to guarantee the roll succeeds
        if (drop is RangeDrop) {
          final count =
              drop.minCount + random.nextInt(drop.maxCount - drop.minCount + 1);
          return ItemStack(itemRegistry.byName(drop.name), count: count);
        } else if (drop is Drop) {
          return drop.toItemStack();
        }
      }
    }

    // Fallback to last drop
    final lastDrop = drops.last;
    if (lastDrop is RangeDrop) {
      final count =
          lastDrop.minCount +
          random.nextInt(lastDrop.maxCount - lastDrop.minCount + 1);
      return ItemStack(itemRegistry.byName(lastDrop.name), count: count);
    } else if (lastDrop is Drop) {
      return lastDrop.toItemStack();
    }

    return null;
  }
}

/// Egg Chest drop table:
/// Feathers: 1-1,000 count, 50% weight
/// Raw Chicken: 1-40 count, 50% weight
const eggChest = Openable(
  itemName: 'Egg Chest',
  drops: [
    RangeDrop('Feathers', minCount: 1, maxCount: 1000, rate: 1), // 50% weight
    RangeDrop('Raw Chicken', minCount: 1, maxCount: 40, rate: 1), // 50% weight
  ],
);

const List<Openable> _allOpenables = [eggChest];

class OpenableRegistry {
  OpenableRegistry(this._all);

  final List<Openable> _all;

  /// Returns the openable for the given item name, or null if not openable.
  Openable? forItemName(String name) {
    for (final openable in _all) {
      if (openable.itemName == name) {
        return openable;
      }
    }
    return null;
  }

  /// Returns the openable for the given item, or null if not openable.
  Openable? forItem(Item item) => forItemName(item.name);

  /// Returns true if the item can be opened.
  bool isOpenable(Item item) => forItem(item) != null;
}

final openableRegistry = OpenableRegistry(_allOpenables);
