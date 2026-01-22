import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('MiningAction', () {
    test('mining actions are loaded from JSON', () {
      final miningActions = testRegistries.mining.actions;
      expect(miningActions, isNotEmpty);
    });

    test('mining actions have valid properties', () {
      final miningActions = testRegistries.mining.actions;

      for (final action in miningActions) {
        expect(action.name, isNotEmpty);
        expect(action.unlockLevel, greaterThanOrEqualTo(1));
        expect(action.xp, greaterThan(0));
        expect(action.respawnTime.inSeconds, greaterThan(0));
        expect(action.outputs, isNotEmpty);
      }
    });

    test('mining actions belong to mining skill', () {
      final miningActions = testRegistries.mining.actions;

      for (final action in miningActions) {
        expect(action.skill, equals(Skill.mining));
      }
    });
  });

  group('MiningAction.respawnProgress', () {
    late MiningAction miningAction;

    setUp(() {
      final miningActions = testRegistries.mining.actions;
      expect(miningActions, isNotEmpty);
      miningAction = miningActions.first;
    });

    test('returns null when not respawning', () {
      const miningState = MiningState.empty();
      final progress = miningAction.respawnProgress(miningState);
      expect(progress, isNull);
    });

    test('returns null when mining state has no respawn ticks', () {
      const miningState = MiningState();
      final progress = miningAction.respawnProgress(miningState);
      expect(progress, isNull);
    });

    test('returns 0.0 at start of respawn', () {
      final miningState = MiningState(
        respawnTicksRemaining: miningAction.respawnTicks,
      );
      final progress = miningAction.respawnProgress(miningState);
      expect(progress, equals(0.0));
    });

    test('returns 1.0 when respawn complete', () {
      const miningState = MiningState(respawnTicksRemaining: 0);
      final progress = miningAction.respawnProgress(miningState);
      expect(progress, equals(1.0));
    });

    test('returns 0.5 at halfway through respawn', () {
      final halfwayTicks = miningAction.respawnTicks ~/ 2;
      final miningState = MiningState(respawnTicksRemaining: halfwayTicks);
      final progress = miningAction.respawnProgress(miningState);
      expect(progress, closeTo(0.5, 0.01));
    });

    test('returns correct progress for various tick values', () {
      final respawnTicks = miningAction.respawnTicks;

      // 25% complete (75% remaining)
      final quarter = MiningState(
        respawnTicksRemaining: (respawnTicks * 0.75).round(),
      );
      expect(miningAction.respawnProgress(quarter), closeTo(0.25, 0.1));

      // 75% complete (25% remaining)
      final threeQuarter = MiningState(
        respawnTicksRemaining: (respawnTicks * 0.25).round(),
      );
      expect(miningAction.respawnProgress(threeQuarter), closeTo(0.75, 0.1));
    });
  });

  group('MiningAction.maxHpForMasteryLevel', () {
    late MiningAction miningAction;

    setUp(() {
      final miningActions = testRegistries.mining.actions;
      miningAction = miningActions.first;
    });

    test('returns 5 at mastery level 0', () {
      expect(miningAction.maxHpForMasteryLevel(0), equals(5));
    });

    test('returns 6 at mastery level 1', () {
      expect(miningAction.maxHpForMasteryLevel(1), equals(6));
    });

    test('increases by 1 per mastery level', () {
      for (var level = 0; level <= 10; level++) {
        expect(miningAction.maxHpForMasteryLevel(level), equals(5 + level));
      }
    });
  });

  group('MiningAction.respawnTicks', () {
    test('respawnTicks matches respawnTime', () {
      final miningActions = testRegistries.mining.actions;

      for (final action in miningActions) {
        final expectedTicks = ticksFromDuration(action.respawnTime);
        expect(action.respawnTicks, equals(expectedTicks));
      }
    });
  });

  group('MiningState.fromJson', () {
    test('parses all fields', () {
      final json = {
        'totalHpLost': 3,
        'respawnTicksRemaining': 50,
        'hpRegenTicksRemaining': 10,
      };
      final state = MiningState.fromJson(json);
      expect(state.totalHpLost, equals(3));
      expect(state.respawnTicksRemaining, equals(50));
      expect(state.hpRegenTicksRemaining, equals(10));
    });

    test('uses defaults for missing fields', () {
      final state = MiningState.fromJson(const {});
      expect(state.totalHpLost, equals(0));
      expect(state.respawnTicksRemaining, isNull);
      expect(state.hpRegenTicksRemaining, equals(0));
    });

    test('round-trips through toJson', () {
      const original = MiningState(
        totalHpLost: 7,
        respawnTicksRemaining: 100,
        hpRegenTicksRemaining: 25,
      );
      final json = original.toJson();
      final restored = MiningState.fromJson(json);
      expect(restored.totalHpLost, equals(original.totalHpLost));
      expect(
        restored.respawnTicksRemaining,
        equals(original.respawnTicksRemaining),
      );
      expect(
        restored.hpRegenTicksRemaining,
        equals(original.hpRegenTicksRemaining),
      );
    });
  });
}
