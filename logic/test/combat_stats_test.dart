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

  group('resolveCombatModifiers', () {
    test('returns empty modifiers with no equipment or shop purchases', () {
      final state = GlobalState.test(testRegistries);
      final modifiers = state.resolveCombatModifiers();

      // With no equipment or purchases, should have empty modifiers
      expect(modifiers.isEmpty, isTrue);
    });
  });

  group('equipment combat effects', () {
    late Item bronzeSword;
    late Item bronzeHelmet;

    setUpAll(() {
      bronzeSword = testItems.byName('Bronze Sword');
      bronzeHelmet = testItems.byName('Bronze Helmet');
    });

    test('weapon attack speed affects player attack speed', () {
      // Bronze Sword has 2400ms attack speed
      expect(bronzeSword.equipmentStats.attackSpeed, 2400);

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );
      final stateWithWeapon = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateUnarmed = GlobalState.test(testRegistries);

      final statsWithWeapon = PlayerCombatStats.fromState(stateWithWeapon);
      final statsUnarmed = PlayerCombatStats.fromState(stateUnarmed);

      // Unarmed = 4 seconds, Bronze Sword = 2.4 seconds
      expect(statsUnarmed.attackSpeed, 4.0);
      expect(statsWithWeapon.attackSpeed, 2.4);
    });

    test('weapon strength bonus affects max hit', () {
      // Bronze Sword has meleeStrengthBonus in equipmentStats
      expect(bronzeSword.equipmentStats.meleeStrengthBonus, greaterThan(0));

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );
      final stateWithWeapon = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateUnarmed = GlobalState.test(testRegistries);

      final statsWithWeapon = PlayerCombatStats.fromState(stateWithWeapon);
      final statsUnarmed = PlayerCombatStats.fromState(stateUnarmed);

      // Max hit should be higher with weapon strength bonus
      expect(statsWithWeapon.maxHit, greaterThan(statsUnarmed.maxHit));
    });

    test('weapon attack bonus affects accuracy', () {
      // Bronze Sword has stabAttackBonus in equipmentStats
      expect(bronzeSword.equipmentStats.stabAttackBonus, greaterThan(0));

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );
      final stateWithWeapon = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateUnarmed = GlobalState.test(testRegistries);

      final statsWithWeapon = PlayerCombatStats.fromState(stateWithWeapon);
      final statsUnarmed = PlayerCombatStats.fromState(stateUnarmed);

      // Accuracy should be higher with attack bonus
      expect(statsWithWeapon.accuracy, greaterThan(statsUnarmed.accuracy));
    });

    test('armor defence bonus affects evasion', () {
      // Bronze Helmet has meleeDefenceBonus in equipmentStats
      expect(bronzeHelmet.equipmentStats.meleeDefenceBonus, greaterThan(0));

      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.helmet: bronzeHelmet},
      );
      final stateWithArmor = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateNaked = GlobalState.test(testRegistries);

      final statsWithArmor = PlayerCombatStats.fromState(stateWithArmor);
      final statsNaked = PlayerCombatStats.fromState(stateNaked);

      // Evasion should be higher with defence bonus
      expect(statsWithArmor.meleeEvasion, greaterThan(statsNaked.meleeEvasion));
    });

    test('multiple equipment pieces stack bonuses', () {
      // Equip both weapon and helmet
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {
          EquipmentSlot.weapon: bronzeSword,
          EquipmentSlot.helmet: bronzeHelmet,
        },
      );
      final stateFullGear = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final weaponOnly = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.weapon: bronzeSword},
      );
      final stateWeaponOnly = GlobalState.test(
        testRegistries,
        equipment: weaponOnly,
      );

      final statsFullGear = PlayerCombatStats.fromState(stateFullGear);
      final statsWeaponOnly = PlayerCombatStats.fromState(stateWeaponOnly);

      // With helmet, should have higher evasion
      expect(
        statsFullGear.meleeEvasion,
        greaterThan(statsWeaponOnly.meleeEvasion),
      );
      // Attack speed should be same (determined by weapon)
      expect(statsFullGear.attackSpeed, statsWeaponOnly.attackSpeed);
    });
  });

  group('CombatXpGrant', () {
    test('stab style grants Attack XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(10, AttackStyle.stab);

      // Hitpoints: floor(10 * 1.33) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Attack: 10 * 4 = 40
      expect(grant.xpGrants[Skill.attack], equals(40));
      // No Strength or Defence XP
      expect(grant.xpGrants[Skill.strength], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
    });

    test('slash style grants Strength XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(10, AttackStyle.slash);

      // Hitpoints: floor(10 * 1.33) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Strength: 10 * 4 = 40
      expect(grant.xpGrants[Skill.strength], equals(40));
      // No Attack or Defence XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
    });

    test('block style grants Defence XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(10, AttackStyle.block);

      // Hitpoints: floor(10 * 1.33) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Defence: 10 * 4 = 40
      expect(grant.xpGrants[Skill.defence], equals(40));
      // No Attack or Strength XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
    });

    test(
      'controlled style splits XP evenly between Attack, Strength, Defence',
      () {
        final grant = CombatXpGrant.fromDamage(12, AttackStyle.controlled);

        // Hitpoints: floor(12 * 1.33) = 15
        expect(grant.xpGrants[Skill.hitpoints], equals(15));
        // Combat XP = 12 * 4 = 48, split 3 ways = 16 each
        expect(grant.xpGrants[Skill.attack], equals(16));
        expect(grant.xpGrants[Skill.strength], equals(16));
        expect(grant.xpGrants[Skill.defence], equals(16));
      },
    );

    test('totalXp returns sum of all XP grants', () {
      final grant = CombatXpGrant.fromDamage(10, AttackStyle.stab);
      // Hitpoints: 13, Attack: 40, total = 53
      expect(grant.totalXp, equals(53));
    });

    test('isEmpty returns false when XP is granted', () {
      final grant = CombatXpGrant.fromDamage(10, AttackStyle.stab);
      expect(grant.isEmpty, isFalse);
    });

    test('zero damage grants zero XP', () {
      final grant = CombatXpGrant.fromDamage(0, AttackStyle.stab);
      expect(grant.xpGrants[Skill.hitpoints], equals(0));
      expect(grant.xpGrants[Skill.attack], equals(0));
    });
  });

  group('AttackStyle', () {
    test('can be serialized and deserialized', () {
      for (final style in AttackStyle.values) {
        final json = style.toJson();
        final restored = AttackStyle.fromJson(json);
        expect(restored, equals(style));
      }
    });

    test('GlobalState stores and retrieves attackStyle', () {
      final state = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.slash,
      );

      expect(state.attackStyle, equals(AttackStyle.slash));

      final updated = state.setAttackStyle(AttackStyle.controlled);
      expect(updated.attackStyle, equals(AttackStyle.controlled));
    });

    test('attackStyle persists through JSON serialization', () {
      final state = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.block,
      );

      final json = state.toJson();
      final restored = GlobalState.fromJson(testRegistries, json);

      expect(restored.attackStyle, equals(AttackStyle.block));
    });

    test('attackStyle defaults to stab when not in JSON', () {
      final state = GlobalState.test(testRegistries);
      final json = state.toJson()
        // Remove attackStyle from JSON to simulate old save data
        ..remove('attackStyle');

      final restored = GlobalState.fromJson(testRegistries, json);
      expect(restored.attackStyle, equals(AttackStyle.stab));
    });
  });
}
