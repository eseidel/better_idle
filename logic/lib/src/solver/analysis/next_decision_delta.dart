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
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';

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
  const NextDecisionResult({
    required this.deltaTicks,
    required this.waitFor,
    this.intendedAction,
  });

  /// The number of ticks to wait (0 if immediate action available).
  final int deltaTicks;

  /// What we're waiting for.
  final WaitFor waitFor;

  /// The action that should be running during the wait.
  ///
  /// This is the "intended action" - the action that best advances the goal,
  /// which may differ from the currently active action.
  final ActionId? intendedAction;

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
///
/// The [sellPolicy] parameter determines how effective GP is calculated for
/// upgrade affordability. If not provided, defaults to [SellAllPolicy].
/// In segment mode, pass the segment's concrete policy for consistency.
NextDecisionResult nextDecisionDelta(
  GlobalState state,
  Goal goal,
  Candidates candidates, {
  SellPolicy sellPolicy = const SellAllPolicy(),
}) {
  // Check if goal is already satisfied
  if (goal.isSatisfied(state)) {
    return NextDecisionResult(deltaTicks: 0, waitFor: WaitForGoal(goal));
  }

  // Check for immediate availability (upgrades already affordable)
  // Only consider upgrades that are competitive (in buyUpgrades), not the
  // broader watch list which includes all potentially useful upgrades.
  // Note: We check plain state.gp here because this is "can buy right now"
  // (shop requires actual GP, not potential GP from selling).
  final shopRegistry = state.registries.shop;
  for (final purchaseId in candidates.buyUpgrades) {
    final purchase = shopRegistry.byId(purchaseId);
    if (purchase == null) continue;
    final cost = purchase.cost.gpCost;
    if (cost != null && state.gp >= cost) {
      return NextDecisionResult(
        deltaTicks: 0,
        waitFor: WaitForEffectiveCredits(
          cost,
          sellPolicy: sellPolicy,
          reason: purchase.name,
        ),
      );
    }
  }

  // Check for immediate sell availability
  if (candidates.shouldEmitSellCandidate) {
    final usedFraction = state.inventoryCapacity > 0
        ? state.inventoryUsed / state.inventoryCapacity
        : 0.0;
    if (usedFraction >= defaultInventoryThreshold) {
      return const NextDecisionResult(
        deltaTicks: 0,
        waitFor: WaitForInventoryThreshold(defaultInventoryThreshold),
      );
    }
  }

  // Compute the "intended action" - the action that best advances the goal.
  // This may differ from state.activeAction (e.g., after a consuming skill
  // macro ends with producer active, the intent is still the consuming skill).
  final intendedActionId = _computeIntendedAction(state, goal, candidates);

  // Get rates for the intended action (or active action if no intent)
  final rates = intendedActionId != null
      ? estimateRatesForAction(state, intendedActionId)
      : estimateRates(state);
  final progressRate = goal.progressPerTick(state, rates);

  // Get rates for the ACTIVE action (for inputs depleted calculation)
  // This is separate from "intended action" rates because we need to know
  // what the currently running action is consuming, not what we intend to do.
  final activeRates = estimateRates(state);

  // Compute deltas for each category
  final deltas = <_DeltaCandidate>[];

  // A) Time until goal reached
  final goalDelta = _deltaUntilGoalWithWaitFor(state, goal, progressRate);
  if (goalDelta != null && goalDelta.ticks > 0) {
    deltas.add(goalDelta);
  }

  // B) Time until any watched upgrade becomes affordable
  final deltaUpgrade = _deltaUntilUpgradeAffordable(
    state,
    candidates,
    rates,
    sellPolicy,
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
    final deltaInv = _deltaUntilInventoryFull(state, activeRates);
    if (deltaInv != null && deltaInv > 0) {
      deltas.add(
        _DeltaCandidate(ticks: deltaInv, waitFor: const WaitForInventoryFull()),
      );
    }
  }

  // Note: Death is NOT a decision point - it's handled automatically during
  // plan execution by restarting the activity. The planner still accounts for
  // death in expected-value calculations via ticksUntilDeath in
  // [_advanceExpected].

  // E) Time until inputs depleted (for consuming actions)
  // Use activeRates because we want to know if the ACTIVE action runs out of
  // inputs, not the intended action.
  final deltaInputsDepleted = _deltaUntilInputsDepleted(state, activeRates);
  if (deltaInputsDepleted != null) {
    deltas.add(deltaInputsDepleted);
  }

  // E2) Time until inputs available for watched consuming activities
  // Use activeRates because we're checking if the ACTIVE action produces inputs
  final deltaInputsAvailable = _deltaUntilInputsAvailable(
    state,
    candidates,
    activeRates,
  );
  if (deltaInputsAvailable != null) {
    deltas.add(deltaInputsAvailable);
  }

  // E3) Time until sufficient inputs to complete goal via consuming activity
  // Use activeRates because we're checking if the ACTIVE action produces inputs
  final deltaSufficientInputs = _deltaUntilSufficientInputsForGoal(
    state,
    candidates,
    goal,
    activeRates,
  );
  if (deltaSufficientInputs != null) {
    deltas.add(deltaSufficientInputs);
  }

  // F) Time until next skill level that unlocks a watched activity
  final deltaSkillLevel = _deltaUntilNextSkillLevel(state, rates, candidates);
  if (deltaSkillLevel != null) {
    deltas.add(deltaSkillLevel);
  }

  // G) Time until next mastery level - ONLY for thieving where mastery
  // directly affects success rate. For other skills, mastery only provides
  // minor bonuses that don't warrant a replan decision point.
  final deltaMasteryLevel = _deltaUntilNextMasteryLevel(state, rates, goal);
  if (deltaMasteryLevel != null) {
    deltas.add(deltaMasteryLevel);
  }

  // Find minimum positive delta
  if (deltas.isEmpty) {
    // Dead end - use the goal but with infinite ticks
    return NextDecisionResult(
      deltaTicks: infTicks,
      waitFor: WaitForGoal(goal),
      intendedAction: intendedActionId,
    );
  }

  deltas.sort((a, b) => a.ticks.compareTo(b.ticks));
  final best = deltas.first;

  // Ensure at least 1 tick (avoid returning 0 unless immediate)
  final finalDelta = best.ticks < 1 ? 1 : best.ticks;

  return NextDecisionResult(
    deltaTicks: finalDelta,
    waitFor: best.waitFor,
    intendedAction: intendedActionId,
  );
}

