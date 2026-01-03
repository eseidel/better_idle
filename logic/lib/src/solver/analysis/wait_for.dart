import 'package:equatable/equatable.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/next_decision_delta.dart'
    show infTicks;
import 'package:logic/src/solver/analysis/replan_boundary.dart'
    show WaitConditionSatisfied;
import 'package:logic/src/solver/core/goal.dart' show Goal;
import 'package:logic/src/solver/execution/plan.dart' show WaitStep;
import 'package:logic/src/solver/interactions/interaction.dart'
    show SellPolicy, effectiveCredits;
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Wait For (what we're waiting for)
// ---------------------------------------------------------------------------

/// Describes what a [WaitStep] is waiting for.
///
/// During planning, the solver uses expected-value modeling which may differ
/// from actual simulation due to randomness. WaitFor types allow plan
/// execution to continue until the condition is actually met, rather than
/// stopping after a fixed number of ticks.
///
/// Each WaitFor type has:
/// - [isSatisfied] - check if condition is met (for execution)
/// - [progress] - current progress toward the condition (for stuck detection)
/// - [describe] - human-readable description with values
/// - [shortDescription] - brief label for plan display (e.g., "Skill +1")
sealed class WaitFor extends Equatable {
  const WaitFor();

  /// Returns true if this wait condition is satisfied in the given state.
  bool isSatisfied(GlobalState state);

  /// Returns the specific [WaitFor] that was satisfied in the given state.
  ///
  /// For simple waits, returns `this` if satisfied, null otherwise.
  /// For [WaitForAnyOf], returns the first satisfied child condition.
  ///
  /// This is used by consumeUntil to populate [WaitConditionSatisfied]
  /// with the specific condition that triggered, allowing callers to
  /// determine which branch of a composite wait was satisfied without
  /// re-probing state.
  WaitFor? findSatisfied(GlobalState state) {
    return isSatisfied(state) ? this : null;
  }

  /// Returns current progress toward this condition.
  ///
  /// Higher values mean closer to satisfaction. Used to detect when execution
  /// is stuck (no progress being made). Returns 0 for conditions that don't
  /// have meaningful progress tracking.
  int progress(GlobalState state);

  /// Estimates ticks to satisfy this condition given current rates.
  ///
  /// ## Return value semantics
  ///
  /// - **0 with [isSatisfied] true**: Condition already met, no waiting needed.
  /// - **0 with [isSatisfied] false**: "Immediate boundary" - execution would
  ///   terminate immediately due to a blocking condition (e.g., inventory full,
  ///   action can't run). The solver should treat this as a replanning signal,
  ///   not a successful wait. This allows the solver to insert sell/bank/batch
  ///   interactions before continuing.
  /// - **Positive value**: Estimated ticks until condition is satisfied.
  /// - **[infTicks]**: Condition cannot be reached with current rates (e.g.,
  ///   no production of required item). Unlike 0, this means "truly impossible"
  ///   rather than "blocked by a boundary we could resolve."
  ///
  /// ## Implementation notes
  ///
  /// Subclasses that track inventory items should check for immediate
  /// boundaries before computing the normal estimate:
  /// 1. If `state.activeAction` exists but `!state.canStartAction(action)`,
  ///    return 0 (action can't make progress).
  /// 2. If `state.inventoryRemaining <= 0`, return 0 (inventory full).
  /// 3. If `rates.itemTypesPerTick > 0`, cap by time to inventory full.
  int estimateTicks(GlobalState state, Rates rates);

  /// Human-readable description of what we're waiting for (with values).
  String describe();

  /// Short description for plan (e.g., "Skill +1", "Upgrade affordable").
  String get shortDescription;

  /// Serializes this [WaitFor] to a JSON-compatible map.
  Map<String, dynamic> toJson();

  /// Deserializes a [WaitFor] from a JSON-compatible map.
  static WaitFor fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'WaitForEffectiveCredits' => WaitForEffectiveCredits(
        json['targetValue'] as int,
        reason: json['reason'] as String? ?? 'Upgrade',
        sellPolicy: SellPolicy.fromJson(
          json['sellPolicy'] as Map<String, dynamic>,
        ),
      ),
      'WaitForSkillXp' => WaitForSkillXp(
        Skill.fromName(json['skill'] as String),
        json['targetXp'] as int,
        reason: json['reason'] as String?,
      ),
      'WaitForMasteryXp' => WaitForMasteryXp(
        ActionId.fromJson(json['actionId'] as String),
        json['targetMasteryXp'] as int,
      ),
      'WaitForInventoryThreshold' => WaitForInventoryThreshold(
        (json['threshold'] as num).toDouble(),
      ),
      'WaitForInventoryFull' => const WaitForInventoryFull(),
      'WaitForGoal' => WaitForGoal(
        Goal.fromJson(json['goal'] as Map<String, dynamic>),
      ),
      'WaitForInputsDepleted' => WaitForInputsDepleted(
        ActionId.fromJson(json['actionId'] as String),
      ),
      'WaitForInputsAvailable' => WaitForInputsAvailable(
        ActionId.fromJson(json['actionId'] as String),
      ),
      'WaitForInventoryAtLeast' => WaitForInventoryAtLeast(
        MelvorId.fromJson(json['itemId'] as String),
        json['minCount'] as int,
      ),
      'WaitForInventoryDelta' => WaitForInventoryDelta(
        MelvorId.fromJson(json['itemId'] as String),
        json['delta'] as int,
        startCount: json['startCount'] as int,
      ),
      'WaitForSufficientInputs' => WaitForSufficientInputs(
        ActionId.fromJson(json['actionId'] as String),
        json['targetCount'] as int,
      ),
      'WaitForAnyOf' => WaitForAnyOf(
        (json['conditions'] as List<dynamic>)
            .map((c) => WaitFor.fromJson(c as Map<String, dynamic>))
            .toList(),
      ),
      _ => throw ArgumentError('Unknown WaitFor type: $type'),
    };
  }
}

