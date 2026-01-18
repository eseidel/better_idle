/// Shared utilities for plan execution and reporting.
///
/// These functions are used by both `bin/solver.dart` and `bin/execute.dart`
/// to print execution results and format plan steps.
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/strings.dart';

/// Prints the final state after executing a plan.
void printFinalState(GlobalState state) {
  print('=== Final State ===');
  print('GP: ${preciseNumberString(state.gp)}');
  print('');

  // Print skill levels
  print('Skills:');
  for (final skill in Skill.values) {
    final skillState = state.skillState(skill);
    if (skillState.skillLevel > 1 || skillState.xp > 0) {
      print(
        '  ${skill.name}: Level ${skillState.skillLevel} '
        '(${preciseNumberString(skillState.xp)} XP)',
      );
    }
  }

  // Print inventory if not empty
  if (state.inventory.items.isNotEmpty) {
    print('');
    print('Inventory:');
    for (final stack in state.inventory.items) {
      print('  ${stack.item.name}: ${preciseNumberString(stack.count)}');
    }
    final totalValue = state.inventory.items.fold<int>(
      0,
      (sum, stack) => sum + stack.sellsFor,
    );
    print('Total value: ${preciseNumberString(totalValue)} GP');
  }
}

/// Prints execution statistics comparing planned vs actual ticks.
void printExecutionStats(PlanExecutionResult result, {int? expectedDeaths}) {
  print('=== Execution Stats ===');
  print('Planned: ${durationStringWithTicks(result.plannedTicks)}');
  print('Actual: ${durationStringWithTicks(result.actualTicks)}');
  print('Delta: ${signedDurationStringWithTicks(result.ticksDelta)}');
  if (expectedDeaths != null) {
    print('Deaths: ${result.totalDeaths} actual, $expectedDeaths expected');
  } else {
    print('Deaths: ${result.totalDeaths}');
  }
}

/// Describes a plan step in human-readable format.
///
/// [currentAction] provides context for wait steps that don't have an
/// explicit expected action.
String describeStep(
  PlanStep step,
  Registries registries, {
  ActionId? currentAction,
}) {
  return switch (step) {
    InteractionStep(:final interaction) => switch (interaction) {
      SwitchActivity(:final actionId) =>
        'Switch to ${registries.actionById(actionId).name}',
      BuyShopItem(:final purchaseId) => 'Buy ${purchaseId.name}',
      SellItems(:final policy) => _formatSellPolicy(policy),
    },
    WaitStep(:final deltaTicks, :final waitFor, :final expectedAction) => () {
      final actionToUse = expectedAction ?? currentAction;
      final actionName = actionToUse != null
          ? registries.actionById(actionToUse).name
          : null;
      final prefix = actionName ?? 'Wait';
      return '$prefix $deltaTicks ticks -> ${waitFor.shortDescription}';
    }(),
    MacroStep(:final macro, :final deltaTicks) => switch (macro) {
      TrainSkillUntil(:final skill) => '${skill.name} for $deltaTicks ticks',
      TrainConsumingSkillUntil(:final consumingSkill) =>
        '${consumingSkill.name} for $deltaTicks ticks',
      AcquireItem(:final itemId, :final quantity) =>
        'Acquire ${quantity}x $itemId ($deltaTicks ticks)',
      EnsureStock(:final itemId, :final minTotal) =>
        'EnsureStock ${itemId.name}: $minTotal ($deltaTicks ticks)',
      ProduceItem(:final itemId, :final minTotal) =>
        'Produce ${itemId.name}: $minTotal ($deltaTicks ticks)',
    },
  };
}

/// Formats a sell policy for display.
String _formatSellPolicy(SellPolicy policy) {
  return switch (policy) {
    SellAllPolicy() => 'Sell all',
    SellExceptPolicy(:final keepItems) => () {
      final names = keepItems.map((id) => id.name).toList()..sort();
      if (names.length <= 3) {
        return 'Sell all except ${names.join(', ')}';
      }
      return 'Sell all except ${names.length} items '
          '(${names.take(3).join(', ')}, ...)';
    }(),
  };
}

/// Writes a plan to a JSON file.
void writePlanToJson(Plan plan, String path) {
  final json = plan.toJson();
  const encoder = JsonEncoder.withIndent('  ');
  final jsonString = encoder.convert(json);
  File(path).writeAsStringSync(jsonString);
  print('');
  print('Plan written to: $path');
  print('Run: dart run bin/execute.dart $path');
}
