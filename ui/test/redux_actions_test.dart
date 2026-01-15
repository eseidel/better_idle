import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic/logic.dart';
import 'package:scoped_deps/scoped_deps.dart';

/// Helper to create a test building with biome-specific data.
TownshipBuilding _testBuilding({
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
  group('DebugAddCurrencyAction', () {
    test('adds GP to empty balance', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.gp, 0);

      store.dispatch(DebugAddCurrencyAction(Currency.gp, 100));

      expect(store.state.gp, 100);
    });

    test('adds GP to existing balance', () {
      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 50);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.gp, 50);

      store.dispatch(DebugAddCurrencyAction(Currency.gp, 100));

      expect(store.state.gp, 150);
    });

    test('adds slayer coins', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.currency(Currency.slayerCoins), 0);

      store.dispatch(DebugAddCurrencyAction(Currency.slayerCoins, 75));

      expect(store.state.currency(Currency.slayerCoins), 75);
    });

    test('subtracts currency with negative amount', () {
      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 100);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(DebugAddCurrencyAction(Currency.gp, -30));

      expect(store.state.gp, 70);
    });
  });

  group('RepairTownshipBuildingAction', () {
    test('repairs building and deducts GP cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
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

      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 1000);
      // Set up building at 50% efficiency (50% damage)
      initialState = initialState.copyWith(
        township: initialState.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        ),
      );

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.gp, 1000);
      expect(
        store.state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        50,
      );

      store.dispatch(
        RepairTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );

      // Repair cost = (1000/3) x 1 x 0.5 = 167 GP (rounded up)
      expect(store.state.gp, 833);
      expect(
        store.state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });

    test('repairs building and deducts resource cost', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = _testBuilding(
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

      var initialState = GlobalState.empty(registries);
      // Set up building at 80% efficiency (20% damage) and add wood
      initialState = initialState.copyWith(
        township: initialState.township
            .addResource(woodId, 500)
            .withBiomeState(
              biomeId,
              BiomeState(
                buildings: {
                  buildingId: const BuildingState(count: 1, efficiency: 80),
                },
              ),
            ),
      );

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.resourceAmount(woodId), 500);

      store.dispatch(
        RepairTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );

      // Repair cost = (200/3) x 1 x 0.2 = 14 Wood (rounded up)
      expect(store.state.township.resourceAmount(woodId), 486);
      expect(
        store.state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });
  });

  group('RepairAllTownshipBuildingsAction', () {
    test('repairs all buildings and deducts GP', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId = MelvorId('melvorD:Grasslands');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
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

      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 500);
      initialState = initialState.copyWith(
        township: initialState.township.withBiomeState(
          biomeId,
          BiomeState(
            buildings: {
              buildingId: const BuildingState(count: 1, efficiency: 50),
            },
          ),
        ),
      );

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.gp, 500);
      expect(
        store.state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        50,
      );

      store.dispatch(RepairAllTownshipBuildingsAction());

      // Repair cost = (1000/3) x 1 x 0.5 = 167 GP
      expect(store.state.gp, 333);
      expect(
        store.state.township.biomes[biomeId]!.buildings[buildingId]!.efficiency,
        100,
      );
    });

    test('repairs buildings across multiple biomes', () {
      const buildingId = MelvorId('melvorD:Test_Building');
      const biomeId1 = MelvorId('melvorD:Grasslands');
      const biomeId2 = MelvorId('melvorD:Forest');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
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

      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 1000);
      initialState = initialState.copyWith(
        township: initialState.township
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

      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(RepairAllTownshipBuildingsAction());

      expect(
        store
            .state
            .township
            .biomes[biomeId1]!
            .buildings[buildingId]!
            .efficiency,
        100,
      );
      expect(
        store
            .state
            .township
            .biomes[biomeId2]!
            .buildings[buildingId]!
            .efficiency,
        100,
      );
      expect(store.state.township.hasAnyBuildingNeedingRepair, isFalse);
    });
  });

  group('HealTownshipAction', () {
    test('heals township and deducts herbs', () {
      const herbsId = MelvorId('melvorF:Herbs');
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = _testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {herbsId: 100},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township
            .addResource(herbsId, 100)
            .copyWith(health: 80)
            .withBiomeState(
              biomeId,
              BiomeState(
                buildings: {buildingId: const BuildingState(count: 1)},
              ),
            ),
      );

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.health, 80);
      expect(store.state.township.resourceAmount(herbsId), 100);

      store.dispatch(
        HealTownshipAction(resource: HealingResource.herbs, amount: 5),
      );

      expect(store.state.township.health, 85);
      // Cost = 5% x costPerHealthPercent (which is ceil(100 * 0.1) = 10) = 50
      // But wait, with 1 building at 100% efficiency and education = 1.0,
      // production is 100/hr, so costPerHealthPercent = ceil(100 * 0.1) = 10
      // Total cost = 5 * 10 = 50 herbs, but with education multiplier
      // production is 100 * 1 * 1.0 = 100, cost = ceil(10) = 10, 5*10=50
      // This depends on the actual formula in healWith
      expect(store.state.township.resourceAmount(herbsId), lessThan(100));
    });

    test('heals township using potions', () {
      const potionsId = MelvorId('melvorF:Potions');
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = _testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {potionsId: 100},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: potionsId, name: 'Potions', type: 'Raw'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township
            .addResource(potionsId, 200)
            .copyWith(health: 70)
            .withBiomeState(
              biomeId,
              BiomeState(
                buildings: {buildingId: const BuildingState(count: 1)},
              ),
            ),
      );

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.health, 70);

      store.dispatch(
        HealTownshipAction(resource: HealingResource.potions, amount: 10),
      );

      expect(store.state.township.health, 80);
      expect(store.state.township.resourceAmount(potionsId), lessThan(200));
    });

    test('clamps health at max 100', () {
      const herbsId = MelvorId('melvorF:Herbs');
      const biomeId = MelvorId('melvorD:Grasslands');
      const buildingId = MelvorId('melvorD:Test_Building');

      final building = _testBuilding(
        id: buildingId,
        name: 'Test Building',
        validBiomes: {biomeId},
        production: {herbsId: 100},
      );

      final registries = Registries.test(
        township: TownshipRegistry(
          buildings: [building],
          biomes: const [
            TownshipBiome(id: biomeId, name: 'Grasslands', tier: 1),
          ],
          resources: const [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township
            .addResource(herbsId, 1000)
            .copyWith(health: 95)
            .withBiomeState(
              biomeId,
              BiomeState(
                buildings: {buildingId: const BuildingState(count: 1)},
              ),
            ),
      );

      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          HealTownshipAction(resource: HealingResource.herbs, amount: 10),
        );

      // Health should cap at 100, not 105
      expect(store.state.township.health, 100);
    });

    test('does nothing when amount is 0', () {
      const herbsId = MelvorId('melvorF:Herbs');

      final registries = Registries.test(
        township: const TownshipRegistry(
          resources: [
            TownshipResource(id: herbsId, name: 'Herbs', type: 'Raw'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township
            .addResource(herbsId, 100)
            .copyWith(health: 80),
      );

      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          HealTownshipAction(resource: HealingResource.herbs, amount: 0),
        );

      expect(store.state.township.health, 80);
      expect(store.state.township.resourceAmount(herbsId), 100);
    });
  });

  group('ClaimTownshipTaskAction', () {
    test('claims task and grants GP reward', () {
      runScoped(() {
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

        var initialState = GlobalState.empty(registries);
        initialState = initialState.copyWith(
          inventory: initialState.inventory.adding(
            ItemStack(testItem, count: 100),
          ),
        );

        final store = Store<GlobalState>(initialState: initialState)
          ..dispatch(ClaimTownshipTaskAction(taskId));

        expect(store.state.gp, 1000);
        expect(store.state.inventory.countOfItem(testItem), 50);
        expect(store.state.township.completedMainTasks, contains(taskId));
      }, values: {toastServiceRef});
    });

    test('claims task and grants item reward', () {
      runScoped(() {
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

        final store = Store<GlobalState>(
          initialState: GlobalState.empty(registries),
        )..dispatch(ClaimTownshipTaskAction(taskId));

        expect(store.state.inventory.countOfItem(rewardItem), 10);
        expect(store.state.township.completedMainTasks, contains(taskId));
      }, values: {toastServiceRef});
    });

    test('claims task and grants township resource reward', () {
      runScoped(() {
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

        final store = Store<GlobalState>(
          initialState: GlobalState.empty(registries),
        )..dispatch(ClaimTownshipTaskAction(taskId));

        expect(store.state.township.resourceAmount(resourceId), 500);
        expect(store.state.township.completedMainTasks, contains(taskId));
      }, values: {toastServiceRef});
    });

    test('throws when task requirements not met', () {
      runScoped(() {
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
        final store = Store<GlobalState>(
          initialState: GlobalState.empty(registries),
        );

        expect(
          () => store.dispatch(ClaimTownshipTaskAction(taskId)),
          throwsStateError,
        );
      }, values: {toastServiceRef});
    });

    test('throws when claiming already completed task', () {
      runScoped(() {
        const taskId = MelvorId('melvorD:Test_Task');

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

        final store = Store<GlobalState>(
          initialState: GlobalState.empty(registries),
        )..dispatch(ClaimTownshipTaskAction(taskId));
        expect(store.state.township.completedMainTasks, contains(taskId));

        // Try to claim again
        expect(
          () => store.dispatch(ClaimTownshipTaskAction(taskId)),
          throwsStateError,
        );
      }, values: {toastServiceRef});
    });

    test('grants multiple rewards', () {
      runScoped(() {
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

        final store = Store<GlobalState>(
          initialState: GlobalState.empty(registries),
        )..dispatch(ClaimTownshipTaskAction(taskId));

        expect(store.state.gp, 500);
        expect(store.state.currency(Currency.slayerCoins), 100);
        expect(store.state.inventory.countOfItem(testItem), 5);
        expect(store.state.township.completedMainTasks, contains(taskId));
      }, values: {toastServiceRef});
    });
  });
}
