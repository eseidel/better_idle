/// Wait-time selector: computes the soonest "interesting" time to re-evaluate.
///
/// ## Purpose
///
/// Computes **one** wait delta: the soonest time a replan might be beneficial.
/// Uses [Candidates.watch] sets to define "interesting events" (goal, unlock,
/// affordability, inventory, death/stop, skill level, mastery level).
///
/// Must be cheap and non-simulating.
///
/// ## Critical Invariant: dt=0 Rule
///
/// `dt == 0` is only allowed when some **immediate interaction** exists
/// (planner can do something now).
///
/// Affordable upgrades that are merely "watched" must not force dt=0.
/// In practice: if upgrade is affordable but not in [Candidates.buyUpgrades],
/// ignore it for dt=0 (still relevant for time-to-afford when not yet
/// affordable).
///
/// Watch lists can contain already-affordable items; that should not cause
/// solver churn.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';

import 'enumerate_candidates.dart';
import 'estimate_rates.dart';
import 'goal.dart';
import 'plan.dart';
import 'value_model.dart';

/// Sentinel value for "infinite" ticks (no progress possible).
const int infTicks = 1 << 60;

/// A candidate delta (time until some event occurs).
class _DeltaCandidate {
  const _DeltaCandidate({required this.ticks, required this.waitFor});

  final int ticks;
  final WaitFor waitFor;
}

/// Result of nextDecisionDelta computation with explanation.
class NextDecisionResult {
  const NextDecisionResult({required this.deltaTicks, required this.waitFor});

  /// The number of ticks to wait (0 if immediate action available).
  final int deltaTicks;

  /// What we're waiting for.
  final WaitFor waitFor;

  bool get isImmediate => deltaTicks == 0;
  bool get isDeadEnd => deltaTicks == infTicks;
}

/// Computes the next "interesting" time to re-evaluate the plan.
///
/// Returns 0 if:
/// - Goal is already satisfied
/// - Any candidate interaction is available right now
///
/// Otherwise returns the smallest positive delta among:
/// - Time until goal reached
/// - Time until any watched upgrade becomes affordable
/// - Time until any watched locked activity unlocks
/// - Time until inventory fills (if watching)
/// - Time until activity stops (death from thieving)
/// - Time until next skill level (rates may change)
/// - Time until next mastery level (rates may change, especially for thieving)
///
/// Returns [infTicks] if no progress is possible.
NextDecisionResult nextDecisionDelta(
  GlobalState state,
  Goal goal,
  Candidates candidates, {
  ValueModel valueModel = defaultValueModel,
}) {
  // Check if goal is already satisfied
  if (goal.isSatisfied(state)) {
    return NextDecisionResult(deltaTicks: 0, waitFor: WaitForGoal(goal));
  }

  // Check for immediate availability (upgrades already affordable)
  // Only consider upgrades that are competitive (in buyUpgrades), not the
  // broader watch list which includes all potentially useful upgrades.
  final shopRegistry = state.registries.shop;
  for (final purchaseId in candidates.buyUpgrades) {
    final purchase = shopRegistry.byId(purchaseId);
    if (purchase == null) continue;
    final cost = purchase.cost.gpCost;
    if (cost != null && state.gp >= cost) {
      return NextDecisionResult(
        deltaTicks: 0,
        waitFor: WaitForInventoryValue(cost, reason: purchase.name),
      );
    }
  }

  // Check for immediate SellAll availability
  if (candidates.includeSellAll) {
    final usedFraction = state.inventoryCapacity > 0
        ? state.inventoryUsed / state.inventoryCapacity
        : 0.0;
    if (usedFraction >= defaultInventoryThreshold) {
      return NextDecisionResult(
        deltaTicks: 0,
        waitFor: const WaitForInventoryThreshold(defaultInventoryThreshold),
      );
    }
  }

  // Get current rates and compute progress rate toward goal
  final rates = estimateRates(state);
  final progressRate = goal.progressPerTick(state, rates);
  // Value rate is still needed for upgrade affordability calculations
  final valueRate = valueModel.valuePerTick(state, rates);

  // Compute deltas for each category
  final deltas = <_DeltaCandidate>[];

  // A) Time until goal reached
  final deltaGoal = _deltaUntilGoal(state, goal, progressRate);
  if (deltaGoal != null && deltaGoal > 0) {
    deltas.add(_DeltaCandidate(ticks: deltaGoal, waitFor: WaitForGoal(goal)));
  }

  // B) Time until any watched upgrade becomes affordable
  final deltaUpgrade = _deltaUntilUpgradeAffordable(
    state,
    candidates,
    valueRate,
  );
  if (deltaUpgrade != null) {
    deltas.add(deltaUpgrade);
  }

  // C) Time until any watched locked activity unlocks
  final deltaUnlock = _deltaUntilActivityUnlocks(state, candidates, rates);
  if (deltaUnlock != null) {
    deltas.add(deltaUnlock);
  }

  // D) Time until inventory fills (if watching)
  if (candidates.watch.inventory) {
    final deltaInv = _deltaUntilInventoryFull(state, rates);
    if (deltaInv != null && deltaInv > 0) {
      deltas.add(
        _DeltaCandidate(ticks: deltaInv, waitFor: const WaitForInventoryFull()),
      );
    }
  }

  // Note: Death is NOT a decision point - it's handled automatically during
  // plan execution by restarting the activity. The planner still accounts for
  // death in expected-value calculations via ticksUntilDeath in _advanceExpected.

  // E) Time until inputs depleted (for consuming actions)
  final deltaInputsDepleted = _deltaUntilInputsDepleted(state, rates);
  if (deltaInputsDepleted != null) {
    deltas.add(deltaInputsDepleted);
  }

  // E2) Time until inputs available for watched consuming activities
  final deltaInputsAvailable = _deltaUntilInputsAvailable(
    state,
    candidates,
    rates,
  );
  if (deltaInputsAvailable != null) {
    deltas.add(deltaInputsAvailable);
  }

  // F) Time until next skill level that unlocks a watched activity
  final deltaSkillLevel = _deltaUntilNextSkillLevel(state, rates, candidates);
  if (deltaSkillLevel != null) {
    deltas.add(deltaSkillLevel);
  }

  // G) Time until next mastery level (rates may change, especially for thieving)
  final deltaMasteryLevel = _deltaUntilNextMasteryLevel(state, rates);
  if (deltaMasteryLevel != null) {
    deltas.add(deltaMasteryLevel);
  }

  // Find minimum positive delta
  if (deltas.isEmpty) {
    // Dead end - use the goal but with infinite ticks
    return NextDecisionResult(deltaTicks: infTicks, waitFor: WaitForGoal(goal));
  }

  deltas.sort((a, b) => a.ticks.compareTo(b.ticks));
  final best = deltas.first;

  // Ensure at least 1 tick (avoid returning 0 unless immediate)
  final finalDelta = best.ticks < 1 ? 1 : best.ticks;

  return NextDecisionResult(deltaTicks: finalDelta, waitFor: best.waitFor);
}

