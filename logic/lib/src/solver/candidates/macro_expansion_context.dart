/// Context object for macro expansion in the solver.
///
/// Bundles state, goal, boundaries, and helper methods needed to expand macros.
/// This allows MacroCandidate.expand() to be a method while accessing solver
/// internals.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart' show startXpForLevel;
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/execution/prerequisites.dart';
import 'package:logic/src/state.dart';

/// Context for macro expansion operations.
///
/// Provides access to solver state and helper methods that macros need during
/// expansion. This decouples the macro expansion logic from the solver
/// implementation while still allowing access to solver utilities.
///
/// Note: This context is used for deterministic planning. All macro expansion
/// uses expected-value modeling (deterministic averages), not randomness.
class MacroExpansionContext {
  MacroExpansionContext({
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

  /// Finds an action that produces the given item.
  ActionId? findProducerAction(GlobalState s, MelvorId item, Goal g) =>
      findProducerActionForItem(s, item, g);

  /// Finds an action that produces the given item, even if locked.
  ///
  /// Returns null if no action produces this item at all.
  /// Unlike [findProducerAction], this finds producers regardless
  /// of skill level requirements.
  SkillAction? findAnyProducer(GlobalState s, MelvorId item) =>
      findAnyProducerForItem(s, item);

  /// Returns prerequisite check result for an action.
  ///
  /// Checks:
  /// 1. Skill level requirements - generates TrainSkillUntil if locked
  /// 2. Input requirements - recursively checks producers for each input
  ///
  /// Returns [ExecReady] if action can execute now, [ExecNeedsMacros] if
  /// prerequisites are needed, or [ExecUnknown] if we can't determine how
  /// to make the action feasible (e.g., no producer exists, cycle detected).
  EnsureExecResult ensureExecutable(
    GlobalState s,
    ActionId actionId,
    Goal g, {
    int depth = 0,
    int maxDepth = 8,
    Set<ActionId>? visited,
  }) {
    visited ??= <ActionId>{};
    if (!visited.add(actionId)) {
      return ExecUnknown('cycle: $actionId');
    }
    if (depth >= maxDepth) {
      return ExecUnknown('depth limit: $actionId');
    }

    final action = s.registries.actions.byId(actionId);
    if (action is! SkillAction) return const ExecReady();

    final macros = <MacroCandidate>[];

    // 1. Check skill level requirement
    final currentLevel = s.skillState(action.skill).skillLevel;
    if (action.unlockLevel > currentLevel) {
      macros.add(
        TrainSkillUntil(
          action.skill,
          StopAtLevel(action.skill, action.unlockLevel),
        ),
      );
    }

    // 2. Check inputs - recursively ensure each can be produced
    // NOTE: We only check feasibility (skill unlocks), NOT stocking.
    // Stocking amounts should be determined by the caller with proper batch
    // sizing, not here with minimal amounts that cause plan thrash.
    for (final inputId in action.inputs.keys) {
      final inputCount = action.inputs[inputId]!;
      final inputItem = s.registries.items.byId(inputId);
      final currentCount = s.inventory.countOfItem(inputItem);

      // If we already have enough of this input, no prereq needed
      if (currentCount >= inputCount) continue;

      // First check if there's an unlocked producer
      final producer = findProducerActionForItem(s, inputId, g);
      if (producer != null) {
        // Producer exists and is unlocked, check its prerequisites
        final result = ensureExecutable(
          s,
          producer,
          g,
          depth: depth + 1,
          maxDepth: maxDepth,
          visited: visited,
        );
        switch (result) {
          case ExecReady():
            break; // Producer is ready
          case ExecNeedsMacros(macros: final producerMacros):
            macros.addAll(producerMacros);
          case ExecUnknown(:final reason):
            return ExecUnknown('input $inputId blocked: $reason');
        }
        // NOTE: We do NOT add EnsureStock here. The caller (e.g.,
        // _expandEnsureStock) handles stocking with proper batch sizing.
        // Adding small EnsureStock prereqs here causes plan thrash.
      } else {
        // No unlocked producer - check if one exists but is locked
        final lockedProducer = findAnyProducerForItem(s, inputId);
        if (lockedProducer == null) {
          return ExecUnknown('no producer for $inputId');
        }
        // Producer exists but is locked - need to train that skill
        final neededLevel = lockedProducer.unlockLevel;
        macros.add(
          TrainSkillUntil(
            lockedProducer.skill,
            StopAtLevel(lockedProducer.skill, neededLevel),
          ),
        );
        // NOTE: We do NOT add EnsureStock here. After training, the caller
        // will handle stocking with proper batch sizing.
      }
    }

    return macros.isEmpty ? const ExecReady() : ExecNeedsMacros(macros);
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
  /// Uses power-of-2 based buckets: {20, 40, 80, 160, 320, 640, 1280, ...}
  /// This ensures at most ~6 distinct target levels per item, preventing
  /// the solver from exploring many similar EnsureStock variants.
  ///
  /// The minimum bucket is 20 to avoid micro-stocking (8, 9, 10 style jitter).
  int quantizeStockTarget(GlobalState s, int target, SkillAction? action) {
    // Minimum batch size to avoid micro-stocking
    const minBucket = 20;

    if (target <= minBucket) return minBucket;

    // Find next power of 2 >= target, then use that as bucket
    // This gives buckets: 20, 40, 80, 160, 320, 640, 1280, 2560, ...
    var bucket = minBucket;
    while (bucket < target) {
      bucket *= 2;
    }

    // Optional: step down bucket if inventory is constrained
    final freeSlots = s.inventoryCapacity - s.inventory.items.length;
    if (freeSlots < 10 && bucket > minBucket) {
      // Tight on inventory - use smaller bucket
      bucket = bucket ~/ 2;
      if (bucket < target) bucket = target; // But at least cover target
    }

    return bucket;
  }

  /// For consuming skills (Smithing, Firemaking, etc.), computes how many
  /// craft actions are needed to reach the next skill level boundary.
  ///
  /// Returns null if no boundary exists (at max level) or already satisfied.
  BatchSizeResult? computeBatchToNextUnlock({
    required GlobalState state,
    required SkillAction consumingAction,
    required Map<Skill, SkillBoundaries> boundaries,
    int safetyMargin = 2,
  }) {
    final skill = consumingAction.skill;
    final currentLevel = state.skillState(skill).skillLevel;
    final currentXp = state.skillState(skill).xp;

    // Find next unlock boundary
    final skillBoundaries = boundaries[skill];
    if (skillBoundaries == null) return null;

    final nextLevel = skillBoundaries.nextBoundary(currentLevel);
    if (nextLevel == null) return null; // At or past max

    // Calculate XP needed
    final targetXp = startXpForLevel(nextLevel);
    final xpNeeded = targetXp - currentXp;
    if (xpNeeded <= 0) return null; // Already there

    // Calculate crafts needed
    final xpPerCraft = consumingAction.xp;
    final craftsNeeded = (xpNeeded / xpPerCraft).ceil() + safetyMargin;

    // Calculate input requirements (absolute totals)
    final inputRequirements = <MelvorId, int>{};
    for (final inputEntry in consumingAction.inputs.entries) {
      final inputId = inputEntry.key;
      final perCraft = inputEntry.value;

      final totalNeeded = craftsNeeded * perCraft;
      inputRequirements[inputId] = totalNeeded;
    }

    return BatchSizeResult(
      craftsNeeded: craftsNeeded,
      inputRequirements: inputRequirements,
      targetLevel: nextLevel,
    );
  }

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
      final producerId = findProducerActionForItem(s, itemId, g);
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

  /// Creates a new context with updated state.
  MacroExpansionContext withState(GlobalState newState) {
    return MacroExpansionContext(
      state: newState,
      goal: goal,
      boundaries: boundaries,
    );
  }
}

/// Result of computing batch size to next unlock.
class BatchSizeResult {
  BatchSizeResult({
    required this.craftsNeeded,
    required this.inputRequirements,
    required this.targetLevel,
  });

  final int craftsNeeded;
  final Map<MelvorId, int> inputRequirements;
  final int targetLevel;
}
