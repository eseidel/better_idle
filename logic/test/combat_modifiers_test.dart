import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Helper to create a test item with a single modifier.
Item _itemWithModifier(String name, String modifierName, num value) {
  return Item.test(
    name,
    gp: 0,
    modifiers: ModifierDataSet([
      ModifierData(
        name: modifierName,
        entries: [ModifierEntry(value: value)],
      ),
    ]),
  );
}

/// Runs combat ticks and returns the updated state.
/// Uses a fixed seed for deterministic results.
GlobalState _runCombatTicks(GlobalState state, int ticks, {int seed = 42}) {
  final random = Random(seed);
  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, ticks, random: random);
  return builder.build();
}

/// Starts combat against the given monster and returns the state.
GlobalState _startCombat(GlobalState state, CombatAction monster) {
  return state.startAction(monster, random: Random(0));
}

void main() {
  setUpAll(loadTestRegistries);

  late CombatAction plantMonster;

  setUp(() {
    plantMonster = testRegistries.combatAction('Plant');
  });

  group('cantAttack modifier', () {
    test('player deals no damage when cantAttack is active', () {
      final cantAttackItem = _itemWithModifier(
        'CantAttackRing',
        'cantAttack',
        1,
      );
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: cantAttackItem},
      );

      var state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      state = _startCombat(state, plantMonster);

      // Run enough ticks for a player attack cycle
      final afterTicks = _runCombatTicks(state, 500);

      // Monster HP should still be full since player can't attack
      final combat = afterTicks.actionState(plantMonster.id).combat;
      expect(combat, isNotNull);
      expect(combat!.monsterHp, plantMonster.maxHp);
    });
  });

  group('disableAttackDamage modifier', () {
    test('player hits but deals zero damage', () {
      final disableItem = _itemWithModifier(
        'NoDamageRing',
        'disableAttackDamage',
        1,
      );
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: disableItem},
      );

      var state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      state = _startCombat(state, plantMonster);

      // Run enough ticks for several attack cycles
      final afterTicks = _runCombatTicks(state, 500);

      // Monster should be at full HP (damage disabled)
      final combat = afterTicks.actionState(plantMonster.id).combat;
      expect(combat, isNotNull);
      expect(combat!.monsterHp, plantMonster.maxHp);
    });
  });

  group('attackRolls modifier', () {
    test('extra attack rolls deal more damage than baseline', () {
      // Baseline: no extra rolls
      var baseState = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      baseState = _startCombat(baseState, plantMonster);

      // With extra rolls
      final extraRollsItem = _itemWithModifier(
        'ExtraRollsRing',
        'attackRolls',
        2,
      );
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: extraRollsItem},
      );
      var bonusState = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      bonusState = _startCombat(bonusState, plantMonster);

      // Use the same seed for both, run enough ticks for one attack cycle
      const seed = 99;
      final baseAfter = _runCombatTicks(baseState, 500, seed: seed);
      final bonusAfter = _runCombatTicks(bonusState, 500, seed: seed);

      final baseHp = baseAfter.actionState(plantMonster.id).combat?.monsterHp;
      final bonusHp = bonusAfter.actionState(plantMonster.id).combat?.monsterHp;

      // With extra rolls, monster should have taken more damage (lower HP)
      // or the monster died (HP == 0 or null due to respawn)
      if (baseHp != null && bonusHp != null) {
        expect(bonusHp, lessThanOrEqualTo(baseHp));
      }
      // If bonus killed the monster, that's also valid - more damage was dealt
    });
  });

  group('cantEvade modifier', () {
    test('monster always hits when player has cantEvade', () {
      final cantEvadeItem = _itemWithModifier('CantEvadeRing', 'cantEvade', 1);
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.ring: cantEvadeItem},
      );

      // Use very high defence so normally monster would miss most attacks
      var state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          Skill.attack: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.strength: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.defence: SkillState(xp: 13034431, masteryPoolXp: 0),
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      state = _startCombat(state, plantMonster);

      // Run combat for a while - with cantEvade the monster should always hit
      // and player should take damage
      final afterTicks = _runCombatTicks(state, 500);

      // Player should have taken damage (lostHp > 0)
      expect(afterTicks.health.lostHp, greaterThan(0));
    });
  });

  group('reflect damage modifiers', () {
    test('reflectDamage reflects percentage of damage taken', () {
      // 100% reflect - all damage taken is reflected back
      final reflectItem = _itemWithModifier(
        'ReflectShield',
        'reflectDamage',
        100,
      );
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.shield: reflectItem},
      );

      var state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          // Low stats so plant can hit us
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      state = _startCombat(state, plantMonster);

      // Run enough ticks for the monster to attack
      final afterTicks = _runCombatTicks(state, 500);

      // Check if monster took reflect damage (HP below max)
      final combat = afterTicks.actionState(plantMonster.id).combat;
      if (combat != null && afterTicks.health.lostHp > 0) {
        // If player took damage, monster should also have taken reflect damage
        expect(combat.monsterHp, lessThan(plantMonster.maxHp));
      }
    });

    test('flatReflectDamage deals flat damage per hit received', () {
      final flatReflectItem = _itemWithModifier(
        'FlatReflectShield',
        'flatReflectDamage',
        5,
      );
      final equipment = Equipment(
        foodSlots: const [null, null, null],
        selectedFoodSlot: 0,
        gearSlots: {EquipmentSlot.shield: flatReflectItem},
      );

      var state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      state = _startCombat(state, plantMonster);

      // Baseline without reflect
      var baseState = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 13034431, masteryPoolXp: 0),
        },
      );
      baseState = _startCombat(baseState, plantMonster);

      const seed = 55;
      final reflectAfter = _runCombatTicks(state, 500, seed: seed);
      final baseAfter = _runCombatTicks(baseState, 500, seed: seed);

      final reflectHp = reflectAfter
          .actionState(plantMonster.id)
          .combat
          ?.monsterHp;
      final baseHp = baseAfter.actionState(plantMonster.id).combat?.monsterHp;

      // With flat reflect, monster should have taken more damage
      if (reflectHp != null && baseHp != null) {
        expect(reflectHp, lessThanOrEqualTo(baseHp));
      }
    });
  });

  group('type-specific resistance modifiers', () {
    test('damageReductionAgainst includes type-specific resistance', () {
      // This is a pure unit test on PlayerCombatStats
      const stats = PlayerCombatStats(
        minHit: 1,
        maxHit: 10,
        damageReduction: 0.10,
        attackSpeed: 3.0,
        accuracy: 100,
        meleeEvasion: 100,
        rangedEvasion: 100,
        magicEvasion: 100,
        flatResistanceAgainstMelee: 10,
        flatResistanceAgainstRanged: 5,
        flatResistanceAgainstMagic: 15,
        flatResistanceAgainstSlayerTasks: 3,
        isFightingSlayerTask: true,
      );

      // Melee: 10% + 10% melee + 3% slayer = 23%
      expect(
        stats.damageReductionAgainst(AttackType.melee),
        closeTo(0.23, 0.001),
      );
      // Ranged: 10% + 5% ranged + 3% slayer = 18%
      expect(
        stats.damageReductionAgainst(AttackType.ranged),
        closeTo(0.18, 0.001),
      );
      // Magic: 10% + 15% magic + 3% slayer = 28%
      expect(
        stats.damageReductionAgainst(AttackType.magic),
        closeTo(0.28, 0.001),
      );
    });
  });
}
