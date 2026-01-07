/// Prerequisite resolution for macro expansion.
///
/// Provides functions to check if an action is executable and what
/// prerequisites are needed.
library;

import 'package:collection/collection.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/value_model.dart';
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
  /// Creates an ExecNeedsMacros, deduplicating macros by their dedupeKey.
  factory ExecNeedsMacros(List<MacroCandidate> macros) {
    final seen = <String>{};
    final deduped = <MacroCandidate>[];
    for (final macro in macros) {
      if (seen.add(macro.dedupeKey)) deduped.add(macro);
    }
    return ExecNeedsMacros._(deduped);
  }

  const ExecNeedsMacros._(this.macros);
  final List<MacroCandidate> macros;
}

/// Cannot determine how to make action feasible.
class ExecUnknown extends EnsureExecResult {
  const ExecUnknown(this.reason);
  final String reason;
}

/// Finds an action that produces the given item.
ActionId? findProducerActionForItem(GlobalState state, MelvorId item) {
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

  final registries = state.registries;
  final action = registries.actions.byId(actionId);
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
    final inputItem = registries.items.byId(inputId);
    final currentCount = state.inventory.countOfItem(inputItem);

    // If we already have enough of this input, no prereq needed
    if (currentCount >= inputCount) continue;

    // First check if there's an unlocked producer
    final producer = findProducerActionForItem(state, inputId);
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

  return macros.isEmpty ? const ExecReady() : ExecNeedsMacros(macros);
}

/// Finds the best action for a skill based on the goal's criteria.
///
/// For skill goals, picks the action with highest XP rate.
/// For GP goals, picks the action with highest gold rate.
///
/// Unlike `estimateRates`, this function doesn't require the action to be
/// startable. This is important for consuming skills where we want to find
/// the best action even when inputs aren't currently available (because we'll
/// produce them next).
///
/// For consuming actions, this also checks that we can produce the inputs.
ActionId? findBestActionForSkill(GlobalState state, Skill skill, Goal goal) {
  final skillLevel = state.skillState(skill).skillLevel;
  final actions = state.registries.actions.all
      .whereType<SkillAction>()
      .where((action) => action.skill == skill)
      .where((action) => action.unlockLevel <= skillLevel);

  if (actions.isEmpty) return null;

  // Check if this skill is relevant to the goal. If not (e.g., training Mining
  // as a prerequisite for Smithing), use raw XP rate instead of goal rate.
  final skillIsGoalRelevant = goal.isSkillRelevant(skill);

  // Filter out actions with inputs that have no producer at all
  final viableActions = actions
      .where((action) {
        if (action.inputs.isEmpty) return true;

        // For consuming actions, check that ALL inputs can be produced
        // (either directly or via prerequisite training).
        // Handles multi-input actions like Mithril Bar (Mithril Ore + Coal).
        for (final inputItem in action.inputs.keys) {
          // Check if any producer exists (locked or unlocked)
          final anyProducer = findAnyProducerForItem(state, inputItem);
          if (anyProducer == null) {
            // No way to produce this input at all, skip this action
            return false;
          }
        }
        return true;
      })
      .map((a) => a.id);

  // Rank by goal-specific rate
  return findBestActionByRate(
    state,
    viableActions,
    rateExtractor: (rates) {
      final goldRate = defaultValueModel.valuePerTick(state, rates);
      final xpRate = rates.xpPerTickBySkill[skill] ?? 0.0;

      // For prerequisite training (skill not in goal), use raw XP rate
      // to pick the fastest training action.
      return skillIsGoalRelevant
          ? goal.activityRate(skill, goldRate, xpRate)
          : xpRate;
    },
  );
}
