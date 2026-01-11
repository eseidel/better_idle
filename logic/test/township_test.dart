import 'dart:math';

import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/township_state.dart';
import 'package:logic/src/township_update.dart';
import 'package:test/test.dart';

/// Helper to create a test building with biome-specific data.
TownshipBuilding testBuilding({
  required MelvorId id,
  required String name,
  required Set<MelvorId> validBiomes,
  int tier = 1,
  int population = 0,
  double happiness = 0,
  double education = 0,
  int storage = 0,
  Map<MelvorId, double> production = const {},
  Map<MelvorId, int> costs = const {},
  bool canDegrade = true,
}) {
  final biomeData = <MelvorId, BuildingBiomeData>{};
  for (final biomeId in validBiomes) {
    biomeData[biomeId] = BuildingBiomeData(
      biomeId: biomeId,
      costs: costs,
      population: population,
      happiness: happiness,
      education: education,
      storage: storage,
      production: production,
    );
  }
  return TownshipBuilding(
    id: id,
    name: name,
    tier: tier,
    biomeData: biomeData,
    validBiomes: validBiomes,
    canDegrade: canDegrade,
  );
}

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

      expect(restored.biomes.keys, contains(biomeId));
      expect(restored.biomes[biomeId]!.buildings[buildingId]!.count, 5);
      expect(restored.biomes[biomeId]!.buildings[buildingId]!.efficiency, 85);
      expect(restored.resources[const MelvorId('melvorD:Food')], 1000);
      expect(restored.worshipId, const MelvorId('melvorD:Bane'));
      expect(restored.worship, 150);
      expect(restored.season, Season.summer);
      expect(restored.seasonTicksRemaining, 100000);
      expect(restored.ticksUntilUpdate, 5000);
    });

    test('resourceAmount returns 0 for missing resources', () {
      const state = TownshipState.empty();
      expect(state.resourceAmount(const MelvorId('melvorD:Food')), 0);
    });

    test('addResource adds to existing amount', () {
      final state = TownshipState(
        resources: {const MelvorId('melvorD:Food'): 100},
      );
      final newState = state.addResource(const MelvorId('melvorD:Food'), 50);
      expect(newState.resourceAmount(const MelvorId('melvorD:Food')), 150);
    });

    test('removeResource removes from existing amount', () {
      final state = TownshipState(
        resources: {const MelvorId('melvorD:Food'): 100},
      );
      final newState = state.removeResource(const MelvorId('melvorD:Food'), 30);
      expect(newState.resourceAmount(const MelvorId('melvorD:Food')), 70);
    });

    test('removeResource throws when insufficient', () {
      final state = TownshipState(
        resources: {const MelvorId('melvorD:Food'): 50},
      );
      expect(
        () => state.removeResource(const MelvorId('melvorD:Food'), 100),
        throwsStateError,
      );
    });

    test('totalBuildingCount sums across biomes', () {
      const buildingId = MelvorId('melvorD:Wooden_Hut');
      final state = TownshipState(
        biomes: {
          const MelvorId('melvorD:Grasslands'): BiomeState(
            buildings: {buildingId: const BuildingState(count: 3)},
          ),
          const MelvorId('melvorD:Forest'): BiomeState(
            buildings: {buildingId: const BuildingState(count: 2)},
          ),
        },
      );
      expect(state.totalBuildingCount(buildingId), 5);
    });
  });

  group('TownshipStats', () {
    test('empty state has zero stats', () {
      const registry = TownshipRegistry.empty();
      const state = TownshipState.empty();

      final stats = TownshipStats.calculate(state, registry);

      expect(stats.population, 0);
      // Spring provides +50 happiness and +50 education by default
      expect(stats.happiness, 50);
      expect(stats.education, 50);
      expect(stats.health, 0);
      expect(stats.storage, TownshipState.baseStorage);
      expect(stats.worship, 0);
    });

    test('buildings contribute to stats', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        population: 10,
        happiness: 5,
        education: 3,
        storage: 100,
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
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
      // base 50000 + 2 buildings * 100
      expect(stats.storage, 50200);
    });

    test('efficiency affects bonuses but not population or storage', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        population: 10,
        happiness: 10,
        storage: 100,
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
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
      const gpId = MelvorId('melvorF:GP');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {gpId: 100},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
        resources: const [
          TownshipResource(id: gpId, name: 'GP', type: 'Currency'),
        ],
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

      // GP should be produced (100 base * 1 building * 100% efficiency * 1.5
      // education modifier)
      expect(result.gpProduced, greaterThan(0));
    });

    test('produces resources that go into storage', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {woodId: 100},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
        resources: const [
          TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
        ],
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

      // Wood should be produced and stored
      expect(result.state.resourceAmount(woodId), greaterThan(0));
    });

    test('buildings degrade over time', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      // Use a building that can degrade
      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        population: 10,
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
      );

      // Start with many buildings at 100% efficiency for higher chance of
      // degradation
      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 100)},
          ),
        },
      );

      // Run many updates to ensure degradation happens
      var currentState = state;
      var degraded = false;
      final random = Random(42);

      for (var i = 0; i < 10 && !degraded; i++) {
        final result = processTownUpdate(currentState, registry, random);
        currentState = result.state;

        final newEfficiency =
            currentState.biomes[biomeId]!.buildings[buildingId]!.efficiency;
        if (newEfficiency < 100) {
          degraded = true;
        }
      }

      expect(degraded, isTrue, reason: 'Buildings should degrade over time');
    });

    test('storage buildings do not degrade', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Storehouse');

      // Storage building (canDegrade = false)
      final building = testBuilding(
        id: buildingId,
        name: 'Storehouse',
        validBiomes: {biomeId},
        storage: 1000,
        canDegrade: false,
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
      );

      final state = TownshipState(
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 10)},
          ),
        },
      );

      final random = Random(42);
      var currentState = state;

      // Run many updates
      for (var i = 0; i < 10; i++) {
        final result = processTownUpdate(currentState, registry, random);
        currentState = result.state;
      }

      // Should still be at 100% efficiency
      expect(
        currentState.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });

    test('XP is calculated based on effective population', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        population: 10,
        happiness: 50, // Extra happiness for bonus
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
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

      // With no health (0%), effective population is 0, so XP should be 0
      // This is expected behavior - need food/housing balance for health
      expect(result.xpGained, 0);
    });
  });

  group('GlobalState township methods', () {
    test('canBuildTownshipBuilding validates building exists', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );

      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(
        const MelvorId('melvorD:Grasslands'),
        const MelvorId('melvorD:Unknown_Building'),
      );

      expect(error, contains('Unknown building'));
    });

    test('canBuildTownshipBuilding validates biome exists', () {
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {const MelvorId('melvorD:Grasslands')},
      );

      final registries = Registries.test(
        township: TownshipRegistry(buildings: [building]),
      );

      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(
        const MelvorId('melvorD:Unknown_Biome'),
        buildingId,
      );

      expect(error, contains('Unknown biome'));
    });

    test('task completion tracking', () {
      const taskId = MelvorId('melvorD:Test_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [TaskReward(type: 'xp', amount: 100)],
            ),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      // Task with 0 population requirement should be completable
      expect(state.isTaskComplete(taskId), isTrue);
    });

    test('deity selection', () {
      const deityId = MelvorId('melvorD:Bane');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [TownshipDeity(id: deityId, name: 'Bane')],
        ),
      );

      var state = GlobalState.test(registries);

      expect(state.township.worshipId, isNull);

      state = state.selectWorship(deityId);

      expect(state.township.worshipId, deityId);
    });

    test('getWorshipBonus returns 0 when no deity selected', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );

      final state = GlobalState.test(registries);

      expect(state.getWorshipBonus('someModifier'), 0);
    });
  });

  group('TownshipRegistry lookups', () {
    test('buildingById returns correct building', () {
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {const MelvorId('melvorD:Grasslands')},
      );

      final registry = TownshipRegistry(buildings: [building]);

      expect(registry.buildingById(buildingId), building);
      expect(registry.buildingById(const MelvorId('melvorD:Unknown')), isNull);
    });

    test('biomeById returns correct biome', () {
      const biomeId = MelvorId('melvorD:Grasslands');
      const biome = TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1);

      const registry = TownshipRegistry(biomes: [biome]);

      expect(registry.biomeById(biomeId), biome);
      expect(registry.biomeById(const MelvorId('melvorD:Unknown')), isNull);
    });

    test('buildingsForBiome returns filtered buildings', () {
      const biomeId1 = MelvorId('melvorD:Grasslands');
      const biomeId2 = MelvorId('melvorD:Forest');

      final building1 = testBuilding(
        id: const MelvorId('melvorD:Building1'),
        name: 'Building 1',
        validBiomes: {biomeId1},
      );
      final building2 = testBuilding(
        id: const MelvorId('melvorD:Building2'),
        name: 'Building 2',
        validBiomes: {biomeId1, biomeId2},
      );
      final building3 = testBuilding(
        id: const MelvorId('melvorD:Building3'),
        name: 'Building 3',
        validBiomes: {biomeId2},
      );

      final registry = TownshipRegistry(
        buildings: [building1, building2, building3],
      );

      final grasslandsBuildings = registry.buildingsForBiome(biomeId1);
      expect(grasslandsBuildings, hasLength(2));
      expect(grasslandsBuildings, contains(building1));
      expect(grasslandsBuildings, contains(building2));

      final forestBuildings = registry.buildingsForBiome(biomeId2);
      expect(forestBuildings, hasLength(2));
      expect(forestBuildings, contains(building2));
      expect(forestBuildings, contains(building3));
    });

    test('visibleDeities filters hidden deities', () {
      const registry = TownshipRegistry(
        deities: [
          TownshipDeity(id: MelvorId('melvorD:Visible'), name: 'Visible'),
          TownshipDeity(
            id: MelvorId('melvorD:Hidden'),
            name: 'Hidden',
            isHidden: true,
          ),
        ],
      );

      final visible = registry.visibleDeities;
      expect(visible, hasLength(1));
      expect(visible[0].id, const MelvorId('melvorD:Visible'));
    });
  });
}
