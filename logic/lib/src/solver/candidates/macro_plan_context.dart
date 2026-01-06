/// Context object for macro planning in the solver.
///
/// Bundles state, goal, boundaries, and helper methods needed to plan macros.
/// This allows MacroCandidate.plan() to be a method while accessing solver
/// internals.
library;

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/execution/prerequisites.dart' as prereqs;
import 'package:logic/src/state.dart';

/// Context for macro planning operations.
///
/// Provides access to solver state and helper methods that macros need during
/// planning. This decouples the macro planning logic from the solver
/// implementation while still allowing access to solver utilities.
///
/// Note: This context is used for deterministic planning. All macro planning
/// uses expected-value modeling (deterministic averages), not randomness.
class MacroPlanContext {
  MacroPlanContext({
    required this.state,
    required this.goal,
    required this.boundaries,
  });

  /// Current game state.
  final GlobalState state;

  /// The goal being pursued.
  final Goal goal;

  /// Skill boundaries for unlock detection.
  final Map<Skill, SkillBoundaries> boundaries;

  /// Counts inventory items by MelvorId.
  int countItem(GlobalState s, MelvorId itemId) {
    return s.inventory.items
        .where((slot) => slot.item.id == itemId)
        .map((slot) => slot.count)
        .fold(0, (a, b) => a + b);
  }

