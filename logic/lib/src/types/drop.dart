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

/// A single item drop (as opposed to a table of drops).
/// Subclasses define how the count is determined.
abstract class SingleDrop extends Droppable {
  const SingleDrop(this.name, {required this.rate});

  final String name;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  /// The expected count for this drop (used for predictions).
  double get expectedCount;

  @override
  Map<String, double> get expectedItems => {name: expectedCount * rate};
}

/// A simple drop that yields a specific item with a fixed count.
class Drop extends SingleDrop {
  const Drop(super.name, {this.count = 1, super.rate = 1.0});

  final int count;

  @override
  double get expectedCount => count.toDouble();

  ItemStack toItemStack() {
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }

  @override
  ItemStack? roll(Random random) {
    if (rate >= 1.0 || random.nextDouble() < rate) {
      return toItemStack();
    }
    return null;
  }
}

/// A drop that yields a random count within a range.
class RangeDrop extends SingleDrop {
  // We use short names for construction to cut down on typing.
  const RangeDrop(
    super.name, {
    required int min,
    required int max,
    super.rate = 1.0,
  }) : minCount = min,
       maxCount = max;

  // We use full names for fields for clarity.
  final int minCount;
  final int maxCount;

  @override
  double get expectedCount => (minCount + maxCount) / 2.0;

  @override
  ItemStack? roll(Random random) {
    if (rate < 1.0 && random.nextDouble() >= rate) {
      return null;
    }
    // Roll a random count within the range (inclusive)
    final count = minCount + random.nextInt(maxCount - minCount + 1);
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
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

/// Base class for weighted entries in a DropTable.
/// The weight determines relative probability of selection.
abstract class Pick {
  const Pick(this.name, this.weight);

  final String name;

  /// Relative weight for selection in a DropTable.
  final double weight;

  /// The expected count for this pick (used for predictions).
  double get expectedCount;

  /// Creates the ItemStack when this pick is selected.
  ItemStack roll(Random random);
}

/// A simple pick that yields a specific item with a fixed count.
class PickFixed extends Pick {
  const PickFixed(super.name, super.weight, {this.count = 1});

  final int count;

  @override
  double get expectedCount => count.toDouble();

  @override
  ItemStack roll(Random random) {
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }
}

/// A pick that yields a random count within a range.
class PickRange extends Pick {
  const PickRange(
    super.name,
    super.weight, {
    required int min,
    required int max,
  }) : minCount = min,
       maxCount = max;

  final int minCount;
  final int maxCount;

  @override
  double get expectedCount => (minCount + maxCount) / 2.0;

  @override
  ItemStack roll(Random random) {
    final count = minCount + random.nextInt(maxCount - minCount + 1);
    final item = itemRegistry.byName(name);
    return ItemStack(item, count: count);
  }
}

/// A drop table that selects exactly one item from weighted entries.
/// Always drops something (unless entries is empty).
class DropTable extends Droppable {
  const DropTable(this.entries);

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
  ItemStack? roll(Random random) {
    if (entries.isEmpty) return null;

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