/// Wait until effective credits (GP + sellable inventory) reaches a target.
/// Used for: upgrade becomes affordable, GP goal reached.
///
/// Carries the [sellPolicy] to ensure consistent semantics between
/// boundary detection (WatchSet) and satisfaction checking.
@immutable
class WaitForEffectiveCredits extends WaitFor {
  const WaitForEffectiveCredits(
    this.targetValue, {
    required this.sellPolicy,
    this.reason = 'Upgrade',
  });

  final int targetValue;

  /// Why we're waiting for this value (for display).
  final String reason;

  /// The sell policy used to compute effective credits.
  ///
  /// This must match the policy used by WatchSet for boundary detection
  /// to ensure consistent affordability semantics.
  final SellPolicy sellPolicy;

  @override
  bool isSatisfied(GlobalState state) {
    return effectiveCredits(state, sellPolicy) >= targetValue;
  }

  @override
  int progress(GlobalState state) => effectiveCredits(state, sellPolicy);

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentValue = effectiveCredits(state, sellPolicy);
    final needed = targetValue - currentValue;
    if (needed <= 0) return 0;

    // Use floor-corrected rates to match what _advanceExpected actually
    // produces.
    //
    // The issue: valuePerTick uses continuous fractional rates (e.g.,
    // 0.0001667 bird nests/tick at 350 GP = 0.058 GP/tick). But
    // _advanceExpected floors item counts, so in 546 ticks we get
    // floor(0.09) = 0 bird nests = 0 GP.
    //
    // Fix: Exclude rare drops that take too long to produce even 1 item.
    // Only include items where we expect to get at least 1 within a
    // reasonable horizon. This prevents overestimating income from rare
    // high-value drops.
    //
    // Threshold: 1000 ticks (~1.6 minutes real time). Items that take longer
    // than this to produce 1 of are excluded from short-term estimates.
    const maxTicksPerItem = 1000;

