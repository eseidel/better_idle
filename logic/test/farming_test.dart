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
      final plot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 100,
        compostApplied: 0,
      );

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
      final plot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 42,
        compostApplied: 10,
      );

      final json = plot.toJson();
      final restored = PlotState.fromJson(json);

      expect(restored.cropId, cropId);
      expect(restored.growthTicksRemaining, 42);
      expect(restored.compostApplied, 10);
      expect(restored.isGrowing, true);
    });

    test('PlotState ready state (countdown at 0)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 0,
        compostApplied: 0,
      );

      expect(readyPlot.isGrowing, false);
      expect(readyPlot.isReadyToHarvest, true);
    });

    test('PlotState ready state (countdown null)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(
        cropId: cropId,
        growthTicksRemaining: null,
        compostApplied: 0,
      );

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
        compostApplied: 0,
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
        compostApplied: 0,
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
}
