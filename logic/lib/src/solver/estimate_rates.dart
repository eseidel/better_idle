/// Rate estimation: computes expected flows per tick for the current state.
///
/// ## Flows, Not Value
///
/// [estimateRates] is a mechanical model returning **expected flows per tick**:
/// - Direct GP per tick (coins from thieving)
/// - Items per tick (including drops from tables)
/// - XP per tick (skill and mastery)
/// - HP loss per tick (for hazard modeling)
///
/// It must NOT encode "sell everything" or any goal policy.
/// Conversion of items → value belongs to [ValueModel].
///
/// ## Drop Handling
///
/// Drops are represented in [Rates.itemFlowsPerTick] rather than immediately
/// turned into GP here. This allows different [ValueModel]s to value items
/// differently (e.g., sell price vs shadow price for crafting chains).
library;

import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:meta/meta.dart';

/// Expected rates (flows) for the current state, used by the planner.
///
/// This class reports **flows** without assuming any particular valuation
/// policy. Use a [ValueModel] to convert flows into a scalar value.
@immutable
class Rates {
  const Rates({
    required this.directGpPerTick,
    required this.itemFlowsPerTick,
    required this.xpPerTickBySkill,
    required this.itemTypesPerTick,
    this.hpLossPerTick = 0,
    this.masteryXpPerTick = 0,
    this.actionId,
  });

  /// Empty rates with all values at zero.
  static const empty = Rates(
    directGpPerTick: 0,
    itemFlowsPerTick: {},
    xpPerTickBySkill: {},
    itemTypesPerTick: 0,
  );

  /// Direct GP per tick (e.g., thieving gold, not from selling items).
  final double directGpPerTick;

  /// Expected item flows per tick: item name -> expected count per tick.
  /// Includes both action outputs and skill-level/global drops.
  final Map<MelvorId, double> itemFlowsPerTick;

  /// Expected XP per tick for each skill from current activity.
  final Map<Skill, double> xpPerTickBySkill;

  /// Expected unique item types generated per tick (for inventory fill).
  /// This is a rough estimate - assumes one item type per action completion.
  final double itemTypesPerTick;

  /// Expected HP loss per tick (for thieving hazard model).
  /// Zero for non-hazardous activities.
  final double hpLossPerTick;

  /// Expected mastery XP per tick for the current action.
  final double masteryXpPerTick;

  /// The name of the action these rates are for (for mastery tracking).
  final ActionId? actionId;
}

/// Computes the expected ticks until death for thieving.
/// Returns null if no HP loss is expected (safe activity or full health regen).
int? ticksUntilDeath(GlobalState state, Rates rates) {
  if (rates.hpLossPerTick <= 0) return null;

  // HP available before death (current HP - 1, since death occurs at 0)
  final hpAvailable = state.playerHp - 1;
  if (hpAvailable <= 0) return 0; // Already at 1 HP, next hit kills

  return (hpAvailable / rates.hpLossPerTick).floor();
}

/// Adjusts rates to account for death cycle overhead in thieving.
///
/// For activities with HP loss, the long-run effective rate is reduced
/// because time is "lost" to death and restart. This function computes
/// the steady-state rate assuming auto-restart after death.
///
/// Returns the original rates if no death risk, or adjusted rates if
/// death will occur.
Rates deathCycleAdjustedRates(
  GlobalState state,
  Rates rates, {
  int restartOverheadTicks = 0,
}) {
  if (rates.hpLossPerTick <= 0) return rates; // No death risk

  final ticksToDeath = ticksUntilDeath(state, rates);
  if (ticksToDeath == null || ticksToDeath <= 0) return Rates.empty; // Dead

  final ticksPerCycle = ticksToDeath + restartOverheadTicks;
  final cycleRatio = ticksToDeath / ticksPerCycle; // Fraction of cycle alive

  // Adjust all flow rates by the cycle ratio
  return Rates(
    directGpPerTick: rates.directGpPerTick * cycleRatio,
    itemFlowsPerTick: rates.itemFlowsPerTick.map(
      (k, v) => MapEntry(k, v * cycleRatio),
    ),
    xpPerTickBySkill: rates.xpPerTickBySkill.map(
      (k, v) => MapEntry(k, v * cycleRatio),
    ),
    itemTypesPerTick: rates.itemTypesPerTick * cycleRatio,
    hpLossPerTick: rates.hpLossPerTick, // Keep original for death calculations
    masteryXpPerTick: rates.masteryXpPerTick * cycleRatio,
    actionId: rates.actionId,
  );
}