    var effectiveValueRate = rates.directGpPerTick;
    for (final entry in rates.itemFlowsPerTick.entries) {
      final flowRate = entry.value;
      if (flowRate <= 0) continue;

      final ticksPerItem = 1.0 / flowRate;
      if (ticksPerItem > maxTicksPerItem) {
        // Skip rare items - they won't contribute reliably in short term
        continue;
      }

      final itemId = entry.key;
      final item = state.registries.items.byId(itemId);
      effectiveValueRate += flowRate * item.sellsFor;
    }

    // Subtract consumed items
    for (final entry in rates.itemsConsumedPerTick.entries) {
      final consumeRate = entry.value;
      if (consumeRate <= 0) continue;

      final itemId = entry.key;
      final item = state.registries.items.byId(itemId);
      effectiveValueRate -= consumeRate * item.sellsFor;
    }

    if (effectiveValueRate <= 0) return infTicks;

    return (needed / effectiveValueRate).ceil();
  }

  @override
  String describe() => 'credits >= $targetValue';

  @override
  String get shortDescription => '$reason affordable';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForEffectiveCredits',
    'targetValue': targetValue,
    'reason': reason,
    'sellPolicy': sellPolicy.toJson(),
  };

  @override
  List<Object?> get props => [targetValue, sellPolicy];
}

/// Wait until a skill reaches a target XP amount.
/// Used for: skill level up, activity unlock, goal reached.
@immutable
class WaitForSkillXp extends WaitFor {
  const WaitForSkillXp(this.skill, this.targetXp, {this.reason});

  final Skill skill;
  final int targetXp;

  /// Optional reason (e.g., 'Oak Tree unlocks'). If null, shows 'Skill +1'.
  final String? reason;

  @override
  bool isSatisfied(GlobalState state) {
    return state.skillState(skill).xp >= targetXp;
  }

  @override
  int progress(GlobalState state) => state.skillState(skill).xp;

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentXp = state.skillState(skill).xp;
    final needed = targetXp - currentXp;
    if (needed <= 0) return 0;

    final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;
    if (xpRate <= 0) return infTicks;

    return (needed / xpRate).ceil();
  }

  @override
  String describe() => '${skill.name} XP >= $targetXp';

  @override
  String get shortDescription => reason ?? 'Skill +1';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForSkillXp',
    'skill': skill.name,
    'targetXp': targetXp,
    'reason': reason,
  };

  @override
  List<Object?> get props => [skill, targetXp];
}

/// Wait until mastery for an action reaches a target XP amount.
@immutable
class WaitForMasteryXp extends WaitFor {
  const WaitForMasteryXp(this.actionId, this.targetMasteryXp);

  final ActionId actionId;
  final int targetMasteryXp;

  @override
  bool isSatisfied(GlobalState state) {
    return state.actionState(actionId).masteryXp >= targetMasteryXp;
  }

  @override
  int progress(GlobalState state) => state.actionState(actionId).masteryXp;

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentXp = state.actionState(actionId).masteryXp;
    final needed = targetMasteryXp - currentXp;
    if (needed <= 0) return 0;

    final masteryRate = rates.masteryXpPerTick;
    if (masteryRate <= 0) return infTicks;

    return (needed / masteryRate).ceil();
  }

  @override
  String describe() {
    // This isn't the real name, but it's close enough for debugging.
    final actionName = actionId.localId.name;
    return '$actionName mastery XP >= $targetMasteryXp';
  }

  @override
  String get shortDescription => 'Mastery +1';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForMasteryXp',
    'actionId': actionId.toJson(),
    'targetMasteryXp': targetMasteryXp,
  };

  @override
  List<Object?> get props => [actionId, targetMasteryXp];
}

/// Wait until inventory usage reaches a threshold fraction.
@immutable
class WaitForInventoryThreshold extends WaitFor {
  const WaitForInventoryThreshold(this.threshold);

  /// Fraction of inventory capacity (0.0 to 1.0).
  final double threshold;