/// Computes ticks until goal is reached at current progress rate.
int? _deltaUntilGoal(GlobalState state, Goal goal, double progressRate) {
  if (progressRate <= 0) return null;
  if (goal.isSatisfied(state)) return 0;

  final remaining = goal.remaining(state);
  return _ceilDiv(remaining, progressRate);
}

/// Computes ticks until soonest watched upgrade becomes affordable.
_DeltaCandidate? _deltaUntilUpgradeAffordable(
  GlobalState state,
  Candidates candidates,
  double valueRate,
) {
  if (valueRate <= 0) return null;

  int? minDelta;
  String? minUpgradeName;
  int? minUpgradeCost;

  final shopRegistry = state.registries.shop;
  for (final purchaseId in candidates.watch.upgradePurchaseIds) {
    final purchase = shopRegistry.byId(purchaseId);
    if (purchase == null) continue;

    final cost = purchase.cost.gpCost;
    if (cost == null) continue; // Skip special pricing

    if (state.gp >= cost) {
      // Already affordable - should have been caught above
      continue;
    }

    final needed = cost - state.gp;
    final delta = _ceilDiv(needed.toDouble(), valueRate);

    if (minDelta == null || delta < minDelta) {
      minDelta = delta;
      minUpgradeName = purchase.name;
      minUpgradeCost = cost;
    }
  }

  if (minDelta == null || minUpgradeCost == null) return null;
  return _DeltaCandidate(
    ticks: minDelta,
    waitFor: WaitForInventoryValue(minUpgradeCost, reason: minUpgradeName!),
  );
}

