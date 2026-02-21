import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Shorthand for [PlayerCombatStats.fromState] with empty condition context.
PlayerCombatStats testCombatStats(GlobalState state) =>
    PlayerCombatStats.fromState(
      state,
      conditionContext: ConditionContext.empty,
    );

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

      final stats = testCombatStats(state);

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

      final lowStats = testCombatStats(lowStrength);
      final highStats = testCombatStats(highStrength);

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

      final lowStats = testCombatStats(lowAttack);
      final highStats = testCombatStats(highAttack);

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

      final lowStats = testCombatStats(lowDefence);
      final highStats = testCombatStats(highDefence);

      expect(highStats.meleeEvasion, greaterThan(lowStats.meleeEvasion));
      expect(highStats.rangedEvasion, greaterThan(lowStats.rangedEvasion));
      expect(highStats.magicEvasion, greaterThan(lowStats.magicEvasion));
    });
  });

  group('MonsterCombatStats', () {
    test('fromAction computes stats from monster levels', () {
      // Find a combat action (monster)
      final monster = testRegistries.allActions
          .whereType<CombatAction>()
          .firstWhere((CombatAction a) => a.name == 'Plant');

      final stats = MonsterCombatStats.fromAction(monster);

      expect(stats.maxHit, greaterThan(0));
      expect(stats.accuracy, greaterThan(0));
      expect(stats.meleeEvasion, greaterThan(0));
    });
  });

  group('createModifierProvider for combat', () {
    test('returns zero modifiers with no equipment or shop purchases', () {
      final state = GlobalState.test(testRegistries);
      final modifiers = state.createCombatModifierProvider(
        conditionContext: ConditionContext.empty,
      );

      // With no equipment or purchases, should have zero for combat modifiers
      expect(modifiers.lifesteal, 0);
      expect(modifiers.flatMeleeStrengthBonus, 0);
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
      expect(
        bronzeSword.equipmentStats.getAsModifier(
          EquipmentStatModifier.equipmentAttackSpeed,
        ),
        2400,
      );

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

      final statsWithWeapon = testCombatStats(stateWithWeapon);
      final statsUnarmed = testCombatStats(stateUnarmed);

      // Unarmed = 4 seconds, Bronze Sword = 2.4 seconds
      expect(statsUnarmed.attackSpeed, 4.0);
      expect(statsWithWeapon.attackSpeed, 2.4);
    });

    test('weapon strength bonus affects max hit', () {
      // Bronze Sword has meleeStrengthBonus in equipmentStats
      expect(
        bronzeSword.equipmentStats.getAsModifier(
          EquipmentStatModifier.flatMeleeStrengthBonus,
        ),
        greaterThan(0),
      );

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

      final statsWithWeapon = testCombatStats(stateWithWeapon);
      final statsUnarmed = testCombatStats(stateUnarmed);

      // Max hit should be higher with weapon strength bonus
      expect(statsWithWeapon.maxHit, greaterThan(statsUnarmed.maxHit));
    });

    test('weapon attack bonus affects accuracy', () {
      // Bronze Sword has stabAttackBonus in equipmentStats
      expect(
        bronzeSword.equipmentStats.getAsModifier(
          EquipmentStatModifier.flatStabAttackBonus,
        ),
        greaterThan(0),
      );

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

      final statsWithWeapon = testCombatStats(stateWithWeapon);
      final statsUnarmed = testCombatStats(stateUnarmed);

      // Accuracy should be higher with attack bonus
      expect(statsWithWeapon.accuracy, greaterThan(statsUnarmed.accuracy));
    });

    test('armor defence bonus affects evasion', () {
      // Bronze Helmet has meleeDefenceBonus in equipmentStats
      expect(
        bronzeHelmet.equipmentStats.getAsModifier(
          EquipmentStatModifier.flatMeleeDefenceBonus,
        ),
        greaterThan(0),
      );

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

      final statsWithArmor = testCombatStats(stateWithArmor);
      final statsNaked = testCombatStats(stateNaked);

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

      final statsFullGear = testCombatStats(stateFullGear);
      final statsWeaponOnly = testCombatStats(stateWeaponOnly);

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
      // Use 100 damage for clearer numbers
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.stab);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Attack: floor(100 * 0.04) = 4
      expect(grant.xpGrants[Skill.attack], equals(4));
      // No Strength or Defence XP
      expect(grant.xpGrants[Skill.strength], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
    });

    test('slash style grants Strength XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.slash);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Strength: floor(100 * 0.04) = 4
      expect(grant.xpGrants[Skill.strength], equals(4));
      // No Attack or Defence XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
    });

    test('block style grants Defence XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.block);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Defence: floor(100 * 0.04) = 4
      expect(grant.xpGrants[Skill.defence], equals(4));
      // No Attack or Strength XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
    });

    test('totalXp returns sum of all XP grants', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.stab);
      // Hitpoints: 13, Attack: 4, total = 17
      expect(grant.totalXp, equals(17));
    });

    test('isEmpty returns false when XP is granted', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.stab);
      expect(grant.isEmpty, isFalse);
    });

    test('zero damage grants no XP', () {
      final grant = CombatXpGrant.fromDamage(0, AttackStyle.stab);
      expect(grant.xpGrants, isEmpty);
    });

    test('low damage grants minimum 1 XP per skill', () {
      // 1 damage would give floor(1 * 0.04) = 0, but minimum is 1
      final grant = CombatXpGrant.fromDamage(1, AttackStyle.stab);
      expect(grant.xpGrants[Skill.hitpoints], equals(1));
      expect(grant.xpGrants[Skill.attack], equals(1));
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

      final updated = state.setAttackStyle(AttackStyle.block);
      expect(updated.attackStyle, equals(AttackStyle.block));
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

    test('combatType returns correct type for each style', () {
      // Melee styles
      expect(AttackStyle.stab.combatType, equals(CombatType.melee));
      expect(AttackStyle.slash.combatType, equals(CombatType.melee));
      expect(AttackStyle.block.combatType, equals(CombatType.melee));

      // Ranged styles
      expect(AttackStyle.accurate.combatType, equals(CombatType.ranged));
      expect(AttackStyle.rapid.combatType, equals(CombatType.ranged));
      expect(AttackStyle.longRange.combatType, equals(CombatType.ranged));
    });

    test('isMelee and isRanged return correct values', () {
      expect(AttackStyle.stab.isMelee, isTrue);
      expect(AttackStyle.stab.isRanged, isFalse);

      expect(AttackStyle.accurate.isMelee, isFalse);
      expect(AttackStyle.accurate.isRanged, isTrue);
    });
  });

  group('Ranged Combat XP', () {
    test('accurate style grants Ranged XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.accurate);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Ranged: floor(100 * 0.04) = 4
      expect(grant.xpGrants[Skill.ranged], equals(4));
      // No melee XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
    });

    test('rapid style grants Ranged XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.rapid);

      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      expect(grant.xpGrants[Skill.ranged], equals(4));
    });

    test('longRange style splits XP between Ranged and Defence', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.longRange);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Each skill: floor(100 * 0.02) = 2
      expect(grant.xpGrants[Skill.ranged], equals(2));
      expect(grant.xpGrants[Skill.defence], equals(2));
      // No attack/strength XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
    });
  });

  group('Ranged PlayerCombatStats', () {
    test('ranged style uses Ranged level for max hit', () {
      final lowRanged = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
        skillStates: const {
          Skill.ranged: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highRanged = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
        skillStates: const {
          Skill.ranged: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final lowStats = testCombatStats(lowRanged);
      final highStats = testCombatStats(highRanged);

      expect(highStats.maxHit, greaterThan(lowStats.maxHit));
    });

    test('ranged style uses Ranged level for accuracy', () {
      final lowRanged = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
        skillStates: const {
          Skill.ranged: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highRanged = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
        skillStates: const {
          Skill.ranged: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final lowStats = testCombatStats(lowRanged);
      final highStats = testCombatStats(highRanged);

      expect(highStats.accuracy, greaterThan(lowStats.accuracy));
    });

    test('rapid style has faster attack speed', () {
      final accurateState = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
      );
      final rapidState = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.rapid,
      );

      final accurateStats = testCombatStats(accurateState);
      final rapidStats = testCombatStats(rapidState);

      // Rapid should be 20% faster (lower attack speed value)
      expect(rapidStats.attackSpeed, lessThan(accurateStats.attackSpeed));
      // Verify it's approximately 80% of the accurate speed
      expect(
        rapidStats.attackSpeed,
        closeTo(accurateStats.attackSpeed * 0.8, 0.01),
      );
    });

    test('accurate style gives +3 effective ranged level', () {
      // Both have same ranged level, but accurate should have better stats
      // due to +3 effective level bonus
      final rapidState = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.rapid,
        skillStates: const {
          Skill.ranged: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
        },
      );
      final accurateState = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.accurate,
        skillStates: const {
          Skill.ranged: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
        },
      );

      final rapidStats = testCombatStats(rapidState);
      final accurateStats = testCombatStats(accurateState);

      // Accurate should have higher accuracy due to +3 effective level
      expect(accurateStats.accuracy, greaterThan(rapidStats.accuracy));
      // Accurate should also have higher max hit due to +3 effective level
      expect(accurateStats.maxHit, greaterThan(rapidStats.maxHit));
    });
  });

  group('Magic Combat XP', () {
    test('standard style grants Magic XP and Hitpoints XP', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.standard);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Magic: floor(100 * 0.04) = 4
      expect(grant.xpGrants[Skill.magic], equals(4));
      // No melee or ranged XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
      expect(grant.xpGrants[Skill.defence], isNull);
      expect(grant.xpGrants[Skill.ranged], isNull);
    });

    test('defensive style splits XP between Magic and Defence', () {
      final grant = CombatXpGrant.fromDamage(100, AttackStyle.defensive);

      // Hitpoints: floor(100 * 0.133) = 13
      expect(grant.xpGrants[Skill.hitpoints], equals(13));
      // Each skill: floor(100 * 0.02) = 2
      expect(grant.xpGrants[Skill.magic], equals(2));
      expect(grant.xpGrants[Skill.defence], equals(2));
      // No attack/strength/ranged XP
      expect(grant.xpGrants[Skill.attack], isNull);
      expect(grant.xpGrants[Skill.strength], isNull);
      expect(grant.xpGrants[Skill.ranged], isNull);
    });
  });

  group('Magic PlayerCombatStats', () {
    test('magic style uses Magic level for max hit', () {
      final lowMagic = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.standard,
        skillStates: const {
          Skill.magic: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highMagic = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.standard,
        skillStates: const {
          Skill.magic: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final lowStats = testCombatStats(lowMagic);
      final highStats = testCombatStats(highMagic);

      expect(highStats.maxHit, greaterThan(lowStats.maxHit));
    });

    test('magic style uses Magic level for accuracy', () {
      final lowMagic = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.standard,
        skillStates: const {
          Skill.magic: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      final highMagic = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.standard,
        skillStates: const {
          Skill.magic: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final lowStats = testCombatStats(lowMagic);
      final highStats = testCombatStats(highMagic);

      expect(highStats.accuracy, greaterThan(lowStats.accuracy));
    });

    test('magic evasion uses Magic level (70%) and Defence level (30%)', () {
      // Player with high magic but low defence
      final highMagicLowDefence = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.magic: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
          Skill.defence: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
        },
      );

      // Player with low magic but high defence
      final lowMagicHighDefence = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.magic: SkillState(xp: 0, masteryPoolXp: 0), // Level 1
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      // Player with both high
      final highBoth = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.magic: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0), // Level 99
        },
      );

      final statsHighMagic = testCombatStats(highMagicLowDefence);
      final statsHighDefence = testCombatStats(lowMagicHighDefence);
      final statsBoth = testCombatStats(highBoth);

      // Since magic is 70% weighted, high magic should give better magic
      // evasion than high defence alone
      expect(
        statsHighMagic.magicEvasion,
        greaterThan(statsHighDefence.magicEvasion),
      );
      // Both high should be best
      expect(statsBoth.magicEvasion, greaterThan(statsHighMagic.magicEvasion));
    });
  });

  group('Magic AttackStyle', () {
    test('combatType returns magic for magic styles', () {
      expect(AttackStyle.standard.combatType, equals(CombatType.magic));
      expect(AttackStyle.defensive.combatType, equals(CombatType.magic));
    });

    test('isMagic returns true for magic styles', () {
      expect(AttackStyle.standard.isMagic, isTrue);
      expect(AttackStyle.defensive.isMagic, isTrue);

      // And false for others
      expect(AttackStyle.stab.isMagic, isFalse);
      expect(AttackStyle.accurate.isMagic, isFalse);
    });

    test('magic styles can be serialized and deserialized', () {
      for (final style in [AttackStyle.standard, AttackStyle.defensive]) {
        final json = style.toJson();
        final restored = AttackStyle.fromJson(json);
        expect(restored, equals(style));
      }
    });
  });

  group('Min Hit Modifiers', () {
    test('flatMinHit increases minHit for all styles', () {
      // flatMinHit is scaled by 10 during parsing, so we provide the
      // already-scaled value here (simulating post-parsing data).
      const itemWithFlatMinHit = Item(
        id: MelvorId('test:flatMinHitItem'),
        name: 'Test Flat Min Hit',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          // Value of 20 means +20 min hit (already scaled)
          ModifierData(name: 'flatMinHit', entries: [ModifierEntry(value: 20)]),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithFlatMinHit},
      );
      final stateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateWithout = GlobalState.test(testRegistries);

      final statsWithItem = testCombatStats(stateWithItem);
      final statsWithout = testCombatStats(stateWithout);

      // flatMinHit=20 means +20 min hit
      expect(statsWithItem.minHit, equals(statsWithout.minHit + 20));
    });

    test('flatMagicMinHit increases minHit for magic style only', () {
      // flatMagicMinHit is scaled by 10 during parsing, so we provide the
      // already-scaled value here.
      const itemWithFlatMagicMinHit = Item(
        id: MelvorId('test:flatMagicMinHitItem'),
        name: 'Test Flat Magic Min Hit',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          // Value of 15 means +15 min hit for magic (already scaled)
          ModifierData(
            name: 'flatMagicMinHit',
            entries: [ModifierEntry(value: 15)],
          ),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithFlatMagicMinHit},
      );

      // Magic style should benefit from flatMagicMinHit
      final magicStateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
        attackStyle: AttackStyle.standard,
      );
      final magicStateWithout = GlobalState.test(
        testRegistries,
        attackStyle: AttackStyle.standard,
      );

      final magicStatsWithItem = testCombatStats(magicStateWithItem);
      final magicStatsWithout = testCombatStats(magicStateWithout);

      // flatMagicMinHit=15 means +15 min hit for magic
      expect(magicStatsWithItem.minHit, equals(magicStatsWithout.minHit + 15));

      // Melee style should NOT benefit from flatMagicMinHit
      final meleeStateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final meleeStateWithout = GlobalState.test(testRegistries);

      final meleeStatsWithItem = testCombatStats(meleeStateWithItem);
      final meleeStatsWithout = testCombatStats(meleeStateWithout);

      // Melee should have same minHit with or without the magic-specific
      // modifier
      expect(meleeStatsWithItem.minHit, equals(meleeStatsWithout.minHit));
    });

    test('minHitBasedOnMaxHit adds percentage of maxHit to minHit', () {
      const itemWithMinHitPercent = Item(
        id: MelvorId('test:minHitBasedOnMaxHitItem'),
        name: 'Test Min Hit Based On Max',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'minHitBasedOnMaxHit',
            entries: [ModifierEntry(value: 10)],
          ),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithMinHitPercent},
      );
      final stateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );
      final stateWithout = GlobalState.test(testRegistries);

      final statsWithItem = testCombatStats(stateWithItem);
      final statsWithout = testCombatStats(stateWithout);

      // minHitBasedOnMaxHit=10 means +10% of maxHit added to minHit
      // minHit should be base + 10% of maxHit
      final expectedMinHit = 1 + (statsWithItem.maxHit * 10 / 100).floor();
      expect(statsWithItem.minHit, equals(expectedMinHit));
      // Without the modifier, minHit should just be base (1)
      expect(statsWithout.minHit, equals(1));
    });

    test('magicMinHitBasedOnMaxHit adds percentage only for magic style', () {
      const itemWithMagicMinHitPercent = Item(
        id: MelvorId('test:magicMinHitBasedOnMaxHitItem'),
        name: 'Test Magic Min Hit Based On Max',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'magicMinHitBasedOnMaxHit',
            entries: [ModifierEntry(value: 15)],
          ),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithMagicMinHitPercent},
      );

      // Magic style should benefit
      final magicStateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
        attackStyle: AttackStyle.standard,
      );

      final magicStats = testCombatStats(magicStateWithItem);

      // minHit should be base + 15% of maxHit
      final expectedMagicMinHit = 1 + (magicStats.maxHit * 15 / 100).floor();
      expect(magicStats.minHit, equals(expectedMagicMinHit));

      // Melee style should NOT benefit
      final meleeStateWithItem = GlobalState.test(
        testRegistries,
        equipment: equipment,
      );

      final meleeStats = testCombatStats(meleeStateWithItem);

      // minHit should just be base (1) for melee
      expect(meleeStats.minHit, equals(1));
    });

    test('minHit modifiers stack correctly', () {
      // Item with multiple min hit modifiers.
      // flatMinHit and flatMagicMinHit are scaled by 10 during parsing,
      // so we provide already-scaled values here.
      const itemWithMultipleMinHitMods = Item(
        id: MelvorId('test:multiMinHitItem'),
        name: 'Test Multi Min Hit',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          // +10 (already scaled)
          ModifierData(name: 'flatMinHit', entries: [ModifierEntry(value: 10)]),
          // +5 for magic (already scaled)
          ModifierData(
            name: 'flatMagicMinHit',
            entries: [ModifierEntry(value: 5)],
          ),
          // +5% of maxHit
          ModifierData(
            name: 'minHitBasedOnMaxHit',
            entries: [ModifierEntry(value: 5)],
          ),
          // +5% of maxHit for magic
          ModifierData(
            name: 'magicMinHitBasedOnMaxHit',
            entries: [ModifierEntry(value: 5)],
          ),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithMultipleMinHitMods},
      );

      // Magic style: gets all modifiers
      final magicState = GlobalState.test(
        testRegistries,
        equipment: equipment,
        attackStyle: AttackStyle.standard,
      );
      final magicStats = testCombatStats(magicState);

      // Expected: 1 + 10 (flatMinHit) + 5 (flatMagicMinHit) + 10% of maxHit
      // (5% minHitBasedOnMaxHit + 5% magicMinHitBasedOnMaxHit = 10%)
      final expectedMagicMinHit =
          1 + 10 + 5 + (magicStats.maxHit * 10 / 100).floor();
      expect(magicStats.minHit, equals(expectedMagicMinHit));

      // Melee style: only gets generic modifiers
      final meleeState = GlobalState.test(testRegistries, equipment: equipment);
      final meleeStats = testCombatStats(meleeState);

      // Expected: 1 + 10 (flatMinHit) + 5% of maxHit (only generic)
      final expectedMeleeMinHit =
          1 + 10 + (meleeStats.maxHit * 5 / 100).floor();
      expect(meleeStats.minHit, equals(expectedMeleeMinHit));
    });

    test('minHit is clamped to maxHit', () {
      // Item with very high minHit modifiers that would exceed maxHit
      const itemWithHighMinHit = Item(
        id: MelvorId('test:highMinHitItem'),
        name: 'Test High Min Hit',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          // 200% of maxHit!
          ModifierData(
            name: 'minHitBasedOnMaxHit',
            entries: [ModifierEntry(value: 200)],
          ),
        ]),
      );

      const equipment = Equipment(
        foodSlots: [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: itemWithHighMinHit},
      );

      final state = GlobalState.test(testRegistries, equipment: equipment);
      final stats = testCombatStats(state);

      // minHit should be clamped to maxHit
      expect(stats.minHit, equals(stats.maxHit));
    });
  });

  group('CombatTriangle', () {
    group('getModifiers', () {
      test('returns neutral modifiers for same combat type', () {
        // Melee vs Melee
        var mods = CombatTriangle.getModifiers(
          CombatType.melee,
          AttackType.melee,
        );
        expect(mods.damageModifier, equals(1.0));
        expect(mods.damageReductionModifier, equals(1.0));

        // Ranged vs Ranged
        mods = CombatTriangle.getModifiers(
          CombatType.ranged,
          AttackType.ranged,
        );
        expect(mods.damageModifier, equals(1.0));
        expect(mods.damageReductionModifier, equals(1.0));

        // Magic vs Magic
        mods = CombatTriangle.getModifiers(CombatType.magic, AttackType.magic);
        expect(mods.damageModifier, equals(1.0));
        expect(mods.damageReductionModifier, equals(1.0));
      });

      test('melee beats ranged (player advantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.melee,
          AttackType.ranged,
        );
        // Player deals 10% more damage
        expect(mods.damageModifier, equals(1.10));
        // Player's damage reduction is 25% more effective
        expect(mods.damageReductionModifier, equals(1.25));
      });

      test('ranged beats magic (player advantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.ranged,
          AttackType.magic,
        );
        expect(mods.damageModifier, equals(1.10));
        expect(mods.damageReductionModifier, equals(1.25));
      });

      test('magic beats melee (player advantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.magic,
          AttackType.melee,
        );
        expect(mods.damageModifier, equals(1.10));
        expect(mods.damageReductionModifier, equals(1.25));
      });

      test('melee vs magic (player disadvantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.melee,
          AttackType.magic,
        );
        // Player deals 15% less damage
        expect(mods.damageModifier, equals(0.85));
        // Player's damage reduction is 25% less effective
        expect(mods.damageReductionModifier, equals(0.75));
      });

      test('ranged vs melee (player disadvantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.ranged,
          AttackType.melee,
        );
        expect(mods.damageModifier, equals(0.85));
        // Ranged vs Melee has less severe DR penalty (0.95)
        expect(mods.damageReductionModifier, equals(0.95));
      });

      test('magic vs ranged (player disadvantage)', () {
        final mods = CombatTriangle.getModifiers(
          CombatType.magic,
          AttackType.ranged,
        );
        expect(mods.damageModifier, equals(0.85));
        expect(mods.damageReductionModifier, equals(0.85));
      });

      test('random attack type converts to melee for triangle', () {
        // Random attack type converts to melee in AttackType.combatType
        final mods = CombatTriangle.getModifiers(
          CombatType.magic,
          AttackType.random,
        );
        // Magic vs Melee (random -> melee) = advantage
        expect(mods.damageModifier, equals(1.10));
        expect(mods.damageReductionModifier, equals(1.25));
      });
    });

    group('applyDamageModifier', () {
      test('applies neutral modifier correctly', () {
        final damage = CombatTriangle.applyDamageModifier(
          100,
          CombatTriangleModifiers.neutral,
        );
        expect(damage, equals(100));
      });

      test('applies advantage damage modifier (1.10x)', () {
        const advantageMods = CombatTriangleModifiers(
          damageModifier: 1.10,
          damageReductionModifier: 1.25,
        );
        final damage = CombatTriangle.applyDamageModifier(100, advantageMods);
        expect(damage, equals(110));
      });

      test('applies disadvantage damage modifier (0.85x)', () {
        const disadvantageMods = CombatTriangleModifiers(
          damageModifier: 0.85,
          damageReductionModifier: 0.75,
        );
        final damage = CombatTriangle.applyDamageModifier(
          100,
          disadvantageMods,
        );
        expect(damage, equals(85));
      });

      test('rounds correctly for non-integer results', () {
        const mods = CombatTriangleModifiers(
          damageModifier: 1.10,
          damageReductionModifier: 1,
        );
        // 77 * 1.10 = 84.7, should round to 85
        expect(CombatTriangle.applyDamageModifier(77, mods), equals(85));
        // 73 * 1.10 = 80.3, should round to 80
        expect(CombatTriangle.applyDamageModifier(73, mods), equals(80));
      });
    });

    group('applyDamageReduction', () {
      test('applies damage reduction with neutral modifier', () {
        // 100 damage, 20% DR, neutral modifier
        // Result = 100 * (1 - 0.20 * 1.0) = 100 * 0.80 = 80
        final result = CombatTriangle.applyDamageReduction(
          100,
          0.20,
          CombatTriangleModifiers.neutral,
        );
        expect(result, equals(80));
      });

      test('advantage makes damage reduction more effective', () {
        const advantageMods = CombatTriangleModifiers(
          damageModifier: 1.10,
          damageReductionModifier: 1.25,
        );
        // 100 damage, 20% DR, advantage modifier
        // Effective DR = 0.20 * 1.25 = 0.25
        // Result = 100 * (1 - 0.25) = 75
        final result = CombatTriangle.applyDamageReduction(
          100,
          0.20,
          advantageMods,
        );
        expect(result, equals(75));
      });

      test('disadvantage makes damage reduction less effective', () {
        const disadvantageMods = CombatTriangleModifiers(
          damageModifier: 0.85,
          damageReductionModifier: 0.75,
        );
        // 100 damage, 20% DR, disadvantage modifier
        // Effective DR = 0.20 * 0.75 = 0.15
        // Result = 100 * (1 - 0.15) = 85
        final result = CombatTriangle.applyDamageReduction(
          100,
          0.20,
          disadvantageMods,
        );
        expect(result, equals(85));
      });

      test('caps effective damage reduction at 95%', () {
        const advantageMods = CombatTriangleModifiers(
          damageModifier: 1.10,
          damageReductionModifier: 1.25,
        );
        // 100 damage, 90% DR, advantage modifier
        // Without cap: effective DR = 0.90 * 1.25 = 1.125 (>100%!)
        // With cap: effective DR = 0.95
        // Result = 100 * (1 - 0.95) = 5
        final result = CombatTriangle.applyDamageReduction(
          100,
          0.90,
          advantageMods,
        );
        expect(result, equals(5));
      });

      test('does not go below 0% damage reduction', () {
        const badMods = CombatTriangleModifiers(
          damageModifier: 0.85,
          damageReductionModifier: -1, // Hypothetical negative modifier
        );
        // Should clamp to 0% DR, meaning full damage taken
        final result = CombatTriangle.applyDamageReduction(100, 0.20, badMods);
        expect(result, equals(100));
      });
    });

    group('integration with AttackStyle', () {
      test('melee style against ranged monster has advantage', () {
        final mods = CombatTriangle.getModifiers(
          AttackStyle.stab.combatType, // Melee
          AttackType.ranged,
        );
        expect(mods.damageModifier, greaterThan(1.0));
        expect(mods.damageReductionModifier, greaterThan(1.0));
      });

      test('ranged style against melee monster has disadvantage', () {
        final mods = CombatTriangle.getModifiers(
          AttackStyle.accurate.combatType, // Ranged
          AttackType.melee,
        );
        expect(mods.damageModifier, lessThan(1.0));
        expect(mods.damageReductionModifier, lessThan(1.0));
      });

      test('magic style against melee monster has advantage', () {
        final mods = CombatTriangle.getModifiers(
          AttackStyle.standard.combatType, // Magic
          AttackType.melee,
        );
        expect(mods.damageModifier, greaterThan(1.0));
        expect(mods.damageReductionModifier, greaterThan(1.0));
      });
    });
  });

  group('buildCombatConditionContext', () {
    test('populates player and enemy fields', () {
      final monster = testRegistries.combatAction('Plant');
      final state = GlobalState.test(
        testRegistries,
      ).startAction(monster, random: Random(42));

      final context = state.buildCombatConditionContext(
        enemyAction: monster,
        enemyCurrentHp: monster.maxHp,
      );

      expect(context.playerAttackType, state.attackStyle.combatType);
      expect(context.enemyAttackType, monster.attackType.combatType);
      expect(context.playerHpPercent, 100);
      expect(context.enemyHpPercent, 100);
      expect(context.isFightingSlayerTask, false);
    });

    test('enemy HP percentage reflects partial HP', () {
      final monster = testRegistries.combatAction('Plant');
      final state = GlobalState.test(testRegistries);

      final context = state.buildCombatConditionContext(
        enemyAction: monster,
        enemyCurrentHp: monster.maxHp ~/ 2,
      );

      expect(context.enemyHpPercent, closeTo(50, 1));
    });

    test('isFightingSlayerTask true when fighting slayer task monster', () {
      final monster = testRegistries.combatAction('Plant');
      final state = GlobalState.test(
        testRegistries,
        slayerTask: SlayerTask(
          categoryId: const MelvorId('melvorD:Easy'),
          monsterId: monster.id.localId,
          killsRequired: 10,
          killsCompleted: 0,
        ),
        activeActivity: CombatActivity(
          context: MonsterCombatContext(monsterId: monster.id.localId),
          progress: CombatProgressState(
            monsterHp: monster.maxHp,
            playerAttackTicksRemaining: 24,
            monsterAttackTicksRemaining: 24,
          ),
          progressTicks: 0,
          totalTicks: 24,
        ),
      );

      final context = state.buildCombatConditionContext(
        enemyAction: monster,
        enemyCurrentHp: monster.maxHp,
      );

      expect(context.isFightingSlayerTask, true);
    });

    test('PlayerCombatStats.fromState accepts conditionContext', () {
      final state = GlobalState.test(testRegistries);
      // Should not throw with either empty or populated context.
      final statsEmpty = testCombatStats(state);
      final statsWithContext = PlayerCombatStats.fromState(
        state,
        conditionContext: const ConditionContext(
          playerAttackType: CombatType.melee,
          enemyAttackType: CombatType.melee,
          playerHpPercent: 100,
          enemyHpPercent: 50,
        ),
      );
      // Without conditional modifier items, stats should be the same.
      expect(statsWithContext.maxHit, statsEmpty.maxHit);
    });
  });
}