/// Computes ticks until the next skill level for the current activity's skill.
/// Returns null if no XP is being gained or already at max level.
int? ticksUntilNextSkillLevel(GlobalState state, Rates rates) {
  // Get the skill being trained
  if (rates.xpPerTickBySkill.isEmpty) return null;

  // Find the skill with the highest XP rate (the one being trained)
  final entry = rates.xpPerTickBySkill.entries.reduce(
    (a, b) => a.value > b.value ? a : b,
  );
  final skill = entry.key;
  final xpRate = entry.value;

  if (xpRate <= 0) return null;

  final skillState = state.skillState(skill);
  final currentLevel = skillState.skillLevel;

  // Check if at max level
  if (currentLevel >= maxLevel) return null;

  final currentXp = skillState.xp;
  final nextLevelXp = startXpForLevel(currentLevel + 1);
  final xpNeeded = nextLevelXp - currentXp;

  if (xpNeeded <= 0) return 0; // Already have enough XP

  return (xpNeeded / xpRate).ceil();
}

/// Computes ticks until the next mastery level for the current action.
/// Returns null if no mastery XP is being gained or already at max level.
int? ticksUntilNextMasteryLevel(GlobalState state, Rates rates) {
  if (rates.masteryXpPerTick <= 0 || rates.actionId == null) return null;

  final actionState = state.actionState(rates.actionId!);
  final currentLevel = actionState.masteryLevel;

  // Check if at max mastery level (99)
  if (currentLevel >= 99) return null;

  final currentXp = actionState.masteryXp;
  final nextLevelXp = startXpForLevel(currentLevel + 1);
  final xpNeeded = nextLevelXp - currentXp;

  if (xpNeeded <= 0) return 0; // Already have enough XP

  return (xpNeeded / rates.masteryXpPerTick).ceil();
}

/// Computes expected item flows per action from all drops.
///
/// Returns a map of item name -> expected count per action.
/// Uses allDropsForAction which includes action outputs (via rewardsAtLevel),
/// skill-level drops, and global drops.
/// Applies skillItemDoublingChance from resolved modifiers.
Map<MelvorId, double> _computeItemFlowsPerAction(
  GlobalState state,
  SkillAction action,
  RecipeSelection selection,
) {
  // allDropsForAction includes:
  // - Action outputs (via rewardsForSelection -> rewardsAtLevel)
  // - Skill-level drops (e.g., Bobby's Pocket for thieving)
  // - Global drops (e.g., gems)
  final dropsForAction = state.registries.drops.allDropsForAction(
    action,
    selection,
  );

  // Get doubling chance from modifiers
  final modifiers = state.resolveModifiers(action);
  final doublingChance = (modifiers.skillItemDoublingChance / 100.0).clamp(
    0.0,
    1.0,
  );

  return expectedItemsForDrops(dropsForAction, doublingChance: doublingChance);
}

