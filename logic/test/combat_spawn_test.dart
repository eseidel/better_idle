import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late CombatAction cow;

  setUpAll(() async {
    await loadTestRegistries();
    cow = testActions.combat('Cow');
  });

  group('Combat Spawn Delay', () {
    test('combat starts with spawn timer', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);

      // Start combat
      state = state.startAction(cow, random: random);

      // Verify that the combat state starts in spawning mode
      final actionState = state.actionState(cow.id);
      final combat = actionState.combat;

      expect(combat, isNotNull);
      expect(combat!.isSpawning, isTrue);
      expect(combat.monsterHp, 0);
      expect(
        combat.spawnTicksRemaining,
        ticksFromDuration(monsterSpawnDuration),
      );
    });

    test('monster spawns after spawn duration', () {
      var state = GlobalState.empty(testRegistries);
      final random = Random(0);

      // Start combat
      state = state.startAction(cow, random: random);

      final builder = StateUpdateBuilder(state);
      // Advance time by the spawn duration (3 seconds = 30 ticks)
      consumeTicks(
        builder,
        ticksFromDuration(monsterSpawnDuration),
        random: random,
      );
      state = builder.build();

      // Verify that the monster has spawned
      final actionState = state.actionState(cow.id);
      final combat = actionState.combat;

      expect(combat, isNotNull);
      expect(combat!.isSpawning, isFalse);
      expect(combat.monsterHp, cow.maxHp);
      expect(combat.spawnTicksRemaining, isNull);
    });
  });
}
