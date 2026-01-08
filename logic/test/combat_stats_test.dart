import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('CombatCalculator', () {
    test('calculateHitChance returns 50% when accuracy equals evasion', () {
      final hitChance = CombatCalculator.calculateHitChance(100, 100);
      expect(hitChance, closeTo(0.5, 0.001));
    });

    test('calculateHitChance returns > 50% when accuracy > evasion', () {
      final hitChance = CombatCalculator.calculateHitChance(200, 100);
      expect(hitChance, greaterThan(0.5));
      expect(hitChance, lessThan(1.0));
    });

    test('calculateHitChance returns < 50% when accuracy < evasion', () {
      final hitChance = CombatCalculator.calculateHitChance(50, 100);
      expect(hitChance, lessThan(0.5));
      expect(hitChance, greaterThan(0.0));
    });

    test('calculateHitChance returns 0 when accuracy is 0', () {
      final hitChance = CombatCalculator.calculateHitChance(0, 100);
      expect(hitChance, equals(0.0));
    });

    test('calculateHitChance returns 1 when evasion is 0', () {
      final hitChance = CombatCalculator.calculateHitChance(100, 0);
      expect(hitChance, equals(1.0));
    });

    test('calculateHitChance follows Melvor formula', () {
      // When accuracy > evasion: 0.5 + (acc - eva) / (2 * acc)
      // acc=200, eva=100: 0.5 + (200-100)/(2*200) = 0.5 + 100/400 = 0.75
      expect(
        CombatCalculator.calculateHitChance(200, 100),
        closeTo(0.75, 0.001),
      );

      // When accuracy <= evasion: 0.5 * acc / eva
      // acc=50, eva=100: 0.5 * 50/100 = 0.25
      expect(
        CombatCalculator.calculateHitChance(50, 100),
        closeTo(0.25, 0.001),
      );
    });
  });

  group('PlayerCombatStats', () {
    test('fromState computes stats from skill levels', () {
      // Player with level 10 attack and strength
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
          Skill.strength: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
          Skill.defence: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
        },
      );

      final stats = PlayerCombatStats.fromState(state);

      // With no equipment, should have base stats
      expect(stats.maxHit, greaterThan(0));
      expect(stats.minHit, equals(1));
      expect(stats.attackSpeed, equals(4.0)); // Base 4 seconds
      expect(stats.damageReduction, equals(0.0)); // No armor
      expect(stats.accuracy, greaterThan(0));
      expect(stats.meleeEvasion, greaterThan(0));
    });

    test('maxHit increases with strength level', () {
      final lowStrength = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.strength: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highStrength = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0), // Lvl 99
        },
      );

      final lowStats = PlayerCombatStats.fromState(lowStrength);
      final highStats = PlayerCombatStats.fromState(highStrength);

      expect(highStats.maxHit, greaterThan(lowStats.maxHit));
    });

    test('accuracy increases with attack level', () {
      final lowAttack = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highAttack = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final lowStats = PlayerCombatStats.fromState(lowAttack);
      final highStats = PlayerCombatStats.fromState(highAttack);

      expect(highStats.accuracy, greaterThan(lowStats.accuracy));
    });

    test('evasion increases with defence level', () {
      final lowDefence = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.defence: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highDefence = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0), // Lvl 99
        },
      );

      final lowStats = PlayerCombatStats.fromState(lowDefence);
      final highStats = PlayerCombatStats.fromState(highDefence);

      expect(highStats.meleeEvasion, greaterThan(lowStats.meleeEvasion));
      expect(highStats.rangedEvasion, greaterThan(lowStats.rangedEvasion));
      expect(highStats.magicEvasion, greaterThan(lowStats.magicEvasion));
    });
  });

  group('MonsterCombatStats', () {
    test('fromAction computes stats from monster levels', () {
      // Find a combat action (monster)
      final monster = testRegistries.actions.all
          .whereType<CombatAction>()
          .firstWhere((CombatAction a) => a.name == 'Plant');

      final stats = MonsterCombatStats.fromAction(monster);

      expect(stats.maxHit, greaterThan(0));
      expect(stats.accuracy, greaterThan(0));
      expect(stats.meleeEvasion, greaterThan(0));
    });
  });

  group('EquipmentBonuses', () {
    test('empty returns zero for all modifiers', () {
      const bonuses = EquipmentBonuses.empty;

      expect(bonuses.flatMeleeStrengthBonus, equals(0));
      expect(bonuses.flatMaxHit, equals(0));
      expect(bonuses.resistance, equals(0));
    });

    test('fromEquipment sums modifiers from equipped gear', () {
      final state = GlobalState.test(testRegistries);
      final bonuses = EquipmentBonuses.fromEquipment(state);

      // With no equipment, should have empty bonuses
      expect(bonuses.isEmpty, isTrue);
    });
  });
}
