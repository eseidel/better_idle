import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('MasteryLevelBonus', () {
    test('countAtLevel returns 0 when below level', () {
      const bonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([]),
        level: 10,
      );
      expect(bonus.countAtLevel(5), 0);
      expect(bonus.countAtLevel(9), 0);
    });

    test('countAtLevel returns 1 for non-scaling bonus at or above level', () {
      const bonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([]),
        level: 10,
      );
      expect(bonus.countAtLevel(10), 1);
      expect(bonus.countAtLevel(50), 1);
      expect(bonus.countAtLevel(99), 1);
    });

    test('countAtLevel counts scaling bonuses correctly', () {
      const bonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([]),
        level: 10,
        levelScalingSlope: 10,
        levelScalingMax: 90,
      );
      // Triggers at 10, 20, 30, 40, 50, 60, 70, 80, 90
      expect(bonus.countAtLevel(5), 0);
      expect(bonus.countAtLevel(10), 1);
      expect(bonus.countAtLevel(19), 1);
      expect(bonus.countAtLevel(20), 2);
      expect(bonus.countAtLevel(50), 5);
      expect(bonus.countAtLevel(90), 9);
      expect(bonus.countAtLevel(99), 9); // Capped at levelScalingMax
    });

    test('countAtLevel with slope but no max scales indefinitely', () {
      const bonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([]),
        level: 1,
        levelScalingSlope: 1,
      );
      // Triggers at 1, 2, 3, ... up to masteryLevel
      expect(bonus.countAtLevel(1), 1);
      expect(bonus.countAtLevel(50), 50);
      expect(bonus.countAtLevel(99), 99);
    });

    test('fromJson parses scalar modifier', () {
      final json = {
        'modifiers': {'masteryXP': 0.25},
        'level': 99,
        'autoScopeToAction': false,
      };
      final bonus = MasteryLevelBonus.fromJson(json, namespace: 'melvorD');

      expect(bonus.level, 99);
      expect(bonus.levelScalingSlope, isNull);
      expect(bonus.levelScalingMax, isNull);
      expect(bonus.autoScopeToAction, false);
      expect(bonus.modifiers.modifiers.length, 1);
      expect(bonus.modifiers.modifiers.first.name, 'masteryXP');
      expect(bonus.modifiers.modifiers.first.totalValue, 0.25);
    });

    test('fromJson parses array modifier with scope', () {
      final json = {
        'modifiers': {
          'skillInterval': [
            {
              'skillID': 'melvorD:Firemaking',
              'actionID': 'Normal_Logs',
              'value': -0.1,
            },
          ],
        },
        'level': 1,
        'levelScalingSlope': 1,
        'levelScalingMax': 99,
      };
      final bonus = MasteryLevelBonus.fromJson(json, namespace: 'melvorD');

      expect(bonus.level, 1);
      expect(bonus.levelScalingSlope, 1);
      expect(bonus.levelScalingMax, 99);
      expect(bonus.autoScopeToAction, true); // Default
      expect(bonus.modifiers.modifiers.length, 1);

      final mod = bonus.modifiers.modifiers.first;
      expect(mod.name, 'skillInterval');
      expect(mod.entries.length, 1);
      expect(
        mod.entries.first.scope?.skillId,
        const MelvorId('melvorD:Firemaking'),
      );
      expect(
        mod.entries.first.scope?.actionId,
        const MelvorId('melvorD:Normal_Logs'),
      );
      expect(mod.entries.first.value, -0.1);
    });

    test('fromJson parses template modifier (actionID only)', () {
      final json = {
        'modifiers': {
          'fishingMasteryDoublingChance': [
            {'actionID': 'Raw_Shrimp', 'value': 0.4},
          ],
        },
        'level': 1,
        'levelScalingSlope': 1,
        'levelScalingMax': 99,
      };
      final bonus = MasteryLevelBonus.fromJson(json, namespace: 'melvorD');

      expect(bonus.autoScopeToAction, true);
      final mod = bonus.modifiers.modifiers.first;
      expect(mod.entries.first.scope?.skillId, isNull);
      expect(
        mod.entries.first.scope?.actionId,
        const MelvorId('melvorD:Raw_Shrimp'),
      );
    });
  });

  group('MasteryBonusRegistry', () {
    test('loads bonuses for woodcutting', () {
      final woodcutting = testMasteryBonuses.forSkill(
        const MelvorId('melvorD:Woodcutting'),
      );
      expect(woodcutting, isNotNull);
      expect(woodcutting!.bonuses, isNotEmpty);
    });

    test('loads bonuses for fishing', () {
      final fishing = testMasteryBonuses.forSkill(
        const MelvorId('melvorD:Fishing'),
      );
      expect(fishing, isNotNull);
      expect(fishing!.bonuses, isNotEmpty);

      // Fishing has template modifiers (actionID only)
      final templateBonus = fishing.bonuses.firstWhere(
        (b) => b.modifiers.byName('fishingMasteryDoublingChance') != null,
      );
      expect(templateBonus.autoScopeToAction, true);
    });

    test('loads bonuses for firemaking with autoScopeToAction false', () {
      final firemaking = testMasteryBonuses.forSkill(
        const MelvorId('melvorD:Firemaking'),
      );
      expect(firemaking, isNotNull);

      // Firemaking has a level 99 bonus with autoScopeToAction: false
      final globalBonus = firemaking!.bonuses.firstWhere(
        (b) => b.level == 99 && !b.autoScopeToAction,
        orElse: () => throw StateError('Expected global mastery bonus at 99'),
      );
      expect(globalBonus.modifiers.byName('masteryXP'), isNotNull);
    });

    test('returns null for unknown skill', () {
      final unknown = testMasteryBonuses.forSkill(
        const MelvorId('melvorD:UnknownSkill'),
      );
      expect(unknown, isNull);
    });

    test('skillIds returns all skills with bonuses', () {
      expect(
        testMasteryBonuses.skillIds,
        contains(const MelvorId('melvorD:Woodcutting')),
      );
      expect(
        testMasteryBonuses.skillIds,
        contains(const MelvorId('melvorD:Fishing')),
      );
      expect(
        testMasteryBonuses.skillIds,
        contains(const MelvorId('melvorD:Mining')),
      );
      expect(
        testMasteryBonuses.skillIds,
        contains(const MelvorId('melvorD:Cooking')),
      );
    });
  });

  group('SkillMasteryBonuses', () {
    test('contains expected bonus structure for mining', () {
      final mining = testMasteryBonuses.forSkill(
        const MelvorId('melvorD:Mining'),
      );
      expect(mining, isNotNull);

      // Mining has scaling bonuses for node HP and doubling chance
      final hasNodeHpBonus = mining!.bonuses.any(
        (b) => b.modifiers.byName('flatMiningNodeHP') != null,
      );
      expect(hasNodeHpBonus, isTrue);
    });
  });
}
