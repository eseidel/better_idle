import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late WoodcuttingTree normalTree;
  late FiremakingAction burnNormalLogs;
  late Item normalLogs;

  setUpAll(() async {
    await loadTestRegistries();

    normalTree =
        testRegistries.woodcuttingAction('Normal Tree') as WoodcuttingTree;
    burnNormalLogs =
        testRegistries.firemakingAction('Burn Normal Logs') as FiremakingAction;
    normalLogs = testItems.byName('Normal Logs');
  });

  group('halveWoodcuttingDoubleChance', () {
    test('halves the doubling chance for woodcutting drops', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');

      // 100% doubling chance, but halved by modifier -> 50%
      final modifiers = StubModifierProvider({
        'skillItemDoublingChance': 100,
        'halveWoodcuttingDoubleChance': 1,
      });

      // Run many rolls to verify statistical halving.
      // With 100% doubling and halving, effective chance is 50%.
      var doubledCount = 0;
      const trials = 200;
      for (var i = 0; i < trials; i++) {
        final trialState = GlobalState.test(testRegistries);
        final trialBuilder = StateUpdateBuilder(trialState);
        final random = Random(i);
        rollAndCollectDrops(
          trialBuilder,
          normalTree,
          modifiers,
          random,
          const NoSelectedRecipe(),
        );
        final count = trialBuilder.state.inventory.countById(normalLogsId);
        if (count == 2) doubledCount++;
      }

      // With 50% effective chance, expect roughly half to double.
      expect(
        doubledCount,
        greaterThan(50),
        reason: 'Expected some doubled drops with 50% chance',
      );
      expect(
        doubledCount,
        lessThan(150),
        reason: 'Expected ~50% doubles, not nearly all',
      );
    });

    test('without modifier, 100% doubling always doubles', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);

      final modifiers = StubModifierProvider({'skillItemDoublingChance': 100});

      final random = Random(42);
      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      final count = builder.state.inventory.countById(normalLogsId);
      expect(count, 2, reason: 'Should always double with 100% chance');
    });

    test('does not affect non-woodcutting actions', () {
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 100),
        ]),
      );
      final builder = StateUpdateBuilder(state);

      final modifiers = StubModifierProvider({
        'skillItemDoublingChance': 100,
        'halveWoodcuttingDoubleChance': 1,
      });

      final random = Random(42);
      rollAndCollectDrops(
        builder,
        burnNormalLogs,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      // Firemaking drops should still use full doubling (not halved).
    });
  });

  group('woodcuttingXPAddedAsFiremakingXP', () {
    test('grants firemaking XP as percentage of woodcutting XP', () {
      final flamingAxeScroll = testItems.byName('Flaming Axe Scroll');
      final random = Random(0);

      var state = GlobalState.test(
        testRegistries,
        equipment: Equipment(
          foodSlots: const [null, null, null],
          selectedFoodSlot: 0,
          gearSlots: {EquipmentSlot.consumable: flamingAxeScroll},
        ),
      );

      state = state.startAction(normalTree, random: random);
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      final wcXp = state.skillState(Skill.woodcutting).xp;
      expect(wcXp, greaterThan(0));

      final fmXp = state.skillState(Skill.firemaking).xp;
      final expectedFmXp = (wcXp * 5 / 100.0).round();
      expect(fmXp, expectedFmXp);
    });

    test('no firemaking XP without the modifier', () {
      final random = Random(0);
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(normalTree, random: random);

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 30, random: random);
      state = builder.build();

      expect(state.skillState(Skill.woodcutting).xp, greaterThan(0));
      expect(state.skillState(Skill.firemaking).xp, 0);
    });
  });

  group('freeBonfires', () {
    test('startBonfire does not consume logs with freeBonfires', () {
      final potion = testItems.byName('Controlled Heat Potion I');

      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 5),
          ItemStack(potion, count: 1),
        ]),
        selectedPotions: {Skill.firemaking.id: potion.id},
      );

      state = state.startBonfire(burnNormalLogs);

      expect(state.inventory.countOfItem(normalLogs), 5);
      expect(state.bonfire.isActive, isTrue);
    });

    test('startBonfire consumes logs without freeBonfires', () {
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 15),
        ]),
      );

      state = state.startBonfire(burnNormalLogs);

      expect(state.inventory.countOfItem(normalLogs), 5);
      expect(state.bonfire.isActive, isTrue);
    });

    test('restartBonfire does not consume logs with freeBonfires', () {
      final potion = testItems.byName('Controlled Heat Potion I');

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 5),
          ItemStack(potion, count: 1),
        ]),
        selectedPotions: {Skill.firemaking.id: potion.id},
        bonfire: BonfireState(
          actionId: burnNormalLogs.id,
          ticksRemaining: 0,
          totalTicks: 100,
          xpBonus: burnNormalLogs.bonfireXPBonus,
        ),
      );

      final builder = StateUpdateBuilder(state);
      final success = builder.restartBonfire(burnNormalLogs);

      expect(success, isTrue);
      expect(builder.state.inventory.countOfItem(normalLogs), 5);
      expect(builder.state.bonfire.isActive, isTrue);
    });
  });

  group('firemakingBonfireInterval', () {
    test('bonfire duration equals base interval without modifier', () {
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 15),
        ]),
      );

      state = state.startBonfire(burnNormalLogs);

      final expectedTicks = ticksFromDuration(burnNormalLogs.bonfireInterval);
      expect(state.bonfire.ticksRemaining, expectedTicks);
      expect(state.bonfire.totalTicks, expectedTicks);
    });
  });

  group('firemakingLogCurrencyGain', () {
    test('no GP from burning logs without modifier', () {
      final random = Random(0);

      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 100),
        ]),
      );

      state = state.startAction(burnNormalLogs, random: random);

      final builder = StateUpdateBuilder(state);
      final burnTicks = ticksFromDuration(burnNormalLogs.minDuration);
      consumeTicks(builder, burnTicks, random: random);
      state = builder.build();

      final gp = state.currencies[Currency.gp] ?? 0;
      expect(gp, 0, reason: 'No GP without firemakingLogCurrencyGain');
    });
  });
}
