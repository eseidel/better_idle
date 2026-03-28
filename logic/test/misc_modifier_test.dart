import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item birdNestPotionI;
  late Item bones;
  late Item rawChicken;
  late Item feathers;
  late Item shrimp;
  late Action normalTree;

  setUpAll(() async {
    await loadTestRegistries();
    birdNestPotionI = testItems.byName('Bird Nest Potion I');
    bones = testItems.byName('Bones');
    rawChicken = testItems.byName('Raw Chicken');
    feathers = testItems.byName('Feathers');
    shrimp = testItems.byName('Shrimp');
    normalTree = testRegistries.woodcuttingAction('Normal Tree');
  });

  group('flatPotionCharges modifier', () {
    test('consumePotionCharge uses base charges without modifier', () {
      final charges = birdNestPotionI.potionCharges!;
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(birdNestPotionI, count: 2),
        ]),
        selectedPotions: {Skill.woodcutting.id: birdNestPotionI.id},
        potionChargesUsed: {Skill.woodcutting.id: charges - 1},
      );

      // Use a fixed seed random that won't trigger preservation
      final random = Random(42);
      final builder = StateUpdateBuilder(state)
        ..consumePotionCharge(normalTree as SkillAction, random);
      final newState = builder.build();

      // At charges-1, consuming one more should reach maxCharges
      // (base). Since flatPotionCharges modifier is 0 by default,
      // this should consume one potion from inventory.
      expect(newState.inventory.countOfItem(birdNestPotionI), 1);
    });
  });

  group('allowLootContainerStacking modifier', () {
    test('non-bone items do not stack without modifier', () {
      const loot = LootState.empty();
      final stack1 = ItemStack(rawChicken, count: 1);
      final stack2 = ItemStack(rawChicken, count: 1);

      final (loot1, _) = loot.addItem(stack1, isBones: false);
      final (loot2, _) = loot1.addItem(stack2, isBones: false);

      // Without stacking, two separate stacks
      expect(loot2.stackCount, 2);
    });

    test('non-bone items stack with allowStacking', () {
      const loot = LootState.empty();
      final stack1 = ItemStack(rawChicken, count: 1);
      final stack2 = ItemStack(rawChicken, count: 1);

      final (loot1, _) = loot.addItem(
        stack1,
        isBones: false,
        allowStacking: true,
      );
      final (loot2, _) = loot1.addItem(
        stack2,
        isBones: false,
        allowStacking: true,
      );

      // With stacking, items combine into one stack
      expect(loot2.stackCount, 1);
      expect(loot2.stacks[0].count, 2);
    });

    test('bones always stack regardless of allowStacking', () {
      const loot = LootState.empty();
      final stack1 = ItemStack(bones, count: 1);
      final stack2 = ItemStack(bones, count: 2);

      final (loot1, _) = loot.addItem(stack1, isBones: true);
      final (loot2, _) = loot1.addItem(stack2, isBones: true);

      expect(loot2.stackCount, 1);
      expect(loot2.stacks[0].count, 3);
    });

    test('different items do not stack with allowStacking', () {
      const loot = LootState.empty();
      final stack1 = ItemStack(rawChicken, count: 1);
      final stack2 = ItemStack(feathers, count: 1);

      final (loot1, _) = loot.addItem(
        stack1,
        isBones: false,
        allowStacking: true,
      );
      final (loot2, _) = loot1.addItem(
        stack2,
        isBones: false,
        allowStacking: true,
      );

      expect(loot2.stackCount, 2);
    });
  });

  group('rebirthChance modifier', () {
    test('death without rebirth always rolls a slot', () {
      final weapon = testItems.byName('Bronze Scimitar');
      final equipment = const Equipment.empty().copyWith(
        gearSlots: {EquipmentSlot.weapon: weapon},
      );
      final state = GlobalState.test(testRegistries, equipment: equipment);

      // Without rebirth modifier, all deaths should roll a slot
      var slotRolledCount = 0;
      for (var i = 0; i < 50; i++) {
        final random = Random(i);
        final builder = StateUpdateBuilder(state)..applyDeathPenalty(random);
        if (builder.lastDeathPenalty!.slotRolled != null) {
          slotRolledCount++;
        }
      }
      expect(slotRolledCount, 50);
    });
  });

  group('itemProtection modifier', () {
    test('death without protection can lose items', () {
      final weapon = testItems.byName('Bronze Scimitar');
      final equipment = const Equipment.empty().copyWith(
        gearSlots: {EquipmentSlot.weapon: weapon},
      );
      final state = GlobalState.test(testRegistries, equipment: equipment);

      // Run multiple deaths and check that some lose items
      var lostCount = 0;
      for (var i = 0; i < 100; i++) {
        final random = Random(i);
        final builder = StateUpdateBuilder(state)..applyDeathPenalty(random);
        if (builder.lastDeathPenalty!.itemLost != null) {
          lostCount++;
        }
      }
      expect(lostCount, greaterThan(0));
    });
  });

  group('DeathPenaltyResult', () {
    test('slotRolled is nullable for protected deaths', () {
      const result = DeathPenaltyResult(equipment: Equipment.empty());
      expect(result.slotRolled, isNull);
      expect(result.itemLost, isNull);
      expect(result.wasLucky, isTrue);
    });

    test('slotRolled is set for normal deaths', () {
      const result = DeathPenaltyResult(
        equipment: Equipment.empty(),
        slotRolled: EquipmentSlot.weapon,
      );
      expect(result.slotRolled, EquipmentSlot.weapon);
      expect(result.wasLucky, isTrue); // No item lost
    });
  });

  group('autoEquipFoodUnlocked modifier', () {
    test('auto-equip food from bank when food slot empty', () {
      // Create state with food in inventory but not equipped
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 10),
        ]),
        health: const HealthState(lostHp: 50),
      );

      // With autoEquipFoodUnlocked and autoEatThreshold
      final modifiers = StubModifierProvider({
        'autoEatThreshold': 80,
        'autoEatHPLimit': 100,
        'autoEatEfficiency': 100,
        'autoEquipFoodUnlocked': 1,
      });

      final builder = StateUpdateBuilder(state);
      final consumed = builder.tryAutoEat(modifiers);

      // Should have auto-equipped and eaten food
      expect(consumed, greaterThan(0));
    });

    test('no auto-equip without modifier', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(shrimp, count: 10),
        ]),
        health: const HealthState(lostHp: 50),
      );

      // Without autoEquipFoodUnlocked
      final modifiers = StubModifierProvider({
        'autoEatThreshold': 80,
        'autoEatHPLimit': 100,
        'autoEatEfficiency': 100,
      });

      final builder = StateUpdateBuilder(state);
      final consumed = builder.tryAutoEat(modifiers);

      // No food equipped, should not eat
      expect(consumed, 0);
    });
  });

  group('StateUpdateBuilder.addToLoot with allowStacking', () {
    test('passes allowStacking to LootState.addItem', () {
      final state = GlobalState.test(testRegistries);
      // Add same item twice without stacking
      final builder = StateUpdateBuilder(state)
        ..addToLoot(ItemStack(rawChicken, count: 1), isBones: false)
        ..addToLoot(ItemStack(rawChicken, count: 1), isBones: false);
      expect(builder.state.loot.stackCount, 2);

      // Reset and add with stacking
      final state2 = GlobalState.test(testRegistries);
      final builder2 = StateUpdateBuilder(state2)
        ..addToLoot(
          ItemStack(rawChicken, count: 1),
          isBones: false,
          allowStacking: true,
        )
        ..addToLoot(
          ItemStack(rawChicken, count: 1),
          isBones: false,
          allowStacking: true,
        );
      expect(builder2.state.loot.stackCount, 1);
      expect(builder2.state.loot.stacks[0].count, 2);
    });
  });
}
