import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/types/inventory.dart';

/// Base class for anything that can be dropped.
abstract class Droppable {
  const Droppable({required this.rate});

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

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
  const SingleDrop(this.name, {required super.rate});

  final String name;

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

/// A drop that has an outer chance to occur, and when it does,
/// selects from a weighted table of possible outcomes.
///
/// Each entry's `rate` field is used as its relative weight in the table.
///
/// Example: A gem drop with 1% chance, where:
/// - 50% weight Topaz (0.5% effective)
/// - 17.5% weight Sapphire (0.175% effective)
/// - etc.
class DropTable extends Droppable {
  const DropTable(this.entries, {super.rate = 1.0});

  /// The weighted entries in this table. Each entry's `rate` is used as weight.
  final List<SingleDrop> entries;

  /// Returns the total weight of all entries.
  double get _totalWeight => entries.fold(0, (sum, e) => sum + e.rate);

  /// Returns the effective rate for a specific entry (for predictions).
  /// This is: outer rate * (entry weight / total weight)
  double _effectiveRate(SingleDrop entry) {
    return rate * (entry.rate / _totalWeight);
  }

  /// Returns true if this drop table can drop nothing.
  bool get canDropNothing => rate < 1.0 || entries.isEmpty;

  @override
  Map<String, double> get expectedItems {
    final result = <String, double>{};
    for (final entry in entries) {
      final effective = _effectiveRate(entry);
      // Use expectedCount directly (not expectedItems which has rate baked in)
      final value = entry.expectedCount * effective;
      result[entry.name] = (result[entry.name] ?? 0.0) + value;
    }
    return result;
  }

  @override
  ItemStack? roll(Random random) {
    // First roll: does the table trigger at all?
    if (random.nextDouble() >= rate) {
      return null;
    }

    // Second roll: which entry from the table?
    final total = _totalWeight;
    var roll = random.nextDouble() * total;

    for (final entry in entries) {
      roll -= entry.rate;
      if (roll <= 0) {
        return entry.roll(random);
      }
    }

    // Fallback to last entry (shouldn't happen with valid weights)
    return entries.last.roll(random);
  }
}
