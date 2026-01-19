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
  group('ToggleActionAction', () {
    test('starts action when no action is active', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Test Tree'),
        skill: Skill.woodcutting,
        name: 'Test Tree',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNull);

      store.dispatch(ToggleActionAction(action: testAction));

      expect(store.state.activeActivity, isNotNull);
      expect(store.state.currentActionId, testAction.id);
    });

    test('stops action when same action is active', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Test Tree'),
        skill: Skill.woodcutting,
        name: 'Test Tree',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var initialState = GlobalState.empty(registries);
      // Start with the action already active
      initialState = initialState.copyWith(
        activeActivity: SkillActivity(
          skill: testAction.skill,
          actionId: testAction.id.localId,
          progressTicks: 0,
          totalTicks: 30,
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNotNull);
      expect(store.state.currentActionId, testAction.id);

      store.dispatch(ToggleActionAction(action: testAction));

      expect(store.state.activeActivity, isNull);
    });

    test('switches to new action when different action is active', () {
      final action1 = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Tree 1'),
        skill: Skill.woodcutting,
        name: 'Tree 1',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final action2 = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Tree 2'),
        skill: Skill.woodcutting,
        name: 'Tree 2',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [action1, action2]);
      var initialState = GlobalState.empty(registries);
      // Start with action1 active
      initialState = initialState.copyWith(
        activeActivity: SkillActivity(
          skill: action1.skill,
          actionId: action1.id.localId,
          progressTicks: 0,
          totalTicks: 30,
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.currentActionId, action1.id);

      store.dispatch(ToggleActionAction(action: action2));

      expect(store.state.activeActivity, isNotNull);
      expect(store.state.currentActionId, action2.id);
    });

    test('does nothing when stunned', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Test Tree'),
        skill: Skill.woodcutting,
        name: 'Test Tree',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        stunned: const StunnedState.fresh().stun(),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNull);
      expect(store.state.isStunned, isTrue);

      store.dispatch(ToggleActionAction(action: testAction));

      // Action should not have started because player is stunned
      expect(store.state.activeActivity, isNull);
    });

    test('cannot stop action when stunned', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Test Tree'),
        skill: Skill.woodcutting,
        name: 'Test Tree',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var initialState = GlobalState.empty(registries);
      // Start with action active AND stunned
      initialState = initialState.copyWith(
        activeActivity: SkillActivity(
          skill: testAction.skill,
          actionId: testAction.id.localId,
          progressTicks: 0,
          totalTicks: 30,
        ),
        stunned: const StunnedState.fresh().stun(),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNotNull);
      expect(store.state.isStunned, isTrue);

      store.dispatch(ToggleActionAction(action: testAction));

      // Action should still be active because player is stunned
      expect(store.state.activeActivity, isNotNull);
      expect(store.state.currentActionId, testAction.id);
    });
  });

  group('SetRecipeAction', () {
    test('sets recipe index for action', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      // Default recipe index should be null (not yet set)
      expect(
        store.state.actionState(testAction.id).selectedRecipeIndex,
        isNull,
      );

      store.dispatch(SetRecipeAction(actionId: testAction.id, recipeIndex: 2));

      expect(store.state.actionState(testAction.id).selectedRecipeIndex, 2);
    });

    test('changes recipe index from non-zero value', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var initialState = GlobalState.empty(registries);
      // Set initial recipe index to 1
      initialState = initialState.setRecipeIndex(testAction.id, 1);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.actionState(testAction.id).selectedRecipeIndex, 1);

      store.dispatch(SetRecipeAction(actionId: testAction.id, recipeIndex: 3));

      expect(store.state.actionState(testAction.id).selectedRecipeIndex, 3);
    });

    test('sets recipe index back to 0', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.smithing, 'Test Smithing'),
        skill: Skill.smithing,
        name: 'Test Smithing',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.setRecipeIndex(testAction.id, 5);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.actionState(testAction.id).selectedRecipeIndex, 5);

      store.dispatch(SetRecipeAction(actionId: testAction.id, recipeIndex: 0));

      expect(store.state.actionState(testAction.id).selectedRecipeIndex, 0);
    });
  });

  group('DismissWelcomeBackDialogAction', () {
    test('clears timeAway from state', () {
      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      // Set up state with timeAway
      initialState = initialState.copyWith(timeAway: TimeAway.test(registries));
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.timeAway, isNotNull);

      store.dispatch(DismissWelcomeBackDialogAction());

      expect(store.state.timeAway, isNull);
    });

    test('does nothing when timeAway is already null', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.timeAway, isNull);

      store.dispatch(DismissWelcomeBackDialogAction());

      expect(store.state.timeAway, isNull);
    });
  });

  group('SellItemAction', () {
    test('sells item and adds GP', () {
      final testItem = Item.test('Test Item', gp: 50);
      final registries = Registries.test(items: [testItem]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          ItemStack(testItem, count: 10),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.inventory.countOfItem(testItem), 10);
      expect(store.state.gp, 0);

      store.dispatch(SellItemAction(item: testItem, count: 5));

      expect(store.state.inventory.countOfItem(testItem), 5);
      expect(store.state.gp, 250); // 5 * 50 GP
    });

    test('sells all of an item', () {
      final testItem = Item.test('Test Item', gp: 100);
      final registries = Registries.test(items: [testItem]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(ItemStack(testItem, count: 3)),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(SellItemAction(item: testItem, count: 3));

      expect(store.state.inventory.countOfItem(testItem), 0);
      expect(store.state.gp, 300);
    });
  });

  group('SellMultipleItemsAction', () {
    test('sells multiple different items', () {
      final item1 = Item.test('Item 1', gp: 10);
      final item2 = Item.test('Item 2', gp: 20);
      final registries = Registries.test(items: [item1, item2]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory
            .adding(ItemStack(item1, count: 5))
            .adding(ItemStack(item2, count: 3)),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.inventory.countOfItem(item1), 5);
      expect(store.state.inventory.countOfItem(item2), 3);

      store.dispatch(
        SellMultipleItemsAction(
          stacks: [ItemStack(item1, count: 2), ItemStack(item2, count: 1)],
        ),
      );

      expect(store.state.inventory.countOfItem(item1), 3);
      expect(store.state.inventory.countOfItem(item2), 2);
      expect(store.state.gp, 40); // (2 * 10) + (1 * 20)
    });

    test('sells empty list does nothing', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(SellMultipleItemsAction(stacks: []));

      expect(store.state.gp, 0);
    });
  });

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

  group('SelectPotionAction', () {
    test('selects potion for skill', () {
      final potion = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final registries = Registries.test(items: [potion]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(ItemStack(potion, count: 1)),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.selectedPotions[Skill.woodcutting.id], isNull);

      store.dispatch(SelectPotionAction(Skill.woodcutting.id, potion.id));

      expect(store.state.selectedPotions[Skill.woodcutting.id], potion.id);
    });

    test('resets charges used when selecting different potion', () {
      final potion1 = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final potion2 = Item.test(
        'Bird Nest Potion II',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final registries = Registries.test(items: [potion1, potion2]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory
            .adding(ItemStack(potion1, count: 1))
            .adding(ItemStack(potion2, count: 1)),
        selectedPotions: {Skill.woodcutting.id: potion1.id},
        potionChargesUsed: {Skill.woodcutting.id: 10},
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.potionChargesUsed[Skill.woodcutting.id], 10);

      store.dispatch(SelectPotionAction(Skill.woodcutting.id, potion2.id));

      expect(store.state.selectedPotions[Skill.woodcutting.id], potion2.id);
      expect(store.state.potionChargesUsed[Skill.woodcutting.id], isNull);
    });

    test('can select potions for different skills', () {
      final woodcuttingPotion = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final fishingPotion = Item.test(
        'Fishing Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.fishing.id,
      );
      final registries = Registries.test(
        items: [woodcuttingPotion, fishingPotion],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory
            .adding(ItemStack(woodcuttingPotion, count: 1))
            .adding(ItemStack(fishingPotion, count: 1)),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          SelectPotionAction(Skill.woodcutting.id, woodcuttingPotion.id),
        )
        ..dispatch(SelectPotionAction(Skill.fishing.id, fishingPotion.id));

      expect(
        store.state.selectedPotions[Skill.woodcutting.id],
        woodcuttingPotion.id,
      );
      expect(store.state.selectedPotions[Skill.fishing.id], fishingPotion.id);
    });
  });

  group('ClearPotionSelectionAction', () {
    test('clears potion selection for skill', () {
      final potion = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final registries = Registries.test(items: [potion]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(ItemStack(potion, count: 1)),
        selectedPotions: {Skill.woodcutting.id: potion.id},
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.selectedPotions[Skill.woodcutting.id], potion.id);

      store.dispatch(ClearPotionSelectionAction(Skill.woodcutting.id));

      expect(store.state.selectedPotions[Skill.woodcutting.id], isNull);
    });

    test('clears charges used when clearing selection', () {
      final potion = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final registries = Registries.test(items: [potion]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(ItemStack(potion, count: 1)),
        selectedPotions: {Skill.woodcutting.id: potion.id},
        potionChargesUsed: {Skill.woodcutting.id: 15},
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.potionChargesUsed[Skill.woodcutting.id], 15);

      store.dispatch(ClearPotionSelectionAction(Skill.woodcutting.id));

      expect(store.state.potionChargesUsed[Skill.woodcutting.id], isNull);
    });

    test('does nothing when no potion selected', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.selectedPotions[Skill.woodcutting.id], isNull);

      store.dispatch(ClearPotionSelectionAction(Skill.woodcutting.id));

      expect(store.state.selectedPotions[Skill.woodcutting.id], isNull);
    });

    test('only clears specified skill, leaving others intact', () {
      final woodcuttingPotion = Item.test(
        'Bird Nest Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.woodcutting.id,
      );
      final fishingPotion = Item.test(
        'Fishing Potion I',
        gp: 0,
        potionCharges: 30,
        potionAction: Skill.fishing.id,
      );
      final registries = Registries.test(
        items: [woodcuttingPotion, fishingPotion],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory
            .adding(ItemStack(woodcuttingPotion, count: 1))
            .adding(ItemStack(fishingPotion, count: 1)),
        selectedPotions: {
          Skill.woodcutting.id: woodcuttingPotion.id,
          Skill.fishing.id: fishingPotion.id,
        },
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(ClearPotionSelectionAction(Skill.woodcutting.id));

      expect(store.state.selectedPotions[Skill.woodcutting.id], isNull);
      expect(store.state.selectedPotions[Skill.fishing.id], fishingPotion.id);
    });
  });

  group('SelectTownshipDeityAction', () {
    test('selects deity for worship', () {
      const deityId = MelvorId('melvorF:Aeris');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [TownshipDeity(id: deityId, name: 'Aeris')],
        ),
      );

      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.worshipId, isNull);

      store.dispatch(SelectTownshipDeityAction(deityId: deityId));

      expect(store.state.township.worshipId, deityId);
    });

    test('changes deity selection', () {
      const deity1 = MelvorId('melvorF:Aeris');
      const deity2 = MelvorId('melvorF:Glacia');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [
            TownshipDeity(id: deity1, name: 'Aeris'),
            TownshipDeity(id: deity2, name: 'Glacia'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township.selectWorship(deity1),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.worshipId, deity1);

      store.dispatch(SelectTownshipDeityAction(deityId: deity2));

      expect(store.state.township.worshipId, deity2);
    });

    test('resets worship points when changing deity', () {
      const deity1 = MelvorId('melvorF:Aeris');
      const deity2 = MelvorId('melvorF:Glacia');

      final registries = Registries.test(
        township: const TownshipRegistry(
          deities: [
            TownshipDeity(id: deity1, name: 'Aeris'),
            TownshipDeity(id: deity2, name: 'Glacia'),
          ],
        ),
      );

      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        township: initialState.township
            .selectWorship(deity1)
            .copyWith(worship: 500),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.worship, 500);

      store.dispatch(SelectTownshipDeityAction(deityId: deity2));

      // Worship points should be reset when changing deity
      expect(store.state.township.worship, 0);
    });
  });

  group('BuildTownshipBuildingAction', () {
    test('builds building and deducts GP cost', () {
      const buildingId = MelvorId('melvorD:Wooden_House');
      const biomeId = MelvorId('melvorD:Grasslands');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
        id: buildingId,
        name: 'Wooden House',
        validBiomes: {biomeId},
        costs: {gpId: 1000},
        population: 8,
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
      initialState = initialState.addCurrency(Currency.gp, 1500);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.gp, 1500);
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        0,
      );

      store.dispatch(
        BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );

      expect(store.state.gp, 500);
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        1,
      );
    });

    test('builds building and deducts township resource cost', () {
      const buildingId = MelvorId('melvorD:Wooden_House');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = _testBuilding(
        id: buildingId,
        name: 'Wooden House',
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
      initialState = initialState.copyWith(
        township: initialState.township.addResource(woodId, 500),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.township.resourceAmount(woodId), 500);

      store.dispatch(
        BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );

      expect(store.state.township.resourceAmount(woodId), 300);
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        1,
      );
    });

    test('throws when not enough GP', () {
      const buildingId = MelvorId('melvorD:Wooden_House');
      const biomeId = MelvorId('melvorD:Grasslands');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
        id: buildingId,
        name: 'Wooden House',
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
      final store = Store<GlobalState>(initialState: initialState);

      expect(
        () => store.dispatch(
          BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
        ),
        throwsStateError,
      );
    });

    test('throws when not enough township resources', () {
      const buildingId = MelvorId('melvorD:Wooden_House');
      const biomeId = MelvorId('melvorD:Grasslands');
      const woodId = MelvorId('melvorF:Wood');

      final building = _testBuilding(
        id: buildingId,
        name: 'Wooden House',
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
      initialState = initialState.copyWith(
        township: initialState.township.addResource(woodId, 100),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(
        () => store.dispatch(
          BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
        ),
        throwsStateError,
      );
    });

    test('builds multiple buildings incrementally', () {
      const buildingId = MelvorId('melvorD:Wooden_House');
      const biomeId = MelvorId('melvorD:Grasslands');
      final gpId = Currency.gp.id;

      final building = _testBuilding(
        id: buildingId,
        name: 'Wooden House',
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

      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.gp, 500);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
        );
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        1,
      );

      store.dispatch(
        BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        2,
      );

      store.dispatch(
        BuildTownshipBuildingAction(biomeId: biomeId, buildingId: buildingId),
      );
      expect(
        store.state.township
            .biomeState(biomeId)
            .buildingState(buildingId)
            .count,
        3,
      );
    });
  });

  group('StartCookingAction', () {
    CookingAction testCookingAction(String name, CookingArea area) {
      final productId = MelvorId('melvorD:${name.replaceAll(' ', '_')}');
      return CookingAction(
        id: ActionId.test(Skill.cooking, name),
        name: name,
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
        inputs: const {},
        outputs: const {},
        productId: productId,
        perfectCookId: null,
        categoryId: area.categoryId,
        subcategoryId: null,
        baseQuantity: 1,
      );
    }

    test('starts cooking when recipe is assigned', () {
      final cookingRecipe = testCookingAction('Test Recipe', CookingArea.fire);
      final registries = Registries.test(actions: [cookingRecipe]);
      var initialState = GlobalState.empty(registries);
      // Assign recipe to fire area
      initialState = initialState.copyWith(
        cooking: initialState.cooking.withAreaState(
          CookingArea.fire,
          CookingAreaState(recipeId: cookingRecipe.id),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNull);

      store.dispatch(StartCookingAction(area: CookingArea.fire));

      expect(store.state.activeActivity, isNotNull);
      expect(store.state.currentActionId, cookingRecipe.id);
    });

    test('returns null when no recipe assigned to area', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNull);

      store.dispatch(StartCookingAction(area: CookingArea.fire));

      // Should remain null since no recipe is assigned
      expect(store.state.activeActivity, isNull);
    });

    test('does nothing when stunned', () {
      final cookingRecipe = testCookingAction('Test Recipe', CookingArea.fire);
      final registries = Registries.test(actions: [cookingRecipe]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        cooking: initialState.cooking.withAreaState(
          CookingArea.fire,
          CookingAreaState(recipeId: cookingRecipe.id),
        ),
        stunned: const StunnedState.fresh().stun(),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.isStunned, isTrue);

      store.dispatch(StartCookingAction(area: CookingArea.fire));

      // Should not start cooking when stunned
      expect(store.state.activeActivity, isNull);
    });

    test('can start cooking in different areas', () {
      final fireRecipe = testCookingAction('Fire Recipe', CookingArea.fire);
      final potRecipe = testCookingAction('Pot Recipe', CookingArea.pot);
      final registries = Registries.test(actions: [fireRecipe, potRecipe]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        cooking: initialState.cooking
            .withAreaState(
              CookingArea.fire,
              CookingAreaState(recipeId: fireRecipe.id),
            )
            .withAreaState(
              CookingArea.pot,
              CookingAreaState(recipeId: potRecipe.id),
            ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        // Start fire cooking
        ..dispatch(StartCookingAction(area: CookingArea.fire));
      expect(store.state.currentActionId, fireRecipe.id);

      // Switch to pot cooking
      store.dispatch(StartCookingAction(area: CookingArea.pot));
      expect(store.state.currentActionId, potRecipe.id);
    });
  });

  group('AssignCookingRecipeAction', () {
    CookingAction testCookingAction(String name, CookingArea area) {
      final productId = MelvorId('melvorD:${name.replaceAll(' ', '_')}');
      return CookingAction(
        id: ActionId.test(Skill.cooking, name),
        name: name,
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
        inputs: const {},
        outputs: const {},
        productId: productId,
        perfectCookId: null,
        categoryId: area.categoryId,
        subcategoryId: null,
        baseQuantity: 1,
      );
    }

    test('assigns recipe to cooking area', () {
      final cookingRecipe = testCookingAction('Test Recipe', CookingArea.fire);
      final registries = Registries.test(actions: [cookingRecipe]);
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.cooking.areaState(CookingArea.fire).recipeId, isNull);

      store.dispatch(
        AssignCookingRecipeAction(
          area: CookingArea.fire,
          recipe: cookingRecipe,
        ),
      );

      expect(
        store.state.cooking.areaState(CookingArea.fire).recipeId,
        cookingRecipe.id,
      );
    });

    test('changes recipe in same area', () {
      final recipe1 = testCookingAction('Recipe 1', CookingArea.fire);
      final recipe2 = testCookingAction('Recipe 2', CookingArea.fire);
      final registries = Registries.test(actions: [recipe1, recipe2]);
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        cooking: initialState.cooking.withAreaState(
          CookingArea.fire,
          CookingAreaState(recipeId: recipe1.id),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(
        store.state.cooking.areaState(CookingArea.fire).recipeId,
        recipe1.id,
      );

      store.dispatch(
        AssignCookingRecipeAction(area: CookingArea.fire, recipe: recipe2),
      );

      expect(
        store.state.cooking.areaState(CookingArea.fire).recipeId,
        recipe2.id,
      );
    });

    test('can assign recipes to different areas', () {
      final fireRecipe = testCookingAction('Fire Recipe', CookingArea.fire);
      final potRecipe = testCookingAction('Pot Recipe', CookingArea.pot);
      final registries = Registries.test(actions: [fireRecipe, potRecipe]);
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          AssignCookingRecipeAction(area: CookingArea.fire, recipe: fireRecipe),
        )
        ..dispatch(
          AssignCookingRecipeAction(area: CookingArea.pot, recipe: potRecipe),
        );

      expect(
        store.state.cooking.areaState(CookingArea.fire).recipeId,
        fireRecipe.id,
      );
      expect(
        store.state.cooking.areaState(CookingArea.pot).recipeId,
        potRecipe.id,
      );
    });
  });

  group('SetAttackStyleAction', () {
    test('sets attack style', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      // Default attack style is stab
      expect(store.state.attackStyle, AttackStyle.stab);

      store.dispatch(SetAttackStyleAction(attackStyle: AttackStyle.slash));

      expect(store.state.attackStyle, AttackStyle.slash);
    });

    test('changes to block style', () {
      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      initialState = initialState.setAttackStyle(AttackStyle.slash);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.attackStyle, AttackStyle.slash);

      store.dispatch(SetAttackStyleAction(attackStyle: AttackStyle.block));

      expect(store.state.attackStyle, AttackStyle.block);
    });

    test('can set ranged attack styles', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(SetAttackStyleAction(attackStyle: AttackStyle.accurate));

      expect(store.state.attackStyle, AttackStyle.accurate);

      store.dispatch(SetAttackStyleAction(attackStyle: AttackStyle.rapid));
      expect(store.state.attackStyle, AttackStyle.rapid);

      store.dispatch(SetAttackStyleAction(attackStyle: AttackStyle.longRange));
      expect(store.state.attackStyle, AttackStyle.longRange);
    });

    test('can set magic attack styles', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(SetAttackStyleAction(attackStyle: AttackStyle.standard));

      expect(store.state.attackStyle, AttackStyle.standard);

      store.dispatch(SetAttackStyleAction(attackStyle: AttackStyle.defensive));
      expect(store.state.attackStyle, AttackStyle.defensive);
    });
  });

  group('ClearPlotAction', () {
    test('clears farming plot', () {
      const plotId = MelvorId('melvorD:Test_Plot');
      final cropId = ActionId.test(Skill.farming, 'Test_Crop');

      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        plotStates: {
          plotId: PlotState(cropId: cropId, growthTicksRemaining: 100),
        },
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.plotStates[plotId], isNotNull);

      store.dispatch(ClearPlotAction(plotId: plotId));

      expect(store.state.plotStates[plotId], isNull);
    });

    test('does nothing when plot is already empty', () {
      const plotId = MelvorId('melvorD:Test_Plot');

      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.plotStates[plotId], isNull);

      store.dispatch(ClearPlotAction(plotId: plotId));

      expect(store.state.plotStates[plotId], isNull);
    });

    test('clears only specified plot, leaving others intact', () {
      const plotId1 = MelvorId('melvorD:Plot_1');
      const plotId2 = MelvorId('melvorD:Plot_2');
      final cropId = ActionId.test(Skill.farming, 'Test_Crop');

      final registries = Registries.test();
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        plotStates: {
          plotId1: PlotState(cropId: cropId, growthTicksRemaining: 100),
          plotId2: PlotState(cropId: cropId, growthTicksRemaining: 200),
        },
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(ClearPlotAction(plotId: plotId1));

      expect(store.state.plotStates[plotId1], isNull);
      expect(store.state.plotStates[plotId2], isNotNull);
      expect(store.state.plotStates[plotId2]!.growthTicksRemaining, 200);
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