/// Computes the "intended action" - the action that best advances the goal.
///
/// This may differ from state.activeAction. For example, after a consuming
/// skill macro ends with producer active, the intent is still the consuming
/// skill (firemaking), not the producer (woodcutting).
///
/// Returns null if the active action is already the best action for the goal.
ActionId? _computeIntendedAction(
  GlobalState state,
  Goal goal,
  Candidates candidates,
) {
  final activeActionId = state.activeAction?.id;

  // For single skill goals, find the best action for that skill
  if (goal is ReachSkillLevelGoal) {
    final targetSkill = goal.skill;

    // For consuming skills, don't set expectedAction from wait edge.
    // TrainConsumingSkillUntil macro handles action selection with proper
    // prerequisite/coupled-loop logic. Setting expectedAction here causes
    // conflicts (e.g., wait edge picks Gold Bar while macro picks Mithril
    // Platebody, leading to thrash loops when Gold Ore depletes).
    if (targetSkill.isConsuming) {
      return null;
    }

    // If active action is for the goal skill and can continue, it's the intent
    if (activeActionId != null) {
      final activeAction = state.registries.actionById(activeActionId);
      if (activeAction is SkillAction && activeAction.skill == targetSkill) {
        // Verify we can still run this action
        if (state.canStartAction(activeAction)) {
          return activeActionId;
        }
        // Active action can't continue (e.g., inputs depleted), find another
      }
    }

    // Find best unlocked action for the target skill
    return _findBestActionForGoalSkill(state, targetSkill, candidates);
  }

  // For multi-skill goals, find the best action for the most pressing subgoal
  if (goal is MultiSkillGoal) {
    // First check if active action is for an unsatisfied subgoal and can run
    if (activeActionId != null) {
      final activeAction = state.registries.actionById(activeActionId);
      if (activeAction is SkillAction && state.canStartAction(activeAction)) {
        final activeSkill = activeAction.skill;
        // Skip consuming skills - let macro handle action selection
        if (!activeSkill.isConsuming) {
          final matchingSubgoal = goal.subgoals
              .where((g) => g.skill == activeSkill && !g.isSatisfied(state))
              .firstOrNull;
          if (matchingSubgoal != null) {
            return activeActionId;
          }
        }
      }
    }

    // Find the first unsatisfied subgoal and get best action for it
    for (final subgoal in goal.subgoals) {
      if (subgoal.isSatisfied(state)) continue;
      // Skip consuming skills - let macro handle action selection
      if (subgoal.skill.isConsuming) continue;
      final bestAction = _findBestActionForGoalSkill(
        state,
        subgoal.skill,
        candidates,
      );
      if (bestAction != null) return bestAction;
    }
  }

  // Default to active action
  return activeActionId;
}