/// Estimates expected rates (flows) for the current state.
///
/// Uses the active action to compute item flows, XP, and direct GP rates.
/// Returns zero rates if no action is active.
///
/// Note: This function reports **flows** without assuming any valuation
/// policy. Use a [ValueModel] to convert flows into a scalar value.
Rates estimateRates(GlobalState state) {
  final activeAction = state.activeAction;
  if (activeAction == null) {
    return Rates.empty;
  }

  final action = state.registries.actions.byId(activeAction.id);

  // Only skill actions have predictable rates
  if (action is! SkillAction) {
    return Rates.empty;
  }

  // Calculate expected ticks per action completion (with upgrades applied)
  final baseExpectedTicks = ticksFromDuration(action.meanDuration).toDouble();

  // Apply upgrade modifier
  final percentModifier = state.shopDurationModifierForSkill(action.skill);
  final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);

  if (expectedTicks <= 0) {
    return Rates.empty;
  }

  // Compute item flows per action
  final actionState = state.actionState(action.id);
  final selection = actionState.recipeSelection(action);
  final itemFlowsPerAction = _computeItemFlowsPerAction(
    state,
    action,
    selection,
  );

  // For thieving, calculate rates accounting for stun time on failure.
  // On failure, the player is stunned for stunnedDurationTicks, which
  // increases the effective time per action attempt.
  // Also compute HP loss rate for hazard modeling.
  if (action is ThievingAction) {
    final thievingLevel = state.skillState(Skill.thieving).skillLevel;
    final mastery = state.actionState(action.id).masteryLevel;
    final stealth = calculateStealth(thievingLevel, mastery);
    final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
      0.0,
      1.0,
    );
    final failureChance = 1.0 - successChance;

    // Direct GP per attempt (only on success) - thieving gold coins
    final expectedThievingGold = successChance * (1 + action.maxGold) / 2;

    // Expected HP loss per attempt (only on failure)
    // Damage is uniform 1 to maxHit, so expected damage = (1 + maxHit) / 2
    final expectedDamagePerAttempt = failureChance * (1 + action.maxHit) / 2;

    // Effective ticks per attempt = action duration + (failure chance * stun)
    final effectiveTicks = expectedTicks + failureChance * stunnedDurationTicks;

    final directGpPerTick = expectedThievingGold / effectiveTicks;
    final hpLossPerTick = expectedDamagePerAttempt / effectiveTicks;

    // Convert item flows per action to per tick (drops only on success)
    final itemFlowsPerTick = <MelvorId, double>{};
    for (final entry in itemFlowsPerAction.entries) {
      itemFlowsPerTick[entry.key] =
          entry.value * successChance / effectiveTicks;
    }

    // XP is only gained on success, so expected XP = successChance * xp
    final expectedXpPerAction = successChance * action.xp;
    final xpPerTick = expectedXpPerAction / effectiveTicks;
    final xpPerTickBySkill = <Skill, double>{action.skill: xpPerTick};

    // Mastery XP is also only gained on success
    final baseMasteryXpPerAction = masteryXpPerAction(state, action);
    final expectedMasteryXpPerAction = successChance * baseMasteryXpPerAction;
    final masteryXpPerTick = expectedMasteryXpPerAction / effectiveTicks;

    // Item types per tick for inventory estimation
    final uniqueOutputTypes = itemFlowsPerAction.length.toDouble();
    final itemTypesPerTick = uniqueOutputTypes > 0
        ? uniqueOutputTypes / effectiveTicks
        : 0.0;

    return Rates(
      directGpPerTick: directGpPerTick,
      itemFlowsPerTick: itemFlowsPerTick,
      xpPerTickBySkill: xpPerTickBySkill,
      itemTypesPerTick: itemTypesPerTick,
      hpLossPerTick: hpLossPerTick,
      masteryXpPerTick: masteryXpPerTick,
      actionId: action.id,
    );
  }

  // Non-thieving actions: no direct GP, all value comes from items
  // Convert item flows per action to per tick
  final itemFlowsPerTick = <MelvorId, double>{};
  for (final entry in itemFlowsPerAction.entries) {
    itemFlowsPerTick[entry.key] = entry.value / expectedTicks;
  }

  // XP rate for the action's skill
  final xpPerTick = action.xp / expectedTicks;
  final xpPerTickBySkill = <Skill, double>{action.skill: xpPerTick};

  // Mastery XP rate
  final baseMasteryXpPerAction = masteryXpPerAction(state, action);
  final masteryXpPerTick = baseMasteryXpPerAction / expectedTicks;

  // Item types per tick for inventory estimation
  final uniqueOutputTypes = itemFlowsPerAction.length.toDouble();
  final itemTypesPerTick = uniqueOutputTypes > 0
      ? uniqueOutputTypes / expectedTicks
      : 0.0;

  return Rates(
    directGpPerTick: 0, // Non-thieving actions have no direct GP
    itemFlowsPerTick: itemFlowsPerTick,
    xpPerTickBySkill: xpPerTickBySkill,
    itemTypesPerTick: itemTypesPerTick,
    masteryXpPerTick: masteryXpPerTick,
    actionId: action.id,
  );
}
