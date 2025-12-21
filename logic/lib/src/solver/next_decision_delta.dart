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

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/upgrades.dart';
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
  Registries registries,
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
  for (final type in candidates.buyUpgrades) {
    final currentLevel = state.shop.upgradeLevel(type);
    final upgrade = nextUpgrade(type, currentLevel);
    if (upgrade != null && state.gp >= upgrade.cost) {
      return NextDecisionResult(
        deltaTicks: 0,
        waitFor: WaitForInventoryValue(upgrade.cost, reason: upgrade.name),
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
  final rates = estimateRates(registries, state);
  final progressRate = goal.progressPerTick(registries.items, state, rates);
  // Value rate is still needed for upgrade affordability calculations
  final valueRate = valueModel.valuePerTick(registries.items, state, rates);

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
  final deltaUnlock = _deltaUntilActivityUnlocks(
    registries,
    state,
    candidates,
    rates,
  );
  if (deltaUnlock != null) {
    deltas.add(deltaUnlock);
  }

  // D) Time until inventory fills (if watching)
  if (candidates.watch.inventory) {
    final deltaInv = _deltaUntilInventoryFull(registries, state, rates);
    if (deltaInv != null && deltaInv > 0) {
      deltas.add(
        _DeltaCandidate(ticks: deltaInv, waitFor: const WaitForInventoryFull()),
      );
    }
  }

  // Note: Death is NOT a decision point - it's handled automatically during
  // plan execution by restarting the activity. The planner still accounts for
  // death in expected-value calculations via ticksUntilDeath in _advanceExpected.

  // F) Time until next skill level (rates may change)
  final deltaSkillLevel = _deltaUntilNextSkillLevel(registries, state, rates);
  if (deltaSkillLevel != null) {
    deltas.add(deltaSkillLevel);
  }

  // G) Time until next mastery level (rates may change, especially for thieving)
  final deltaMasteryLevel = _deltaUntilNextMasteryLevel(
    registries,
    state,
    rates,
  );
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

  for (final type in candidates.watch.upgradeTypes) {
    final currentLevel = state.shop.upgradeLevel(type);
    final upgrade = nextUpgrade(type, currentLevel);
    if (upgrade == null) continue;

    if (state.gp >= upgrade.cost) {
      // Already affordable - should have been caught above
      continue;
    }

    final needed = upgrade.cost - state.gp;
    final delta = _ceilDiv(needed.toDouble(), valueRate);

    if (minDelta == null || delta < minDelta) {
      minDelta = delta;
      minUpgradeName = upgrade.name;
      minUpgradeCost = upgrade.cost;
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
  Registries registries,
  GlobalState state,
  Candidates candidates,
  Rates rates,
) {
  int? minDelta;
  String? minActivityName;
  Skill? minSkill;
  int? minTargetXp;
  final actionRegistry = registries.actions;
  for (final activityName in candidates.watch.lockedActivityNames) {
    final action = actionRegistry.skillActionByName(activityName);
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
      minActivityName = activityName;
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

/// Computes ticks until next skill level.
_DeltaCandidate? _deltaUntilNextSkillLevel(
  Registries registries,
  GlobalState state,
  Rates rates,
) {
  final ticks = ticksUntilNextSkillLevel(state, rates);
  if (ticks == null || ticks <= 0) return null;

  // Find which skill is being trained
  final actionName = state.activeAction?.name;
  if (actionName == null) return null;

  final action = registries.actions.byName(actionName);
  if (action is! SkillAction) return null;

  final skill = action.skill;
  final currentXp = state.skillState(skill).xp;
  final currentLevel = levelForXp(currentXp);
  final nextLevelXp = startXpForLevel(currentLevel + 1);

  return _DeltaCandidate(
    ticks: ticks,
    waitFor: WaitForSkillXp(skill, nextLevelXp),
  );
}

/// Computes ticks until next mastery level.
_DeltaCandidate? _deltaUntilNextMasteryLevel(
  Registries registries,
  GlobalState state,
  Rates rates,
) {
  final ticks = ticksUntilNextMasteryLevel(state, rates);
  if (ticks == null || ticks <= 0) return null;

  // Find which action is being performed
  final actionName = state.activeAction?.name;
  if (actionName == null) return null;

  final currentMasteryXp = state.actionState(actionName).masteryXp;
  final currentLevel = levelForXp(currentMasteryXp);
  final nextLevelXp = startXpForLevel(currentLevel + 1);

  return _DeltaCandidate(
    ticks: ticks,
    waitFor: WaitForMasteryXp(actionName, nextLevelXp),
  );
}

/// Computes ticks until inventory is full.
int? _deltaUntilInventoryFull(
  Registries registries,
  GlobalState state,
  Rates rates,
) {
  if (rates.itemTypesPerTick <= 0) return null;

  final slotsRemaining = state.inventoryRemaining;
  if (slotsRemaining <= 0) return 0;

  return _ceilDiv(slotsRemaining.toDouble(), rates.itemTypesPerTick);
}

/// Ceiling division for doubles to int.
int _ceilDiv(double numerator, double denominator) {
  if (denominator <= 0) return infTicks;
  return (numerator / denominator).ceil();
}
