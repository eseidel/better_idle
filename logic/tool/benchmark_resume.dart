// Benchmarks resuming after a 24h absence (woodcutting by default).
//
// Usage:
//   dart run tool/benchmark_resume.dart [action_name]
//   dart --observe run tool/benchmark_resume.dart --profile
//
// Then analyze the profile:
//   dart run tool/analyze_profile.dart cpu_profile.json
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/data/registries_io.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// It's not valid to look up an action by name, since there are duplicates
// e.g. Golbin thieving and combat.  But this is good enough for this script.
Action? actionByName(Registries registries, String name) {
  return registries.allActions.firstWhereOrNull((a) => a.name == name);
}

void main(List<String> args) async {
  final profile = args.contains('--profile');
  final positionalArgs = args.where((a) => a != '--profile').toList();
  final actionName = positionalArgs.isNotEmpty
      ? positionalArgs.join(' ')
      : 'Normal Tree';

  final registries = await loadRegistries();

  final action = actionByName(registries, actionName);
  if (action == null) {
    print('Error: Unknown action "$actionName"');
    return;
  }

  // Create initial state with the action running.
  var state = GlobalState.empty(registries);

  // If the action requires inputs, add them to the inventory.
  if (action is SkillAction && action.inputs.isNotEmpty) {
    var inventory = state.inventory;
    for (final entry in action.inputs.entries) {
      final item = registries.items.byId(entry.key);
      const itemsNeeded = 50000;
      inventory = inventory.adding(ItemStack(item, count: itemsNeeded));
    }
    state = state.copyWith(inventory: inventory);
  }

  final random = Random(42); // Fixed seed for reproducibility.
  state = state.startAction(action, random: random);

  const oneDay = Duration(hours: 24);
  final ticks = ticksFromDuration(oneDay);

  print('Benchmarking 24h resume of "${action.name}" ($ticks ticks)...');

  // Warm up (short run to JIT-compile hot paths).
  final warmupState = state;
  final warmupRandom = Random(0);
  consumeManyTicks(
    warmupState,
    1000,
    endTime: DateTime.now(),
    random: warmupRandom,
  );

  // Connect to VM service for CPU profiling if requested.
  ({VmService service, String isolateId})? profiler;
  if (profile) {
    final info = await Service.getInfo();
    final uri = info.serverWebSocketUri;
    if (uri == null) {
      print('ERROR: --profile requires VM service.');
      print('Run: dart --observe run tool/benchmark_resume.dart --profile');
      exit(1);
    }
    final service = await vmServiceConnectUri(uri.toString());
    final vm = await service.getVM();
    final id = vm.isolates!.first.id!;
    await service.clearCpuSamples(id);
    profiler = (service: service, isolateId: id);
  }

  // Benchmark.
  final sw = Stopwatch()..start();
  final (_, finalState) = consumeManyTicks(
    state,
    ticks,
    endTime: state.updatedAt.add(oneDay),
    random: random,
  );
  sw.stop();

  // Collect CPU profile if requested.
  if (profiler != null) {
    final cpuSamples = await profiler.service.getCpuSamples(
      profiler.isolateId,
      0,
      ~0 >>> 1,
    );
    final profileJson = jsonEncode(cpuSamples.json);
    final outFile = File('cpu_profile.json')..writeAsStringSync(profileJson);
    print('CPU profile written to ${outFile.path}');
    await profiler.service.dispose();
  }

  final ms = sw.elapsedMilliseconds;
  final ticksPerMs = ticks / ms;
  print('Completed in ${ms}ms (${ticksPerMs.toStringAsFixed(0)} ticks/ms)');
  print(
    'Woodcutting level: '
    '${finalState.skillState(Skill.woodcutting).skillLevel}',
  );
}