/// Computes ticks until soonest watched locked activity unlocks.
_DeltaCandidate? _deltaUntilActivityUnlocks(
  GlobalState state,
  Candidates candidates,
  Rates rates,
) {
  int? minDelta;
  String? minActivityName;
  Skill? minSkill;
  int? minTargetXp;
  final actionRegistry = state.registries.actions;
  for (final activityId in candidates.watch.lockedActivityIds) {
    final action = actionRegistry.byId(activityId);
    if (action is! SkillAction) continue;
    final skill = action.skill;
    final requiredLevel = action.unlockLevel;
    final requiredXp = startXpForLevel(requiredLevel);
    final currentXp = state.skillState(skill).xp;

    if (currentXp >= requiredXp) {
      // Already unlocked - shouldn't happen but handle gracefully
      continue;
    }

    final xpRate = rates.xpPerTickBySkill[skill];
    if (xpRate == null || xpRate <= 0) {
      // Not currently gaining XP in this skill
      continue;
    }

    final xpNeeded = requiredXp - currentXp;
    final delta = _ceilDiv(xpNeeded.toDouble(), xpRate);

    if (minDelta == null || delta < minDelta) {
      minDelta = delta;
      minActivityName = action.name;
      minSkill = skill;
      minTargetXp = requiredXp;
    }
  }

  if (minDelta == null || minSkill == null || minTargetXp == null) return null;
  return _DeltaCandidate(
    ticks: minDelta,
    waitFor: WaitForSkillXp(
      minSkill,
      minTargetXp,
      reason: '$minActivityName unlocks',
    ),
  );
}

/// Computes ticks until next meaningful skill level (unlock threshold).
///
/// Rather than watching every skill level up, we only watch levels that
/// unlock new actions. This reduces the number of wait steps in the plan.
/// Unlock thresholds are determined by the lockedActivityIds in the watch list.
_DeltaCandidate? _deltaUntilNextSkillLevel(
  GlobalState state,
  Rates rates,
  Candidates candidates,
) {
  // Find which skill is being trained
  final actionId = state.activeAction?.id;
  if (actionId == null) return null;

  final registries = state.registries;
  final action = registries.actions.byId(actionId);
  if (action is! SkillAction) return null;

  final skill = action.skill;
  final xpRate = rates.xpPerTickBySkill[skill];
  if (xpRate == null || xpRate <= 0) return null;

  final currentXp = state.skillState(skill).xp;
  final currentLevel = levelForXp(currentXp);

  // Find the next unlock level for any locked activity of this skill
  int? nextUnlockLevel;
  for (final lockedId in candidates.watch.lockedActivityIds) {
    final lockedAction = registries.actions.byId(lockedId);
    if (lockedAction is! SkillAction) continue;
    if (lockedAction.skill != skill) continue;

    final unlockLevel = lockedAction.unlockLevel;
    if (unlockLevel > currentLevel) {
      if (nextUnlockLevel == null || unlockLevel < nextUnlockLevel) {
        nextUnlockLevel = unlockLevel;
      }
    }
  }

  // If no unlock levels are being watched, don't add a skill level wait
  if (nextUnlockLevel == null) return null;

  final targetXp = startXpForLevel(nextUnlockLevel);
  final xpNeeded = targetXp - currentXp;
  if (xpNeeded <= 0) return null;

  final ticks = (xpNeeded / xpRate).ceil();

  return _DeltaCandidate(
    ticks: ticks,
    waitFor: WaitForSkillXp(skill, targetXp, reason: 'Level $nextUnlockLevel'),
  );
}

/// Mastery level interval for watch events.
/// Instead of watching every mastery level, we only watch at these boundaries.
/// This reduces plan noise while still allowing the solver to re-evaluate
/// at meaningful rate changes.
const int _masteryLevelInterval = 10;

/// Computes ticks until next meaningful mastery level boundary.
///
/// Rather than watching every mastery level up, we watch at intervals
/// (e.g., every 10 levels: 10, 20, 30, ...). This reduces the number
/// of wait steps while still allowing rate recalculation at meaningful points.
///
/// For thieving, mastery affects stealth directly, but the effect is gradual
/// enough that checking every 10 levels is sufficient for planning purposes.
_DeltaCandidate? _deltaUntilNextMasteryLevel(GlobalState state, Rates rates) {
  if (rates.masteryXpPerTick <= 0 || rates.actionId == null) return null;

  final actionId = rates.actionId!;
  final actionState = state.actionState(actionId);
  final currentLevel = actionState.masteryLevel;

  // Check if at max mastery level (99)
  if (currentLevel >= 99) return null;

  // Find the next boundary level (multiple of _masteryLevelInterval, or 99)
  final nextBoundary =
      ((currentLevel ~/ _masteryLevelInterval) + 1) * _masteryLevelInterval;
  final targetLevel = nextBoundary > 99 ? 99 : nextBoundary;

  // If we're already at or past the target, no wait needed
  if (currentLevel >= targetLevel) return null;

  final currentXp = actionState.masteryXp;
  final targetXp = startXpForLevel(targetLevel);
  final xpNeeded = targetXp - currentXp;

  if (xpNeeded <= 0) return null;

  final ticks = (xpNeeded / rates.masteryXpPerTick).ceil();

  return _DeltaCandidate(
    ticks: ticks,
    waitFor: WaitForMasteryXp(actionId, targetXp),
  );
}

