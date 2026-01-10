import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/township_state.dart';
import 'package:logic/src/township_update.dart';
import 'package:test/test.dart';

void main() {
  group('TownshipState', () {
    test('empty state has default values', () {
      const state = TownshipState.empty();
      expect(state.biomes, isEmpty);
      expect(state.resources, isEmpty);
      expect(state.worshipId, isNull);
      expect(state.worship, 0);
      expect(state.season, Season.spring);
      expect(state.seasonTicksRemaining, ticksPerSeasonCycle);
      expect(state.ticksUntilUpdate, ticksPerHour);
      expect(state.tasks, isEmpty);
      expect(state.completedMainTasks, isEmpty);
    });

    test('toJson/fromJson round trip preserves state', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Wooden_Hut');

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 5, efficiency: 85),
            },
          ),
        },
        resources: {
          const MelvorId('melvorD:Food'): 1000,
          const MelvorId('melvorD:Wood'): 500,
        },
        worshipId: const MelvorId('melvorD:Bane'),
        worship: 150,
        season: Season.summer,
        seasonTicksRemaining: 100000,
        ticksUntilUpdate: 5000,
      );

      final json = state.toJson();
      final restored = TownshipState.fromJson(json);

      expect(restored.biomes.length, 1);
      expect(restored.biomes[biomeId]!.buildings[buildingId]!.count, 5);
      expect(restored.biomes[biomeId]!.buildings[buildingId]!.efficiency, 85.0);
      expect(restored.resources.length, 2);
      expect(restored.worshipId, state.worshipId);
      expect(restored.worship, 150);
      expect(restored.season, Season.summer);
      expect(restored.seasonTicksRemaining, 100000);
      expect(restored.ticksUntilUpdate, 5000);
    });

    test('addResource and removeResource work correctly', () {
      const state = TownshipState.empty();
      const foodId = MelvorId('melvorD:Food');

      final withFood = state.addResource(foodId, 100);
      expect(withFood.resourceAmount(foodId), 100);

      final moreFood = withFood.addResource(foodId, 50);
      expect(moreFood.resourceAmount(foodId), 150);

      final lessFood = moreFood.removeResource(foodId, 75);
      expect(lessFood.resourceAmount(foodId), 75);

      // Removing exact amount removes the key
      final noFood = lessFood.removeResource(foodId, 75);
      expect(noFood.resources.containsKey(foodId), isFalse);
    });

    test('removeResource throws on insufficient resources', () {
      const state = TownshipState.empty();
      const foodId = MelvorId('melvorD:Food');

      final withFood = state.addResource(foodId, 50);

      expect(() => withFood.removeResource(foodId, 100), throwsStateError);
    });

    test('advanceSeason cycles through seasons', () {
      var state = const TownshipState();

      state = state.advanceSeason();
      expect(state.season, Season.summer);
      expect(state.seasonTicksRemaining, ticksPerSeasonCycle);

      state = state.advanceSeason();
      expect(state.season, Season.fall);

      state = state.advanceSeason();
      expect(state.season, Season.winter);

      state = state.advanceSeason();
      expect(state.season, Season.spring);
    });

    test('totalBuildingCount sums across biomes', () {
      const biome1 = MelvorId('melvorD:Grasslands');
      const biome2 = MelvorId('melvorD:Forest');
      const buildingId = MelvorId('melvorD:Wooden_Hut');

      final state = TownshipState(
        biomes: {
          biome1: BiomeState(
            buildings: {buildingId: const BuildingState(count: 3)},
          ),
          biome2: BiomeState(
            buildings: {buildingId: const BuildingState(count: 2)},
          ),
        },
      );

      expect(state.totalBuildingCount(buildingId), 5);
    });
  });

  group('Season', () {
    test('happinessModifier varies by season', () {
      expect(Season.spring.happinessModifier, 50);
      expect(Season.summer.happinessModifier, 0);
      expect(Season.fall.happinessModifier, 0);
      expect(Season.winter.happinessModifier, -50);
    });

    test('educationModifier varies by season', () {
      expect(Season.spring.educationModifier, 50);
      expect(Season.summer.educationModifier, 0);
      expect(Season.fall.educationModifier, 0);
      expect(Season.winter.educationModifier, 0);
    });
  });

  group('TownshipStats', () {
    test('empty state has base values', () {
      const state = TownshipState.empty();
      const registry = TownshipRegistry.empty();

      final stats = TownshipStats.calculate(state, registry);

      expect(stats.population, 0);
      // Spring gives +50 happiness and +50 education
      expect(stats.happiness, 50);
      expect(stats.education, 50);
      expect(stats.health, 0);
      expect(stats.storage, TownshipState.baseStorage);
      expect(stats.worship, 0);
    });

    test('buildings contribute to stats', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: const {},
        gpCost: 0,
        populationBonus: 10,
        happinessBonus: 5,
        educationBonus: 3,
        healthBonus: 2,
        storageBonus: 100,
        worshipBonus: 5,
        validBiomes: {biomeId},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands')],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 2)},
          ),
        },
      );

      final stats = TownshipStats.calculate(state, registry);

      // 2 buildings * 10 population each
      expect(stats.population, 20);
      // 2 buildings * 5 happiness + 50 from spring
      expect(stats.happiness, 60);
      // 2 buildings * 3 education + 50 from spring
      expect(stats.education, 56);
      // 2 buildings * 2 health
      expect(stats.health, 4);
      // base 50000 + 2 buildings * 100
      expect(stats.storage, 50200);
      // 2 buildings * 5 worship
      expect(stats.worship, 10);
    });

    test('efficiency affects bonuses but not population or storage', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      const building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: {},
        gpCost: 0,
        populationBonus: 10,
        happinessBonus: 10,
        storageBonus: 100,
      );

      const registry = TownshipRegistry(
        buildings: [building],
        biomes: [TownshipBiome(id: biomeId, name: 'Grasslands')],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        },
      );

      final stats = TownshipStats.calculate(state, registry);

      // Population is NOT affected by efficiency
      expect(stats.population, 10);
      // Happiness IS affected: 10 * 0.5 + 50 from spring
      expect(stats.happiness, 55);
      // Storage is NOT affected by efficiency
      expect(stats.storage, 50100);
    });
  });

  group('processTownUpdate', () {
    test('produces GP from buildings', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');
      const gpResourceId = MelvorId('melvorD:GP');

      const gpResource = TownshipResource(
        id: gpResourceId,
        name: 'GP',
        depositsToBank: true,
      );

      final building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: const {},
        gpCost: 0,
        production: {gpResourceId: 100},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands')],
        resources: const [gpResource],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 1)},
          ),
        },
      );

      final random = Random(42);
      final result = processTownUpdate(state, registry, random);

      // Should produce GP (exact amount depends on education modifier)
      expect(result.gpProduced, greaterThan(0));
    });

    test('produces resources to storage', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');
      const woodId = MelvorId('melvorD:Wood');

      const woodResource = TownshipResource(id: woodId, name: 'Wood');

      final building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: const {},
        gpCost: 0,
        production: {woodId: 50},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands')],
        resources: const [woodResource],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 1)},
          ),
        },
      );

      final random = Random(42);
      final result = processTownUpdate(state, registry, random);

      // Wood should go to township storage, not GP
      expect(result.gpProduced, 0);
      expect(result.state.resourceAmount(woodId), greaterThan(0));
    });

    test('calculates XP based on population and happiness', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      const building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: {},
        gpCost: 0,
        populationBonus: 100,
        happinessBonus: 50,
        healthBonus: 100, // Need 100% health for full effective population
      );

      const registry = TownshipRegistry(
        buildings: [building],
        biomes: [TownshipBiome(id: biomeId, name: 'Grasslands')],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 1)},
          ),
        },
      );

      final random = Random(42);
      final result = processTownUpdate(state, registry, random);

      // XP = effectivePopulation * (1 + happiness/100)
      // population = 100, health = 100% (capped), effective population = 100
      // happiness = 50 + 50 (spring) = 100
      // XP = 100 * 2 = 200
      expect(result.xpGained, 200);
    });
  });

  group('GlobalState township methods', () {
    late Registries registries;
    const biomeId = MelvorId('melvorD:Grasslands');
    const buildingId = MelvorId('melvorD:Test_Building');

    setUp(() {
      final building = TownshipBuilding(
        id: buildingId,
        name: 'Test Building',
        levelRequired: 1,
        populationRequired: 0,
        costs: const {},
        gpCost: 100,
        populationBonus: 10,
        validBiomes: {biomeId},
      );

      final township = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands')],
      );

      registries = Registries.test(township: township);
    });

    test('canBuildTownshipBuilding validates requirements', () {
      var state = GlobalState.test(registries, gp: 50);

      // Not enough GP
      expect(
        state.canBuildTownshipBuilding(biomeId, buildingId),
        contains('Not enough GP'),
      );

      // Enough GP
      state = GlobalState.test(registries, gp: 100);
      expect(state.canBuildTownshipBuilding(biomeId, buildingId), isNull);
    });

    test('buildTownshipBuilding deducts GP and adds building', () {
      var state = GlobalState.test(registries, gp: 100);

      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.gp, 0);
      expect(state.township.totalBuildingCount(buildingId), 1);
    });

    test('buildTownshipBuilding throws on invalid building', () {
      final state = GlobalState.test(registries, gp: 100);
      const invalidBuilding = MelvorId('melvorD:Invalid');

      expect(
        () => state.buildTownshipBuilding(biomeId, invalidBuilding),
        throwsStateError,
      );
    });
  });

  group('Township trading', () {
    late Registries registries;
    late Item logItem;
    const woodId = MelvorId('melvorD:Township_Wood');
    const tradeId = MelvorId('melvorD:Trade_Logs');

    setUp(() {
      const woodResource = TownshipResource(id: woodId, name: 'Wood');
      logItem = Item.test('Oak Logs', gp: 10);
      final trade = TownshipTrade(
        id: tradeId,
        itemId: logItem.id,
        costs: {woodId: 100},
        itemQuantity: 10,
      );

      final township = TownshipRegistry(
        resources: const [woodResource],
        trades: [trade],
      );

      registries = Registries.test(items: [logItem], township: township);
    });

    test('canExecuteTownshipTrade validates resource availability', () {
      // No resources
      var state = GlobalState.test(registries);
      expect(state.canExecuteTownshipTrade(tradeId), contains('Not enough'));

      // With enough resources
      state = GlobalState.test(
        registries,
        township: const TownshipState().addResource(woodId, 100),
      );
      expect(state.canExecuteTownshipTrade(tradeId), isNull);
    });

    test('executeTownshipTrade converts resources to items', () {
      var state = GlobalState.test(
        registries,
        township: const TownshipState().addResource(woodId, 200),
      );

      state = state.executeTownshipTrade(tradeId);

      // Resources deducted
      expect(state.township.resourceAmount(woodId), 100);
      // Items received
      expect(state.inventory.countOfItem(logItem), 10);
    });

    test('executeTownshipTrade supports quantity parameter', () {
      var state = GlobalState.test(
        registries,
        township: const TownshipState().addResource(woodId, 300),
      );

      state = state.executeTownshipTrade(tradeId, quantity: 2);

      // Resources deducted (100 * 2 = 200)
      expect(state.township.resourceAmount(woodId), 100);
      // Items received (10 * 2 = 20)
      expect(state.inventory.countOfItem(logItem), 20);
    });

    test('TownshipTrade.costsWithDiscount applies Trading Post discount', () {
      final trade = TownshipTrade(
        id: tradeId,
        itemId: logItem.id,
        costs: {woodId: 1000},
      );

      // No Trading Posts = no discount
      var costs = trade.costsWithDiscount(0);
      expect(costs[woodId], 1000);

      // 10 Trading Posts = 3.3% discount
      costs = trade.costsWithDiscount(10);
      expect(costs[woodId], lessThan(1000));

      // 150 Trading Posts = 49.5% discount (max)
      costs = trade.costsWithDiscount(150);
      expect(costs[woodId], 505); // ceil(1000 * 0.505)
    });
  });
}
