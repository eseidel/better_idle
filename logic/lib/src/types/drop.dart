import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/types/inventory.dart';

/// Base class for anything that can be dropped.
abstract class Droppable {
  const Droppable();

  /// Rolls this drop and returns the ItemStack if successful, null otherwise.
  ItemStack? roll(Random random);

  /// Returns the expected items per action for prediction purposes.
  /// Maps item name to expected count (rate * count for simple drops).
  Map<String, double> get expectedItems;
}

Map<String, double> expectedItemsForDrops(List<Droppable> drops) {
  final result = <String, double>{};
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
  /// Creates a drop with a fixed count (default 1).
  const Drop(this.name, {this.count = 1, this.rate = 1.0})
    : assert(count > 0, 'Count must be greater than 0');
  final String name;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  final int count;

  /// The expected count for this drop (used for predictions).
  double get expectedCount => count * rate;

  @override
  Map<String, double> get expectedItems => {name: expectedCount * rate};

  /// Creates an ItemStack with a fixed count (for fixed drops).
  ItemStack toItemStack() {
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }

  @override
  ItemStack? roll(Random random) {
    if (rate < 1.0 && random.nextDouble() >= rate) {
      return null;
    }
    return toItemStack();
  }
}

/// A conditional drop that wraps any Droppable with a probability gate.
class DropChance extends Droppable {
  const DropChance(this.child, {required this.rate});

  final Droppable child;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  @override
  ItemStack? roll(Random random) {
    if (random.nextDouble() >= rate) {
      return null;
    }
    return child.roll(random);
  }

  @override
  Map<String, double> get expectedItems {
    final childItems = child.expectedItems;
    return childItems.map((key, value) => MapEntry(key, value * rate));
  }
}

/// A weighted entry in a DropTable.
/// The weight determines relative probability of selection.
class Pick {
  /// Creates a pick with a fixed count (default 1).
  const Pick(this.name, this.weight, {int count = 1})
    : minCount = count,
      maxCount = count;

  /// Creates a pick with a random count within a range.
  const Pick.range(this.name, this.weight, {required int min, required int max})
    : minCount = min,
      maxCount = max;

  final String name;

  /// Relative weight for selection in a DropTable.
  final double weight;

  final int minCount;
  final int maxCount;

  /// The expected count for this pick (used for predictions).
  double get expectedCount => (minCount + maxCount) / 2.0;

  /// Creates the ItemStack when this pick is selected.
  ItemStack roll(Random random) {
    final count = minCount == maxCount
        ? minCount
        : minCount + random.nextInt(maxCount - minCount + 1);
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }
}

/// A drop table that selects exactly one item from weighted entries.
/// Always drops something (unless entries is empty).
class DropTable extends Droppable {
  DropTable(this.entries)
    : assert(entries.isNotEmpty, 'Entries must not be empty');

  /// The weighted entries in this table.
  final List<Pick> entries;

  /// Returns the total weight of all entries.
  double get _totalWeight => entries.fold(0, (sum, e) => sum + e.weight);

  @override
  Map<String, double> get expectedItems {
    final result = <String, double>{};
    final total = _totalWeight;
    for (final entry in entries) {
      final probability = entry.weight / total;
      final value = entry.expectedCount * probability;
      result[entry.name] = (result[entry.name] ?? 0.0) + value;
    }
    return result;
  }

  @override
  ItemStack roll(Random random) {
    final total = _totalWeight;
    var roll = random.nextDouble() * total;

    for (final entry in entries) {
      roll -= entry.weight;
      if (roll <= 0) {
        return entry.roll(random);
      }
    }

    // Fallback to last entry (shouldn't happen with valid weights)
    return entries.last.roll(random);
  }
}