  @override
  bool isSatisfied(GlobalState state) {
    if (state.inventoryCapacity <= 0) return false;
    final usedFraction = state.inventoryUsed / state.inventoryCapacity;
    return usedFraction >= threshold;
  }

  @override
  int progress(GlobalState state) => state.inventoryUsed;

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    if (state.inventoryCapacity <= 0) return infTicks;
    final targetSlots = (threshold * state.inventoryCapacity).ceil();
    final neededSlots = targetSlots - state.inventoryUsed;
    if (neededSlots <= 0) return 0;

    final slotsPerTick = rates.itemTypesPerTick;
    if (slotsPerTick <= 0) return infTicks;

    return (neededSlots / slotsPerTick).ceil();
  }

  @override
  String describe() => 'inventory >= ${(threshold * 100).toInt()}%';

  @override
  String get shortDescription => 'Inventory threshold';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForInventoryThreshold',
    'threshold': threshold,
  };

  @override
  List<Object?> get props => [threshold];
}

/// Wait until inventory is completely full.
@immutable
class WaitForInventoryFull extends WaitFor {
  const WaitForInventoryFull();

  @override
  bool isSatisfied(GlobalState state) {
    return state.inventoryRemaining <= 0;
  }

  @override
  int progress(GlobalState state) => state.inventoryUsed;

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final neededSlots = state.inventoryRemaining;
    if (neededSlots <= 0) return 0;

    final slotsPerTick = rates.itemTypesPerTick;
    if (slotsPerTick <= 0) return infTicks;

    return (neededSlots / slotsPerTick).ceil();
  }

  @override
  String describe() => 'inventory full';

  @override
  String get shortDescription => 'Inventory full';

  @override
  Map<String, dynamic> toJson() => {'type': 'WaitForInventoryFull'};

  @override
  List<Object?> get props => [];
}

/// Wait until goal is reached. This is a terminal wait.
@immutable
class WaitForGoal extends WaitFor {
  const WaitForGoal(this.goal);

  final Goal goal;

  @override
  bool isSatisfied(GlobalState state) => goal.isSatisfied(state);

  @override
  int progress(GlobalState state) => goal.progress(state);

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final remaining = goal.remaining(state);
    if (remaining <= 0) return 0;

    final progressRate = goal.progressPerTick(state, rates);
    if (progressRate <= 0) return infTicks;

    return (remaining / progressRate).ceil();
  }

  @override
  String describe() => goal.describe();

  @override
  String get shortDescription => 'Goal reached';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForGoal',
    'goal': goal.toJson(),
  };

  @override
  List<Object?> get props => [goal];
}

/// Wait until inputs for the current action are depleted.
/// Used for consuming actions (firemaking, cooking, etc.) to signal when
/// the solver should switch to a producer action.
@immutable
class WaitForInputsDepleted extends WaitFor {
  const WaitForInputsDepleted(this.actionId);

  final ActionId actionId;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    // Inputs are depleted when we can no longer start the action
    return !state.canStartAction(action);
  }

  @override
  int progress(GlobalState state) => 0; // Not a goal-oriented condition

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return infTicks;

    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) return infTicks; // Non-consuming action

    // Find minimum ticks based on available inputs
    var minInputTicks = infTicks;
    final actionDurationTicks = action.minDuration.inMilliseconds ~/ msPerTick;

    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      final consumedPerAction = entry.value;
      final consumedPerTick =
          consumedPerAction / actionDurationTicks.toDouble();

      if (consumedPerTick > 0) {
        final ticksUntilDepleted = (available / consumedPerTick).floor();
        if (ticksUntilDepleted < minInputTicks) {
          minInputTicks = ticksUntilDepleted;
        }
      }
    }

    return minInputTicks;
  }

  @override
  String describe() => 'inputs depleted for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Inputs depleted';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForInputsDepleted',
    'actionId': actionId.toJson(),
  };

  @override
  List<Object?> get props => [actionId];
}

/// Wait until inputs for a consuming action become available.
/// Used when a producer action is gathering inputs for a consuming action.
@immutable
class WaitForInputsAvailable extends WaitFor {
  const WaitForInputsAvailable(this.actionId);

