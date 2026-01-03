// Executes a plan from a JSON file.
//
// Usage: dart run bin/execute.dart plan.json [options]
//
// Options:
//   --verbose, -v    Print step-by-step progress during execution
//   --seed <int>     Random seed for execution (default: 42)
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart';

final _parser = ArgParser()
  ..addFlag(
    'verbose',
    abbr: 'v',
    help: 'Print step-by-step progress during execution',
    negatable: false,
  )
  ..addOption(
    'seed',
    help: 'Random seed for execution (default: 42)',
    defaultsTo: '42',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Show this help message',
    negatable: false,
  );

void main(List<String> args) async {
  final results = _parser.parse(args);

  if (results['help'] as bool || results.rest.isEmpty) {
    print('Usage: dart run bin/execute.dart plan.json [options]');
    print('');
    print('Executes a plan from a JSON file.');
    print('');
    print('Options:');
    print(_parser.usage);
    return;
  }

  final planPath = results.rest[0];
  final verbose = results['verbose'] as bool;
  final seed = int.parse(results['seed'] as String);

  // Load registries
  print('Loading game data...');
  final registries = await loadRegistries();

  // Load plan from JSON
  print('Loading plan from: $planPath');
  final planFile = File(planPath);
  if (!planFile.existsSync()) {
    print('ERROR: Plan file not found: $planPath');
    exit(1);
  }

  final planJson =
      jsonDecode(planFile.readAsStringSync()) as Map<String, dynamic>;
  final plan = Plan.fromJson(planJson);

  print('');
  print('=== Plan Summary ===');
  print('Steps: ${plan.steps.length}');
  print('Planned ticks: ${plan.totalTicks}');
  print('Interactions: ${plan.interactionCount}');
  print('Expected deaths: ${plan.expectedDeaths}');
  print('Segments: ${plan.segmentMarkers.length}');
  print('');

  // Create initial state
  final initialState = GlobalState.empty(registries);

  // Execute the plan
  print('Executing plan with seed=$seed...');
  final stopwatch = Stopwatch()..start();

  final execResult = executePlan(
    initialState,
    plan,
    random: Random(seed),
    onStepComplete: verbose ? _printStepProgress : null,
  );

  stopwatch.stop();
  print('Execution completed in ${stopwatch.elapsedMilliseconds}ms');
  print('');

  // Print final state
  _printFinalState(execResult.finalState);
  print('');

  // Print execution stats
  print('=== Execution Stats ===');
  print('Planned: ${durationStringWithTicks(execResult.plannedTicks)}');
  print('Actual: ${durationStringWithTicks(execResult.actualTicks)}');
  print('Delta: ${signedDurationStringWithTicks(execResult.ticksDelta)}');
  print('Deaths: ${execResult.totalDeaths} (expected: ${plan.expectedDeaths})');

  // Report any unexpected boundaries
  if (execResult.hasUnexpectedBoundaries) {
    print('');
    print('=== WARNING: Unexpected Boundaries ===');
    for (final boundary in execResult.unexpectedBoundaries) {
      print('  - $boundary');
    }
  }
}

void _printStepProgress({
  required int stepIndex,
  required PlanStep step,
  required int plannedTicks,
  required int estimatedTicksAtExecution,
  required int actualTicks,
  required int cumulativeActualTicks,
  required int cumulativePlannedTicks,
  required GlobalState stateAfter,
  required GlobalState stateBefore,
  required dynamic boundary,
}) {
  final delta = actualTicks - plannedTicks;
  final deltaStr = delta >= 0 ? '+$delta' : '$delta';

  // Only print for significant steps or deviations
  if (plannedTicks > 0 || delta.abs() > 100) {
    final stepDesc = _describeStep(step, stateBefore.registries);
    print(
      'Step ${stepIndex + 1}: $stepDesc '
      '(planned=$plannedTicks, actual=$actualTicks, $deltaStr)',
    );
  }
}

String _describeStep(PlanStep step, Registries registries) {
  return switch (step) {
    InteractionStep(:final interaction) => switch (interaction) {
      SwitchActivity(:final actionId) =>
        'Switch to ${registries.actions.byId(actionId).name}',
      BuyShopItem(:final purchaseId) => 'Buy ${purchaseId.name}',
      SellItems(:final policy) => 'Sell (${policy.runtimeType})',
    },
    WaitStep(:final deltaTicks, :final waitFor) =>
      'Wait $deltaTicks ticks -> ${waitFor.shortDescription}',
    MacroStep(:final macro, :final deltaTicks) => switch (macro) {
      TrainSkillUntil(:final skill) =>
        'Train ${skill.name} ($deltaTicks ticks)',
      TrainConsumingSkillUntil(:final consumingSkill) =>
        'Train ${consumingSkill.name} ($deltaTicks ticks)',
      AcquireItem(:final itemId, :final quantity) =>
        'Acquire ${quantity}x ${itemId.name}',
      EnsureStock(:final itemId, :final minTotal) =>
        'EnsureStock ${itemId.name}: $minTotal',
    },
  };
}

void _printFinalState(GlobalState state) {
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
