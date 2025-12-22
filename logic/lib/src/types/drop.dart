import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/inventory.dart';

/// Base class for anything that can be dropped.
abstract class Droppable {
  const Droppable();

  /// Rolls this drop and returns the ItemStack if successful, null otherwise.
  ItemStack? roll(ItemRegistry items, Random random);

  /// Returns the expected items per action for prediction purposes.
  /// Maps MelvorId string to expected count (rate * count for simple drops).
  Map<MelvorId, double> get expectedItems;
}

Map<MelvorId, double> expectedItemsForDrops(List<Droppable> drops) {
  final result = <MelvorId, double>{};
  for (final drop in drops) {
    final expectedItems = drop.expectedItems;
    for (final entry in expectedItems.entries) {
      result[entry.key] = (result[entry.key] ?? 0) + entry.value;
    }
  }
  return result;
}

/// A single item drop with an optional activation rate.
class Drop extends Droppable {
  /// Creates a drop from a MelvorId.
  const Drop(this.itemId, {this.count = 1, this.rate = 1.0})
    : assert(count > 0, 'Count must be greater than 0');

  /// Creates a drop from a string name (convenience constructor).
  Drop.fromName(String name, {int count = 1, double rate = 1.0})
    : this(MelvorId.fromName(name), count: count, rate: rate);

  final MelvorId itemId;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  final int count;

  String get name => itemId.name;

  @override
  Map<MelvorId, double> get expectedItems => {itemId: count * rate};

  /// Creates an ItemStack with a fixed count (for fixed drops).
  ItemStack toItemStack(ItemRegistry items) {
    final item = items.byId(itemId);
    return ItemStack(item, count: count);
  }

  @override
  ItemStack? roll(ItemRegistry items, Random random) {
    if (rate < 1.0 && random.nextDouble() >= rate) {
      return null;
    }
    return toItemStack(items);
  }
}

/// A conditional drop that wraps any Droppable with a probability gate.
class DropChance extends Droppable {
  const DropChance(this.child, {required this.rate});

  final Droppable child;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  @override
  ItemStack? roll(ItemRegistry items, Random random) {
    if (random.nextDouble() >= rate) {
      return null;
    }
    return child.roll(items, random);
  }

  @override
  Map<MelvorId, double> get expectedItems {
    final childItems = child.expectedItems;
    return childItems.map((key, value) => MapEntry(key, value * rate));
  }
}

/// Deprecated, to be removed once we're loading everything from MelvorData.
class Pick extends DropTableEntry {
  Pick(String itemName, {int count = 1, required super.weight})
    : super(
        itemID: MelvorId.fromName(itemName),
        minQuantity: count,
        maxQuantity: count,
      );
}

/// A drop table that selects exactly one item from weighted entries.
/// Always drops something (unless entries is empty).
class DropTable extends Droppable {
  DropTable(this.entries)
    : assert(entries.isNotEmpty, 'Entries must not be empty');

  /// The weighted entries in this table.
  final List<DropTableEntry> entries;

  /// Returns the total weight of all entries.
  double get _totalWeight => entries.fold(0, (sum, e) => sum + e.weight);

  @override
  Map<MelvorId, double> get expectedItems {
    final result = <MelvorId, double>{};
    final total = _totalWeight;
    for (final entry in entries) {
      final probability = entry.weight / total;
      final value = entry.expectedCount * probability;
      final key = entry.itemID;
      result[key] = (result[key] ?? 0.0) + value;
    }
    return result;
  }

  @override
  ItemStack roll(ItemRegistry items, Random random) {
    final total = _totalWeight;
    var roll = random.nextDouble() * total;

    for (final entry in entries) {
      roll -= entry.weight;
      if (roll <= 0) {
        // In a DropTable, entries always have rate = 1.0, so roll never returns null.
        return entry.roll(items, random);
      }
    }

    // Fallback to last entry (shouldn't happen with valid weights)
    return entries.last.roll(items, random);
  }
}
