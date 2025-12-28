/// Macro-level planning primitives for solver.
///
/// Macros represent "train until boundary/goal/upgrade" decisions that span
/// many ticks, reducing the solver's branching factor and state explosion.
library;

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/unlock_boundaries.dart';
import 'package:logic/src/state.dart';

/// A macro-level planning action that commits to an activity for an
/// extended period.
///
/// Macros stop when ANY of their stop conditions trigger, allowing the solver
/// to react to unlock boundaries, goal completion, or upgrade affordability.
sealed class MacroCandidate {
  const MacroCandidate();
}

/// Train a skill by doing its best action until ANY stop condition triggers.
///
/// Example: "Train Woodcutting until (next boundary OR Steel Axe affordable)"
class TrainSkillUntil extends MacroCandidate {
  const TrainSkillUntil(
    this.skill,
    this.primaryStop, {
    this.watchedStops = const [],
  });

  final Skill skill;

  /// Primary stop condition (usually boundary or goal).
  final MacroStopRule primaryStop;

  /// Additional stop conditions to watch (upgrades, inputs, etc.).
  /// Macro stops when ANY condition (primary OR watched) triggers.
  final List<MacroStopRule> watchedStops;

  /// All stop conditions (primary + watched).
  List<MacroStopRule> get allStops => [primaryStop, ...watchedStops];
}

/// Stop conditions for macro training.
///
/// Each rule knows how to convert itself to a WaitFor for plan execution.
sealed class MacroStopRule {
  const MacroStopRule();

  /// Convert this stop rule to a WaitFor for plan execution.
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries);
}

/// Stop at the next unlock boundary for this skill.
///
/// Boundaries are levels where new actions become available.
class StopAtNextBoundary extends MacroStopRule {
  const StopAtNextBoundary(this.skill);

  final Skill skill;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    final currentLevel = state.skillState(skill).skillLevel;
    final nextBoundary = boundaries[skill]?.nextBoundary(currentLevel);
    final targetLevel = nextBoundary ?? 99;
    final targetXp = startXpForLevel(targetLevel);

    return WaitForSkillXp(skill, targetXp, reason: 'Boundary L$targetLevel');
  }
}

/// Stop when skill reaches goal level.
class StopAtGoal extends MacroStopRule {
  const StopAtGoal(this.skill, this.targetXp);

  final Skill skill;
  final int targetXp;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForSkillXp(skill, targetXp, reason: 'Goal reached');
  }
}

/// Stop when upgrade becomes affordable.
///
/// Used to allow early purchase of valuable upgrades before reaching
/// the next boundary.
class StopWhenUpgradeAffordable extends MacroStopRule {
  const StopWhenUpgradeAffordable(this.purchaseId, this.cost, this.upgradeName);

  final MelvorId purchaseId;
  final int cost;
  final String upgradeName;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForInventoryValue(cost, reason: upgradeName);
  }
}

/// Stop when inputs are depleted (for consuming actions like Firemaking).
///
/// This ensures the macro doesn't continue when there are no logs/fish to
/// consume, allowing the solver to switch to a producer action.
class StopWhenInputsDepleted extends MacroStopRule {
  const StopWhenInputsDepleted(this.actionId);

  final ActionId actionId;

  @override
  WaitFor toWaitFor(GlobalState state, Map<Skill, SkillBoundaries> boundaries) {
    return WaitForInputsDepleted(actionId);
  }
}
