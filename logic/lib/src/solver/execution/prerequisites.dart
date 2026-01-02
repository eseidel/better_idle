/// Prerequisite resolution for macro expansion.
///
/// Provides functions to check if an action is executable and what
/// prerequisites are needed.
library;

import 'package:collection/collection.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart' show Skill, SkillAction;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';

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

/// Deduplicates macros, keeping first occurrence of each unique macro.
List<MacroCandidate> dedupeMacros(List<MacroCandidate> macros) {
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
    };
    if (seen.add(key)) result.add(macro);
  }
  return result;
}

/// Finds an action that produces the given item.
ActionId? findProducerActionForItem(
  GlobalState state,
  MelvorId item,
  Goal goal,
) {
  int skillLevel(Skill skill) => state.skillState(skill).skillLevel;

  // Find all actions that produce this item
  final producers = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.outputs.containsKey(item))
      .where((action) => action.unlockLevel <= skillLevel(action.skill));

  if (producers.isEmpty) return null;

  // Rank by production rate (outputs per tick)
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
SkillAction? findAnyProducerForItem(GlobalState state, MelvorId item) {
  return state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.outputs.containsKey(item))
      .firstOrNull;
}

/// Returns prerequisite check result for an action.
///
/// Checks:
/// 1. Skill level requirements - generates TrainSkillUntil if action is locked
/// 2. Input requirements - recursively checks producers for each input
///
/// Returns [ExecReady] if action can execute now, [ExecNeedsMacros] if
/// prerequisites are needed, or [ExecUnknown] if we can't determine how
/// to make the action feasible (e.g., no producer exists, cycle detected).
EnsureExecResult ensureExecutable(
  GlobalState state,
  ActionId actionId,
  Goal goal, {
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

  final action = state.registries.actions.byId(actionId);
  if (action is! SkillAction) return const ExecReady();

  final macros = <MacroCandidate>[];

  // 1. Check skill level requirement
  final currentLevel = state.skillState(action.skill).skillLevel;
  if (action.unlockLevel > currentLevel) {
    macros.add(
      TrainSkillUntil(
        action.skill,
        StopAtLevel(action.skill, action.unlockLevel),
      ),
    );
  }

  // 2. Check inputs - recursively ensure each can be produced
  for (final inputId in action.inputs.keys) {
    final inputCount = action.inputs[inputId]!;
    final inputItem = state.registries.items.byId(inputId);
    final currentCount = state.inventory.countOfItem(inputItem);

    // If we already have enough of this input, no prereq needed
    if (currentCount >= inputCount) continue;

    // First check if there's an unlocked producer
    final producer = findProducerActionForItem(state, inputId, goal);
    if (producer != null) {
      // Producer exists and is unlocked, check its prerequisites
      final result = ensureExecutable(
        state,
        producer,
        goal,
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
    } else {
      // No unlocked producer - check if one exists but is locked
      final lockedProducer = findAnyProducerForItem(state, inputId);
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
    }
  }

  return macros.isEmpty
      ? const ExecReady()
      : ExecNeedsMacros(dedupeMacros(macros));
}

/// Finds the best action for a skill based on the goal's criteria.
///
/// For skill goals, picks the action with highest XP rate.
/// For GP goals, picks the action with highest gold rate.
///
/// For consuming actions, this also checks that we can produce the inputs.
ActionId? findBestActionForSkill(GlobalState state, Skill skill, Goal goal) {
  final skillLevel = state.skillState(skill).skillLevel;
  final actions = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.skill == skill)
      .where((action) => action.unlockLevel <= skillLevel);

  if (actions.isEmpty) return null;

  // Rank by goal-specific rate
  ActionId? best;
  double bestRate = 0;

  // Check if this skill is relevant to the goal
  final skillIsGoalRelevant = goal.isSkillRelevant(skill);

  actionLoop:
  for (final action in actions) {
    // For consuming actions, check that ALL inputs can be produced
    if (action.inputs.isNotEmpty) {
      for (final inputItem in action.inputs.keys) {
        final anyProducer = findAnyProducerForItem(state, inputItem);
        if (anyProducer == null) {
          // No way to produce this input at all, skip this action
          continue actionLoop;
        }
      }
    }

    // Calculate rate based on goal type
    final ticksPerAction = ticksFromDuration(action.meanDuration).toDouble();

    double rate;
    if (skillIsGoalRelevant && goal is ReachSkillLevelGoal) {
      // For skill goals, use XP rate
      rate = action.xp / ticksPerAction;
    } else {
      // For GP goals or non-relevant skills, use gold rate
      var goldPerAction = 0.0;
      for (final output in action.outputs.entries) {
        final item = state.registries.items.byId(output.key);
        goldPerAction += item.sellsFor * output.value;
      }
      rate = goldPerAction / ticksPerAction;
    }

    if (rate > bestRate) {
      bestRate = rate;
      best = action.id;
    }
  }

  return best;
}