/// Computes ticks until inventory is full.
int? _deltaUntilInventoryFull(GlobalState state, Rates rates) {
  if (rates.itemTypesPerTick <= 0) return null;

  final slotsRemaining = state.inventoryRemaining;
  if (slotsRemaining <= 0) return 0;

  return _ceilDiv(slotsRemaining.toDouble(), rates.itemTypesPerTick);
}

/// Computes ticks until inputs become available for a watched consuming action.
///
/// When running a producer action (e.g., woodcutting), this calculates when
/// we'll have enough items to start a consuming action (e.g., firemaking).
_DeltaCandidate? _deltaUntilInputsAvailable(
  GlobalState state,
  Candidates candidates,
  Rates rates,
) {
  if (candidates.watch.consumingActivityIds.isEmpty) return null;

  final registries = state.registries;
  int? minTicks;
  ActionId? soonestActionId;

  for (final consumingActionId in candidates.watch.consumingActivityIds) {
    final action = registries.actions.byId(consumingActionId);
    if (action is! SkillAction) continue;

    // Get the inputs needed for this action
    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    // Find the slowest input to acquire (limiting factor)
    int? maxTicksForAction;

    for (final entry in inputs.entries) {
      final itemId = entry.key;
      final needed = entry.value;

      // Get current count (skip if item not in registry)
      final item = registries.items.tryById(itemId);
      if (item == null) continue;
      final available = state.inventory.countOfItem(item);

      if (available >= needed) {
        // Already have enough of this input
        continue;
      }

      final stillNeeded = needed - available;

      // Check if current action produces this item
      final productionRate = rates.itemFlowsPerTick[itemId];
      if (productionRate == null || productionRate <= 0) {
        // Current action doesn't produce this item - can't estimate
        maxTicksForAction = null;
        break;
      }

      final ticksForInput = (stillNeeded / productionRate).ceil();
      if (maxTicksForAction == null || ticksForInput > maxTicksForAction) {
        maxTicksForAction = ticksForInput;
      }
    }

    // If we could estimate time for all inputs of this action
    if (maxTicksForAction != null && maxTicksForAction > 0) {
      if (minTicks == null || maxTicksForAction < minTicks) {
        minTicks = maxTicksForAction;
        soonestActionId = consumingActionId;
      }
    }
  }

  if (minTicks == null || soonestActionId == null) return null;

  return _DeltaCandidate(
    ticks: minTicks,
    waitFor: WaitForInputsAvailable(soonestActionId),
  );
}

/// Computes ticks until inputs are depleted for a consuming action.
///
/// For actions that consume inputs (firemaking, cooking, etc.), this
/// calculates when the inventory will run out of required items based
/// on the consumption rate. Returns null for non-consuming actions.
_DeltaCandidate? _deltaUntilInputsDepleted(GlobalState state, Rates rates) {
  // No consumption means no depletion event
  if (rates.itemsConsumedPerTick.isEmpty) return null;
  if (rates.actionId == null) return null;

  // Find the limiting input (the one that runs out first)
  int? minTicks;

  for (final entry in rates.itemsConsumedPerTick.entries) {
    final itemId = entry.key;
    final consumptionRate = entry.value;

    if (consumptionRate <= 0) continue;

    // Get current inventory count for this item (skip if not in registry)
    final item = state.registries.items.tryById(itemId);
    if (item == null) continue;
    final available = state.inventory.countOfItem(item);

    if (available <= 0) {
      // Already depleted - this shouldn't happen if we're running the action
      return _DeltaCandidate(
        ticks: 0,
        waitFor: WaitForInputsDepleted(rates.actionId!),
      );
    }

    // Calculate ticks until this input is depleted
    final ticksUntilDepleted = (available / consumptionRate).floor();

    if (minTicks == null || ticksUntilDepleted < minTicks) {
      minTicks = ticksUntilDepleted;
    }
  }

  if (minTicks == null || minTicks <= 0) return null;

  return _DeltaCandidate(
    ticks: minTicks,
    waitFor: WaitForInputsDepleted(rates.actionId!),
  );
}

/// Ceiling division for doubles to int.
int _ceilDiv(double numerator, double denominator) {
  if (denominator <= 0) return infTicks;
  return (numerator / denominator).ceil();
}