/// Finds the best unlocked action for a given skill.
ActionId? _findBestActionForGoalSkill(
  GlobalState state,
  Skill skill,
  Candidates candidates,
) {
  // For consuming skills, look for the best consuming action
  if (skill.isConsuming) {
    return findBestActionByRate(
      state,
      candidates.switchToActivities,
      rateExtractor: (rates) => rates.xpPerTickBySkill[skill] ?? 0.0,
      skill: skill,
      canStartAction: (state, action) => state.canStartAction(action),
    );
  }

  // For non-consuming skills, find the best producing action
  return findBestActionByRate(
    state,
    candidates.switchToActivities,
    rateExtractor: (rates) => rates.xpPerTickBySkill[skill] ?? 0.0,
    skill: skill,
  );
}

/// Computes ticks until goal is reached at current progress rate.
///
/// For multi-skill goals, computes time until the CURRENT skill being trained
/// reaches its target (not time until all skills are done, which would require
/// switching activities). Returns appropriate WaitFor for plan execution.
///
/// For single skill goals, only returns a delta if the active action is
/// actually training the goal skill. If you're running a producer action
/// for a consuming skill goal, the goal delta should not apply (you need to
/// switch to the consuming action first).
_DeltaCandidate? _deltaUntilGoalWithWaitFor(
  GlobalState state,
  Goal goal,
  double progressRate,
) {
  if (progressRate <= 0) return null;
  if (goal.isSatisfied(state)) return null;

  final actionId = state.activeAction?.id;
  if (actionId == null) return null;

  final registries = state.registries;
  final action = registries.actionById(actionId);
  if (action is! SkillAction) return null;

  final activeSkill = action.skill;

  // For multi-skill goals, only consider skills we're currently training
  if (goal is MultiSkillGoal) {
    // Find the subgoal for the active skill
    final activeSubgoal = goal.subgoals
        .where((g) => g.skill == activeSkill && !g.isSatisfied(state))
        .firstOrNull;

    if (activeSubgoal == null) {
      // Not training a goal skill, or already satisfied
      return null;
    }

    // Return time until THIS skill's goal is reached
    final remaining = activeSubgoal.remaining(state);
    final ticks = _ceilDiv(remaining, progressRate);

    // Use WaitForSkillXp for the specific subgoal, not WaitForGoal
    // This ensures plan execution waits for just this skill
    final skillName = activeSubgoal.skill.name;
    final targetLevel = activeSubgoal.targetLevel;
    return _DeltaCandidate(
      ticks: ticks,
      waitFor: WaitForSkillXp(
        activeSubgoal.skill,
        activeSubgoal.targetXp,
        reason: 'Goal: $skillName $targetLevel',
      ),
    );
  }

  // For single skill goals, only return a delta if the active action is
  // actually training the goal skill
  if (goal is ReachSkillLevelGoal && activeSkill != goal.skill) {
    // Active action is not training the goal skill (e.g., producing logs for
    // firemaking goal) - no goal progress from current action
    return null;
  }

  // Single goal: use WaitForGoal
  final remaining = goal.remaining(state);
  final ticks = _ceilDiv(remaining, progressRate);
  return _DeltaCandidate(ticks: ticks, waitFor: WaitForGoal(goal));
}

