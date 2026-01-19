import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ActionState', () {
    group('toJson/fromJson', () {
      test('round-trips with CombatActionState', () {
        final monsterId = ActionId.test(Skill.combat, 'Cow');
        final original = ActionState(
          masteryXp: 100,
          combat: CombatActionState(
            monsterId: monsterId,
            monsterHp: 50,
            playerAttackTicksRemaining: 24,
            monsterAttackTicksRemaining: 30,
          ),
        );

        final json = original.toJson();
        final restored = ActionState.fromJson(json);

        expect(restored.masteryXp, original.masteryXp);
        expect(restored.combat, isNotNull);
        expect(restored.combat!.monsterId, monsterId);
        expect(restored.combat!.monsterHp, 50);
        expect(restored.combat!.playerAttackTicksRemaining, 24);
        expect(restored.combat!.monsterAttackTicksRemaining, 30);
        expect(restored.combat!.spawnTicksRemaining, isNull);
      });

      test(
        'round-trips with CombatActionState including respawnTicksRemaining',
        () {
          final monsterId = ActionId.test(Skill.combat, 'Cow');
          final original = ActionState(
            masteryXp: 250,
            combat: CombatActionState(
              monsterId: monsterId,
              monsterHp: 0,
              playerAttackTicksRemaining: 20,
              monsterAttackTicksRemaining: 25,
              spawnTicksRemaining: 30,
            ),
          );

          final json = original.toJson();
          final restored = ActionState.fromJson(json);

          expect(restored.masteryXp, original.masteryXp);
          expect(restored.combat, isNotNull);
          expect(restored.combat!.monsterId, monsterId);
          expect(restored.combat!.monsterHp, 0);
          expect(restored.combat!.playerAttackTicksRemaining, 20);
          expect(restored.combat!.monsterAttackTicksRemaining, 25);
          expect(restored.combat!.spawnTicksRemaining, 30);
        },
      );

      test('round-trips empty ActionState', () {
        const original = ActionState.empty();

        final json = original.toJson();
        final restored = ActionState.fromJson(json);

        expect(restored.masteryXp, 0);
        expect(restored.combat, isNull);
      });

      test('round-trips ActionState with only masteryXp', () {
        const original = ActionState(masteryXp: 500);

        final json = original.toJson();
        final restored = ActionState.fromJson(json);

        expect(restored.masteryXp, 500);
        expect(restored.combat, isNull);
      });
    });
  });

  group('CombatActionState', () {
    group('toJson/fromJson', () {
      test('round-trips correctly', () {
        final monsterId = ActionId.test(Skill.combat, 'Goblin');
        final original = CombatActionState(
          monsterId: monsterId,
          monsterHp: 100,
          playerAttackTicksRemaining: 24,
          monsterAttackTicksRemaining: 28,
        );

        final json = original.toJson();
        final restored = CombatActionState.fromJson(json);

        expect(restored.monsterId, monsterId);
        expect(restored.monsterHp, 100);
        expect(restored.playerAttackTicksRemaining, 24);
        expect(restored.monsterAttackTicksRemaining, 28);
        expect(restored.spawnTicksRemaining, isNull);
      });

      test('round-trips with respawnTicksRemaining', () {
        final monsterId = ActionId.test(Skill.combat, 'Goblin');
        final original = CombatActionState(
          monsterId: monsterId,
          monsterHp: 0,
          playerAttackTicksRemaining: 24,
          monsterAttackTicksRemaining: 28,
          spawnTicksRemaining: 30,
        );

        final json = original.toJson();
        final restored = CombatActionState.fromJson(json);

        expect(restored.monsterId, monsterId);
        expect(restored.monsterHp, 0);
        expect(restored.playerAttackTicksRemaining, 24);
        expect(restored.monsterAttackTicksRemaining, 28);
        expect(restored.spawnTicksRemaining, 30);
      });
    });

    test('isSpawning returns true when spawnTicksRemaining is set', () {
      final state = CombatActionState(
        monsterId: ActionId.test(Skill.combat, 'Cow'),
        monsterHp: 0,
        playerAttackTicksRemaining: 24,
        monsterAttackTicksRemaining: 28,
        spawnTicksRemaining: 30,
      );
      expect(state.isSpawning, isTrue);
    });

    test('isSpawning returns false when spawnTicksRemaining is null', () {
      final state = CombatActionState(
        monsterId: ActionId.test(Skill.combat, 'Cow'),
        monsterHp: 50,
        playerAttackTicksRemaining: 24,
        monsterAttackTicksRemaining: 28,
      );
      expect(state.isSpawning, isFalse);
    });
  });
}
