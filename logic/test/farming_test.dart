import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('Farming countdown pattern', () {
    test('PlotState uses countdown pattern like mining/stunned', () {
      // Verify that PlotState uses the countdown pattern (growthTicksRemaining)
      // instead of timestamp-based tracking (plantedAtTick).

      final cropId = ActionId.test(Skill.farming, 'Potato');

      // Create a plot with 100 ticks remaining
      final plot = PlotState(cropId: cropId, growthTicksRemaining: 100);

      expect(plot.growthTicksRemaining, 100);
      expect(plot.isGrowing, true);
      expect(plot.isReadyToHarvest, false);

      // Decrement the countdown
      final updated = plot.copyWith(growthTicksRemaining: 50);
      expect(updated.growthTicksRemaining, 50);
      expect(updated.isGrowing, true);

      // Reach zero
      final ready = plot.copyWith(growthTicksRemaining: 0);
      expect(ready.growthTicksRemaining, 0);
      expect(ready.isGrowing, false);
      expect(ready.isReadyToHarvest, true);
    });

    test('PlotState handles null cropId (empty plot)', () {
      const emptyPlot = PlotState.empty();

      expect(emptyPlot.cropId, isNull);
      expect(emptyPlot.isEmpty, true);
      expect(emptyPlot.isGrowing, false);
      expect(emptyPlot.isReadyToHarvest, false);
    });

    test('PlotState serialization preserves countdown', () {
      final cropId = ActionId.test(Skill.farming, 'Potato');
      final plot = PlotState(cropId: cropId, growthTicksRemaining: 42);

      final json = plot.toJson();
      final restored = PlotState.fromJson(testItems, json);

      expect(restored.cropId, cropId);
      expect(restored.growthTicksRemaining, 42);
      expect(restored.isGrowing, true);
    });

    test('PlotState ready state (countdown at 0)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(cropId: cropId, growthTicksRemaining: 0);

      expect(readyPlot.isGrowing, false);
      expect(readyPlot.isReadyToHarvest, true);
    });

    test('PlotState ready state (countdown null)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(cropId: cropId, growthTicksRemaining: null);

      expect(readyPlot.isGrowing, false);
      expect(readyPlot.isReadyToHarvest, true);
    });
  });

  group('Farming XP', () {
    // Per the spec:
    // - Planting allotment/herb seeds grants base XP
    // - Planting tree seeds grants NO XP
    // - Harvesting trees grants fixed XP (baseXP)
    // - Harvesting allotments/herbs grants XP = baseXP * quantity harvested

    late FarmingCrop allotmentCrop;
    late FarmingCrop treeCrop;
    late FarmingCategory allotmentCategory;
    late FarmingCategory treeCategory;
    late MelvorId plotId;

    setUpAll(() {
      // Get an allotment crop (level 1 for easier testing)
      allotmentCategory = testRegistries.farmingCategories.all.firstWhere(
        (c) => c.name == 'Allotments',
      );
      allotmentCrop = testRegistries.farmingCrops
          .forCategory(allotmentCategory.id)
          .firstWhere((c) => c.level == 1);

      // Get a tree crop (trees start at level 15, so get the lowest level one)
      treeCategory = testRegistries.farmingCategories.all.firstWhere(
        (c) => c.name == 'Trees',
      );
      final treeCrops = testRegistries.farmingCrops.forCategory(
        treeCategory.id,
      );
      treeCrops.sort((a, b) => a.level.compareTo(b.level));
      treeCrop = treeCrops.first;

      // Get an unlocked plot
      plotId = testRegistries.farmingPlots.initialPlots().first;
    });

    test('allotment category has correct flags', () {
      expect(allotmentCategory.giveXPOnPlant, isTrue);
      expect(allotmentCategory.scaleXPWithQuantity, isTrue);
    });

    test('tree category has correct flags', () {
      expect(treeCategory.giveXPOnPlant, isFalse);
      expect(treeCategory.scaleXPWithQuantity, isFalse);
    });

    test('planting allotment seed grants base XP', () {
      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );

      final xpBefore = state.skillState(Skill.farming).xp;
      state = state.plantCrop(plotId, allotmentCrop);
      final xpAfter = state.skillState(Skill.farming).xp;

      expect(xpAfter - xpBefore, allotmentCrop.baseXP);
    });

    test('planting tree seed grants NO XP', () {
      final seed = testRegistries.items.byId(treeCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      // Set farming level high enough for the tree crop
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: treeCrop.seedCost),
        ]),
        skillStates: {
          Skill.farming: SkillState(
            xp: startXpForLevel(treeCrop.level),
            masteryPoolXp: 0,
          ),
        },
      );

      final xpBefore = state.skillState(Skill.farming).xp;
      state = state.plantCrop(plotId, treeCrop);
      final xpAfter = state.skillState(Skill.farming).xp;

      expect(xpAfter - xpBefore, 0);
    });

    test('harvesting tree grants fixed XP (not scaled by quantity)', () {
      final random = Random(42);
      final seed = testRegistries.items.byId(treeCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      // Set farming level high enough for the tree crop
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: treeCrop.seedCost),
        ]),
        skillStates: {
          Skill.farming: SkillState(
            xp: startXpForLevel(treeCrop.level),
            masteryPoolXp: 0,
          ),
        },
      );

      // Plant and immediately set as ready
      state = state.plantCrop(plotId, treeCrop);
      final readyPlotState = PlotState(
        cropId: treeCrop.id,
        growthTicksRemaining: 0,
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      final xpBefore = state.skillState(Skill.farming).xp;
      state = state.harvestCrop(plotId, random);
      final xpAfter = state.skillState(Skill.farming).xp;

      // Tree harvest should give exactly baseXP (not scaled)
      expect(xpAfter - xpBefore, treeCrop.baseXP);
    });

    test('harvesting allotment grants XP scaled by quantity', () {
      final random = Random(42);
      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      final product = testRegistries.items.byId(allotmentCrop.productId);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );

      // Plant (grants base XP)
      state = state.plantCrop(plotId, allotmentCrop);

      // Set as ready to harvest
      final readyPlotState = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 0,
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      final xpBeforeHarvest = state.skillState(Skill.farming).xp;
      state = state.harvestCrop(plotId, random);
      final xpAfterHarvest = state.skillState(Skill.farming).xp;

      // Determine how many items were harvested
      final harvestedQuantity = state.inventory.countOfItem(product);

      // Allotment harvest should give baseXP * quantity
      final expectedHarvestXp = allotmentCrop.baseXP * harvestedQuantity;
      expect(xpAfterHarvest - xpBeforeHarvest, expectedHarvestXp);
    });
  });

  group('Harvest success chance', () {
    late FarmingCrop allotmentCrop;
    late MelvorId plotId;

    setUpAll(() {
      final allotmentCategory = testRegistries.farmingCategories.all.firstWhere(
        (c) => c.name == 'Allotments',
      );
      allotmentCrop = testRegistries.farmingCrops
          .forCategory(allotmentCategory.id)
          .firstWhere((c) => c.level == 1);
      plotId = testRegistries.farmingPlots.initialPlots().first;
    });

    test('harvest fails ~50% of the time with no compost', () {
      // Use fixed seed random to get predictable results
      // We'll test many harvests to verify the success rate is around 50%
      var successCount = 0;
      const trials = 100;

      for (var i = 0; i < trials; i++) {
        final random = Random(i); // Different seed each iteration
        final seed = testRegistries.items.byId(allotmentCrop.seedId);
        var state = GlobalState.empty(testRegistries);
        state = state.copyWith(
          inventory: Inventory.fromItems(testItems, [
            ItemStack(seed, count: allotmentCrop.seedCost),
          ]),
        );

        // Plant the crop
        state = state.plantCrop(plotId, allotmentCrop);

        // Set as ready to harvest (no compost = 50% success chance)
        final readyPlotState = PlotState(
          cropId: allotmentCrop.id,
          growthTicksRemaining: 0,
        );
        state = state.copyWith(plotStates: {plotId: readyPlotState});

        final product = testRegistries.items.byId(allotmentCrop.productId);
        state = state.harvestCrop(plotId, random);

        if (state.inventory.countOfItem(product) > 0) {
          successCount++;
        }
      }

      // With 50% success rate and 100 trials, we expect roughly 50 successes
      // Allow some variance (40-60 range)
      expect(successCount, greaterThan(30));
      expect(successCount, lessThan(70));
    });

    test('harvest succeeds with 50 compost (100% success chance)', () {
      // With 50 compost, success chance is 50% + 50% = 100%
      final random = Random(42);
      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );

      // Plant the crop
      state = state.plantCrop(plotId, allotmentCrop);

      // Set as ready to harvest with 50 compost = 100% success
      final compost50 = testCompost(compostValue: 50);
      final readyPlotState = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 0,
        compostItems: [compost50],
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      final product = testRegistries.items.byId(allotmentCrop.productId);
      state = state.harvestCrop(plotId, random);

      // With 100% success, we should always get the product
      expect(state.inventory.countOfItem(product), greaterThan(0));
    });

    test('harvest can fail with fixed seed that would otherwise fail', () {
      // Find a seed that causes failure at 50% chance
      // We need to find a random seed where nextDouble() >= 0.5
      int? failingSeed;
      for (var i = 0; i < 100; i++) {
        final testRandom = Random(i);
        if (testRandom.nextDouble() >= 0.5) {
          failingSeed = i;
          break;
        }
      }
      expect(failingSeed, isNotNull, reason: 'Should find a failing seed');

      final random = Random(failingSeed!);
      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );

      // Plant the crop
      state = state.plantCrop(plotId, allotmentCrop);

      // Set as ready to harvest (no compost = 50% success chance)
      final readyPlotState = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 0,
      );
      state = state.copyWith(plotStates: {plotId: readyPlotState});

      final product = testRegistries.items.byId(allotmentCrop.productId);
      state = state.harvestCrop(plotId, random);

      // With a failing seed at 50% chance, we should get no product
      expect(state.inventory.countOfItem(product), 0);
      // Plot should be cleared even on failure
      expect(state.plotStates[plotId], isNull);
    });
  });

  group('Harvest bonus', () {
    late FarmingCrop allotmentCrop;
    late FarmingCategory allotmentCategory;
    late MelvorId plotId;

    setUpAll(() {
      allotmentCategory = testRegistries.farmingCategories.all.firstWhere(
        (c) => c.name == 'Allotments',
      );
      allotmentCrop = testRegistries.farmingCrops
          .forCategory(allotmentCategory.id)
          .firstWhere((c) => c.level == 1);
      plotId = testRegistries.farmingPlots.initialPlots().first;
    });

    test('harvest bonus increases quantity by percentage', () {
      final seed = testRegistries.items.byId(allotmentCrop.seedId);

      // First harvest without harvest bonus
      var stateWithout = GlobalState.empty(testRegistries);
      stateWithout = stateWithout.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );
      stateWithout = stateWithout.plantCrop(plotId, allotmentCrop);
      // Compost with 50 value (100% success), no harvest bonus
      final compostNoBonus = testCompost(compostValue: 50, harvestBonus: 0);
      final plotStateWithout = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 0,
        compostItems: [compostNoBonus],
      );
      stateWithout = stateWithout.copyWith(
        plotStates: {plotId: plotStateWithout},
      );

      final product = testRegistries.items.byId(allotmentCrop.productId);
      stateWithout = stateWithout.harvestCrop(plotId, Random(42));
      final quantityWithout = stateWithout.inventory.countOfItem(product);

      // Now harvest with 50% harvest bonus (large enough to see the difference)
      var stateWith = GlobalState.empty(testRegistries);
      stateWith = stateWith.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );
      stateWith = stateWith.plantCrop(plotId, allotmentCrop);
      // Compost with 50 value (100% success) and 50% harvest bonus
      final compostWithBonus = testCompost(compostValue: 50, harvestBonus: 50);
      final plotStateWith = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 0,
        compostItems: [compostWithBonus],
      );
      stateWith = stateWith.copyWith(plotStates: {plotId: plotStateWith});

      stateWith = stateWith.harvestCrop(plotId, Random(42));
      final quantityWith = stateWith.inventory.countOfItem(product);

      // Calculate expected values
      // Base quantity * category multiplier = base (e.g., 1 * 3 = 3)
      // Without bonus: base * 1.0 = 3
      // With 50% bonus: base * 1.5 = 4.5 -> rounds to 5 (or 4 depending on rounding)
      final baseQuantity = allotmentCrop.baseQuantity;
      final multiplier = allotmentCategory.harvestMultiplier;
      final expectedWithout = baseQuantity * multiplier;
      final expectedWith = (baseQuantity * multiplier * 1.5).round();

      expect(quantityWithout, expectedWithout);
      expect(quantityWith, expectedWith);
      expect(quantityWith, greaterThan(quantityWithout));
    });

    test('applyCompost stores harvestBonus from item', () {
      // Create a test item with compostValue=50 and harvestBonus=10
      final weirdGloop = Item.test(
        'Weird Gloop',
        gp: 750,
        compostValue: 50,
        harvestBonus: 10,
      );

      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
          ItemStack(weirdGloop, count: 1),
        ]),
      );

      // Apply the item to the plot
      state = state.applyCompost(plotId, weirdGloop);

      // Verify both compost and harvest bonus were stored
      final plotState = state.plotStates[plotId]!;
      expect(plotState.compostApplied, 50);
      expect(plotState.harvestBonusApplied, 10);
    });
  });

  group('Clear plot', () {
    late FarmingCrop allotmentCrop;
    late MelvorId plotId;

    setUpAll(() {
      final allotmentCategory = testRegistries.farmingCategories.all.firstWhere(
        (c) => c.name == 'Allotments',
      );
      allotmentCrop = testRegistries.farmingCrops
          .forCategory(allotmentCategory.id)
          .firstWhere((c) => c.level == 1);
      plotId = testRegistries.farmingPlots.initialPlots().first;
    });

    test('clearPlot clears both seeds and compost', () {
      final seed = testRegistries.items.byId(allotmentCrop.seedId);
      var state = GlobalState.empty(testRegistries);

      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(seed, count: allotmentCrop.seedCost),
        ]),
      );

      // Plant the crop
      state = state.plantCrop(plotId, allotmentCrop);

      // Manually set up plot with compost (as if compost was applied)
      final compost = testCompost(compostValue: 25, harvestBonus: 5);
      final plotWithCompost = PlotState(
        cropId: allotmentCrop.id,
        growthTicksRemaining: 100,
        compostItems: [compost],
      );
      state = state.copyWith(plotStates: {plotId: plotWithCompost});

      // Verify the plot has both the crop and the compost
      expect(state.plotStates[plotId]!.cropId, allotmentCrop.id);
      expect(state.plotStates[plotId]!.compostApplied, 25);
      expect(state.plotStates[plotId]!.harvestBonusApplied, 5);
      expect(state.plotStates[plotId]!.isGrowing, isTrue);

      // Clear the plot
      state = state.clearPlot(plotId);

      // Verify the plot is completely cleared (no entry in plotStates)
      expect(state.plotStates[plotId], isNull);
    });

    test('clearPlot clears plot with only compost applied', () {
      var state = GlobalState.empty(testRegistries);

      // Create a compost item
      final compost = Item.test(
        'Test Compost',
        gp: 100,
        compostValue: 30,
        harvestBonus: 10,
      );

      state = state.copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(compost, count: 1),
        ]),
      );

      // Apply compost to empty plot (no seed planted)
      state = state.applyCompost(plotId, compost);

      // Verify compost was applied
      expect(state.plotStates[plotId]!.compostApplied, 30);
      expect(state.plotStates[plotId]!.isEmpty, isTrue); // No crop planted

      // Clear the plot
      state = state.clearPlot(plotId);

      // Verify the plot is completely cleared
      expect(state.plotStates[plotId], isNull);
    });
  });
}