  /// Computes the maximum feasible batch size for an EnsureStock macro.
  ///
  /// Given a target quantity, this returns the largest batch that can be
  /// produced without overflowing inventory. Returns:
  /// - `target` if the full batch is feasible
  /// - A reduced batch size if inventory is constrained
  /// - 0 if no batch is feasible (inventory too full)
  ///
  /// The computation accounts for:
  /// - Current free inventory slots
  /// - New item types that will be created by the production chain
  /// - A safety margin for byproducts (gems, etc.)
  int computeFeasibleBatchSize(
    GlobalState s,
    MelvorId targetItemId,
    int target,
    Goal g,
  ) {
    final freeSlots = s.inventoryRemaining;

    // Estimate new slots needed for the full batch
    final newSlotsNeeded = _estimateNewSlotsForProduction(
      s,
      targetItemId,
      target,
      g,
    );

    // Reserve some slots for unexpected byproducts
    const safetyMargin = 2;
    final slotsAfterProduction = freeSlots - newSlotsNeeded - safetyMargin;

    if (slotsAfterProduction >= 0) {
      // Full batch is feasible
      return target;
    }

    // Need to reduce batch size
    // Binary search for largest feasible batch
    var low = 1;
    var high = target;
    var feasibleBatch = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final slotsForMid = _estimateNewSlotsForProduction(
        s,
        targetItemId,
        mid,
        g,
      );

      if (freeSlots - slotsForMid - safetyMargin >= 0) {
        feasibleBatch = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return feasibleBatch;
  }

  /// Quantizes a stock target to a coarse bucket to reduce plan thrash.
  ///
  /// Uses power-of-2 buckets capped at 640: {20, 40, 80, 160, 320, 640}
  /// This ensures at most 6 distinct target levels per item, preventing
  /// the solver from exploring many similar EnsureStock variants.
  ///
  /// The minimum bucket is 20 to avoid micro-stocking (8, 9, 10 style jitter).
  /// The maximum bucket is 640 to limit state explosion.
  ///
  /// IMPORTANT: This function always returns a value >= target. Inventory
  /// pressure handling is done elsewhere (EnsureStock.expand returns
  /// MacroNeedsBoundary, or execution hits inventory pressure naturally).
  /// Do NOT add step-down logic here - it can violate EnsureStock invariants.
  int quantizeStockTarget(GlobalState s, int target, SkillAction? action) {
    // Minimum batch size to avoid micro-stocking
    const minBucket = 20;

    if (target <= minBucket) return minBucket;

    // Find next power of 2 >= target, capped at maxChunkSize
    var bucket = minBucket;
    while (bucket < target && bucket < maxChunkSize) {
      bucket *= 2;
    }
    // Cap at maxChunkSize (bucket will be >= target since we stop when
    // bucket >= target OR bucket >= maxChunkSize)
    if (bucket > maxChunkSize) bucket = maxChunkSize;

    return bucket;
  }

  /// Computes a discrete bucket target for hard prerequisites.
  ///
  /// Unlike [quantizeStockTarget] which caps at maxChunkSize (for soft hints),
  /// this function ensures the returned value is >= [needed] while using
  /// discrete buckets to limit state space explosion.
  ///
  /// Strategy:
  /// - For needed <= maxChunkSize: use next power-of-2 bucket >= needed
  /// - For needed > maxChunkSize: round up to next multiple of maxChunkSize
  ///
  /// This guarantees forward progress (target >= needed) while keeping
  /// the number of distinct targets bounded.
  static int discreteHardTarget(int needed) {
    const minBucket = 20;

    if (needed <= minBucket) return minBucket;

    if (needed <= maxChunkSize) {
      // Use power-of-2 buckets for small targets
      var bucket = minBucket;
      while (bucket < needed) {
        bucket *= 2;
      }
      return bucket;
    }

    // For large targets, round up to next multiple of maxChunkSize
    return ((needed + maxChunkSize - 1) ~/ maxChunkSize) * maxChunkSize;
  }

  /// Maximum items to produce per EnsureStock expansion chunk.
  ///
  /// This limits work-per-expansion to prevent state explosion while
  /// preserving hard EnsureStock semantics. Large requirements are
  /// fulfilled across multiple replan cycles.
  static const int maxChunkSize = 640;

  // ---------------------------------------------------------------------------
  // Private helper methods
  // ---------------------------------------------------------------------------

  /// Estimates the number of new inventory slots needed for a production chain.
  ///
  /// For multi-tier production (e.g., bars need ores), this counts:
  /// - New item types from the target item itself
  /// - New item types from intermediate products (e.g., ores for bars)
  /// - New item types from byproducts (e.g., gems from mining)
  ///
  /// The result is a conservative estimate that helps ensure EnsureStock
  /// doesn't plan batches that will overflow inventory during execution.
  int _estimateNewSlotsForProduction(
    GlobalState s,
    MelvorId targetItemId,
    int quantity,
    Goal g,
  ) {
    var newSlots = 0;
    final visited = <MelvorId>{};

    void countNewSlots(MelvorId itemId, int qty) {
      if (visited.contains(itemId)) return;
      visited.add(itemId);

      // Check if this item is already in inventory
      final item = s.registries.items.byId(itemId);
      final currentCount = s.inventory.countOfItem(item);
      if (currentCount == 0) {
        newSlots++;
      }

      // Find the producer for this item to check for intermediates
      final producerId = prereqs.findProducerActionForItem(s, itemId);
      if (producerId == null) return;

      final producerAction = s.registries.actions.byId(producerId);
      if (producerAction is! SkillAction) return;

      // For mining actions, add potential gem slots (conservative estimate)
      if (producerAction.skill == Skill.mining && qty > 20) {
        // Mining can produce up to 5 gem types over many actions.
        // With 1% gem chance, expect to see gems after ~100 mining actions.
        // Be conservative: assume we'll fill some gem slots over large batches.
        const gemNames = ['Topaz', 'Sapphire', 'Ruby', 'Emerald', 'Diamond'];
        for (final gemName in gemNames) {
          final gemId = MelvorId('melvorD:$gemName');
          if (!visited.contains(gemId)) {
            visited.add(gemId);
            // Check if gem is in inventory by searching directly
            final hasGem = s.inventory.items.any(
              (stack) => stack.item.id == gemId,
            );
            if (!hasGem) {
              newSlots++;
            }
          }
        }
      }

      // Recurse into inputs for consuming actions
      for (final inputEntry in producerAction.inputs.entries) {
        final inputQty =
            (qty / (producerAction.outputs[itemId] ?? 1)).ceil() *
            inputEntry.value;
        countNewSlots(inputEntry.key, inputQty);
      }
    }

    countNewSlots(targetItemId, quantity);
    return newSlots;
  }
}
