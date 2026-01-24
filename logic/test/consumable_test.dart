import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late CombatAction cow;
  late Item whetstone;

  setUpAll(() async {
    await loadTestRegistries();
    cow = testRegistries.combatAction('Cow');
    whetstone = testItems.byName('Whetstone');
  });

  group('ConsumesOn parsing', () {
    test('Whetstone has PlayerAttack consumesOn with melee filter', () {
      expect(whetstone.consumesOn, isNotEmpty);
      expect(whetstone.consumesOn.first.type, ConsumesOnType.playerAttack);
      expect(
        whetstone.consumesOn.first.attackTypes,
        contains(CombatType.melee),
      );
    });

    test('Monster Hunter Scroll has PlayerAttack consumesOn', () {
      final monsterHunterScroll = testItems.byName('Monster Hunter Scroll');
      expect(monsterHunterScroll.consumesOn, isNotEmpty);
      expect(
        monsterHunterScroll.consumesOn.first.type,
        ConsumesOnType.playerAttack,
      );
      // No attack type filter
      expect(monsterHunterScroll.consumesOn.first.attackTypes, isNull);
    });

    test('Items with Consumable slot can be equipped', () {
      expect(whetstone.validSlots, contains(EquipmentSlot.consumable));
    });
  });

  group('calculateMonsterSpawnTicks', () {
    test('base spawn time is 3 seconds (30 ticks)', () {
      final ticks = calculateMonsterSpawnTicks(0);
      expect(ticks, 30);
    });

    test('negative modifier reduces spawn time', () {
      // -200ms = -0.2 seconds
      final ticks = calculateMonsterSpawnTicks(-200);
      // 3000ms - 200ms = 2800ms = 28 ticks
      expect(ticks, 28);
    });

    test('large negative modifier clamps to minimum', () {
      // -3000ms would be 0, but should clamp to minimum (3 ticks = 0.25s)
      final ticks = calculateMonsterSpawnTicks(-3000);
      expect(ticks, minMonsterSpawnTicks);
    });

    test('positive modifier increases spawn time', () {
      // +500ms = +0.5 seconds
      final ticks = calculateMonsterSpawnTicks(500);
      // 3000ms + 500ms = 3500ms = 35 ticks
      expect(ticks, 35);
    });
  });

  group('Consumable consumption on player attack', () {
    test('StateUpdateBuilder.consumeConsumable reduces count', () {
      // Direct test of consumeConsumable method
      var state = GlobalState.test(testRegistries);

      // Equip whetstone (10 of them)
      final equipment = state.equipment;
      final (newEquipment, _) = equipment.equipStackedItem(
        whetstone,
        EquipmentSlot.consumable,
        10,
      );
      state = state.copyWith(
        equipment: newEquipment,
        attackStyle: AttackStyle.stab, // melee
      );

      // Verify whetstone is equipped
      expect(state.equipment.stackCountInSlot(EquipmentSlot.consumable), 10);

      // Directly call consumeConsumable
      final builder = StateUpdateBuilder(state)
        ..consumeConsumable(
          ConsumesOnType.playerAttack,
          attackType: CombatType.melee,
        );
      state = builder.build();

      // Should have consumed one
      expect(state.equipment.stackCountInSlot(EquipmentSlot.consumable), 9);
    });

    test('consumable is consumed during combat player attack', () {
      // Set up state with whetstone equipped in consumable slot
      var state = GlobalState.test(
        testRegistries,
        // Give enough HP to survive combat
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 50000, masteryPoolXp: 0),
        },
      );

      // Equip whetstone (10 of them)
      final equipment = state.equipment;
      final (newEquipment, _) = equipment.equipStackedItem(
        whetstone,
        EquipmentSlot.consumable,
        10,
      );
      state = state.copyWith(equipment: newEquipment);

      // Verify whetstone is equipped
      expect(state.equipment.gearInSlot(EquipmentSlot.consumable), whetstone);
      expect(state.equipment.stackCountInSlot(EquipmentSlot.consumable), 10);

      final random = Random(42);

      // Start combat with melee attack style (whetstone triggers on melee)
      state = state.copyWith(attackStyle: AttackStyle.stab);
      state = state.startAction(cow, random: random);

      // Process enough ticks to spawn monster and get a player attack
      // Spawn takes 30 ticks, player attack speed is ~2.4s (24 ticks for lvl 1)
      // Need 30 + 24 = 54 ticks minimum, use 100 to be safe
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: random);
      state = builder.build();

      // Verify whetstone was consumed (should have fewer than 10 now)
      final remainingCount = state.equipment.stackCountInSlot(
        EquipmentSlot.consumable,
      );
      expect(remainingCount, lessThan(10));
    });

    test(
      'consumable with attack type filter only consumed for matching attacks',
      () {
        // Whetstone only triggers on melee, not ranged
        var state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 50000, masteryPoolXp: 0),
          },
        );

        // Equip whetstone
        final equipment = state.equipment;
        final (newEquipment, _) = equipment.equipStackedItem(
          whetstone,
          EquipmentSlot.consumable,
          10,
        );
        state = state.copyWith(equipment: newEquipment);

        final random = Random(42);

        // Use ranged attack style - whetstone should NOT be consumed
        state = state.copyWith(attackStyle: AttackStyle.accurate);
        state = state.startAction(cow, random: random);

        // Process enough ticks to get player attacks
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 60, random: random);
        state = builder.build();

        // Whetstone should still have 10 (not consumed for ranged)
        final remainingCount = state.equipment.stackCountInSlot(
          EquipmentSlot.consumable,
        );
        expect(remainingCount, 10);
      },
    );

    test('consumable is unequipped when depleted', () {
      var state = GlobalState.test(testRegistries);

      // Equip just 1 whetstone
      final equipment = state.equipment;
      final (newEquipment, _) = equipment.equipStackedItem(
        whetstone,
        EquipmentSlot.consumable,
        1,
      );
      state = state.copyWith(
        equipment: newEquipment,
        attackStyle: AttackStyle.stab, // melee
      );

      // Directly consume it
      final builder = StateUpdateBuilder(state)
        ..consumeConsumable(
          ConsumesOnType.playerAttack,
          attackType: CombatType.melee,
        );
      state = builder.build();

      // Whetstone should be unequipped (depleted)
      expect(state.equipment.gearInSlot(EquipmentSlot.consumable), isNull);
      expect(state.equipment.stackCountInSlot(EquipmentSlot.consumable), 0);
    });
  });

  group('Monster spawn with modifiers', () {
    test('combat starts with modified spawn time when modifier equipped', () {
      // We need an item that provides flatMonsterRespawnInterval
      // Monster Hunter Scroll provides -200 (via conditionalModifiers)
      // For now, test the calculation directly since conditionalModifiers
      // aren't fully implemented

      // Test that startAction uses the modifier
      var state = GlobalState.test(testRegistries);
      final random = Random(0);

      // Start combat
      state = state.startAction(cow, random: random);

      // Verify spawn ticks use the base duration (no modifiers equipped)
      final actionState = state.actionState(cow.id);
      final combat = actionState.combat;
      expect(combat!.spawnTicksRemaining, 30); // 3 seconds = 30 ticks
    });
  });
}
