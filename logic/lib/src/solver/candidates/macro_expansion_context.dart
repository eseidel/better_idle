/// Context object for macro expansion in the solver.
///
/// Bundles state, goal, boundaries, and helper methods needed to expand macros.
/// This allows MacroCandidate.expand() to be a method while accessing solver
/// internals.
library;

import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart' show startXpForLevel;
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/value_model.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart' show ticksFromDuration;

/// Context for macro expansion operations.
///
/// Provides access to solver state and helper methods that macros need during
/// expansion. This decouples the macro expansion logic from the solver
/// implementation while still allowing access to solver utilities.
class MacroExpansionContext {
  MacroExpansionContext({
    required this.state,
    required this.goal,
    required this.boundaries,
    required this.random,
  });

  /// Current game state.
  final GlobalState state;

  /// The goal being pursued.
  final Goal goal;

  /// Skill boundaries for unlock detection.
  final Map<Skill, SkillBoundaries> boundaries;

  /// Random number generator for deterministic planning.
  final Random random;

  /// Counts inventory items by MelvorId.
  int countItem(GlobalState s, MelvorId itemId) {
    return s.inventory.items
        .where((slot) => slot.item.id == itemId)
        .map((slot) => slot.count)
        .fold(0, (a, b) => a + b);
  }

  /// Finds an action that produces the given item.
  ActionId? findProducerActionForItem(GlobalState s, MelvorId item, Goal g) {
    int skillLevel(Skill skill) => s.skillState(skill).skillLevel;

    // Find all actions that produce this item
    final producers = s.registries.actions.all
        .whereType<SkillAction>()
        .where((action) => action.outputs.containsKey(item))
        .where((action) => action.unlockLevel <= skillLevel(action.skill));

    if (producers.isEmpty) return null;

    // Rank by production rate (outputs per tick)
    // Producer actions (woodcutting, fishing, mining) don't require inputs,
    // so we can directly calculate rates without testing applyInteraction.
    ActionId? best;
    double bestRate = 0;

    for (final action in producers) {
      final ticksPerAction = ticksFromDuration(action.meanDuration).toDouble();
      final outputsPerAction = action.outputs[item] ?? 1;
      final outputsPerTick = outputsPerAction / ticksPerAction;

      if (outputsPerTick > bestRate) {
        bestRate = outputsPerTick;
        best = action.id;
      }
    }

    return best;
  }

  /// Finds an action that produces the given item, even if locked.
  ///
  /// Returns null if no action produces this item at all.
  /// Unlike [findProducerActionForItem], this finds producers regardless
  /// of skill level requirements.
  SkillAction? findAnyProducerForItem(GlobalState s, MelvorId item) {
    return s.registries.actions.all
        .whereType<SkillAction>()
        .where((action) => action.outputs.containsKey(item))
        .firstOrNull;
  }

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

