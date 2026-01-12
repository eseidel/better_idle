import 'dart:math';

import 'package:logic/logic.dart';
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
  group('TownshipTaskState', () {
    test('toJson/fromJson round trip preserves state', () {
      const state = TownshipTaskState(
        taskId: MelvorId('melvorD:Test_Task'),
        progress: {'population': 50, 'buildBuilding': 3},
        completed: true,
      );

      final json = state.toJson();
      final restored = TownshipTaskState.fromJson(json);

      expect(restored.taskId, const MelvorId('melvorD:Test_Task'));
      expect(restored.progress, {'population': 50, 'buildBuilding': 3});
      expect(restored.completed, isTrue);
    });

    test('toJson/fromJson round trip with empty progress', () {
      const state = TownshipTaskState(taskId: MelvorId('melvorD:Simple_Task'));

      final json = state.toJson();
      final restored = TownshipTaskState.fromJson(json);

      expect(restored.taskId, const MelvorId('melvorD:Simple_Task'));
      expect(restored.progress, isEmpty);
      expect(restored.completed, isFalse);
    });
  });

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
      const registry = TownshipRegistry.empty();

      final state = TownshipState(
        registry: registry,
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
      final restored = TownshipState.fromJson(registry, json);

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
        registry: const TownshipRegistry.empty(),
        resources: {const MelvorId('melvorD:Food'): 100},
      );
      final newState = state.addResource(const MelvorId('melvorD:Food'), 50);
      expect(newState.resourceAmount(const MelvorId('melvorD:Food')), 150);
    });

    test('removeResource removes from existing amount', () {
      final state = TownshipState(
        registry: const TownshipRegistry.empty(),
        resources: {const MelvorId('melvorD:Food'): 100},
      );
      final newState = state.removeResource(const MelvorId('melvorD:Food'), 30);
      expect(newState.resourceAmount(const MelvorId('melvorD:Food')), 70);
    });

    test('removeResource throws when insufficient', () {
      final state = TownshipState(
        registry: const TownshipRegistry.empty(),
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
        registry: const TownshipRegistry.empty(),
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

      expect(stats.population, TownshipStats.basePopulation);
      // Spring provides +50 happiness and +50 education by default
      expect(stats.happiness, 50);
      expect(stats.education, 50);
      expect(stats.health, TownshipStats.maxHealth);
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
        registry: registry,
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 2)},
          ),
        },
      );

      final stats = TownshipStats.calculate(state, registry);

      // base 7 + 2 buildings * 10 population each
      expect(stats.population, TownshipStats.basePopulation + 20);
      // 2 buildings * 5 happiness + 50 from spring
      expect(stats.happiness, 60);
      // 2 buildings * 3 education + 50 from spring
      expect(stats.education, 56);
      // base 50000 + 2 buildings * 100
      expect(stats.storage, 50200);
    });

    test('health cannot fall below 20%', () {
      // Currently health starts at 100% and nothing decreases it,
      // but the constraint ensures it can never go below 20%.
      const registry = TownshipRegistry.empty();
      const state = TownshipState.empty();

      final stats = TownshipStats.calculate(state, registry);

      // Verify the minimum health constant exists and is 20
      expect(TownshipStats.minHealth, 20);
      // Health should be at least minHealth
      expect(stats.health, greaterThanOrEqualTo(TownshipStats.minHealth));
      // Health should be at most maxHealth
      expect(stats.health, lessThanOrEqualTo(TownshipStats.maxHealth));
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
        registry: registry,
        biomes: {
          biomeId: BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        },
      );

      final stats = TownshipStats.calculate(state, registry);

      // Population is NOT affected by efficiency (base 7 + 10 from building)
      expect(stats.population, TownshipStats.basePopulation + 10);
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
        registry: registry,
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
        registry: registry,
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
        registry: registry,
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
        registry: registry,
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
        registry: registry,
        biomes: {
          biomeId: BiomeState(
            buildings: {buildingId: const BuildingState(count: 1)},
          ),
        },
      );

      final random = Random(42);
      final result = processTownUpdate(state, registry, random);

      // Population: 7 base + 10 from building = 17
      // Health: 100% (base), so effective population = 17
      // Happiness: 50 from spring + 50 from building = 100 (2x XP multiplier)
      // XP = 17 * 2.0 = 34
      expect(result.xpGained, 34);
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

    test('canBuildTownshipBuilding validates building is valid for biome', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const grasslandsId = MelvorId('melvorD:Grasslands');
      const forestId = MelvorId('melvorD:Forest');

      // Building is only valid for Grasslands, not Forest
      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {grasslandsId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: grasslandsId, name: 'Grasslands', tier: 1),
            TownshipBiome(id: forestId, name: 'Forest', tier: 1),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(forestId, buildingId);

      expect(error, contains('cannot be built in'));
    });

    test('canBuildTownshipBuilding validates level requirement', () {
      const buildingId = MelvorId('melvorD:Tier2_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      // Tier 2 building requires level 30
      final building = testBuilding(
        id: buildingId,
        name: 'Tier 2 Building',
        validBiomes: {biomeId},
        tier: 2,
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      // Default state has level 1 Township
      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, contains('Requires Township level 15'));
    });

    test('canBuildTownshipBuilding validates GP cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 1000},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      // State with no GP
      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, contains('Not enough GP'));
      expect(error, contains('1000'));
    });

    test('canBuildTownshipBuilding validates township resource cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {woodId: 500},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      // State with no township resources
      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, contains('Not enough Wood'));
      expect(error, contains('500'));
      expect(error, contains('have 0'));
    });

    test('canBuildTownshipBuilding returns null when all checks pass', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 100, woodId: 50},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      // State with enough GP and township resources
      var state = GlobalState.test(registries);
      state = state.addCurrency(Currency.gp, 200);
      state = state.copyWith(township: state.township.addResource(woodId, 100));

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, isNull);
    });

    test('canBuildTownshipBuilding with tier 3 requires level 35', () {
      const buildingId = MelvorId('melvorD:Tier3_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Tier 3 Building',
        validBiomes: {biomeId},
        tier: 3,
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, contains('Requires Township level 35'));
    });

    test('canBuildTownshipBuilding with tier 4 requires level 60', () {
      const buildingId = MelvorId('melvorD:Tier4_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Tier 4 Building',
        validBiomes: {biomeId},
        tier: 4,
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      final error = state.canBuildTownshipBuilding(biomeId, buildingId);

      expect(error, contains('Requires Township level 60'));
    });

    test('buildTownshipBuilding throws when validation fails', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );

      final state = GlobalState.test(registries);

      expect(
        () => state.buildTownshipBuilding(
          const MelvorId('melvorD:Grasslands'),
          const MelvorId('melvorD:Unknown_Building'),
        ),
        throwsStateError,
      );
    });

    test('buildTownshipBuilding deducts GP cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 100},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.addCurrency(Currency.gp, 500);

      expect(state.gp, 500);

      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.gp, 400);
    });

    test('buildTownshipBuilding deducts township resource cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {woodId: 50},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(township: state.township.addResource(woodId, 200));

      expect(state.township.resourceAmount(woodId), 200);

      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.township.resourceAmount(woodId), 150);
    });

    test('buildTownshipBuilding increments building count', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);

      expect(state.township.totalBuildingCount(buildingId), 0);

      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.township.totalBuildingCount(buildingId), 1);
      expect(state.township.biomes[biomeId]!.buildings[buildingId]!.count, 1);

      // Build a second one
      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.township.totalBuildingCount(buildingId), 2);
    });

    test('buildTownshipBuilding deducts both GP and resources', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');
      const woodId = MelvorId('melvorF:Wood');
      const stoneId = MelvorId('melvorF:Stone');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 100, woodId: 50, stoneId: 25},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
            TownshipResource(id: stoneId, name: 'Stone', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.addCurrency(Currency.gp, 500);
      state = state.copyWith(
        township: state.township
            .addResource(woodId, 200)
            .addResource(stoneId, 100),
      );

      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(state.gp, 400);
      expect(state.township.resourceAmount(woodId), 150);
      expect(state.township.resourceAmount(stoneId), 75);
      expect(state.township.totalBuildingCount(buildingId), 1);
    });

    test('buildTownshipBuilding new building starts at 100% efficiency', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.buildTownshipBuilding(biomeId, buildingId);

      final buildingState =
          state.township.biomes[biomeId]!.buildings[buildingId]!;
      expect(buildingState.efficiency, 100);
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

      expect(state.township.getWorshipBonus('someModifier'), 0);
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

  group('canExecuteTownshipTrade', () {
    test('returns error for unknown trade', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );
      final state = GlobalState.test(registries);

      final error = state.canExecuteTownshipTrade(
        const MelvorId('melvorD:Unknown'),
      );

      expect(error, contains('Unknown trade'));
    });

    test('returns error for quantity less than 1', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 1000),
      );

      final error = state.canExecuteTownshipTrade(tradeId, quantity: 0);

      expect(error, contains('Quantity must be at least 1'));
    });

    test('returns error when insufficient township resources', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      // State with only 50 Food (need 100)
      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 50),
      );

      final error = state.canExecuteTownshipTrade(tradeId);

      expect(error, contains('Not enough Food'));
      expect(error, contains('need 100'));
      expect(error, contains('have 50'));
    });

    test('returns error when inventory is full', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      // Create enough unique items to fill inventory slots
      final fillerItems = <Item>[];
      for (var i = 0; i < 100; i++) {
        fillerItems.add(Item.test('Filler $i', gp: 1));
      }

      final registries = Registries.test(
        items: [testItem, ...fillerItems],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 1000),
      );

      // Fill inventory with unique item types (each takes a slot)
      for (var i = 0; i < state.inventoryCapacity; i++) {
        state = state.copyWith(
          inventory: state.inventory.adding(
            ItemStack(fillerItems[i], count: 1),
          ),
        );
      }

      final error = state.canExecuteTownshipTrade(tradeId);

      expect(error, contains('Inventory is full'));
    });

    test('returns null when all checks pass', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 200),
      );

      final error = state.canExecuteTownshipTrade(tradeId);

      expect(error, isNull);
    });

    test('validates resources for multiple quantity', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      // Have 150 Food, but try to buy 2 (needs 200)
      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 150),
      );

      final error = state.canExecuteTownshipTrade(tradeId, quantity: 2);

      expect(error, contains('Not enough Food'));
      expect(error, contains('need 200'));
    });
  });

  group('executeTownshipTrade', () {
    test('throws when validation fails', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );
      final state = GlobalState.test(registries);

      expect(
        () =>
            state.executeTownshipTrade(const MelvorId('melvorD:Unknown_Trade')),
        throwsStateError,
      );
    });

    test('deducts township resources and adds items', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              itemQuantity: 5,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 500),
      );

      expect(state.township.resourceAmount(resourceId), 500);
      expect(state.inventory.countOfItem(testItem), 0);

      state = state.executeTownshipTrade(tradeId);

      expect(state.township.resourceAmount(resourceId), 400);
      expect(state.inventory.countOfItem(testItem), 5);
    });

    test('supports multiple quantity', () {
      const tradeId = MelvorId('melvorD:Test_Trade');
      const resourceId = MelvorId('melvorF:Food');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          trades: [
            TownshipTrade(
              id: tradeId,
              resourceId: resourceId,
              itemId: testItem.id,
              itemQuantity: 5,
              costs: {resourceId: 100},
            ),
          ],
          resources: const [
            TownshipResource(id: resourceId, name: 'Food', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(
        township: state.township.addResource(resourceId, 500),
      );

      state = state.executeTownshipTrade(tradeId, quantity: 3);

      // 3 trades * 100 cost each = 300 spent
      expect(state.township.resourceAmount(resourceId), 200);
      // 3 trades * 5 items each = 15 items
      expect(state.inventory.countOfItem(testItem), 15);
    });
  });

  group('repairTownshipBuilding', () {
    test('throws for unknown building', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );
      final state = GlobalState.test(registries);

      expect(
        () => state.repairTownshipBuilding(
          const MelvorId('melvorD:Grasslands'),
          const MelvorId('melvorD:Unknown_Building'),
        ),
        throwsStateError,
      );
    });

    test('throws when building has no data for biome', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const otherBiomeId = MelvorId('melvorD:Forest');

      // Building only valid for Forest, not Grasslands
      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {otherBiomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
            TownshipBiome(id: otherBiomeId, name: 'Forest', tier: 1),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      expect(
        () => state.repairTownshipBuilding(biomeId, buildingId),
        throwsStateError,
      );
    });

    test('throws when no buildings to repair', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      expect(
        () => state.repairTownshipBuilding(biomeId, buildingId),
        throwsStateError,
      );
    });

    test('throws when building is already at full efficiency', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      // Build the building (starts at 100% efficiency)
      state = state.buildTownshipBuilding(biomeId, buildingId);

      expect(
        () => state.repairTownshipBuilding(biomeId, buildingId),
        throwsStateError,
      );
    });

    test('throws when not enough GP for repair', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 1000},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      // Manually set up a building at 50% efficiency
      state = state.copyWith(
        township: state.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        ),
      );

      expect(
        () => state.repairTownshipBuilding(biomeId, buildingId),
        throwsStateError,
      );
    });

    test('throws when not enough township resources for repair', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {woodId: 1000},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      // Manually set up a building at 50% efficiency
      state = state.copyWith(
        township: state.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        ),
      );

      expect(
        () => state.repairTownshipBuilding(biomeId, buildingId),
        throwsStateError,
      );
    });

    test('repairs building and deducts proportional GP cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const gpId = MelvorId('melvorF:GP');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {gpId: 1000},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.addCurrency(Currency.gp, 1000);

      // Set up building at 50% efficiency (50% damage)
      // Repair cost = (1000 / 3) × 1 × 0.5 = 166.67 → ceil = 167 GP
      state = state.copyWith(
        township: state.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        ),
      );

      expect(state.gp, 1000);
      expect(
        state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        50,
      );

      state = state.repairTownshipBuilding(biomeId, buildingId);

      // Repair cost = (1000 / 3) × 1 × 0.5 = 167 GP (rounded up)
      expect(state.gp, 833);
      expect(
        state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });

    test('repairs building and deducts proportional resource cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        costs: {woodId: 200},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.copyWith(township: state.township.addResource(woodId, 500));

      // Set up building at 80% efficiency (20% damage)
      // Repair cost = (200 / 3) × 1 × 0.2 = 13.33 → ceil = 14 Wood
      state = state.copyWith(
        township: state.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 80),
            },
          ),
        ),
      );

      expect(state.township.resourceAmount(woodId), 500);

      state = state.repairTownshipBuilding(biomeId, buildingId);

      // Repair cost = (200 / 3) × 1 × 0.2 = 14 Wood (rounded up)
      expect(state.township.resourceAmount(woodId), 486);
      expect(
        state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });
  });

  group('claimTaskReward', () {
    test('throws for unknown task', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );
      final state = GlobalState.test(registries);

      expect(
        () => state.claimTaskReward(const MelvorId('melvorD:Unknown_Task')),
        throwsStateError,
      );
    });

    test('throws when task requirements not met', () {
      const taskId = MelvorId('melvorD:Test_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: [TaskRequirement(type: 'population', target: 100)],
              rewards: [TaskReward(type: 'xp', amount: 100)],
            ),
          ],
        ),
      );

      // State has 0 population
      final state = GlobalState.test(registries);

      expect(() => state.claimTaskReward(taskId), throwsStateError);
    });

    test('grants XP reward', () {
      const taskId = MelvorId('melvorD:Test_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [TaskReward(type: 'xp', amount: 500)],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      final initialXp = state.skillState(Skill.town).xp;

      state = state.claimTaskReward(taskId);

      expect(state.skillState(Skill.town).xp, initialXp + 500);
    });

    test('grants GP reward', () {
      const taskId = MelvorId('melvorD:Test_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [TaskReward(type: 'gp', amount: 1000)],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.gp, 0);

      state = state.claimTaskReward(taskId);

      expect(state.gp, 1000);
    });

    test('grants item reward', () {
      const taskId = MelvorId('melvorD:Test_Task');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: const [
                TaskRequirement(type: 'population', target: 0),
              ],
              rewards: [
                TaskReward(type: 'item', amount: 10, itemId: testItem.id),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.inventory.countOfItem(testItem), 0);

      state = state.claimTaskReward(taskId);

      expect(state.inventory.countOfItem(testItem), 10);
    });

    test('grants township resource reward', () {
      const taskId = MelvorId('melvorD:Test_Task');
      const resourceId = MelvorId('melvorF:Wood');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [
                TaskReward(
                  type: 'townshipResource',
                  amount: 500,
                  itemId: resourceId,
                ),
              ],
            ),
          ],
          resources: [
            TownshipResource(id: resourceId, name: 'Wood', type: 'Raw'),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.township.resourceAmount(resourceId), 0);

      state = state.claimTaskReward(taskId);

      expect(state.township.resourceAmount(resourceId), 500);
    });

    test('marks main task as completed', () {
      const taskId = MelvorId('melvorD:Main_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Main Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [TaskReward(type: 'xp', amount: 100)],
              isMainTask: true,
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.township.completedMainTasks, isEmpty);

      state = state.claimTaskReward(taskId);

      expect(state.township.completedMainTasks, contains(taskId));
    });

    test('prevents claiming main task twice', () {
      const taskId = MelvorId('melvorD:Main_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Main Task',
              requirements: [TaskRequirement(type: 'population', target: 0)],
              rewards: [TaskReward(type: 'xp', amount: 100)],
              isMainTask: true,
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.claimTaskReward(taskId);

      // Trying to claim again should fail
      expect(() => state.claimTaskReward(taskId), throwsStateError);
    });

    test('grants multiple rewards', () {
      const taskId = MelvorId('melvorD:Test_Task');
      final testItem = Item.test('Test Item', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              name: 'Test Task',
              requirements: const [
                TaskRequirement(type: 'population', target: 0),
              ],
              rewards: [
                const TaskReward(type: 'xp', amount: 100),
                const TaskReward(type: 'gp', amount: 500),
                TaskReward(type: 'item', amount: 5, itemId: testItem.id),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      final initialXp = state.skillState(Skill.town).xp;

      state = state.claimTaskReward(taskId);

      expect(state.skillState(Skill.town).xp, initialXp + 100);
      expect(state.gp, 500);
      expect(state.inventory.countOfItem(testItem), 5);
    });

    test('validates buildBuilding requirement', () {
      const taskId = MelvorId('melvorD:Test_Task');
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          tasks: const [
            TownshipTask(
              id: taskId,
              name: 'Build Task',
              requirements: [
                TaskRequirement(
                  type: 'buildBuilding',
                  target: 3,
                  targetId: buildingId,
                ),
              ],
              rewards: [TaskReward(type: 'xp', amount: 100)],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);

      // Should fail with 0 buildings
      expect(() => state.claimTaskReward(taskId), throwsStateError);

      // Build 2 buildings (still not enough)
      state = state.buildTownshipBuilding(biomeId, buildingId);
      state = state.buildTownshipBuilding(biomeId, buildingId);
      expect(() => state.claimTaskReward(taskId), throwsStateError);

      // Build a third building (now meets requirement)
      state = state.buildTownshipBuilding(biomeId, buildingId);
      state = state.claimTaskReward(taskId);
      expect(state.skillState(Skill.town).xp, greaterThan(0));
    });
  });
}