  final ActionId actionId;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    // Inputs are available when we can start the action
    return state.canStartAction(action);
  }

  // Binary condition, no meaningful progress
  @override
  int progress(GlobalState state) => 0;

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    // If inputs are already available, no waiting needed
    if (isSatisfied(state)) return 0;

    // This is typically used when gathering inputs with a producer action.
    // The estimate depends on the production rate of the current action.
    // For now, return infTicks as a conservative fallback - the actual
    // estimation is usually done at a higher level when planning the
    // producer/consumer cycle.
    return infTicks;
  }

  @override
  String describe() => 'inputs available for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Inputs available';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForInputsAvailable',
    'actionId': actionId.toJson(),
  };

  @override
  List<Object?> get props => [actionId];
}

/// Wait until inventory has at least a certain count of an item.
/// Used during adaptive produce/consume cycles to gather enough inputs
/// before switching back to the consuming action.
@immutable
class WaitForInventoryAtLeast extends WaitFor {
  const WaitForInventoryAtLeast(this.itemId, this.minCount);

  final MelvorId itemId;
  final int minCount;

  @override
  bool isSatisfied(GlobalState state) {
    final count = state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
    return count >= minCount;
  }

  @override
  int progress(GlobalState state) {
    return state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentCount = state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
    final needed = minCount - currentCount;
    if (needed <= 0) return 0;

    // Step 1: Check if the current action can run. If not, executor will
    // terminate immediately with NoProgressPossible/ActionUnavailable.
    final active = state.activeAction;
    if (active != null) {
      final action = state.registries.actions.byId(active.id);
      if (!state.canStartAction(action)) {
        return 0; // Immediate stop - can't make progress
      }
    }

    // Step 2: Check if inventory is full. If no free slots, we'll hit
    // InventoryFull immediately when trying to produce new item types.
    final freeSlots = state.inventoryRemaining;
    if (freeSlots <= 0) {
      return 0; // Immediate stop - inventory full
    }

    // Step 3: Normal EV estimate to reach target count.
    final productionRate = rates.itemFlowsPerTick[itemId] ?? 0.0;
    if (productionRate <= 0) return infTicks;

    final ticksToTarget = (needed / productionRate).ceil();

    // Step 4: Cap by predicted time to inventory full (if producing new types).
    // If the action produces new item types, we may fill inventory before
    // reaching the target count.
    final typesPerTick = rates.itemTypesPerTick;
    if (typesPerTick > 0) {
      final ticksToFull = (freeSlots / typesPerTick).floor();
      // Return the minimum: either we hit target or inventory fills first.
      if (ticksToFull < ticksToTarget) {
        // Cap at ticksToFull, but ensure we return at least 0.
        return ticksToFull.clamp(0, infTicks);
      }
    }

    return ticksToTarget;
  }

  @override
  String describe() => '${itemId.localId} count >= $minCount';

  @override
  String get shortDescription => 'Inventory at least $minCount';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForInventoryAtLeast',
    'itemId': itemId.toJson(),
    'minCount': minCount,
  };

  @override
  List<Object?> get props => [itemId, minCount];
}

/// Wait until inventory count of an item has increased by a delta amount.
///
/// Uses delta semantics: targetCount = startCount + delta.
/// This is the correct semantics for AcquireItem - "acquire N more items".
///
/// The [startCount] is captured at creation time and remains fixed.
/// This prevents the condition from being affected by items already present.
@immutable
class WaitForInventoryDelta extends WaitFor {
  /// Creates a wait condition for acquiring [delta] more of [itemId].
  ///
  /// [startCount] is the inventory count at the time this was created.
  /// The condition is satisfied when count >= startCount + delta.
  const WaitForInventoryDelta(
    this.itemId,
    this.delta, {
    required this.startCount,
  });