    return macros.isEmpty
        ? const ExecReady()
        : ExecNeedsMacros(_dedupeMacros(macros));
  }

  /// Finds the best action for a skill based on the goal's criteria.
  ///
  /// For skill goals, picks the action with highest XP rate.
  /// For GP goals, picks the action with highest gold rate.
  ///
  /// Unlike `estimateRates`, this function doesn't require the action to be
  /// startable. This is important for consuming skills where we want to find
  /// the best action even when inputs aren't currently available (because we'll
  /// produce them next).
  ///
  /// For consuming actions, this also checks that we can produce the inputs.
  ActionId? findBestActionForSkill(GlobalState s, Skill skill, Goal g) {
    final skillLevel = s.skillState(skill).skillLevel;
    final actions = s.registries.actions.all
        .whereType<SkillAction>()
        .where((action) => action.skill == skill)
        .where((action) => action.unlockLevel <= skillLevel);

    if (actions.isEmpty) return null;

    // Rank by goal-specific rate
    ActionId? best;
    double bestRate = 0;

    // Check if this skill is relevant to the goal. If not (e.g., training
    // Mining as a prerequisite for Smithing), use raw XP rate instead.
    final skillIsGoalRelevant = g.isSkillRelevant(skill);

    actionLoop:
    for (final action in actions) {
      // For consuming actions, check that ALL inputs can be produced
      // (either directly or via prerequisite training).
      // This handles multi-input actions like Mithril Bar (Mithril Ore + Coal).
      if (action.inputs.isNotEmpty) {
        for (final inputItem in action.inputs.keys) {
          // Check if any producer exists (locked or unlocked)
          final anyProducer = findAnyProducerForItem(s, inputItem);
          if (anyProducer == null) {
            // No way to produce this input at all, skip this action
            continue actionLoop;
          }
        }
      }

      // Use estimateRatesForAction which doesn't require action to be active
      // or have inputs available. Allows planning for consuming actions
      // before inputs are produced.
      final rates = estimateRatesForAction(s, action.id);

      final goldRate = defaultValueModel.valuePerTick(s, rates);
      final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;

      // For prerequisite training (skill not in goal), use raw XP rate
      // to pick the fastest training action.
      final rate = skillIsGoalRelevant
          ? g.activityRate(skill, goldRate, xpRate)
          : xpRate;

      if (rate > bestRate) {
        bestRate = rate;
        best = action.id;
      }
    }

    return best;
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
  /// Buckets: {10, 20, 50, 100, 200}
  /// Selection is based on free inventory slots and action output diversity.
  int quantizeStockTarget(GlobalState s, int target, SkillAction? action) {
    const buckets = [10, 20, 50, 100, 200];

    // If target is already large, just round up to nearest bucket
    if (target >= 200) return target;

    // Determine base bucket from free inventory slots
    final usedSlots = s.inventory.items.length;
    final freeSlots = s.inventoryCapacity - usedSlots;
    int baseBucketIndex;
    if (freeSlots < 10) {
      baseBucketIndex = 0; // 10
    } else if (freeSlots < 20) {
      baseBucketIndex = 1; // 20
    } else if (freeSlots < 40) {
      baseBucketIndex = 2; // 50
    } else {
      baseBucketIndex = 3; // 100
    }

    // Step down one bucket if action produces many distinct outputs
    if (action != null && action.outputs.length > 2 && baseBucketIndex > 0) {
      baseBucketIndex--;
    }

    final bucketSize = buckets[baseBucketIndex];

    // Quantize: round up to nearest bucket
    // Always round up to at least the minimum bucket size to avoid tiny amounts
    final quantized = ((target + bucketSize - 1) ~/ bucketSize) * bucketSize;

    // Ensure we return at least the minimum bucket (10) to avoid tiny stocking
    return quantized < 10 ? 10 : quantized;
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

  /// Deduplicates macros, keeping first occurrence of each unique macro.
  static List<MacroCandidate> _dedupeMacros(List<MacroCandidate> macros) {
    final seen = <String>{};
    final result = <MacroCandidate>[];
    for (final macro in macros) {
      final key = switch (macro) {
        TrainSkillUntil(:final skill, :final primaryStop) =>
          'train:${skill.name}:${primaryStop.hashCode}',
        TrainConsumingSkillUntil(:final consumingSkill, :final primaryStop) =>
          'trainConsuming:${consumingSkill.name}:${primaryStop.hashCode}',
        AcquireItem(:final itemId, :final quantity) =>
          'acquire:${itemId.localId}:$quantity',
        EnsureStock(:final itemId, :final minTotal) =>
          'ensure:${itemId.localId}:$minTotal',
        ProduceItem(:final itemId, :final minTotal, :final actionId) =>
          'produce:${itemId.localId}:$minTotal:${actionId.localId}',
      };
      if (seen.add(key)) result.add(macro);
    }
    return result;
  }

  /// Creates a new context with updated state.
  MacroExpansionContext withState(GlobalState newState) {
    return MacroExpansionContext(
      state: newState,
      goal: goal,
      boundaries: boundaries,
      random: random,
    );
  }
}

/// Result of checking if an action's prerequisites are satisfied.
sealed class EnsureExecResult {
  const EnsureExecResult();
}

/// Action is ready to execute now.
class ExecReady extends EnsureExecResult {
  const ExecReady();
}

/// Action needs prerequisite macros before it can execute.
class ExecNeedsMacros extends EnsureExecResult {
  const ExecNeedsMacros(this.macros);
  final List<MacroCandidate> macros;
}

/// Cannot determine how to make action feasible.
class ExecUnknown extends EnsureExecResult {
  const ExecUnknown(this.reason);
  final String reason;
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
