import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late SkillAction normalTree;
  late SkillAction copperMining;

  setUpAll(() async {
    await loadTestRegistries();
    normalTree = testRegistries.woodcuttingAction('Normal Tree');
    copperMining = testRegistries.miningAction('Copper');
  });

  group('SkillAction', () {
    test(
      'woodcutting base rewards return 1 item (doubling applied via modifiers)',
      () {
        // Woodcutting now uses defaultRewards (1 item per action).
        // The doubling mechanic is applied via skillItemDoublingChance modifier
        // at roll time in rollAndCollectDrops(), not in the rewards themselves.
        const normalLogsId = MelvorId('melvorD:Normal_Logs');

        // Base rewards are always 1 item (doubling applied via modifiers)
        final rewards = normalTree.rewardsForSelection(
          const NoSelectedRecipe(),
        );
        expect(rewards.length, 1);
        final expected = rewards.first.expectedItems[normalLogsId]!;
        expect(expected, closeTo(1.0, 0.001));
      },
    );

    test('expectedItemsForDrops applies doubling chance multiplier', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final drops = testDrops.allDropsForAction(
        normalTree,
        const NoSelectedRecipe(),
      );

      // With 0% doubling chance, expected items = 1.0
      final expected0 = expectedItemsForDrops(drops);
      expect(expected0[normalLogsId], closeTo(1.0, 0.001));

      // With 5% doubling chance, expected items = 1.05
      final expected5 = expectedItemsForDrops(drops, doublingChance: 0.05);
      expect(expected5[normalLogsId], closeTo(1.05, 0.001));

      // With 10% doubling chance, expected items = 1.10
      final expected10 = expectedItemsForDrops(drops, doublingChance: 0.10);
      expect(expected10[normalLogsId], closeTo(1.10, 0.001));

      // With 25% doubling chance, expected items = 1.25
      final expected25 = expectedItemsForDrops(drops, doublingChance: 0.25);
      expect(expected25[normalLogsId], closeTo(1.25, 0.001));
    });
  });

  group('CombatRegistry', () {
    test('monsterById returns CombatAction for valid monster ID', () {
      final chicken = testRegistries.combatAction('Chicken');
      final monsterId = chicken.id.localId;

      final result = testRegistries.combat.monsterById(monsterId);

      expect(result, isA<CombatAction>());
      expect(result.name, 'Chicken');
      expect(result.id, chicken.id);
    });

    test('monsterById throws for invalid monster ID', () {
      const invalidId = MelvorId('melvorD:NonExistentMonster');

      expect(
        () => testRegistries.combat.monsterById(invalidId),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('allDropsForAction', () {
    test('ore mining actions include gem drops (giveGems: true)', () {
      final drops = testDrops.allDropsForAction(
        copperMining,
        const NoSelectedRecipe(),
      );

      // Check that miningGemTable (a DropChance wrapping DropTable) is included
      final hasGemTable = drops.any(
        (d) => d is DropChance && d.child is DropTable,
      );
      expect(
        hasGemTable,
        isTrue,
        reason: 'Ore mining actions should include gem drop table',
      );

      // Verify gems appear in expectedItems
      final allExpectedItems = expectedItemsForDrops(drops);

      // At least one gem should be present (keys are now MelvorId)
      final gemIds = [
        const MelvorId('melvorD:Topaz'),
        const MelvorId('melvorD:Sapphire'),
        const MelvorId('melvorD:Ruby'),
        const MelvorId('melvorD:Emerald'),
        const MelvorId('melvorD:Diamond'),
      ];
      final hasAnyGem = gemIds.any(allExpectedItems.containsKey);
      expect(
        hasAnyGem,
        isTrue,
        reason: 'Ore mining drops should include gems from miningGemTable',
      );
    });

    test('essence mining does not include gem drops (giveGems: false)', () {
      final runeEssence = testRegistries.miningAction('Rune Essence');

      // Verify the action has giveGems: false
      expect(
        runeEssence.giveGems,
        isFalse,
        reason: 'Rune Essence should have giveGems: false',
      );

      final drops = testDrops.allDropsForAction(
        runeEssence,
        const NoSelectedRecipe(),
      );

      // Check that no gem drop table is included
      final hasGemTable = drops.any(
        (d) => d is DropChance && d.child is DropTable,
      );
      expect(
        hasGemTable,
        isFalse,
        reason: 'Essence mining should NOT include gem drop table',
      );

      // Verify no gems appear in expectedItems
      final allExpectedItems = expectedItemsForDrops(drops);
      final gemIds = [
        const MelvorId('melvorD:Topaz'),
        const MelvorId('melvorD:Sapphire'),
        const MelvorId('melvorD:Ruby'),
        const MelvorId('melvorD:Emerald'),
        const MelvorId('melvorD:Diamond'),
      ];
      final hasAnyGem = gemIds.any(allExpectedItems.containsKey);
      expect(
        hasAnyGem,
        isFalse,
        reason: 'Essence mining drops should NOT include any gems',
      );
    });
  });

  group('outputsForRecipe', () {
    test('returns base outputs for NoSelectedRecipe', () {
      const ironBarId = MelvorId('melvorD:Iron_Bar');
      const coalOreId = MelvorId('melvorD:Coal_Ore');
      const ironOreId = MelvorId('melvorD:Iron_Ore');

      final action = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
        outputs: {ironBarId: 1},
        alternativeRecipes: [
          AlternativeRecipe(
            inputs: {coalOreId: 1, ironOreId: 1},
            quantityMultiplier: 1,
          ),
          AlternativeRecipe(
            inputs: {coalOreId: 2, ironOreId: 2},
            quantityMultiplier: 2,
          ),
        ],
      );

      final outputs = action.outputsForRecipe(const NoSelectedRecipe());

      expect(outputs, {ironBarId: 1});
    });

    test('applies quantityMultiplier from selected recipe', () {
      const ironBarId = MelvorId('melvorD:Iron_Bar');
      const coalOreId = MelvorId('melvorD:Coal_Ore');
      const ironOreId = MelvorId('melvorD:Iron_Ore');

      final action = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
        outputs: {ironBarId: 1},
        alternativeRecipes: [
          AlternativeRecipe(
            inputs: {coalOreId: 1, ironOreId: 1},
            quantityMultiplier: 1,
          ),
          AlternativeRecipe(
            inputs: {coalOreId: 2, ironOreId: 2},
            quantityMultiplier: 2,
          ),
          AlternativeRecipe(
            inputs: {coalOreId: 3, ironOreId: 3},
            quantityMultiplier: 3,
          ),
        ],
      );

      // Select recipe at index 0 (multiplier = 1)
      final outputs0 = action.outputsForRecipe(const SelectedRecipe(index: 0));
      expect(outputs0, {ironBarId: 1});

      // Select recipe at index 1 (multiplier = 2)
      final outputs1 = action.outputsForRecipe(const SelectedRecipe(index: 1));
      expect(outputs1, {ironBarId: 2});

      // Select recipe at index 2 (multiplier = 3)
      final outputs2 = action.outputsForRecipe(const SelectedRecipe(index: 2));
      expect(outputs2, {ironBarId: 3});
    });

    test('clamps out-of-bounds recipe index', () {
      const ironBarId = MelvorId('melvorD:Iron_Bar');
      const coalOreId = MelvorId('melvorD:Coal_Ore');

      final action = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
        outputs: {ironBarId: 1},
        alternativeRecipes: [
          AlternativeRecipe(inputs: {coalOreId: 1}, quantityMultiplier: 1),
          AlternativeRecipe(inputs: {coalOreId: 2}, quantityMultiplier: 5),
        ],
      );

      // Index -1 should clamp to 0 (multiplier = 1)
      final outputsNegative = action.outputsForRecipe(
        const SelectedRecipe(index: -1),
      );
      expect(outputsNegative, {ironBarId: 1});

      // Index 10 should clamp to last index (1, multiplier = 5)
      final outputsOverflow = action.outputsForRecipe(
        const SelectedRecipe(index: 10),
      );
      expect(outputsOverflow, {ironBarId: 5});
    });

    test('applies multiplier to multiple output items', () {
      const ironBarId = MelvorId('melvorD:Iron_Bar');
      const steelBarId = MelvorId('melvorD:Steel_Bar');
      const coalOreId = MelvorId('melvorD:Coal_Ore');

      final action = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Multi-Output'),
        skill: Skill.smithing,
        name: 'Test Multi-Output',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
        outputs: {ironBarId: 2, steelBarId: 3},
        alternativeRecipes: [
          AlternativeRecipe(inputs: {coalOreId: 1}, quantityMultiplier: 1),
          AlternativeRecipe(inputs: {coalOreId: 4}, quantityMultiplier: 4),
        ],
      );

      // Select recipe with multiplier = 4
      final outputs = action.outputsForRecipe(const SelectedRecipe(index: 1));
      expect(outputs, {ironBarId: 8, steelBarId: 12});
    });
  });

  group('rollAndCollectDrops', () {
    test('doubles items when random triggers doubling chance', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);

      // Create modifiers with 100% doubling chance to guarantee doubling
      final modifiers = StubModifierProvider({'skillItemDoublingChance': 100});

      // Use a fixed seed random - the doubling check uses random.nextDouble()
      // With 100% chance, any random value will trigger doubling
      final random = Random(42);

      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      // With 100% doubling chance, we should get 2 logs instead of 1
      final inventory = builder.state.inventory;
      final logsCount = inventory.countById(normalLogsId);
      expect(logsCount, 2, reason: 'Should have doubled the logs drop');
    });

    test('does not double items when doubling chance is 0', () {
      const normalLogsId = MelvorId('melvorD:Normal_Logs');
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);

      // No doubling chance
      final modifiers = StubModifierProvider();

      final random = Random(42);

      rollAndCollectDrops(
        builder,
        normalTree,
        modifiers,
        random,
        const NoSelectedRecipe(),
      );

      // With 0% doubling chance, we should get exactly 1 log
      final inventory = builder.state.inventory;
      final logsCount = inventory.countById(normalLogsId);
      expect(
        logsCount,
        1,
        reason: 'Should have exactly 1 log without doubling',
      );
    });
  });

  group('RareDrop with requiredItemId', () {
    test('RareDrop drops when no requiredItemId is set', () {
      const testItemId = MelvorId('melvorD:Normal_Logs');
      const rareDrop = RareDrop(
        itemId: testItemId,
        chance: FixedChance(1), // 100% drop rate
      );

      final result = rareDrop.rollWithContext(
        testItems,
        Random(42),
        skillLevel: 1,
        totalMastery: 0,
        hasRequiredItem: false, // Shouldn't matter since no requirement
      );

      expect(result, isNotNull);
      expect(result!.item.id, testItemId);
    });

    test('RareDrop blocked when requiredItemId not found', () {
      const testItemId = MelvorId('melvorD:Normal_Logs');
      const requiredId = MelvorId('melvorD:Oak_Logs');
      const rareDrop = RareDrop(
        itemId: testItemId,
        chance: FixedChance(1), // 100% drop rate
        requiredItemId: requiredId,
      );

      final result = rareDrop.rollWithContext(
        testItems,
        Random(42),
        skillLevel: 1,
        totalMastery: 0,
        hasRequiredItem: false, // Required item not found
      );

      expect(result, isNull, reason: 'Should block drop when required missing');
    });

    test('RareDrop allowed when requiredItemId has been found', () {
      const testItemId = MelvorId('melvorD:Normal_Logs');
      const requiredId = MelvorId('melvorD:Oak_Logs');
      const rareDrop = RareDrop(
        itemId: testItemId,
        chance: FixedChance(1), // 100% drop rate
        requiredItemId: requiredId,
      );

      final result = rareDrop.rollWithContext(
        testItems,
        Random(42),
        skillLevel: 1,
        totalMastery: 0,
        hasRequiredItem: true, // Required item has been found
      );

      expect(result, isNotNull);
      expect(result!.item.id, testItemId);
    });

    test('inventory hasEverAcquired gates RareDrop in rollAndCollectDrops', () {
      // This test verifies the integration between inventory tracking
      // and RareDrop requirements in rollAndCollectDrops
      const oakLogsId = MelvorId('melvorD:Oak_Logs');

      // Start with empty inventory - oak logs never acquired
      final state = GlobalState.test(testRegistries);
      expect(state.inventory.hasEverAcquired(oakLogsId), isFalse);

      // Add oak logs to inventory
      final stateWithOak = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(testItems.byId(oakLogsId), count: 1),
        ),
      );
      expect(stateWithOak.inventory.hasEverAcquired(oakLogsId), isTrue);

      // Now remove oak logs - hasEverAcquired should still be true
      final stateOakRemoved = stateWithOak.copyWith(
        inventory: stateWithOak.inventory.removing(
          ItemStack(testItems.byId(oakLogsId), count: 1),
        ),
      );
      expect(stateOakRemoved.inventory.countById(oakLogsId), 0);
      expect(stateOakRemoved.inventory.hasEverAcquired(oakLogsId), isTrue);
    });
  });

  group('MasteryScalingChance', () {
    test('Circlet of Rhaelyx has correct drop rates from wiki', () {
      // Wiki: https://wiki.melvoridle.com/w/Circlet_of_Rhaelyx
      // Base rate: 1/10,000,000 per action
      // Max rate: 1/100,000 at 24,750 total mastery
      // Scaling: improves by 1/2,500,000,000 per mastery level
      const circlet = MasteryScalingChance(
        baseChance: 1e-7, // 1/10,000,000
        maxChance: 1e-5, // 1/100,000
        scalingFactor: 4e-10, // 1/2,500,000,000
      );

      // At 0 mastery, should be base rate
      expect(circlet.calculate(), closeTo(1e-7, 1e-10));

      // At max mastery (24,750), should be max rate
      expect(circlet.calculate(totalMastery: 24750), closeTo(1e-5, 1e-8));

      // At mid mastery, should be between base and max
      final midChance = circlet.calculate(totalMastery: 12000);
      expect(midChance, greaterThan(1e-7));
      expect(midChance, lessThan(1e-5));

      // Beyond max mastery should still cap at max
      expect(circlet.calculate(totalMastery: 50000), closeTo(1e-5, 1e-8));
    });

    test('woodcutting skill drops include Circlet with correct rates', () {
      const circletId = MelvorId('melvorD:Circlet_of_Rhaelyx');

      final drops = testDrops.forSkill(Skill.woodcutting);
      final circletDrop = drops.whereType<RareDrop>().firstWhere(
        (d) => d.itemId == circletId,
      );

      expect(circletDrop.chance, isA<MasteryScalingChance>());
      final chance = circletDrop.chance as MasteryScalingChance;

      // Verify the parsed values match expected (after /100 conversion)
      expect(chance.baseChance, closeTo(1e-7, 1e-10));
      expect(chance.maxChance, closeTo(1e-5, 1e-8));
      expect(chance.scalingFactor, closeTo(4e-10, 1e-13));
    });
  });
}