  /// Factory that captures the current inventory count from state.
  factory WaitForInventoryDelta.fromState(
    GlobalState state,
    MelvorId itemId,
    int delta,
  ) {
    final currentCount = _countItem(state, itemId);
    return WaitForInventoryDelta(itemId, delta, startCount: currentCount);
  }

  final MelvorId itemId;

  /// How many items to acquire (delta from startCount).
  final int delta;

  /// Inventory count at the time this condition was created.
  final int startCount;

  /// Target count: startCount + delta.
  int get targetCount => startCount + delta;

  static int _countItem(GlobalState state, MelvorId itemId) {
    return state.inventory.items
        .where((s) => s.item.id == itemId)
        .map((s) => s.count)
        .fold(0, (a, b) => a + b);
  }

  @override
  bool isSatisfied(GlobalState state) {
    return _countItem(state, itemId) >= targetCount;
  }

  @override
  int progress(GlobalState state) {
    return _countItem(state, itemId);
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    final currentCount = _countItem(state, itemId);
    final needed = targetCount - currentCount;
    if (needed <= 0) return 0;

    // Step 1: Check if the current action can run. If not, executor will
    // terminate immediately with NoProgressPossible/ActionUnavailable.
    final active = state.activeAction;
    if (active != null) {
      final action = state.registries.actions.byId(active.id);
      if (!state.canStartAction(action)) {
        return 0; // Immediate stop - can't make progress
      }
    }

    // Step 2: Check if inventory is full. If no free slots, we'll hit
    // InventoryFull immediately when trying to produce new item types.
    final freeSlots = state.inventoryRemaining;
    if (freeSlots <= 0) {
      return 0; // Immediate stop - inventory full
    }

    // Step 3: Normal EV estimate to reach target count.
    final productionRate = rates.itemFlowsPerTick[itemId] ?? 0.0;
    if (productionRate <= 0) return infTicks;

    final ticksToTarget = (needed / productionRate).ceil();

    // Step 4: Cap by predicted time to inventory full (if producing new types).
    // If the action produces new item types, we may fill inventory before
    // reaching the target count.
    final typesPerTick = rates.itemTypesPerTick;
    if (typesPerTick > 0) {
      final ticksToFull = (freeSlots / typesPerTick).floor();
      // Return the minimum: either we hit target or inventory fills first.
      if (ticksToFull < ticksToTarget) {
        // Cap at ticksToFull, but ensure we return at least 0.
        return ticksToFull.clamp(0, infTicks);
      }
    }

    return ticksToTarget;
  }

  @override
  String describe() => '${itemId.localId}: $startCount + $delta = $targetCount';

  @override
  String get shortDescription => 'Acquire +$delta';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForInventoryDelta',
    'itemId': itemId.toJson(),
    'delta': delta,
    'startCount': startCount,
  };

  @override
  List<Object?> get props => [itemId, delta, startCount];
}

/// Wait until we have enough inputs to complete the goal via a consuming
/// action. Used when a producer action needs to gather sufficient inputs before
/// switching to the consuming action to complete the skill goal.
@immutable
class WaitForSufficientInputs extends WaitFor {
  const WaitForSufficientInputs(this.actionId, this.targetCount);

  final ActionId actionId;
  final int targetCount;

