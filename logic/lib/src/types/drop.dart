import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// Base class for anything that can be dropped.
abstract class Droppable {
  const Droppable();

  /// Rolls this drop and returns the ItemStack if successful, null otherwise.
  ItemStack? roll(ItemRegistry items, Random random);

  /// Returns the expected items per action for prediction purposes.
  /// Maps MelvorId string to expected count (rate * count for simple drops).
  Map<MelvorId, double> get expectedItems;
}

/// Computes expected items per action from a list of drops.
/// If [doublingChance] is provided (0.0-1.0), applies it as a multiplier.
Map<MelvorId, double> expectedItemsForDrops(
  List<Droppable> drops, {
  double doublingChance = 0.0,
}) {
  final result = <MelvorId, double>{};
  final multiplier = 1.0 + doublingChance;
  for (final drop in drops) {
    final expectedItems = drop.expectedItems;
    for (final entry in expectedItems.entries) {
      result[entry.key] = (result[entry.key] ?? 0) + entry.value * multiplier;
    }
  }
  return result;
}

/// A single item drop with an optional activation rate.
///
/// This is separate from [RareDrop] because they correspond to different JSON
/// structures in the Melvor data: simple drops have a numeric `chance` field,
/// while rare drops have a complex `chance` object with scaling parameters.
@immutable
class Drop extends Droppable {
  /// Creates a drop from a MelvorId.
  const Drop(this.itemId, {this.count = 1, this.rate = 1.0})
    : assert(count > 0, 'Count must be greater than 0');

  final MelvorId itemId;

  /// The chance this drop is triggered (0.0 to 1.0).
  final double rate;

  final int count;

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
@immutable
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

/// Calculates drop chance based on player progress.
///
/// Different implementations handle fixed chances vs scaling with level/mastery.
@immutable
sealed class DropChanceCalculator {
  const DropChanceCalculator();

  /// Calculates the effective drop chance given player context.
  double calculate({int skillLevel = 1, int totalMastery = 0});

  /// Returns a representative chance for estimation purposes.
  /// Uses mid-game defaults (level 50, 5000 mastery).
  double get estimatedChance => calculate(skillLevel: 50, totalMastery: 5000);
}

/// Fixed drop chance that doesn't scale with player progress.
@immutable
class FixedChance extends DropChanceCalculator {
  const FixedChance(this.chance);

  final double chance;

  @override
  double calculate({int skillLevel = 1, int totalMastery = 0}) => chance;

  @override
  double get estimatedChance => chance;
}

/// Drop chance that scales with skill level.
@immutable
class LevelScalingChance extends DropChanceCalculator {
  const LevelScalingChance({
    required this.baseChance,
    required this.maxChance,
    required this.scalingFactor,
  });

  final double baseChance;
  final double maxChance;
  final double scalingFactor;

  @override
  double calculate({int skillLevel = 1, int totalMastery = 0}) {
    final scaled = baseChance + (skillLevel * scalingFactor);
    return scaled.clamp(0.0, maxChance);
  }
}

/// Drop chance that scales with total mastery in the skill.
@immutable
class MasteryScalingChance extends DropChanceCalculator {
  const MasteryScalingChance({
    required this.baseChance,
    required this.maxChance,
    required this.scalingFactor,
  });

  final double baseChance;
  final double maxChance;
  final double scalingFactor;

  @override
  double calculate({int skillLevel = 1, int totalMastery = 0}) {
    final scaled = baseChance + (totalMastery * scalingFactor);
    return scaled.clamp(0.0, maxChance);
  }
}

/// A rare drop with dynamic chance based on skill level or mastery.
///
/// Rare drops have complex chance calculations that depend on the player's
/// progress. The chance is calculated at roll time based on the provided
/// skill level and total mastery.
///
/// This is separate from [Drop] because they correspond to different JSON
/// structures in the Melvor data: rare drops have a complex `chance` object
/// with type and scaling parameters, while simple drops have a numeric chance.
@immutable
class RareDrop extends Droppable {
  const RareDrop({
    required this.itemId,
    required this.chance,
    this.count = 1,
    this.requiredItemId,
  });

  final MelvorId itemId;

  /// How the drop chance is calculated.
  final DropChanceCalculator chance;

  /// Number of items dropped.
  final int count;

  /// Item that must have been found for this drop to be available.
  final MelvorId? requiredItemId;

  @override
  Map<MelvorId, double> get expectedItems {
    // Use mid-game estimate for expected items calculation
    return {itemId: count * chance.estimatedChance};
  }

  @override
  ItemStack? roll(ItemRegistry items, Random random) {
    // Note: This uses default chance. For proper rolling, use rollWithContext.
    final rate = chance.calculate();
    if (random.nextDouble() >= rate) {
      return null;
    }
    final item = items.byId(itemId);
    return ItemStack(item, count: count);
  }

  /// Rolls the drop with skill level and mastery context.
  ///
  /// Returns null if the roll fails or if requirements aren't met.
  ItemStack? rollWithContext(
    ItemRegistry items,
    Random random, {
    required int skillLevel,
    required int totalMastery,
    required bool hasRequiredItem,
  }) {
    // Check requirements
    if (requiredItemId != null && !hasRequiredItem) {
      return null;
    }

    final rate = chance.calculate(
      skillLevel: skillLevel,
      totalMastery: totalMastery,
    );
    if (random.nextDouble() >= rate) {
      return null;
    }
    final item = items.byId(itemId);
    return ItemStack(item, count: count);
  }
}

/// A drop table that selects exactly one item from weighted entries.
/// Always drops something (unless entries is empty).
@immutable
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
        return entry.roll(items, random);
      }
    }

    // Fallback to last entry (shouldn't happen with valid weights)
    return entries.last.roll(items, random);
  }
}