/// Computes ticks until soonest watched upgrade becomes affordable.
///
/// Uses [WaitForEffectiveCredits.estimateTicks] to ensure consistency between
/// the estimated ticks and the satisfaction check (both account for flooring
/// of rare item drops).
_DeltaCandidate? _deltaUntilUpgradeAffordable(
  GlobalState state,
  Candidates candidates,
  Rates rates,
  SellPolicy sellPolicy,
) {
  int? minDelta;
  WaitForEffectiveCredits? minWaitFor;

  final shopRegistry = state.registries.shop;
  for (final purchaseId in candidates.watch.upgradePurchaseIds) {
    final purchase = shopRegistry.byId(purchaseId);
    if (purchase == null) continue;

    final cost = purchase.cost.gpCost;
    if (cost == null) continue; // Skip special pricing

    // Create the WaitFor and use its estimateTicks for consistency
    final waitFor = WaitForEffectiveCredits(
      cost,
      sellPolicy: sellPolicy,
      reason: purchase.name,
    );

    // Use the WaitFor's own estimation logic (handles flooring correctly)
    final delta = waitFor.estimateTicks(state, rates);
    if (delta == 0) {
      // Already affordable - should have been caught above
      continue;
    }
    if (delta == infTicks) {
      // Can't afford this upgrade with current rates
      continue;
    }

    if (minDelta == null || delta < minDelta) {
      minDelta = delta;
      minWaitFor = waitFor;
    }
  }

  if (minDelta == null || minWaitFor == null) return null;
  return _DeltaCandidate(ticks: minDelta, waitFor: minWaitFor);
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
  final registries = state.registries;
  for (final activityId in candidates.watch.lockedActivityIds) {
    final action = registries.actionById(activityId);
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
  final action = registries.actionById(actionId);
  if (action is! SkillAction) return null;

  final skill = action.skill;
  final xpRate = rates.xpPerTickBySkill[skill];
  if (xpRate == null || xpRate <= 0) return null;

  final currentXp = state.skillState(skill).xp;
  final currentLevel = levelForXp(currentXp);

  // Find the next unlock level for any locked activity of this skill
  int? nextUnlockLevel;
  for (final lockedId in candidates.watch.lockedActivityIds) {
    final lockedAction = registries.actionById(lockedId);
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
/// ONLY returns a delta for thieving, where mastery directly affects success
/// rate (stealth). For other skills, mastery only provides minor bonuses
/// (like double drops in woodcutting) that don't warrant interrupting the plan.
///
/// For thieving, we watch at intervals (e.g., every 10 levels: 10, 20, 30, ...)
/// to reduce plan noise while still allowing rate recalculation.
_DeltaCandidate? _deltaUntilNextMasteryLevel(
  GlobalState state,
  Rates rates,
  Goal goal,
) {
  if (rates.masteryXpPerTick <= 0 || rates.actionId == null) return null;

  final actionId = rates.actionId!;
  final action = state.registries.actionById(actionId);

  // Only track mastery for thieving - it directly affects success rate.
  // For other skills, mastery bonuses are minor and don't warrant replanning.
  if (action is! ThievingAction) return null;

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

  // Track the limiting item for more robust wait conditions
  MelvorId? limitingItemId;
  int? limitingItemTarget;

  for (final consumingActionId in candidates.watch.consumingActivityIds) {
    final action = registries.actionById(consumingActionId);
    if (action is! SkillAction) continue;

    // Get the inputs needed for this action
    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    // Check if ALL inputs are either already satisfied or being produced
    // Track which item is the limiting factor
    int? maxTicksForAction;
    MelvorId? slowestItemId;
    int? slowestItemTarget;

    for (final entry in inputs.entries) {
      final itemId = entry.key;
      final needed = entry.value;

      // Get current count (skip if item not in registry)
      final item = registries.items.byId(itemId);
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
        slowestItemId = itemId;
        slowestItemTarget = needed;
      }
    }

    // If we could estimate time for all inputs of this action
    if (maxTicksForAction != null && maxTicksForAction > 0) {
      if (minTicks == null || maxTicksForAction < minTicks) {
        minTicks = maxTicksForAction;
        soonestActionId = consumingActionId;
        limitingItemId = slowestItemId;
        limitingItemTarget = slowestItemTarget;
      }
    }
  }

  if (minTicks == null || soonestActionId == null) return null;

  // Use WaitForInventoryAtLeast for the specific item we're producing.
  // This is more robust than WaitForInputsAvailable because it doesn't
  // assume other inputs (that we're not producing) will still be available.
  // The wait condition is: "have at least N of itemX" rather than
  // "can start actionY" which depends on ALL inputs being present.
  if (limitingItemId != null && limitingItemTarget != null) {
    return _DeltaCandidate(
      ticks: minTicks,
      waitFor: WaitForInventoryAtLeast(limitingItemId, limitingItemTarget),
    );
  }

  // Fallback to the original behavior if we couldn't track the limiting item
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
    final item = state.registries.items.byId(itemId);
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

/// Computes ticks until we have enough inputs to reach the goal via a consumer.
///
/// When running a producer action (e.g., woodcutting), this calculates when
/// we'll have enough items to complete the consuming action (e.g., firemaking)
/// all the way to the goal. This is different from [_deltaUntilInputsAvailable]
/// which only waits for enough to start one action.
_DeltaCandidate? _deltaUntilSufficientInputsForGoal(
  GlobalState state,
  Candidates candidates,
  Goal goal,
  Rates rates,
) {
  if (candidates.watch.consumingActivityIds.isEmpty) return null;
  if (goal is! ReachSkillLevelGoal) return null; // Only for skill goals

  final registries = state.registries;
  int? bestTicks;
  ActionId? bestActionId;
  int? bestInputsNeeded;

  for (final consumingActionId in candidates.watch.consumingActivityIds) {
    final action = registries.actionById(consumingActionId);
    if (action is! SkillAction) continue;

    // Only consider actions that train the goal skill
    if (action.skill != goal.skill) continue;

    // Get the inputs needed per action
    final actionStateVal = state.actionState(action.id);
    final selection = actionStateVal.recipeSelection(action);
    final inputs = action.inputsForRecipe(selection);

    if (inputs.isEmpty) continue;

    // Calculate how many actions are needed to reach the goal
    final xpPerAction = action.xp.toDouble();
    if (xpPerAction <= 0) continue;

    final xpNeeded = goal.remaining(state);
    if (xpNeeded <= 0) continue;

    final actionsNeeded = (xpNeeded / xpPerAction).ceil();

    // For each input, calculate total needed and production time
    int? maxTicksForAction;

    for (final entry in inputs.entries) {
      final itemId = entry.key;
      final neededPerAction = entry.value;
      final totalNeeded = neededPerAction * actionsNeeded;

      // Get current count
      final item = registries.items.byId(itemId);
      final available = state.inventory.countOfItem(item);

      if (available >= totalNeeded) {
        // Already have enough
        continue;
      }

      final stillNeeded = totalNeeded - available;

      // Check if current action produces this item
      final productionRate = rates.itemFlowsPerTick[itemId];
      if (productionRate == null || productionRate <= 0) {
        // Current action doesn't produce this item
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
      if (bestTicks == null || maxTicksForAction < bestTicks) {
        bestTicks = maxTicksForAction;
        bestActionId = consumingActionId;
        // Calculate total inputs needed for description
        final firstInput = inputs.entries.first;
        bestInputsNeeded = firstInput.value * actionsNeeded;
      }
    }
  }

  if (bestTicks == null || bestActionId == null) return null;

  return _DeltaCandidate(
    ticks: bestTicks,
    waitFor: WaitForSufficientInputs(bestActionId, bestInputsNeeded ?? 0),
  );
}

/// Ceiling division for doubles to int.
int _ceilDiv(double numerator, double denominator) {
  if (denominator <= 0) return infTicks;
  return (numerator / denominator).ceil();
}
