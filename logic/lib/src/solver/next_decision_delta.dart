import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/upgrades.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';

import 'enumerate_candidates.dart';
import 'estimate_rates.dart';

/// Sentinel value for "infinite" ticks (no progress possible).
const int infTicks = 1 << 60;

/// A goal for the planner. V0 is "reach X credits".
class Goal {
  const Goal({required this.targetCredits});

  final int targetCredits;
}

/// Result of nextDecisionDelta computation with explanation.
class NextDecisionResult {
  const NextDecisionResult({
    required this.deltaTicks,
    required this.reason,
    this.details,
  });

  /// The number of ticks to wait (0 if immediate action available).
  final int deltaTicks;

  /// Human-readable reason for this delta.
  final String reason;

  /// Optional details (e.g., which upgrade becomes affordable).
  final String? details;

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
///
/// Returns [infTicks] if no progress is possible.
NextDecisionResult nextDecisionDelta(
  GlobalState state,
  Goal goal,
  Candidates candidates,
) {
  // Check if goal is already satisfied
  if (state.gp >= goal.targetCredits) {
    return const NextDecisionResult(
      deltaTicks: 0,
      reason: 'goal_reached',
      details: 'Already have enough credits',
    );
  }

  // Check for immediate availability (upgrades already affordable)
  for (final type in candidates.watch.upgradeTypes) {
    final currentLevel = state.shop.upgradeLevel(type);
    final upgrade = nextUpgrade(type, currentLevel);
    if (upgrade != null && state.gp >= upgrade.cost) {
      return NextDecisionResult(
        deltaTicks: 0,
        reason: 'upgrade_affordable',
        details: '${upgrade.name} is affordable now',
      );
    }
  }

  // Check for immediate SellAll availability
  if (candidates.includeSellAll) {
    final usedFraction = state.inventoryCapacity > 0
        ? state.inventoryUsed / state.inventoryCapacity
        : 0.0;
    if (usedFraction >= defaultInventoryThreshold) {
      return const NextDecisionResult(
        deltaTicks: 0,
        reason: 'inventory_threshold',
        details: 'Inventory above threshold',
      );
    }
  }

  // Get current rates
  final rates = estimateRates(state);

  // Compute deltas for each category
  final deltas = <(int, String, String?)>[];

  // A) Time until goal reached
  final deltaGoal = _deltaUntilGoal(state, goal, rates);
  if (deltaGoal != null && deltaGoal > 0) {
    deltas.add((deltaGoal, 'goal_reached', 'Goal of ${goal.targetCredits} GP'));
  }

  // B) Time until any watched upgrade becomes affordable
  final deltaUpgrade = _deltaUntilUpgradeAffordable(state, candidates, rates);
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
      deltas.add((deltaInv, 'inventory_full', 'Inventory will be full'));
    }
  }

  // E) Time until activity stops (death from thieving)
  final deltaDeath = ticksUntilDeath(state, rates);
  if (deltaDeath != null && deltaDeath > 0) {
    deltas.add((deltaDeath, 'activity_stops', 'Player will die (thieving)'));
  }

  // Find minimum positive delta
  if (deltas.isEmpty) {
    return const NextDecisionResult(
      deltaTicks: infTicks,
      reason: 'dead_end',
      details: 'No progress possible',
    );
  }

  deltas.sort((a, b) => a.$1.compareTo(b.$1));
  final (delta, reason, details) = deltas.first;

  // Ensure at least 1 tick (avoid returning 0 unless immediate)
  final finalDelta = delta < 1 ? 1 : delta;

  return NextDecisionResult(
    deltaTicks: finalDelta,
    reason: reason,
    details: details,
  );
}

/// Computes ticks until goal is reached at current gold rate.
int? _deltaUntilGoal(GlobalState state, Goal goal, Rates rates) {
  if (rates.goldPerTick <= 0) return null;
  if (state.gp >= goal.targetCredits) return 0;

  final needed = goal.targetCredits - state.gp;
  return _ceilDiv(needed.toDouble(), rates.goldPerTick);
}

/// Computes ticks until soonest watched upgrade becomes affordable.
(int, String, String?)? _deltaUntilUpgradeAffordable(
  GlobalState state,
  Candidates candidates,
  Rates rates,
) {
  if (rates.goldPerTick <= 0) return null;

  int? minDelta;
  String? minUpgradeName;

  for (final type in candidates.watch.upgradeTypes) {
    final currentLevel = state.shop.upgradeLevel(type);
    final upgrade = nextUpgrade(type, currentLevel);
    if (upgrade == null) continue;

    if (state.gp >= upgrade.cost) {
      // Already affordable - should have been caught above
      continue;
    }

    final needed = upgrade.cost - state.gp;
    final delta = _ceilDiv(needed.toDouble(), rates.goldPerTick);

    if (minDelta == null || delta < minDelta) {
      minDelta = delta;
      minUpgradeName = upgrade.name;
    }
  }

  if (minDelta == null) return null;
  return (minDelta, 'upgrade_affordable', '$minUpgradeName becomes affordable');
}

/// Computes ticks until soonest watched locked activity unlocks.
(int, String, String?)? _deltaUntilActivityUnlocks(
  GlobalState state,
  Candidates candidates,
  Rates rates,
) {
  int? minDelta;
  String? minActivityName;

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
    }
  }

  if (minDelta == null) return null;
  return (minDelta, 'activity_unlocks', '$minActivityName unlocks');
}

/// Computes ticks until inventory is full.
int? _deltaUntilInventoryFull(GlobalState state, Rates rates) {
  if (rates.itemsPerTick <= 0) return null;

  final slotsRemaining = state.inventoryRemaining;
  if (slotsRemaining <= 0) return 0;

  return _ceilDiv(slotsRemaining.toDouble(), rates.itemsPerTick);
}

/// Ceiling division for doubles to int.
int _ceilDiv(double numerator, double denominator) {
  if (denominator <= 0) return infTicks;
  return (numerator / denominator).ceil();
}
