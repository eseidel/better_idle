import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('MiningAction', () {
    test('mining actions are loaded from JSON', () {
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();
      expect(miningActions, isNotEmpty);
    });

    test('mining actions have valid properties', () {
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();

      for (final action in miningActions) {
        expect(action.name, isNotEmpty);
        expect(action.unlockLevel, greaterThanOrEqualTo(1));
        expect(action.xp, greaterThan(0));
        expect(action.respawnTime.inSeconds, greaterThan(0));
        expect(action.outputs, isNotEmpty);
      }
    });

    test('mining actions belong to mining skill', () {
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();

      for (final action in miningActions) {
        expect(action.skill, equals(Skill.mining));
      }
    });
  });

  group('MiningAction.respawnProgress', () {
    late MiningAction miningAction;

    setUp(() {
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();
      expect(miningActions, isNotEmpty);
      miningAction = miningActions.first;
    });

    test('returns null when not respawning', () {
      const actionState = ActionState(masteryXp: 0);
      final progress = miningAction.respawnProgress(actionState);
      expect(progress, isNull);
    });

    test('returns null when mining state has no respawn ticks', () {
      const actionState = ActionState(masteryXp: 0, mining: MiningState());
      final progress = miningAction.respawnProgress(actionState);
      expect(progress, isNull);
    });

    test('returns 0.0 at start of respawn', () {
      final actionState = ActionState(
        masteryXp: 0,
        mining: MiningState(respawnTicksRemaining: miningAction.respawnTicks),
      );
      final progress = miningAction.respawnProgress(actionState);
      expect(progress, equals(0.0));
    });

    test('returns 1.0 when respawn complete', () {
      const actionState = ActionState(
        masteryXp: 0,
        mining: MiningState(respawnTicksRemaining: 0),
      );
      final progress = miningAction.respawnProgress(actionState);
      expect(progress, equals(1.0));
    });

    test('returns 0.5 at halfway through respawn', () {
      final halfwayTicks = miningAction.respawnTicks ~/ 2;
      final actionState = ActionState(
        masteryXp: 0,
        mining: MiningState(respawnTicksRemaining: halfwayTicks),
      );
      final progress = miningAction.respawnProgress(actionState);
      expect(progress, closeTo(0.5, 0.01));
    });

    test('returns correct progress for various tick values', () {
      final respawnTicks = miningAction.respawnTicks;

      // 25% complete (75% remaining)
      final quarter = ActionState(
        masteryXp: 0,
        mining: MiningState(
          respawnTicksRemaining: (respawnTicks * 0.75).round(),
        ),
      );
      expect(miningAction.respawnProgress(quarter), closeTo(0.25, 0.1));

      // 75% complete (25% remaining)
      final threeQuarter = ActionState(
        masteryXp: 0,
        mining: MiningState(
          respawnTicksRemaining: (respawnTicks * 0.25).round(),
        ),
      );
      expect(miningAction.respawnProgress(threeQuarter), closeTo(0.75, 0.1));
    });
  });

  group('MiningAction.maxHpForMasteryLevel', () {
    late MiningAction miningAction;

    setUp(() {
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();
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
      final miningActions = testActions
          .forSkill(Skill.mining)
          .whereType<MiningAction>()
          .toList();

      for (final action in miningActions) {
        final expectedTicks = ticksFromDuration(action.respawnTime);
        expect(action.respawnTicks, equals(expectedTicks));
      }
    });
  });
}
