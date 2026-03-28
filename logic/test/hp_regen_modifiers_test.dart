import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';
import 'test_modifiers.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('HpRegenParams', () {
    test('none has all-zero values', () {
      const params = HpRegenParams.none;
      expect(params.hitpointRegeneration, 0);
      expect(params.flatHPRegen, 0);
      expect(params.flatRegenerationInterval, 0);
      expect(params.flatHPRegenBasedOnMaxHit, 0);
      expect(params.hpRegenWhenEnemyHasMoreEvasion, 0);
      expect(params.hitpointRegenerationAgainstSlayerTasks, 0);
    });

    test('fromModifiers reads hitpointRegeneration', () {
      const modifiers = TestModifiers({'hitpointRegeneration': 50});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(params.hitpointRegeneration, 50);
    });

    test('fromModifiers reads flatHPRegen', () {
      const modifiers = TestModifiers({'flatHPRegen': 5});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(params.flatHPRegen, 5);
    });

    test('fromModifiers reads flatRegenerationInterval', () {
      const modifiers = TestModifiers({'flatRegenerationInterval': -2000});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(params.flatRegenerationInterval, -2000);
    });

    test('fromModifiers computes flatHPRegenBasedOnMeleeMaxHit', () {
      const modifiers = TestModifiers({'flatHPRegenBasedOnMeleeMaxHit': 10});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 200,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      // 10% of 200 = 20
      expect(params.flatHPRegenBasedOnMaxHit, 20);
    });

    test('fromModifiers computes flatHPRegenBasedOnRangedMaxHit', () {
      const modifiers = TestModifiers({'flatHPRegenBasedOnRangedMaxHit': 15});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.ranged,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      // 15% of 100 = 15
      expect(params.flatHPRegenBasedOnMaxHit, 15);
    });

    test('fromModifiers computes flatHPRegenBasedOnMagicMaxHit', () {
      const modifiers = TestModifiers({'flatHPRegenBasedOnMagicMaxHit': 20});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 150,
        currentCombatType: CombatType.magic,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      // 20% of 150 = 30
      expect(params.flatHPRegenBasedOnMaxHit, 30);
    });

    test('maxHit-based regen is zero when combat type does not match', () {
      // Modifier for melee, but player is using ranged.
      const modifiers = TestModifiers({'flatHPRegenBasedOnMeleeMaxHit': 10});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 200,
        currentCombatType: CombatType.ranged,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(params.flatHPRegenBasedOnMaxHit, 0);
    });

    test('maxHit-based regen is zero outside combat', () {
      const modifiers = TestModifiers({'flatHPRegenBasedOnMeleeMaxHit': 10});
      final params = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 0,
        currentCombatType: null,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(params.flatHPRegenBasedOnMaxHit, 0);
    });

    test(
      'hpRegenWhenEnemyHasMoreEvasion only applies when enemy evasion higher',
      () {
        const modifiers = TestModifiers({'hpRegenWhenEnemyHasMoreEvasion': 3});

        // Enemy has more evasion.
        final paramsActive = HpRegenParams.fromModifiers(
          modifiers,
          currentMaxHit: 100,
          currentCombatType: CombatType.melee,
          enemyHasMoreEvasion: true,
          isFightingSlayerTask: false,
        );
        expect(paramsActive.hpRegenWhenEnemyHasMoreEvasion, 3);

        // Enemy does NOT have more evasion.
        final paramsInactive = HpRegenParams.fromModifiers(
          modifiers,
          currentMaxHit: 100,
          currentCombatType: CombatType.melee,
          enemyHasMoreEvasion: false,
          isFightingSlayerTask: false,
        );
        expect(paramsInactive.hpRegenWhenEnemyHasMoreEvasion, 0);
      },
    );

    test('hitpointRegenerationAgainstSlayerTasks only applies on task', () {
      const modifiers = TestModifiers({
        'hitpointRegenerationAgainstSlayerTasks': 25,
      });

      final paramsOnTask = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: true,
      );
      expect(paramsOnTask.hitpointRegenerationAgainstSlayerTasks, 25);

      final paramsOffTask = HpRegenParams.fromModifiers(
        modifiers,
        currentMaxHit: 100,
        currentCombatType: CombatType.melee,
        enemyHasMoreEvasion: false,
        isFightingSlayerTask: false,
      );
      expect(paramsOffTask.hitpointRegenerationAgainstSlayerTasks, 0);
    });
  });

  group('_applyPlayerHpRegenTicks with modifiers', () {
    // We test via consumeTicks since the regen function is private.
    // The background tick path calls _applyPlayerHpRegenTicks.

    test('base regen heals 1% of max HP every 10 seconds', () {
      // Hitpoints level 10 = 100 maxHP. 1% = 1 HP per regen tick.
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
        },
        health: const HealthState(lostHp: 5),
      );
      expect(state.maxPlayerHp, 100);
      expect(state.playerHp, 95);

      // 100 ticks = 10 seconds = 1 regen tick
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: _seededRandom());
      state = builder.build();

      // Should have healed 1 HP (1% of 100).
      expect(state.health.lostHp, 4);
    });

    test('regen does nothing at full health', () {
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
        },
      );
      expect(state.health.isFullHealth, true);

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 200, random: _seededRandom());
      state = builder.build();

      expect(state.health.isFullHealth, true);
    });

    test('multiple regen ticks heal multiple times', () {
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
        },
        health: const HealthState(lostHp: 10),
      );
      expect(state.maxPlayerHp, 100);

      // 300 ticks = 30 seconds = 3 regen ticks, heals 3 HP.
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 300, random: _seededRandom());
      state = builder.build();

      expect(state.health.lostHp, 7);
    });
  });

  group('foodHealingValue modifier', () {
    late Item shrimp;

    setUpAll(() {
      shrimp = testItems.byName('Shrimp');
    });

    test('foodHealingValue adds flat HP to food healing', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      // Hitpoints level 1 = 10 maxHP. lostHp 9 = 1 HP.
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState(lostHp: 9),
      );

      final builder = StateUpdateBuilder(state);
      // foodHealingValue of 20 adds 20 to shrimp's base heal (30).
      // Total heal = 50 per food. Efficiency 100%.
      // Auto-eat threshold 50 = eat when HP < 5 (player at 1).
      // HP limit 100 = eat until full (10 HP).
      // Need to heal 9 lost HP. 50 per food = 1 food eaten (heals to full).
      const modifiers = TestModifiers({
        'autoEatThreshold': 50,
        'autoEatEfficiency': 100,
        'autoEatHPLimit': 100,
        'foodHealingValue': 20,
      });
      final consumed = builder.tryAutoEat(modifiers);

      expect(consumed, 1);
      // Healed 50 HP (30 base + 20 bonus), but only 9 lost, so full.
      expect(builder.state.health.lostHp, 0);
    });

    test('foodHealingValue of 0 uses base healing only', () {
      final equipment = Equipment(
        foodSlots: [ItemStack(shrimp, count: 10), null, null],
        selectedFoodSlot: 0,
      );
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
        health: const HealthState(lostHp: 9),
      );

      final builder = StateUpdateBuilder(state);
      const modifiers = TestModifiers({
        'autoEatThreshold': 50,
        'autoEatEfficiency': 100,
        'autoEatHPLimit': 100,
      });
      final consumed = builder.tryAutoEat(modifiers);

      expect(consumed, 1);
      // Shrimp heals 30, only lost 9, so fully healed.
      expect(builder.state.health.lostHp, 0);
    });
  });
}

Random _seededRandom() => Random(42);
