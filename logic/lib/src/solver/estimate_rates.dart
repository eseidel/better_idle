import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Expected rates for the current state, used by the planner.
@immutable
class Rates {
  const Rates({
    required this.goldPerTick,
    required this.xpPerTickBySkill,
    required this.itemsPerTick,
  });

  /// Expected gold per tick from current activity (selling outputs).
  final double goldPerTick;

  /// Expected XP per tick for each skill from current activity.
  final Map<Skill, double> xpPerTickBySkill;

  /// Expected unique item types generated per tick (for inventory fill).
  /// This is a rough estimate - assumes one item type per action completion.
  final double itemsPerTick;
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

  // For thieving, add expected gold from the action itself
  if (action is ThievingAction) {
    final thievingLevel = state.skillState(Skill.thieving).skillLevel;
    final mastery = state.actionState(action.name).masteryLevel;
    final stealth = calculateStealth(thievingLevel, mastery);
    final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
      0.0,
      1.0,
    );
    final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
    expectedGoldPerAction += expectedThievingGold;
  }

  final goldPerTick = expectedGoldPerAction / expectedTicks;

  // XP rate for the action's skill
  final xpPerTick = action.xp / expectedTicks;
  final xpPerTickBySkill = <Skill, double>{action.skill: xpPerTick};

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
  );
}
