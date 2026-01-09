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

    test(
      'controlled style splits XP evenly between Attack, Strength, Defence',
      () {
        final grant = CombatXpGrant.fromDamage(300, AttackStyle.controlled);

        // Hitpoints: floor(300 * 0.133) = 39
        expect(grant.xpGrants[Skill.hitpoints], equals(39));
        // Each skill: floor(300 * 0.04 / 3) = floor(4) = 4
        expect(grant.xpGrants[Skill.attack], equals(4));
        expect(grant.xpGrants[Skill.strength], equals(4));
        expect(grant.xpGrants[Skill.defence], equals(4));
      },
    );

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

    test('combatType returns correct type for each style', () {
      // Melee styles
      expect(AttackStyle.stab.combatType, equals(CombatType.melee));
      expect(AttackStyle.slash.combatType, equals(CombatType.melee));
      expect(AttackStyle.block.combatType, equals(CombatType.melee));
      expect(AttackStyle.controlled.combatType, equals(CombatType.melee));

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

      final lowStats = PlayerCombatStats.fromState(lowRanged);
      final highStats = PlayerCombatStats.fromState(highRanged);

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

      final lowStats = PlayerCombatStats.fromState(lowRanged);
      final highStats = PlayerCombatStats.fromState(highRanged);

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

      final accurateStats = PlayerCombatStats.fromState(accurateState);
      final rapidStats = PlayerCombatStats.fromState(rapidState);

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

      final rapidStats = PlayerCombatStats.fromState(rapidState);
      final accurateStats = PlayerCombatStats.fromState(accurateState);

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

      final lowStats = PlayerCombatStats.fromState(lowMagic);
      final highStats = PlayerCombatStats.fromState(highMagic);

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

      final lowStats = PlayerCombatStats.fromState(lowMagic);
      final highStats = PlayerCombatStats.fromState(highMagic);

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

      final statsHighMagic = PlayerCombatStats.fromState(highMagicLowDefence);
      final statsHighDefence = PlayerCombatStats.fromState(lowMagicHighDefence);
      final statsBoth = PlayerCombatStats.fromState(highBoth);

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
}