  @override
  bool isSatisfied(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return false;

    // Get the inputs needed for this action
    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    // Check if we have enough of all inputs
    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      // We need at least targetCount of the primary input
      // (for simplicity, check if we have enough to run targetCount actions)
      final neededPerAction = entry.value;
      if (available <
          targetCount * neededPerAction / inputs.length.toDouble()) {
        return false;
      }
    }
    return true;
  }

  @override
  int progress(GlobalState state) {
    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return 0;

    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) return 0;

    // Return minimum available count across all inputs
    var minAvailable = 0x7FFFFFFF; // max int
    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      if (available < minAvailable) minAvailable = available;
    }
    return minAvailable;
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    if (isSatisfied(state)) return 0;

    final action = state.registries.actions.byId(actionId);
    if (action is! SkillAction) return infTicks;

    // Step 1: Check if the current action can run. If not, executor will
    // terminate immediately with NoProgressPossible/ActionUnavailable.
    final active = state.activeAction;
    if (active != null) {
      final activeAction = state.registries.actions.byId(active.id);
      if (!state.canStartAction(activeAction)) {
        return 0; // Immediate stop - can't make progress
      }
    }

    // Step 2: Check if inventory is full. If no free slots, we'll hit
    // InventoryFull immediately when trying to produce new item types.
    final freeSlots = state.inventoryRemaining;
    if (freeSlots <= 0) {
      return 0; // Immediate stop - inventory full
    }

    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) return 0;

    // Find the bottleneck input (longest time to gather)
    var maxTicks = 0;
    for (final entry in inputs.entries) {
      final item = state.registries.items.byId(entry.key);
      final available = state.inventory.countOfItem(item);
      final neededPerAction = entry.value;
      final totalNeeded = (targetCount * neededPerAction / inputs.length)
          .ceil();
      final needed = totalNeeded - available;
      if (needed <= 0) continue;

      final productionRate = rates.itemFlowsPerTick[entry.key] ?? 0.0;
      if (productionRate <= 0) return infTicks;

      final ticks = (needed / productionRate).ceil();
      if (ticks > maxTicks) maxTicks = ticks;
    }

    // Step 3: Cap by predicted time to inventory full (if producing new types).
    final typesPerTick = rates.itemTypesPerTick;
    if (typesPerTick > 0 && maxTicks > 0) {
      final ticksToFull = (freeSlots / typesPerTick).floor();
      if (ticksToFull < maxTicks) {
        return ticksToFull.clamp(0, infTicks);
      }
    }

    return maxTicks;
  }

  @override
  String describe() =>
      'sufficient inputs ($targetCount) for ${actionId.localId.name}';

  @override
  String get shortDescription => 'Sufficient inputs';

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForSufficientInputs',
    'actionId': actionId.toJson(),
    'targetCount': targetCount,
  };

  @override
  List<Object?> get props => [actionId, targetCount];
}

/// Wait until ANY of the given conditions is satisfied.
///
/// Used for macro-step planning where we want to stop training when the
/// soonest of several conditions triggers (e.g., "next boundary OR upgrade
/// affordable OR inputs depleted").
class WaitForAnyOf extends WaitFor {
  const WaitForAnyOf(this.conditions);

  final List<WaitFor> conditions;

  @override
  bool isSatisfied(GlobalState state) {
    // Satisfied if ANY condition is met
    return conditions.any((condition) => condition.isSatisfied(state));
  }

  @override
  WaitFor? findSatisfied(GlobalState state) {
    // Return the first satisfied child condition (recursively)
    for (final condition in conditions) {
      final satisfied = condition.findSatisfied(state);
      if (satisfied != null) return satisfied;
    }
    return null;
  }

  @override
  int progress(GlobalState state) {
    if (conditions.isEmpty) return 0;
    // Return max progress among all conditions (closest to being satisfied)
    return conditions
        .map((c) => c.progress(state))
        .reduce((a, b) => a > b ? a : b);
  }

  @override
  int estimateTicks(GlobalState state, Rates rates) {
    if (conditions.isEmpty) return infTicks;

    // Return minimum ticks among all conditions (first to trigger wins)
    var minTicks = infTicks;
    for (final condition in conditions) {
      final ticks = condition.estimateTicks(state, rates);
      if (ticks < minTicks) {
        minTicks = ticks;
      }
    }
    return minTicks;
  }

  @override
  String describe() {
    final descriptions = conditions.map((c) => c.describe()).join(' OR ');
    return 'any of ($descriptions)';
  }

  @override
  String get shortDescription {
    // Use the first condition's short description for brevity
    return conditions.isNotEmpty
        ? conditions.first.shortDescription
        : 'Any condition';
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'WaitForAnyOf',
    'conditions': conditions.map((c) => c.toJson()).toList(),
  };

  @override
  List<Object?> get props => [conditions];
}
