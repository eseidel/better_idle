import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveActivity round-trip', () {
    test('CombatActivity with MonsterCombatContext', () {
      const activity = CombatActivity(
        context: MonsterCombatContext(monsterId: MelvorId('melvorD:Goblin')),
        progress: CombatProgressState(
          monsterHp: 50,
          playerAttackTicksRemaining: 10,
          monsterAttackTicksRemaining: 15,
        ),
        progressTicks: 5,
        totalTicks: 20,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<CombatActivity>());
      final combat = restored as CombatActivity;
      expect(combat.progressTicks, 5);
      expect(combat.totalTicks, 20);
      expect(combat.context, isA<MonsterCombatContext>());
      final context = combat.context as MonsterCombatContext;
      expect(context.monsterId, const MelvorId('melvorD:Goblin'));
      expect(combat.progress.monsterHp, 50);
      expect(combat.progress.playerAttackTicksRemaining, 10);
      expect(combat.progress.monsterAttackTicksRemaining, 15);
      expect(combat.progress.spawnTicksRemaining, isNull);
    });

    test('CombatActivity with MonsterCombatContext and spawn ticks', () {
      const activity = CombatActivity(
        context: MonsterCombatContext(monsterId: MelvorId('melvorD:Cow')),
        progress: CombatProgressState(
          monsterHp: 100,
          playerAttackTicksRemaining: 20,
          monsterAttackTicksRemaining: 25,
          spawnTicksRemaining: 30,
        ),
        progressTicks: 0,
        totalTicks: 30,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<CombatActivity>());
      final combat = restored as CombatActivity;
      expect(combat.progress.spawnTicksRemaining, 30);
      expect(combat.progress.isSpawning, isTrue);
    });

    test('CombatActivity with DungeonCombatContext', () {
      final monsterIds = [
        const MelvorId('melvorD:Goblin'),
        const MelvorId('melvorD:Orc'),
        const MelvorId('melvorD:Troll'),
      ];

      final activity = CombatActivity(
        context: DungeonCombatContext(
          dungeonId: const MelvorId('melvorD:Chicken_Coop'),
          currentMonsterIndex: 1,
          monsterIds: monsterIds,
        ),
        progress: const CombatProgressState(
          monsterHp: 75,
          playerAttackTicksRemaining: 12,
          monsterAttackTicksRemaining: 18,
        ),
        progressTicks: 8,
        totalTicks: 25,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<CombatActivity>());
      final combat = restored as CombatActivity;
      expect(combat.progressTicks, 8);
      expect(combat.totalTicks, 25);
      expect(combat.context, isA<DungeonCombatContext>());
      final context = combat.context as DungeonCombatContext;
      expect(context.dungeonId, const MelvorId('melvorD:Chicken_Coop'));
      expect(context.currentMonsterIndex, 1);
      expect(context.monsterIds, monsterIds);
      expect(context.currentMonsterId, const MelvorId('melvorD:Orc'));
      expect(context.isLastMonster, isFalse);
    });

    test('SkillActivity round-trip', () {
      const activity = SkillActivity(
        skill: Skill.woodcutting,
        actionId: MelvorId('melvorD:Oak_Tree'),
        progressTicks: 10,
        totalTicks: 30,
        selectedRecipeIndex: 2,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<SkillActivity>());
      final skill = restored as SkillActivity;
      expect(skill.skill, Skill.woodcutting);
      expect(skill.actionId, const MelvorId('melvorD:Oak_Tree'));
      expect(skill.progressTicks, 10);
      expect(skill.totalTicks, 30);
      expect(skill.selectedRecipeIndex, 2);
    });

    test('SkillActivity round-trip without selectedRecipeIndex', () {
      const activity = SkillActivity(
        skill: Skill.fishing,
        actionId: MelvorId('melvorD:Raw_Shrimp'),
        progressTicks: 5,
        totalTicks: 15,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<SkillActivity>());
      final skill = restored as SkillActivity;
      expect(skill.selectedRecipeIndex, isNull);
    });

    test('maybeFromJson returns null for null input', () {
      final result = ActiveActivity.maybeFromJson(null);
      expect(result, isNull);
    });

    test('fromJson throws for unknown type', () {
      expect(
        () => ActiveActivity.fromJson({'type': 'unknown'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('AgilityActivity round-trip', () {
      const obstacleIds = [
        ActionId(MelvorId('melvorD:Agility'), MelvorId('melvorD:Rope_Swing')),
        ActionId(MelvorId('melvorD:Agility'), MelvorId('melvorD:Pipe_Balance')),
        ActionId(MelvorId('melvorD:Agility'), MelvorId('melvorD:Rooftop_Run')),
      ];

      const activity = AgilityActivity(
        obstacleIds: obstacleIds,
        currentObstacleIndex: 1,
        progressTicks: 15,
        totalTicks: 40,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<AgilityActivity>());
      final agility = restored as AgilityActivity;
      expect(agility.obstacleIds.length, 3);
      expect(agility.obstacleIds[0], obstacleIds[0]);
      expect(agility.obstacleIds[1], obstacleIds[1]);
      expect(agility.obstacleIds[2], obstacleIds[2]);
      expect(agility.currentObstacleIndex, 1);
      expect(agility.progressTicks, 15);
      expect(agility.totalTicks, 40);
      expect(agility.currentObstacleId, obstacleIds[1]);
      expect(agility.isLastObstacle, isFalse);
      expect(agility.obstacleCount, 3);
    });

    test('AgilityActivity round-trip at last obstacle', () {
      const obstacleIds = [
        ActionId(MelvorId('melvorD:Agility'), MelvorId('melvorD:Rope_Swing')),
        ActionId(MelvorId('melvorD:Agility'), MelvorId('melvorD:Pipe_Balance')),
      ];

      const activity = AgilityActivity(
        obstacleIds: obstacleIds,
        currentObstacleIndex: 1,
        progressTicks: 5,
        totalTicks: 20,
      );

      final json = activity.toJson();
      final restored = ActiveActivity.fromJson(json);

      expect(restored, isA<AgilityActivity>());
      final agility = restored as AgilityActivity;
      expect(agility.isLastObstacle, isTrue);
      expect(agility.currentObstacleId, obstacleIds[1]);
    });
  });
}
