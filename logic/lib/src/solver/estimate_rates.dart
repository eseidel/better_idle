import 'package:logic/src/consume_ticks.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:meta/meta.dart';

/// Expected rates for the current state, used by the planner.
@immutable
class Rates {
  const Rates({
    required this.goldPerTick,
    required this.xpPerTickBySkill,
    required this.itemsPerTick,
    this.hpLossPerTick = 0,
    this.masteryXpPerTick = 0,
    this.actionName,
  });

  /// Expected gold per tick from current activity (selling outputs).
  final double goldPerTick;

  /// Expected XP per tick for each skill from current activity.
  final Map<Skill, double> xpPerTickBySkill;

  /// Expected unique item types generated per tick (for inventory fill).
  /// This is a rough estimate - assumes one item type per action completion.
  final double itemsPerTick;

  /// Expected HP loss per tick (for thieving hazard model).
  /// Zero for non-hazardous activities.
  final double hpLossPerTick;

  /// Expected mastery XP per tick for the current action.
  final double masteryXpPerTick;

  /// The name of the action these rates are for (for mastery tracking).
  final String? actionName;
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
  if (rates.masteryXpPerTick <= 0 || rates.actionName == null) return null;

  final actionState = state.actionState(rates.actionName!);
  final currentLevel = actionState.masteryLevel;

  // Check if at max mastery level (99)
  if (currentLevel >= 99) return null;

  final currentXp = actionState.masteryXp;
  final nextLevelXp = startXpForLevel(currentLevel + 1);
  final xpNeeded = nextLevelXp - currentXp;

  if (xpNeeded <= 0) return 0; // Already have enough XP

  return (xpNeeded / rates.masteryXpPerTick).ceil();
}

/// Estimates expected rates for the current state.
///
/// Uses the active action to compute gold, XP, and item rates.
/// Returns zero rates if no action is active.
Rates estimateRates(GlobalState state) {
  final activeAction = state.activeAction;
  if (activeAction == null) {
    return const Rates(goldPerTick: 0, xpPerTickBySkill: {}, itemsPerTick: 0);
  }

  final action = actionRegistry.byName(activeAction.name);

  // Only skill actions have predictable rates
  if (action is! SkillAction) {
    return const Rates(goldPerTick: 0, xpPerTickBySkill: {}, itemsPerTick: 0);
  }

  // Calculate expected ticks per action completion (with upgrades applied)
  final baseExpectedTicks = ticksFromDuration(action.meanDuration).toDouble();

  // Apply upgrade modifier
  final percentModifier = state.shop.durationModifierForSkill(action.skill);
  final expectedTicks = baseExpectedTicks * (1.0 + percentModifier);

  if (expectedTicks <= 0) {
    return const Rates(goldPerTick: 0, xpPerTickBySkill: {}, itemsPerTick: 0);
  }

  // Calculate expected gold per action from selling outputs
  var expectedGoldPerAction = 0.0;
  for (final output in action.outputs.entries) {
    final item = itemRegistry.byName(output.key);
    expectedGoldPerAction += item.sellsFor * output.value;
  }

  // For thieving, calculate rates accounting for stun time on failure.
  // On failure, the player is stunned for stunnedDurationTicks, which
  // increases the effective time per action attempt.
  // Also compute HP loss rate for hazard modeling.
  if (action is ThievingAction) {
    final thievingLevel = state.skillState(Skill.thieving).skillLevel;
    final mastery = state.actionState(action.name).masteryLevel;
    final stealth = calculateStealth(thievingLevel, mastery);
    final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
      0.0,
      1.0,
    );
    final failureChance = 1.0 - successChance;

    // Expected gold per attempt (only on success)
    final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
    expectedGoldPerAction += expectedThievingGold;

    // Expected HP loss per attempt (only on failure)
    // Damage is uniform 1 to maxHit, so expected damage = (1 + maxHit) / 2
    final expectedDamagePerAttempt = failureChance * (1 + action.maxHit) / 2;

    // Effective ticks per attempt = action duration + (failure chance * stun)
    final effectiveTicks = expectedTicks + failureChance * stunnedDurationTicks;

    final goldPerTick = expectedGoldPerAction / effectiveTicks;
    final hpLossPerTick = expectedDamagePerAttempt / effectiveTicks;

    // XP is only gained on success, so expected XP = successChance * xp
    final expectedXpPerAction = successChance * action.xp;
    final xpPerTick = expectedXpPerAction / effectiveTicks;
    final xpPerTickBySkill = <Skill, double>{action.skill: xpPerTick};

    // Mastery XP is also only gained on success
    final baseMasteryXpPerAction = masteryXpPerAction(state, action);
    final expectedMasteryXpPerAction = successChance * baseMasteryXpPerAction;
    final masteryXpPerTick = expectedMasteryXpPerAction / effectiveTicks;

    // Items per tick (thieving typically has no item outputs)
    final uniqueOutputTypes = action.outputs.length.toDouble();
    final itemsPerTick = uniqueOutputTypes > 0
        ? uniqueOutputTypes / effectiveTicks
        : 0.0;

    return Rates(
      goldPerTick: goldPerTick,
      xpPerTickBySkill: xpPerTickBySkill,
      itemsPerTick: itemsPerTick,
      hpLossPerTick: hpLossPerTick,
      masteryXpPerTick: masteryXpPerTick,
      actionName: action.name,
    );
  }

  final goldPerTick = expectedGoldPerAction / expectedTicks;

  // XP rate for the action's skill
  final xpPerTick = action.xp / expectedTicks;
  final xpPerTickBySkill = <Skill, double>{action.skill: xpPerTick};

  // Mastery XP rate
  final baseMasteryXpPerAction = masteryXpPerAction(state, action);
  final masteryXpPerTick = baseMasteryXpPerAction / expectedTicks;

  // Items per tick - rough estimate based on outputs
  // Count unique output types per action completion
  final uniqueOutputTypes = action.outputs.length.toDouble();
  final itemsPerTick = uniqueOutputTypes > 0
      ? uniqueOutputTypes / expectedTicks
      : 0.0;

  return Rates(
    goldPerTick: goldPerTick,
    xpPerTickBySkill: xpPerTickBySkill,
    itemsPerTick: itemsPerTick,
    masteryXpPerTick: masteryXpPerTick,
    actionName: action.name,
  );
}
