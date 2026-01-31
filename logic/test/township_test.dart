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

    group('buildingNeedsRepair', () {
      test('returns false when no building exists', () {
        const state = TownshipState.empty();
        expect(
          state.buildingNeedsRepair(
            const MelvorId('melvorD:Grasslands'),
            const MelvorId('melvorD:Test_Building'),
          ),
          isFalse,
        );
      });

      test('returns false when building is at 100% efficiency', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 5)},
            ),
          },
        );

        expect(state.buildingNeedsRepair(biomeId, buildingId), isFalse);
      });

      test('returns true when building has reduced efficiency', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 5, efficiency: 80),
              },
            ),
          },
        );

        expect(state.buildingNeedsRepair(biomeId, buildingId), isTrue);
      });

      test('returns false when building count is 0', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 0, efficiency: 50),
              },
            ),
          },
        );

        expect(state.buildingNeedsRepair(biomeId, buildingId), isFalse);
      });
    });

    group('totalRepairCosts', () {
      test('returns empty map when no buildings need repair', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {const MelvorId('melvorD:GP'): 1000},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        );

        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 5)},
            ),
          },
        );

        expect(state.totalRepairCosts, isEmpty);
      });

      test('returns repair costs for single damaged building', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 1000},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
        );

        // 1 building at 50% efficiency = 50% damage
        // Repair cost = (1000 / 3) × 1 × 0.5 = 166.67 → ceil = 167
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

        final costs = state.totalRepairCosts;
        expect(costs[gpId], 167);
      });

      test('aggregates costs across multiple biomes', () {
        const biomeId1 = MelvorId('melvorD:Grasslands');
        const biomeId2 = MelvorId('melvorD:Forest');
        const buildingId = MelvorId('melvorD:Test_Building');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId1, biomeId2},
          costs: {gpId: 300},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId1, name: 'Grasslands', tier: 1),
            TownshipBiome(id: biomeId2, name: 'Forest', tier: 1),
          ],
        );

        // Both biomes have damaged buildings
        // Biome 1: 1 building at 50% = (300/3) × 1 × 0.5 = 50
        // Biome 2: 2 buildings at 80% = (300/3) × 2 × 0.2 = 40
        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId1: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 1, efficiency: 50),
              },
            ),
            biomeId2: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 2, efficiency: 80),
              },
            ),
          },
        );

        final costs = state.totalRepairCosts;
        expect(costs[gpId], 90); // 50 + 40
      });

      test('aggregates multiple resource types', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');
        final gpId = Currency.gp.id;
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 300, woodId: 150},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        );

        // 2 buildings at 50% efficiency = 50% damage
        // GP repair = (300/3) × 2 × 0.5 = 100
        // Wood repair = (150/3) × 2 × 0.5 = 50
        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 2, efficiency: 50),
              },
            ),
          },
        );

        final costs = state.totalRepairCosts;
        expect(costs[gpId], 100);
        expect(costs[woodId], 50);
      });
    });

    group('hasAnyBuildingNeedingRepair', () {
      test('returns false when no buildings exist', () {
        const state = TownshipState.empty();
        expect(state.hasAnyBuildingNeedingRepair, isFalse);
      });

      test('returns false when all buildings at 100% efficiency', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 5)},
            ),
          },
        );

        expect(state.hasAnyBuildingNeedingRepair, isFalse);
      });

      test('returns true when any building has reduced efficiency', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId1 = MelvorId('melvorD:Building1');
        const buildingId2 = MelvorId('melvorD:Building2');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId: BiomeState(
              buildings: {
                buildingId1: const BuildingState(count: 5),
                buildingId2: const BuildingState(count: 3, efficiency: 80),
              },
            ),
          },
        );

        expect(state.hasAnyBuildingNeedingRepair, isTrue);
      });

      test('returns true when buildings in different biomes need repair', () {
        const biomeId1 = MelvorId('melvorD:Grasslands');
        const biomeId2 = MelvorId('melvorD:Forest');
        const buildingId = MelvorId('melvorD:Test_Building');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          biomes: {
            biomeId1: BiomeState(
              buildings: {buildingId: const BuildingState(count: 5)},
            ),
            biomeId2: BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 3, efficiency: 50),
              },
            ),
          },
        );

        expect(state.hasAnyBuildingNeedingRepair, isTrue);
      });
    });

    group('productionRatesPerHour', () {
      test('returns empty map when no buildings produce resources', () {
        const state = TownshipState.empty();
        expect(state.productionRatesPerHour, isEmpty);
      });

      test('calculates production for single building type', () {
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
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 2)},
            ),
          },
        );

        final rates = state.productionRatesPerHour;
        // 100 base × 2 buildings × 1.0 efficiency × 1.5 education multiplier
        // (50% from spring)
        expect(rates[woodId], 300);
      });

      test('applies efficiency modifier', () {
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
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
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

        final rates = state.productionRatesPerHour;
        // 100 base × 1 building × 0.5 efficiency × 1.5 education
        expect(rates[woodId], 75);
      });

      test('applies deity production modifier', () {
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');
        const woodId = MelvorId('melvorF:Wood');
        const deityId = MelvorId('melvorD:TestDeity');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {woodId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
          deities: const [
            TownshipDeity(
              id: deityId,
              name: 'Test Deity',
              baseModifiers: DeityModifiers(
                buildingProduction: [
                  BiomeProductionModifier(biomeId: biomeId, value: 50),
                ],
              ),
            ),
          ],
        );

        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
          worshipId: deityId,
        );

        final rates = state.productionRatesPerHour;
        // 100 base × 1 building × 1.0 efficiency × 1.5 education × 1.5 deity
        expect(rates[woodId], 225);
      });

      test('sums production across multiple buildings and biomes', () {
        const biomeId1 = MelvorId('melvorD:Grasslands');
        const biomeId2 = MelvorId('melvorD:Forest');
        const buildingId1 = MelvorId('melvorD:Building1');
        const buildingId2 = MelvorId('melvorD:Building2');
        const woodId = MelvorId('melvorF:Wood');

        final building1 = testBuilding(
          id: buildingId1,
          name: 'Building 1',
          validBiomes: {biomeId1},
          production: {woodId: 100},
        );
        final building2 = testBuilding(
          id: buildingId2,
          name: 'Building 2',
          validBiomes: {biomeId2},
          production: {woodId: 50},
        );

        final registry = TownshipRegistry(
          buildings: [building1, building2],
          biomes: const [
            TownshipBiome(id: biomeId1, name: 'Grasslands', tier: 1),
            TownshipBiome(id: biomeId2, name: 'Forest', tier: 1),
          ],
          resources: const [
            TownshipResource(id: woodId, name: 'Wood', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          biomes: {
            biomeId1: BiomeState(
              buildings: {buildingId1: const BuildingState(count: 2)},
            ),
            biomeId2: BiomeState(
              buildings: {buildingId2: const BuildingState(count: 3)},
            ),
          },
        );

        final rates = state.productionRatesPerHour;
        // Biome 1: 100 × 2 × 1.0 × 1.5 = 300
        // Biome 2: 50 × 3 × 1.0 × 1.5 = 225
        // Total: 525
        expect(rates[woodId], 525);
      });
    });

    group('maxHealableWith', () {
      test('returns 0 when no healing resource available', () {
        const state = TownshipState.empty();
        expect(state.maxHealableWith(HealingResource.herbs), 0);
        expect(state.maxHealableWith(HealingResource.potions), 0);
      });

      test('returns 0 when health is already at max', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        // Need production to calculate costPerHealthPercent
        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 1000},
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        expect(state.maxHealableWith(HealingResource.herbs), 0);
      });

      test('calculates healable amount based on resources and production', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        // Production rate of 100/hr means costPerHealthPercent = ceil(100 * 0.1) = 10
        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 100}, // 100 herbs available
          health: 80, // Need 20% to reach max
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        // costPerHealthPercent = ceil(150 * 0.1) = 15 (100 base * 1.5 edu)
        // 100 herbs / 15 cost = 6 max from resources, need 20% to max
        expect(state.maxHealableWith(HealingResource.herbs), 6);
      });

      test('limits healable amount by health needed', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 10000}, // Lots of herbs
          health: 95, // Only need 5% to max
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        // Even with lots of herbs, can only heal 5%
        expect(state.maxHealableWith(HealingResource.herbs), 5);
      });
    });

    group('healWith', () {
      test('throws when insufficient resources', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 5}, // Very few herbs
          health: 50,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        expect(
          () => state.healWith(HealingResource.herbs, 10),
          throwsStateError,
        );
      });

      test('increases health and deducts resources', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        // Production of 100/hr with 1.5 education = 150/hr
        // costPerHealthPercent = ceil(150 * 0.1) = 15
        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 100},
          health: 80,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        final newState = state.healWith(HealingResource.herbs, 5);

        expect(newState.health, 85);
        // Cost = 5% × 15 per percent = 75 herbs
        expect(newState.resourceAmount(herbsId), 25);
      });

      test('clamps health at max', () {
        const herbsId = MelvorId('melvorF:Herbs');
        const biomeId = MelvorId('melvorD:Grasslands');
        const buildingId = MelvorId('melvorD:Test_Building');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          production: {herbsId: 100},
        );

        final registry = TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        );

        final state = TownshipState(
          registry: registry,
          resources: {herbsId: 1000},
          health: 95,
          biomes: {
            biomeId: BiomeState(
              buildings: {buildingId: const BuildingState(count: 1)},
            ),
          },
        );

        final newState = state.healWith(HealingResource.herbs, 10);

        // Health should cap at 100, not 105
        expect(newState.health, 100);
      });

      test('returns same state when amount is 0', () {
        const herbsId = MelvorId('melvorF:Herbs');

        final state = TownshipState(
          registry: const TownshipRegistry.empty(),
          resources: {herbsId: 100},
          health: 80,
        );

        final newState = state.healWith(HealingResource.herbs, 0);

        expect(newState.health, 80);
        expect(newState.resourceAmount(herbsId), 100);
      });
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
      final gpId = Currency.gp.id;

      final building = testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {gpId: 100},
      );

      final registry = TownshipRegistry(
        buildings: [building],
        biomes: const [TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1)],
        resources: [TownshipResource(id: gpId, name: 'GP', type: 'Currency')],
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
      final result = processTownUpdate(
        state,
        registry,
        random,
        townshipLevel: 1,
      );

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
      final result = processTownUpdate(
        state,
        registry,
        random,
        townshipLevel: 1,
      );

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
        final result = processTownUpdate(
          currentState,
          registry,
          random,
          townshipLevel: 1,
        );
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
        final result = processTownUpdate(
          currentState,
          registry,
          random,
          townshipLevel: 1,
        );
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
      final result = processTownUpdate(
        state,
        registry,
        random,
        townshipLevel: 1,
      );

      // Population: 7 base + 10 from building = 17
      // Health: 100% (base), so effective population = 17
      // Happiness: 50 from spring + 50 from building = 100 (2x XP multiplier)
      // XP = 17 * 2.0 = 34
      expect(result.xpGained, 34);
    });

    test('health does not decrease below level 15', () {
      const registry = TownshipRegistry.empty();
      const state = TownshipState(registry: registry);

      final random = Random(42);
      // Run many updates at level 1 - health should never decrease
      var currentState = state;
      for (var i = 0; i < 100; i++) {
        final result = processTownUpdate(
          currentState,
          registry,
          random,
          townshipLevel: 1,
        );
        currentState = result.state;
      }

      expect(currentState.health, 100);
    });

    test('health can decrease at level 15+', () {
      const registry = TownshipRegistry.empty();
      const state = TownshipState(registry: registry);

      final random = Random(42);
      // Run many updates at level 15 - health should eventually decrease
      var currentState = state;
      var healthDecreased = false;
      for (var i = 0; i < 100 && !healthDecreased; i++) {
        final result = processTownUpdate(
          currentState,
          registry,
          random,
          townshipLevel: 15,
        );
        currentState = result.state;
        if (currentState.health < 100) {
          healthDecreased = true;
        }
      }

      expect(healthDecreased, isTrue);
      expect(currentState.health, lessThan(100));
      expect(
        currentState.health,
        greaterThanOrEqualTo(TownshipState.minHealth),
      );
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
      final gpId = Currency.gp.id;

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
      final gpId = Currency.gp.id;
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
      final gpId = Currency.gp.id;

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
      final gpId = Currency.gp.id;
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

    group('canAffordTownshipRepair', () {
      test('returns true when building has no repair costs', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {const MelvorId('melvorD:GP'): 1000},
        );

        final registries = Registries.test(
          township: TownshipRegistry(
            buildings: [building],
            biomes: const [
              TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
            ],
          ),
        );

        // Building at 100% efficiency has no repair costs
        var state = GlobalState.test(registries);
        state = state.copyWith(
          township: state.township.withBiomeState(
            biomeId,
            BiomeState(buildings: {buildingId: const BuildingState(count: 1)}),
          ),
        );

        expect(state.canAffordTownshipRepair(biomeId, buildingId), isTrue);
      });

      test('returns true when player has enough GP', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

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
        state = state.addCurrency(Currency.gp, 500);
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

        // Repair cost = (1000/3) × 1 × 0.5 = 167 GP
        expect(state.canAffordTownshipRepair(biomeId, buildingId), isTrue);
      });

      test('returns false when player lacks GP', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

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
        // No GP added
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

        expect(state.canAffordTownshipRepair(biomeId, buildingId), isFalse);
      });

      test('returns false when player lacks township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {woodId: 300},
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
        // No wood resources
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

        expect(state.canAffordTownshipRepair(biomeId, buildingId), isFalse);
      });

      test('returns true when player has enough township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {woodId: 300},
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
        state = state.copyWith(
          township: state.township
              .addResource(woodId, 100)
              .withBiomeState(
                biomeId,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 1, efficiency: 50),
                  },
                ),
              ),
        );

        // Repair cost = (300/3) × 1 × 0.5 = 50 wood, we have 100
        expect(state.canAffordTownshipRepair(biomeId, buildingId), isTrue);
      });
    });

    group('canAffordAllTownshipRepairs', () {
      test('returns true when no buildings need repair', () {
        final registries = Registries.test(
          township: const TownshipRegistry.empty(),
        );

        final state = GlobalState.test(registries);
        expect(state.canAffordAllTownshipRepairs(), isTrue);
      });

      test('returns true when player has enough resources for all repairs', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId1 = MelvorId('melvorD:Grasslands');
        const biomeId2 = MelvorId('melvorD:Forest');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId1, biomeId2},
          costs: {gpId: 300},
        );

        final registries = Registries.test(
          township: TownshipRegistry(
            buildings: [building],
            biomes: const [
              TownshipBiome(id: biomeId1, name: 'Grasslands', tier: 1),
              TownshipBiome(id: biomeId2, name: 'Forest', tier: 1),
            ],
          ),
        );

        var state = GlobalState.test(registries);
        state = state.addCurrency(Currency.gp, 1000);
        state = state.copyWith(
          township: state.township
              .withBiomeState(
                biomeId1,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 1, efficiency: 50),
                  },
                ),
              )
              .withBiomeState(
                biomeId2,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 2, efficiency: 80),
                  },
                ),
              ),
        );

        expect(state.canAffordAllTownshipRepairs(), isTrue);
      });

      test('returns false when player cannot afford total costs', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 10000},
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
        state = state.addCurrency(Currency.gp, 100); // Only 100 GP
        state = state.copyWith(
          township: state.township.withBiomeState(
            biomeId,
            BiomeState(
              buildings: {
                buildingId: const BuildingState(count: 5, efficiency: 20),
              },
            ),
          ),
        );

        expect(state.canAffordAllTownshipRepairs(), isFalse);
      });

      test('checks both GP and township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 300, woodId: 300},
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
        state = state.addCurrency(Currency.gp, 1000); // Enough GP
        // No wood - should fail
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

        expect(state.canAffordAllTownshipRepairs(), isFalse);

        // Add enough wood
        state = state.copyWith(
          township: state.township.addResource(woodId, 100),
        );

        expect(state.canAffordAllTownshipRepairs(), isTrue);
      });
    });

    group('canAffordTownshipBuildingCosts', () {
      test('returns false for invalid building', () {
        final registries = Registries.test(
          township: const TownshipRegistry.empty(),
        );

        final state = GlobalState.test(registries);
        expect(
          state.canAffordTownshipBuildingCosts(
            const MelvorId('melvorD:Grasslands'),
            const MelvorId('melvorD:Nonexistent'),
          ),
          isFalse,
        );
      });

      test('returns false for invalid biome', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {const MelvorId('melvorD:GP'): 1000},
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
        // Building exists but biome is invalid for this building
        expect(
          state.canAffordTownshipBuildingCosts(
            const MelvorId('melvorD:InvalidBiome'),
            buildingId,
          ),
          isFalse,
        );
      });

      test('returns true when player has enough GP', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

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

        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isTrue,
        );
      });

      test('returns false when player lacks GP', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

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
        state = state.addCurrency(Currency.gp, 500); // Not enough

        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isFalse,
        );
      });

      test('returns true when player has enough township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {woodId: 100},
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
        state = state.copyWith(
          township: state.township.addResource(woodId, 100),
        );

        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isTrue,
        );
      });

      test('returns false when player lacks township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {woodId: 100},
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
        state = state.copyWith(
          township: state.township.addResource(woodId, 50), // Not enough
        );

        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isFalse,
        );
      });

      test('checks both GP and township resources', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 500, woodId: 100},
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

        // Has GP but no wood
        var state = GlobalState.test(registries);
        state = state.addCurrency(Currency.gp, 500);
        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isFalse,
        );

        // Add wood - now should pass
        state = state.copyWith(
          township: state.township.addResource(woodId, 100),
        );
        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isTrue,
        );
      });

      test('applies deity building cost modifier', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const deityId = MelvorId('melvorD:TestDeity');
        final gpId = Currency.gp.id;

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
            deities: const [
              TownshipDeity(
                id: deityId,
                name: 'Test Deity',
                baseModifiers: DeityModifiers(buildingCost: -25),
              ),
            ],
          ),
        );

        // With -25% cost modifier, 1000 GP cost becomes 750 GP
        var state = GlobalState.test(registries);
        state = state.copyWith(
          township: state.township.copyWith(worshipId: deityId),
        );
        state = state.addCurrency(Currency.gp, 750);

        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isTrue,
        );

        // With 749 GP, should not be able to afford
        state = state.addCurrency(Currency.gp, -1);
        expect(
          state.canAffordTownshipBuildingCosts(biomeId, buildingId),
          isFalse,
        );
      });
    });

    group('repairAllTownshipBuildings', () {
      test('throws when no buildings need repair', () {
        final registries = Registries.test(
          township: const TownshipRegistry.empty(),
        );

        final state = GlobalState.test(registries);

        expect(state.repairAllTownshipBuildings, throwsStateError);
      });

      test('throws when player cannot afford costs', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {gpId: 10000},
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

        expect(() => state.repairAllTownshipBuildings(), throwsStateError);
      });

      test('deducts GP and restores efficiency', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        final gpId = Currency.gp.id;

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
        state = state.addCurrency(Currency.gp, 500);
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

        expect(state.gp, 500);
        expect(
          state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
          50,
        );

        state = state.repairAllTownshipBuildings();

        // Repair cost = (1000/3) × 1 × 0.5 = 167 GP
        expect(state.gp, 333);
        expect(
          state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
          100,
        );
      });

      test('deducts resources and restores efficiency', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId = MelvorId('melvorD:Grasslands');
        const woodId = MelvorId('melvorF:Wood');

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId},
          costs: {woodId: 300},
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
        state = state.copyWith(
          township: state.township
              .addResource(woodId, 200)
              .withBiomeState(
                biomeId,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 1, efficiency: 50),
                  },
                ),
              ),
        );

        expect(state.township.resourceAmount(woodId), 200);

        state = state.repairAllTownshipBuildings();

        // Repair cost = (300/3) × 1 × 0.5 = 50 wood
        expect(state.township.resourceAmount(woodId), 150);
        expect(
          state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
          100,
        );
      });

      test('repairs all buildings across multiple biomes', () {
        const buildingId = MelvorId('melvorD:Test_Building');
        const biomeId1 = MelvorId('melvorD:Grasslands');
        const biomeId2 = MelvorId('melvorD:Forest');
        final gpId = Currency.gp.id;

        final building = testBuilding(
          id: buildingId,
          name: 'Test Building',
          validBiomes: {biomeId1, biomeId2},
          costs: {gpId: 300},
        );

        final registries = Registries.test(
          township: TownshipRegistry(
            buildings: [building],
            biomes: const [
              TownshipBiome(id: biomeId1, name: 'Grasslands', tier: 1),
              TownshipBiome(id: biomeId2, name: 'Forest', tier: 1),
            ],
          ),
        );

        var state = GlobalState.test(registries);
        state = state.addCurrency(Currency.gp, 1000);
        state = state.copyWith(
          township: state.township
              .withBiomeState(
                biomeId1,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 1, efficiency: 50),
                  },
                ),
              )
              .withBiomeState(
                biomeId2,
                BiomeState(
                  buildings: {
                    buildingId: const BuildingState(count: 2, efficiency: 80),
                  },
                ),
              ),
        );

        state = state.repairAllTownshipBuildings();

        expect(
          state.township.biomes[biomeId1]!.buildings[buildingId]!.efficiency,
          100,
        );
        expect(
          state.township.biomes[biomeId2]!.buildings[buildingId]!.efficiency,
          100,
        );
        expect(state.township.hasAnyBuildingNeedingRepair, isFalse);
      });
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
              category: TaskCategory.easy,
              // No goals means immediately completable
              rewards: [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 100,
                ),
              ],
            ),
          ],
        ),
      );

      final state = GlobalState.test(registries);

      // Task with no goals should be completable
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

    test('getProductionModifierForBiome returns 0 when no deity selected', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );

      final state = GlobalState.test(registries);

      expect(
        state.township.getProductionModifierForBiome(
          const MelvorId('melvorF:Grasslands'),
        ),
        0,
      );
    });

    test('deity base modifiers apply to production', () {
      const deityId = MelvorId('melvorD:TestDeity');
      const grasslandsId = MelvorId('melvorF:Grasslands');
      const desertId = MelvorId('melvorF:Desert');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [
            TownshipDeity(
              id: deityId,
              name: 'Test Deity',
              baseModifiers: DeityModifiers(
                buildingProduction: [
                  BiomeProductionModifier(biomeId: grasslandsId, value: 25),
                  BiomeProductionModifier(biomeId: desertId, value: -50),
                ],
                buildingCost: -15,
              ),
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.selectWorship(deityId);

      // Base modifiers apply immediately (no worship needed)
      expect(state.township.getProductionModifierForBiome(grasslandsId), 25);
      expect(state.township.getProductionModifierForBiome(desertId), -50);
      expect(state.township.getBuildingCostModifier(), -15);
    });

    test('deity checkpoint modifiers unlock at thresholds', () {
      const deityId = MelvorId('melvorD:TestDeity');
      const mountainsId = MelvorId('melvorF:Mountains');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [
            TownshipDeity(
              id: deityId,
              name: 'Test Deity',
              checkpoints: [
                // Checkpoint 0: unlocks at 5%
                DeityModifiers(
                  buildingProduction: [
                    BiomeProductionModifier(biomeId: mountainsId, value: 10),
                  ],
                ),
                // Checkpoint 1: unlocks at 25%
                DeityModifiers(
                  buildingProduction: [
                    BiomeProductionModifier(biomeId: mountainsId, value: 15),
                  ],
                ),
                // Checkpoint 2: unlocks at 50%
                DeityModifiers(buildingCost: -10),
                // Checkpoint 3: unlocks at 85%
                DeityModifiers(
                  buildingProduction: [
                    BiomeProductionModifier(biomeId: mountainsId, value: 20),
                  ],
                ),
                // Checkpoint 4: unlocks at 95%
                DeityModifiers(
                  buildingProduction: [
                    BiomeProductionModifier(biomeId: mountainsId, value: 25),
                  ],
                  buildingCost: -15,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.selectWorship(deityId);

      // At 0% worship - no checkpoints unlocked
      expect(state.township.worshipPercent, 0);
      expect(state.township.getProductionModifierForBiome(mountainsId), 0);
      expect(state.township.getBuildingCostModifier(), 0);

      // At 5% worship (100 points) - checkpoint 0 unlocked
      state = state.copyWith(township: state.township.copyWith(worship: 100));
      expect(state.township.worshipPercent, 5);
      expect(state.township.getProductionModifierForBiome(mountainsId), 10);

      // At 25% worship (500 points) - checkpoints 0 + 1 unlocked
      state = state.copyWith(township: state.township.copyWith(worship: 500));
      expect(state.township.worshipPercent, 25);
      expect(state.township.getProductionModifierForBiome(mountainsId), 25);

      // At 50% worship (1000 points) - checkpoints 0 + 1 + 2 unlocked
      state = state.copyWith(township: state.township.copyWith(worship: 1000));
      expect(state.township.worshipPercent, 50);
      expect(state.township.getProductionModifierForBiome(mountainsId), 25);
      expect(state.township.getBuildingCostModifier(), -10);

      // At 95% worship (1900 points) - all checkpoints unlocked
      state = state.copyWith(township: state.township.copyWith(worship: 1900));
      expect(state.township.worshipPercent, 95);
      expect(
        state.township.getProductionModifierForBiome(mountainsId),
        70, // 10 + 15 + 20 + 25
      );
      expect(state.township.getBuildingCostModifier(), -25); // -10 + -15
    });

    test('buildingCostsWithModifier applies deity discount', () {
      const deityId = MelvorId('melvorD:TestDeity');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [
            TownshipDeity(
              id: deityId,
              name: 'Test Deity',
              baseModifiers: DeityModifiers(buildingCost: -25),
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      state = state.selectWorship(deityId);

      final baseCosts = {
        const MelvorId('melvorF:Food'): 100,
        const MelvorId('melvorF:Wood'): 200,
      };

      final modifiedCosts = state.township.buildingCostsWithModifier(baseCosts);

      // -25% cost modifier means 75% of original
      expect(modifiedCosts[const MelvorId('melvorF:Food')], 75);
      expect(modifiedCosts[const MelvorId('melvorF:Wood')], 150);
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
      final gpId = Currency.gp.id;

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
      final gpId = Currency.gp.id;

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

  group('claimTaskRewardWithChanges', () {
    test('throws for unknown task', () {
      final registries = Registries.test(
        township: const TownshipRegistry.empty(),
      );
      final state = GlobalState.test(registries);

      expect(
        () => state.claimTaskRewardWithChanges(
          const MelvorId('melvorD:Unknown_Task'),
        ),
        throwsStateError,
      );
    });

    test('throws when item goal not met', () {
      const taskId = MelvorId('melvorD:Test_Task');
      final testItem = Item.test('Oak Logs', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.easy,
              goals: [
                TaskGoal(
                  type: TaskGoalType.items,
                  id: testItem.id,
                  quantity: 100,
                ),
              ],
              rewards: const [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 1000,
                ),
              ],
            ),
          ],
        ),
      );

      // State has no items
      final state = GlobalState.test(registries);

      expect(() => state.claimTaskRewardWithChanges(taskId), throwsStateError);
    });

    test('grants GP reward and consumes items', () {
      const taskId = MelvorId('melvorD:Test_Task');
      final testItem = Item.test('Oak Logs', gp: 10);

      final registries = Registries.test(
        items: [testItem],
        township: TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.easy,
              goals: [
                TaskGoal(
                  type: TaskGoalType.items,
                  id: testItem.id,
                  quantity: 50,
                ),
              ],
              rewards: const [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 1000,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      // Add required items to inventory
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(testItem, count: 100)),
      );
      expect(state.gp, 0);
      expect(state.inventory.countOfItem(testItem), 100);

      (state, _) = state.claimTaskRewardWithChanges(taskId);

      expect(state.gp, 1000);
      // Items should be consumed
      expect(state.inventory.countOfItem(testItem), 50);
    });

    test('grants item reward', () {
      const taskId = MelvorId('melvorD:Test_Task');
      final rewardItem = Item.test('Reward Item', gp: 100);

      final registries = Registries.test(
        items: [rewardItem],
        township: TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.easy,
              // No goals means immediately completable
              rewards: [
                TaskReward(
                  type: TaskRewardType.item,
                  id: rewardItem.id,
                  quantity: 10,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.inventory.countOfItem(rewardItem), 0);

      (state, _) = state.claimTaskRewardWithChanges(taskId);

      expect(state.inventory.countOfItem(rewardItem), 10);
    });

    test('grants township resource reward', () {
      const taskId = MelvorId('melvorD:Test_Task');
      const resourceId = MelvorId('melvorF:Wood');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.normal,
              rewards: [
                TaskReward(
                  type: TaskRewardType.townshipResource,
                  id: resourceId,
                  quantity: 500,
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

      (state, _) = state.claimTaskRewardWithChanges(taskId);

      expect(state.township.resourceAmount(resourceId), 500);
    });

    test('marks task as completed', () {
      const taskId = MelvorId('melvorD:Main_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.hard,
              rewards: [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 100,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      expect(state.township.completedMainTasks, isEmpty);

      (state, _) = state.claimTaskRewardWithChanges(taskId);

      expect(state.township.completedMainTasks, contains(taskId));
    });

    test('prevents claiming task twice', () {
      const taskId = MelvorId('melvorD:Main_Task');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.elite,
              rewards: [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 100,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);
      (state, _) = state.claimTaskRewardWithChanges(taskId);

      // Trying to claim again should fail
      expect(() => state.claimTaskRewardWithChanges(taskId), throwsStateError);
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
              category: TaskCategory.veryHard,
              rewards: [
                const TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 500,
                ),
                const TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:SlayerCoins'),
                  quantity: 100,
                ),
                TaskReward(
                  type: TaskRewardType.item,
                  id: testItem.id,
                  quantity: 5,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);

      (state, _) = state.claimTaskRewardWithChanges(taskId);

      expect(state.gp, 500);
      expect(state.currency(Currency.slayerCoins), 100);
      expect(state.inventory.countOfItem(testItem), 5);
    });

    test('validates skillXP goal with progress tracking', () {
      const taskId = MelvorId('melvorD:Test_Task');
      const skillId = MelvorId('melvorD:Woodcutting');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.easy,
              goals: [
                TaskGoal(
                  type: TaskGoalType.skillXP,
                  id: skillId,
                  quantity: 1000,
                ),
              ],
              rewards: [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 500,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);

      // Should fail with no progress
      expect(() => state.claimTaskRewardWithChanges(taskId), throwsStateError);

      // Add progress toward the goal
      state = state.copyWith(
        township: state.township.updateTaskProgress(
          taskId,
          TaskGoalType.skillXP,
          skillId,
          500,
        ),
      );
      // Still not enough
      expect(() => state.claimTaskRewardWithChanges(taskId), throwsStateError);

      // Add more progress to meet the goal
      state = state.copyWith(
        township: state.township.updateTaskProgress(
          taskId,
          TaskGoalType.skillXP,
          skillId,
          500,
        ),
      );
      // Now it should work
      (state, _) = state.claimTaskRewardWithChanges(taskId);
      expect(state.gp, 500);
    });

    test('validates monster kill goal with progress tracking', () {
      const taskId = MelvorId('melvorD:Test_Task');
      const monsterId = MelvorId('melvorD:Golbin');

      final registries = Registries.test(
        township: const TownshipRegistry(
          tasks: [
            TownshipTask(
              id: taskId,
              category: TaskCategory.normal,
              goals: [
                TaskGoal(
                  type: TaskGoalType.monsters,
                  id: monsterId,
                  quantity: 25,
                ),
              ],
              rewards: [
                TaskReward(
                  type: TaskRewardType.currency,
                  id: MelvorId('melvorD:GP'),
                  quantity: 1000,
                ),
              ],
            ),
          ],
        ),
      );

      var state = GlobalState.test(registries);

      // Should fail with no kills
      expect(() => state.claimTaskRewardWithChanges(taskId), throwsStateError);

      // Add 25 kills
      state = state.copyWith(
        township: state.township.updateTaskProgress(
          taskId,
          TaskGoalType.monsters,
          monsterId,
          25,
        ),
      );

      // Now it should work
      (state, _) = state.claimTaskRewardWithChanges(taskId);
      expect(state.gp, 1000);
    });
  });

  group('TaskGoal', () {
    group('displayName', () {
      test('returns skill name + XP for skillXP goals', () {
        const goal = TaskGoal(
          type: TaskGoalType.skillXP,
          id: MelvorId('melvorD:Woodcutting'),
          quantity: 1000,
        );

        final items = ItemRegistry(const []);
        final combat = CombatRegistry(
          monsters: const [],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.displayName(items, combat), 'Woodcutting XP');
      });

      test('returns item name for items goals', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
          media: 'assets/media/bank/logs_oak.png',
        );

        const goal = TaskGoal(
          type: TaskGoalType.items,
          id: itemId,
          quantity: 100,
        );

        final items = ItemRegistry(const [item]);
        final combat = CombatRegistry(
          monsters: const [],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.displayName(items, combat), 'Oak Logs');
      });

      test('returns monster name for monsters goals', () {
        const monsterId = MelvorId('melvorD:Golbin');
        final monster = CombatAction(
          id: ActionId(Skill.combat.id, monsterId),
          name: 'Golbin',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 1,
            strength: 1,
            defense: 1,
            ranged: 1,
            magic: 1,
          ),
          attackType: AttackType.melee,
          attackSpeed: 2.4,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
          media: 'assets/media/monsters/golbin.png',
        );

        const goal = TaskGoal(
          type: TaskGoalType.monsters,
          id: monsterId,
          quantity: 25,
        );

        final items = ItemRegistry(const []);
        final combat = CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.displayName(items, combat), 'Golbin');
      });
    });

    group('asset', () {
      test('returns skill asset path for skillXP goals', () {
        const goal = TaskGoal(
          type: TaskGoalType.skillXP,
          id: MelvorId('melvorD:Woodcutting'),
          quantity: 1000,
        );

        final items = ItemRegistry(const []);
        final combat = CombatRegistry(
          monsters: const [],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.asset(items, combat), Skill.woodcutting.assetPath);
      });

      test('returns item media for items goals', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
          media: 'assets/media/bank/logs_oak.png',
        );

        const goal = TaskGoal(
          type: TaskGoalType.items,
          id: itemId,
          quantity: 100,
        );

        final items = ItemRegistry(const [item]);
        final combat = CombatRegistry(
          monsters: const [],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.asset(items, combat), 'assets/media/bank/logs_oak.png');
      });

      test('returns monster media for monsters goals', () {
        const monsterId = MelvorId('melvorD:Golbin');
        final monster = CombatAction(
          id: ActionId(Skill.combat.id, monsterId),
          name: 'Golbin',
          levels: const MonsterLevels(
            hitpoints: 10,
            attack: 1,
            strength: 1,
            defense: 1,
            ranged: 1,
            magic: 1,
          ),
          attackType: AttackType.melee,
          attackSpeed: 2.4,
          lootChance: 0,
          minGpDrop: 0,
          maxGpDrop: 0,
          media: 'assets/media/monsters/golbin.png',
        );

        const goal = TaskGoal(
          type: TaskGoalType.monsters,
          id: monsterId,
          quantity: 25,
        );

        final items = ItemRegistry(const []);
        final combat = CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        );

        expect(goal.asset(items, combat), 'assets/media/monsters/golbin.png');
      });
    });
  });

  group('TaskReward', () {
    group('displayName', () {
      test('returns item name for item rewards', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
          media: 'assets/media/bank/logs_oak.png',
        );

        const reward = TaskReward(
          type: TaskRewardType.item,
          id: itemId,
          quantity: 50,
        );

        final items = ItemRegistry(const [item]);
        const township = TownshipRegistry.empty();

        expect(reward.displayName(items, township), 'Oak Logs');
      });

      test('returns currency abbreviation for currency rewards', () {
        const reward = TaskReward(
          type: TaskRewardType.currency,
          id: MelvorId('melvorD:GP'),
          quantity: 1000,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry.empty();

        expect(reward.displayName(items, township), 'GP');
      });

      test('returns slayer coins abbreviation for SC rewards', () {
        const reward = TaskReward(
          type: TaskRewardType.currency,
          id: MelvorId('melvorD:SlayerCoins'),
          quantity: 500,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry.empty();

        expect(reward.displayName(items, township), 'SC');
      });

      test('returns skill name + XP for skillXP rewards', () {
        const reward = TaskReward(
          type: TaskRewardType.skillXP,
          id: MelvorId('melvorD:Mining'),
          quantity: 5000,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry.empty();

        expect(reward.displayName(items, township), 'Mining XP');
      });

      test('returns resource name for townshipResource rewards', () {
        const resourceId = MelvorId('melvorF:Wood');
        const resource = TownshipResource(
          id: resourceId,
          name: 'Wood',
          type: 'Raw',
          media: 'assets/media/township/wood.png',
        );

        const reward = TaskReward(
          type: TaskRewardType.townshipResource,
          id: resourceId,
          quantity: 200,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry(resources: [resource]);

        expect(reward.displayName(items, township), 'Wood');
      });
    });

    group('asset', () {
      test('returns item media for item rewards', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
          media: 'assets/media/bank/logs_oak.png',
        );

        const reward = TaskReward(
          type: TaskRewardType.item,
          id: itemId,
          quantity: 50,
        );

        final items = ItemRegistry(const [item]);
        const township = TownshipRegistry.empty();

        expect(reward.asset(items, township), 'assets/media/bank/logs_oak.png');
      });

      test('returns currency asset path for currency rewards', () {
        const reward = TaskReward(
          type: TaskRewardType.currency,
          id: MelvorId('melvorD:GP'),
          quantity: 1000,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry.empty();

        expect(reward.asset(items, township), Currency.gp.assetPath);
      });

      test('returns skill asset path for skillXP rewards', () {
        const reward = TaskReward(
          type: TaskRewardType.skillXP,
          id: MelvorId('melvorD:Fishing'),
          quantity: 3000,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry.empty();

        expect(reward.asset(items, township), Skill.fishing.assetPath);
      });

      test('returns resource media for townshipResource rewards', () {
        const resourceId = MelvorId('melvorF:Wood');
        const resource = TownshipResource(
          id: resourceId,
          name: 'Wood',
          type: 'Raw',
          media: 'assets/media/township/wood.png',
        );

        const reward = TaskReward(
          type: TaskRewardType.townshipResource,
          id: resourceId,
          quantity: 200,
        );

        final items = ItemRegistry(const []);
        const township = TownshipRegistry(resources: [resource]);

        expect(reward.asset(items, township), 'assets/media/township/wood.png');
      });
    });
  });

  group('TaskCategory', () {
    test('displayName returns correct values for all categories', () {
      expect(TaskCategory.easy.displayName, 'Easy');
      expect(TaskCategory.normal.displayName, 'Normal');
      expect(TaskCategory.hard.displayName, 'Hard');
      expect(TaskCategory.veryHard.displayName, 'Very Hard');
      expect(TaskCategory.elite.displayName, 'Elite');
    });
  });

  group('TownshipTask', () {
    group('rewardsToChanges', () {
      test('converts item rewards to Changes', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
        );

        const task = TownshipTask(
          id: MelvorId('melvorD:Test_Task'),
          category: TaskCategory.easy,
          rewards: [
            TaskReward(type: TaskRewardType.item, id: itemId, quantity: 100),
          ],
        );

        final items = ItemRegistry(const [item]);
        final changes = task.rewardsToChanges(items);

        expect(changes.inventoryChanges.counts.length, 1);
        expect(changes.inventoryChanges.counts[itemId], 100);
      });

      test('converts currency rewards to Changes', () {
        const task = TownshipTask(
          id: MelvorId('melvorD:Test_Task'),
          category: TaskCategory.normal,
          rewards: [
            TaskReward(
              type: TaskRewardType.currency,
              id: MelvorId('melvorD:GP'),
              quantity: 5000,
            ),
          ],
        );

        final items = ItemRegistry(const []);
        final changes = task.rewardsToChanges(items);

        expect(changes.currenciesGained.length, 1);
        expect(changes.currenciesGained[Currency.gp], 5000);
      });

      test('converts skillXP rewards to Changes', () {
        const task = TownshipTask(
          id: MelvorId('melvorD:Test_Task'),
          category: TaskCategory.hard,
          rewards: [
            TaskReward(
              type: TaskRewardType.skillXP,
              id: MelvorId('melvorD:Mining'),
              quantity: 10000,
            ),
          ],
        );

        final items = ItemRegistry(const []);
        final changes = task.rewardsToChanges(items);

        expect(changes.skillXpChanges.counts.length, 1);
        expect(changes.skillXpChanges.counts[Skill.mining], 10000);
      });

      test('excludes townshipResource rewards from Changes', () {
        const task = TownshipTask(
          id: MelvorId('melvorD:Test_Task'),
          category: TaskCategory.elite,
          rewards: [
            TaskReward(
              type: TaskRewardType.townshipResource,
              id: MelvorId('melvorF:Wood'),
              quantity: 500,
            ),
          ],
        );

        final items = ItemRegistry(const []);
        final changes = task.rewardsToChanges(items);

        expect(changes.inventoryChanges.isEmpty, isTrue);
        expect(changes.currenciesGained.isEmpty, isTrue);
        expect(changes.skillXpChanges.isEmpty, isTrue);
      });

      test('converts multiple mixed rewards to Changes', () {
        const itemId = MelvorId('melvorD:Oak_Logs');
        const item = Item(
          id: itemId,
          name: 'Oak Logs',
          itemType: 'Logs',
          sellsFor: 5,
        );

        const task = TownshipTask(
          id: MelvorId('melvorD:Test_Task'),
          category: TaskCategory.veryHard,
          rewards: [
            TaskReward(type: TaskRewardType.item, id: itemId, quantity: 50),
            TaskReward(
              type: TaskRewardType.currency,
              id: MelvorId('melvorD:GP'),
              quantity: 2000,
            ),
            TaskReward(
              type: TaskRewardType.skillXP,
              id: MelvorId('melvorD:Woodcutting'),
              quantity: 5000,
            ),
            TaskReward(
              type: TaskRewardType.townshipResource,
              id: MelvorId('melvorF:Stone'),
              quantity: 100,
            ),
          ],
        );

        final items = ItemRegistry(const [item]);
        final changes = task.rewardsToChanges(items);

        expect(changes.inventoryChanges.counts.length, 1);
        expect(changes.inventoryChanges.counts[itemId], 50);
        expect(changes.currenciesGained.length, 1);
        expect(changes.currenciesGained[Currency.gp], 2000);
        expect(changes.skillXpChanges.counts.length, 1);
        expect(changes.skillXpChanges.counts[Skill.woodcutting], 5000);
      });
    });
  });

  group('TownshipRegistry', () {
    group('buildingDisplayName', () {
      test('returns building name for non-statue buildings', () {
        const building = TownshipBuilding(
          id: MelvorId('melvorD:House'),
          name: 'House',
          tier: 1,
          biomeData: {},
          validBiomes: {},
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:Bane'),
          name: 'Bane',
          statueName: 'Statue of Bane',
        );

        const registry = TownshipRegistry(buildings: [building]);

        expect(registry.buildingDisplayName(building, deity), 'House');
      });

      test('returns statue name from deity for statue building', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:Aeris'),
          name: 'Aeris',
          statueName: 'Statue of Aeris',
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(registry.buildingDisplayName(statue, deity), 'Statue of Aeris');
      });

      test('returns building name for statue when deity is null', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(registry.buildingDisplayName(statue, null), 'Statues');
      });

      test('returns building name when deity has empty statueName', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:NoStatue'),
          name: 'No Statue Deity',
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(registry.buildingDisplayName(statue, deity), 'Statues');
      });
    });

    group('buildingDisplayMedia', () {
      test('returns building media for non-statue buildings', () {
        const building = TownshipBuilding(
          id: MelvorId('melvorD:House'),
          name: 'House',
          tier: 1,
          biomeData: {},
          validBiomes: {},
          media: 'assets/media/township/house.png',
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:Bane'),
          name: 'Bane',
          statueMedia: 'assets/media/township/bane_statue.png',
        );

        const registry = TownshipRegistry(buildings: [building]);

        expect(
          registry.buildingDisplayMedia(building, deity),
          'assets/media/township/house.png',
        );
      });

      test('returns statue media from deity for statue building', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
          media: 'assets/media/township/statues.png',
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:Aeris'),
          name: 'Aeris',
          statueMedia: 'assets/media/township/aeris_statue.png',
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(
          registry.buildingDisplayMedia(statue, deity),
          'assets/media/township/aeris_statue.png',
        );
      });

      test('returns building media for statue when deity is null', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
          media: 'assets/media/township/statues.png',
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(
          registry.buildingDisplayMedia(statue, null),
          'assets/media/township/statues.png',
        );
      });

      test('returns building media when deity has null statueMedia', () {
        const statue = TownshipBuilding(
          id: TownshipRegistry.statuesBuildingId,
          name: 'Statues',
          tier: 1,
          biomeData: {},
          validBiomes: {},
          media: 'assets/media/township/statues.png',
        );

        const deity = TownshipDeity(
          id: MelvorId('melvorD:NoMedia'),
          name: 'No Media Deity',
        );

        const registry = TownshipRegistry(buildings: [statue]);

        expect(
          registry.buildingDisplayMedia(statue, deity),
          'assets/media/township/statues.png',
        );
      });
    });
  });
}
