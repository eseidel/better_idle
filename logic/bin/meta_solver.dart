// Entry point for the meta planner - Level 3 meta planning above A* solver.
//
// Usage: dart run bin/meta_solver.dart
//        dart run bin/meta_solver.dart --target 50  # All skills to 50
//        dart run bin/meta_solver.dart --json       # Output plan as JSON
//        dart run bin/meta_solver.dart --verbose    # Show full phase details
//
// The meta planner decomposes AllSkills99 into milestones and uses Level 2
// A* solver as an oracle to produce executable plan segments.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/solver/meta/meta_goal.dart';
import 'package:logic/src/solver/meta/meta_planner.dart';
import 'package:logic/src/solver/meta/milestone.dart';
import 'package:logic/src/solver/meta/milestone_extractor.dart';

final _parser = ArgParser()
  ..addOption(
    'target',
    abbr: 't',
    help: 'Target level for all skills (default: 99)',
    defaultsTo: '99',
  )
  ..addOption(
    'max-phases',
    help: 'Maximum phases to generate (default: 100)',
    defaultsTo: '100',
  )
  ..addOption(
    'phase-budget',
    help: 'Tick budget per phase (default: 100000)',
    defaultsTo: '100000',
  )
  ..addMultiOption(
    'exclude',
    abbr: 'e',
    help: 'Skills to exclude (can be specified multiple times)',
  )
  ..addFlag('json', help: 'Output plan as JSON', negatable: false)
  ..addFlag(
    'verbose',
    abbr: 'v',
    help: 'Show full phase details',
    negatable: false,
  )
  ..addFlag(
    'milestones',
    abbr: 'm',
    help: 'Print milestone graph summary',
    negatable: false,
  )
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Show this help message',
    negatable: false,
  );

/// Formats ticks in a compact human-readable form.
String _formatTicks(int ticks) {
  if (ticks >= 1000000) {
    return '${(ticks / 1000000).toStringAsFixed(1)}M ticks';
  } else if (ticks >= 1000) {
    return '${(ticks / 1000).toStringAsFixed(1)}K ticks';
  }
  return '$ticks ticks';
}

void main(List<String> args) async {
  final results = _parser.parse(args);

  if (results.flag('help')) {
    print('Meta Solver - Level 3 Meta Planning for Melvor Idle');
    print('');
    print('Usage: dart run bin/meta_solver.dart [options]');
    print('');
    print(_parser.usage);
    return;
  }

  final targetLevel = int.parse(results.option('target')!);
  final maxPhases = int.parse(results.option('max-phases')!);
  final phaseBudget = int.parse(results.option('phase-budget')!);
  final excludeNames = results.multiOption('exclude');
  final outputJson = results.flag('json');
  final verbose = results.flag('verbose');
  final showMilestones = results.flag('milestones');

  // Parse excluded skills.
  final excludedSkills = <Skill>{};
  for (final name in excludeNames) {
    final skill = Skill.values.where((s) => s.name == name).firstOrNull;
    if (skill == null) {
      print('Unknown skill: $name');
      print('Available skills: ${Skill.values.map((s) => s.name).join(', ')}');
      exit(1);
    }
    excludedSkills.add(skill);
  }

  // Add default excluded skills.
  excludedSkills.addAll(AllSkills99Goal.defaultExcludedSkills);

  print('Loading game data...');
  final registries = await loadRegistries();

  final goal = AllSkills99Goal(
    excludedSkills: excludedSkills,
    targetLevel: targetLevel,
  );

  print('');
  print('Meta Goal: ${goal.describe()}');
  print('Trainable skills: ${goal.trainableSkills.length}');
  print('Max phases: $maxPhases');
  print('Phase budget: ${_formatTicks(phaseBudget)}');
  print('');

  final config = MetaPlannerConfig(maxPhases: maxPhases, verbose: verbose);

  final planner = MetaPlanner(registries: registries, config: config);

  // Show milestones if requested.
  if (showMilestones) {
    final extractor = MilestoneExtractor(registries);
    final graph = extractor.extractForAllSkills99(goal);
    print('Milestone Graph:');
    print('  Total milestones: ${graph.nodes.length}');
    print('');
    final sortedSkills = goal.trainableSkills.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final skill in sortedSkills) {
      final nodes = graph.forSkill(skill);
      final levels = nodes.map((MilestoneNode n) {
        final m = n.milestone as SkillLevelMilestone;
        return m.level;
      }).toList()..sort();
      print('  ${skill.name}: ${levels.join(', ')}');
    }
    print('');
  }

  print('Running meta planner...');
  print('');

  final initialState = GlobalState.empty(registries);
  final stopwatch = Stopwatch()..start();
  final plan = planner.solve(initialState, goal);
  stopwatch.stop();

  print('');
  print('=== Meta Plan Complete ===');
  print('Wall time: ${stopwatch.elapsedMilliseconds}ms');
  print('');

  if (outputJson) {
    const encoder = JsonEncoder.withIndent('  ');
    print(encoder.convert(plan.toJson()));
  } else if (verbose) {
    print(plan.prettyPrintFull());
  } else {
    print(plan.prettyPrintSummary());
  }
}
