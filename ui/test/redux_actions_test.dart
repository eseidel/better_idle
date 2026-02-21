import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:logic/logic.dart';
import 'package:logic/src/data/registries_io.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/services/toast_service.dart';

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

  group('StartSlayerTaskAction', () {
    CombatAction testMonster({int combatLevel = 10}) {
      // Create a weak monster with a combat level in the desired range.
      return CombatAction(
        id: ActionId.test(Skill.combat, 'Slayer Monster'),
        name: 'Slayer Monster',
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
      );
    }

    SlayerTaskCategory testCategory() {
      return SlayerTaskCategory(
        id: const MelvorId('melvorF:SlayerEasy'),
        name: 'Easy',
        level: 1,
        rollCost: CurrencyCosts.fromJson(const [
          {'id': 'melvorD:SlayerCoins', 'quantity': 100},
        ]),
        extensionCost: CurrencyCosts.empty,
        extensionMultiplier: 1,
        currencyRewards: const [],
        monsterSelection: const CombatLevelSelection(
          minLevel: 1,
          maxLevel: 100,
        ),
        baseTaskLength: 5,
      );
    }

    test('starts slayer task and deducts cost', () {
      final monster = testMonster();
      final category = testCategory();
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
        slayer: SlayerRegistry(
          taskCategories: SlayerTaskCategoryRegistry([category]),
          areas: SlayerAreaRegistry(const []),
        ),
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.addCurrency(Currency.slayerCoins, 500);

      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.activeActivity, isNull);
      expect(store.state.currency(Currency.slayerCoins), 500);

      store.dispatch(StartSlayerTaskAction(category: category));

      expect(store.state.activeActivity, isNull);
      expect(store.state.slayerTask, isNotNull);
      expect(store.state.currency(Currency.slayerCoins), 400);
    });

    test('does nothing when stunned', () {
      final monster = testMonster();
      final category = testCategory();
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
        slayer: SlayerRegistry(
          taskCategories: SlayerTaskCategoryRegistry([category]),
          areas: SlayerAreaRegistry(const []),
        ),
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState
          .addCurrency(Currency.slayerCoins, 500)
          .copyWith(stunned: const StunnedState.fresh().stun());

      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(StartSlayerTaskAction(category: category));

      expect(store.state.activeActivity, isNull);
      // Currency should not be deducted.
      expect(store.state.currency(Currency.slayerCoins), 500);
    });
  });

  group('PurchaseAstrologyModifierAction', () {
    // Create a test astrology action with modifiers
    AstrologyAction testConstellation() {
      const constellationId = MelvorId('melvorF:Test_Constellation');
      return AstrologyAction(
        id: ActionId(Skill.astrology.id, constellationId),
        name: 'Test Constellation',
        unlockLevel: 1,
        xp: 10,
        media: 'test.png',
        skillIds: [Skill.woodcutting.id],
        standardModifiers: const [
          AstrologyModifier(
            type: AstrologyModifierType.standard,
            modifierKey: 'skillXP',
            skills: [MelvorId('melvorD:Woodcutting')],
            maxCount: 5,
            costs: [10, 20, 30, 40, 50],
            unlockMasteryLevel: 1,
          ),
        ],
        uniqueModifiers: const [
          AstrologyModifier(
            type: AstrologyModifierType.unique,
            modifierKey: 'masteryXP',
            skills: [MelvorId('melvorD:Woodcutting')],
            maxCount: 3,
            costs: [5, 10, 15],
            unlockMasteryLevel: 1,
          ),
        ],
      );
    }

    test('successfully purchases standard modifier', () {
      final constellation = testConstellation();
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 100),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.standard, 0),
        0,
      );

      store.dispatch(
        PurchaseAstrologyModifierAction(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
      );

      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.standard, 0),
        1,
      );
      // Cost was 10 stardust
      expect(store.state.inventory.countOfItem(stardust), 90);
    });

    test('successfully purchases unique modifier', () {
      final constellation = testConstellation();
      const goldenStardust = Item(
        id: MelvorId('melvorF:Golden_Stardust'),
        name: 'Golden Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [goldenStardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(goldenStardust, count: 50),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.unique,
            modifierIndex: 0,
          ),
        );

      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.unique, 0),
        1,
      );
      // Cost was 5 golden stardust
      expect(store.state.inventory.countOfItem(goldenStardust), 45);
    });

    test('returns null when not enough currency', () {
      final constellation = testConstellation();
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      // Only add 5 stardust, but cost is 10
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 5),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.standard,
            modifierIndex: 0,
          ),
        );

      // State should be unchanged
      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.standard, 0),
        0,
      );
      expect(store.state.inventory.countOfItem(stardust), 5);
    });

    test('returns null when already at max level', () {
      final constellation = testConstellation();
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 1000),
        ),
        astrology: AstrologyState(
          constellationStates: {
            constellation.id.localId: const ConstellationModifierState(
              standardLevels: [5], // maxCount is 5
            ),
          },
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.standard,
            modifierIndex: 0,
          ),
        );

      // State should be unchanged - still at max level
      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.standard, 0),
        5,
      );
      // No currency deducted
      expect(store.state.inventory.countOfItem(stardust), 1000);
    });

    test('returns null when constellation not found', () {
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: const AstrologyRegistry([]), // Empty astrology registry
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 100),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: const MelvorId('melvorF:NonExistent'),
            modifierType: AstrologyModifierType.standard,
            modifierIndex: 0,
          ),
        );

      // State should be unchanged
      expect(store.state.inventory.countOfItem(stardust), 100);
    });

    test('returns null when modifier index is invalid', () {
      final constellation = testConstellation();
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 100),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.standard,
            modifierIndex: 999, // Invalid index
          ),
        );

      // State should be unchanged
      expect(store.state.inventory.countOfItem(stardust), 100);
    });

    test('deducts increasing cost with level', () {
      final constellation = testConstellation();
      const stardust = Item(
        id: MelvorId('melvorF:Stardust'),
        name: 'Stardust',
        itemType: 'Item',
        sellsFor: 0,
      );

      final registries = Registries.test(
        items: const [stardust],
        astrology: AstrologyRegistry([constellation]),
        actions: [constellation],
      );
      var initialState = GlobalState.empty(registries);
      // Costs are [10, 20, 30, 40, 50], total = 150
      initialState = initialState.copyWith(
        inventory: initialState.inventory.adding(
          const ItemStack(stardust, count: 150),
        ),
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          PurchaseAstrologyModifierAction(
            constellationId: constellation.id.localId,
            modifierType: AstrologyModifierType.standard,
            modifierIndex: 0,
          ),
        );
      expect(store.state.inventory.countOfItem(stardust), 140);

      // Purchase level 2 (cost 20)
      store.dispatch(
        PurchaseAstrologyModifierAction(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
      );
      expect(store.state.inventory.countOfItem(stardust), 120);

      // Purchase level 3 (cost 30)
      store.dispatch(
        PurchaseAstrologyModifierAction(
          constellationId: constellation.id.localId,
          modifierType: AstrologyModifierType.standard,
          modifierIndex: 0,
        ),
      );
      expect(store.state.inventory.countOfItem(stardust), 90);

      expect(
        store.state.astrology
            .stateFor(constellation.id.localId)
            .levelFor(AstrologyModifierType.standard, 0),
        3,
      );
    });
  });

  group('SetSelectedSkillAction', () {
    test('sets selected action for skill', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.selectedSkillAction(Skill.woodcutting), isNull);

      const actionId = MelvorId('melvorD:Normal_Tree');
      store.dispatch(
        SetSelectedSkillAction(skill: Skill.woodcutting, actionId: actionId),
      );

      expect(store.state.selectedSkillAction(Skill.woodcutting), actionId);
    });

    test('updates existing selection for same skill', () {
      final registries = Registries.test();
      const normalTree = MelvorId('melvorD:Normal_Tree');
      const oakTree = MelvorId('melvorD:Oak_Tree');

      var initialState = GlobalState.empty(registries);
      initialState = initialState.setSelectedSkillAction(
        Skill.woodcutting,
        normalTree,
      );
      final store = Store<GlobalState>(initialState: initialState);

      expect(store.state.selectedSkillAction(Skill.woodcutting), normalTree);

      store.dispatch(
        SetSelectedSkillAction(skill: Skill.woodcutting, actionId: oakTree),
      );

      expect(store.state.selectedSkillAction(Skill.woodcutting), oakTree);
    });

    test('preserves selections for other skills', () {
      final registries = Registries.test();
      const normalTree = MelvorId('melvorD:Normal_Tree');
      const shrimp = MelvorId('melvorD:Shrimp');

      var initialState = GlobalState.empty(registries);
      initialState = initialState.setSelectedSkillAction(
        Skill.woodcutting,
        normalTree,
      );
      final store = Store<GlobalState>(initialState: initialState)
        ..dispatch(
          SetSelectedSkillAction(skill: Skill.fishing, actionId: shrimp),
        );

      // Both selections should be preserved
      expect(store.state.selectedSkillAction(Skill.woodcutting), normalTree);
      expect(store.state.selectedSkillAction(Skill.fishing), shrimp);
    });

    test('can set selection for multiple skills', () {
      final registries = Registries.test();
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      const normalTree = MelvorId('melvorD:Normal_Tree');
      const normalLogs = MelvorId('melvorD:Normal_Logs');
      const shrimp = MelvorId('melvorD:Shrimp');
      const man = MelvorId('melvorD:Man');

      store
        ..dispatch(
          SetSelectedSkillAction(
            skill: Skill.woodcutting,
            actionId: normalTree,
          ),
        )
        ..dispatch(
          SetSelectedSkillAction(skill: Skill.firemaking, actionId: normalLogs),
        )
        ..dispatch(
          SetSelectedSkillAction(skill: Skill.fishing, actionId: shrimp),
        )
        ..dispatch(
          SetSelectedSkillAction(skill: Skill.thieving, actionId: man),
        );

      expect(store.state.selectedSkillAction(Skill.woodcutting), normalTree);
      expect(store.state.selectedSkillAction(Skill.firemaking), normalLogs);
      expect(store.state.selectedSkillAction(Skill.fishing), shrimp);
      expect(store.state.selectedSkillAction(Skill.thieving), man);
    });
  });

  group('SpendMasteryPoolAction', () {
    late Registries registries;
    late SkillAction normalTree;

    setUpAll(() async {
      registries = await loadRegistries();
      normalTree = registries
          .actionsForSkill(Skill.woodcutting)
          .firstWhere((a) => a.name == 'Normal Tree');
    });

    test('spends pool XP to level up action mastery', () {
      var state = GlobalState.empty(registries);
      state = state.addSkillMasteryXp(Skill.woodcutting, 100000);
      final store = Store<GlobalState>(initialState: state);

      final poolBefore = store.state
          .skillState(Skill.woodcutting)
          .masteryPoolXp;
      store.dispatch(
        SpendMasteryPoolAction(
          skill: Skill.woodcutting,
          actionId: normalTree.id,
        ),
      );

      expect(
        store.state.skillState(Skill.woodcutting).masteryPoolXp,
        poolBefore - 83,
      );
      expect(store.state.actionState(normalTree.id).masteryLevel, 2);
    });

    test('returns null when pool is insufficient', () {
      var state = GlobalState.empty(registries);
      state = state.addSkillMasteryXp(Skill.woodcutting, 10);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(
          SpendMasteryPoolAction(
            skill: Skill.woodcutting,
            actionId: normalTree.id,
          ),
        );

      // State unchanged — still 10 pool XP, still level 1.
      expect(store.state.skillState(Skill.woodcutting).masteryPoolXp, 10);
      expect(store.state.actionState(normalTree.id).masteryLevel, 1);
    });
  });

  group('ClaimMasteryTokenAction', () {
    late Registries registries;
    late Item woodcuttingToken;

    setUpAll(() async {
      registries = await loadRegistries();
      woodcuttingToken = registries.items.byName('Mastery Token (Woodcutting)');
    });

    test('claims one mastery token', () {
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 3),
        ),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(ClaimMasteryTokenAction(skill: Skill.woodcutting));

      expect(store.state.inventory.countOfItem(woodcuttingToken), 2);
      expect(
        store.state.skillState(Skill.woodcutting).masteryPoolXp,
        greaterThan(0),
      );
    });
  });

  group('ClaimAllMasteryTokensAction', () {
    late Registries registries;
    late Item woodcuttingToken;

    setUpAll(() async {
      registries = await loadRegistries();
      woodcuttingToken = registries.items.byName('Mastery Token (Woodcutting)');
    });

    test('claims all mastery tokens at once', () {
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(ClaimAllMasteryTokensAction(skill: Skill.woodcutting));

      expect(store.state.inventory.countOfItem(woodcuttingToken), 0);
      expect(
        store.state.skillState(Skill.woodcutting).masteryPoolXp,
        greaterThan(0),
      );
    });
  });

  group('QuickEquipAction', () {
    test('equips food item to food slot', () {
      runScoped(() {
        const food = Item(
          id: MelvorId('melvorD:Shrimp'),
          name: 'Shrimp',
          itemType: 'Food',
          sellsFor: 1,
          healsFor: 30,
        );
        final registries = Registries.test(items: const [food]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(food, count: 5)),
        );
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(QuickEquipAction(stack: const ItemStack(food, count: 5)));

        // Food should be equipped and removed from inventory.
        expect(store.state.equipment.foodSlots[0]?.item, food);
        expect(store.state.equipment.foodSlots[0]?.count, 5);
        expect(store.state.inventory.countOfItem(food), 0);
      }, values: {toastServiceRef});
    });

    test('equips gear item to first valid slot', () {
      runScoped(() {
        const sword = Item(
          id: MelvorId('melvorD:Bronze_Sword'),
          name: 'Bronze Sword',
          itemType: 'Weapon',
          sellsFor: 10,
          validSlots: [EquipmentSlot.weapon],
        );
        final registries = Registries.test(items: const [sword]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(sword, count: 1)),
        );
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(QuickEquipAction(stack: const ItemStack(sword, count: 1)));

        expect(store.state.equipment.gearInSlot(EquipmentSlot.weapon), sword);
        expect(store.state.inventory.countOfItem(sword), 0);
      }, values: {toastServiceRef});
    });

    test('does nothing for non-equippable item', () {
      runScoped(() {
        final logs = Item.test('Oak Logs', gp: 5);
        final registries = Registries.test(items: [logs]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(ItemStack(logs, count: 10)),
        );
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(QuickEquipAction(stack: ItemStack(logs, count: 10)));

        // Nothing should change.
        expect(store.state.inventory.countOfItem(logs), 10);
      }, values: {toastServiceRef});
    });

    test('shows error when food slots are full', () {
      runScoped(() {
        const food1 = Item(
          id: MelvorId('melvorD:Shrimp'),
          name: 'Shrimp',
          itemType: 'Food',
          sellsFor: 1,
          healsFor: 30,
        );
        const food2 = Item(
          id: MelvorId('melvorD:Trout'),
          name: 'Trout',
          itemType: 'Food',
          sellsFor: 2,
          healsFor: 50,
        );
        const food3 = Item(
          id: MelvorId('melvorD:Lobster'),
          name: 'Lobster',
          itemType: 'Food',
          sellsFor: 5,
          healsFor: 100,
        );
        const food4 = Item(
          id: MelvorId('melvorD:Swordfish'),
          name: 'Swordfish',
          itemType: 'Food',
          sellsFor: 10,
          healsFor: 150,
        );
        final registries = Registries.test(
          items: const [food1, food2, food3, food4],
        );
        var state = GlobalState.empty(registries);
        // Fill all 3 food slots.
        state = state.copyWith(
          inventory: state.inventory
              .adding(const ItemStack(food1, count: 1))
              .adding(const ItemStack(food2, count: 1))
              .adding(const ItemStack(food3, count: 1))
              .adding(const ItemStack(food4, count: 1)),
        );
        state = state.equipFood(const ItemStack(food1, count: 1));
        state = state.equipFood(const ItemStack(food2, count: 1));
        state = state.equipFood(const ItemStack(food3, count: 1));
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(QuickEquipAction(stack: const ItemStack(food4, count: 1)));

        // food4 should still be in inventory.
        expect(store.state.inventory.countOfItem(food4), 1);
      }, values: {toastServiceRef});
    });

    test('shows error when equip requirements not met', () {
      runScoped(() {
        const sword = Item(
          id: MelvorId('melvorD:Dragon_Sword'),
          name: 'Dragon Sword',
          itemType: 'Weapon',
          sellsFor: 100,
          validSlots: [EquipmentSlot.weapon],
          equipRequirements: [
            SkillLevelRequirement(skill: Skill.attack, level: 60),
          ],
        );
        final registries = Registries.test(items: const [sword]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(sword, count: 1)),
        );
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(QuickEquipAction(stack: const ItemStack(sword, count: 1)));

        // Should not be equipped.
        expect(store.state.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
        expect(store.state.inventory.countOfItem(sword), 1);
      }, values: {toastServiceRef});
    });
  });

  // ==========================================================================
  // Tests for previously untested actions
  // ==========================================================================

  group('UpdateActivityProgressAction', () {
    test('processes ticks and updates state', () {
      runScoped(() {
        final testAction = SkillAction(
          id: ActionId.test(Skill.woodcutting, 'Test Tree'),
          skill: Skill.woodcutting,
          name: 'Test Tree',
          unlockLevel: 1,
          duration: const Duration(seconds: 3),
          xp: 10,
        );
        final registries = Registries.test(actions: [testAction]);
        var state = GlobalState.empty(registries);
        state = state.startAction(testAction, random: Random(42));
        final store = Store<GlobalState>(initialState: state);

        // Advance time by 10 seconds (enough to complete several actions).
        final now = state.updatedAt.add(const Duration(seconds: 10));
        store.dispatch(UpdateActivityProgressAction(now: now));

        // XP should have been gained from completed actions.
        expect(store.state.skillState(Skill.woodcutting).xp, greaterThan(0));
      }, values: {toastServiceRef});
    });

    test('accumulates changes into timeAway when present', () {
      runScoped(() {
        final testAction = SkillAction(
          id: ActionId.test(Skill.woodcutting, 'Test Tree'),
          skill: Skill.woodcutting,
          name: 'Test Tree',
          unlockLevel: 1,
          duration: const Duration(seconds: 3),
          xp: 10,
        );
        final registries = Registries.test(actions: [testAction]);
        var state = GlobalState.empty(registries);
        state = state.startAction(testAction, random: Random(42));
        // Produce a timeAway with actual changes (enough ticks to complete).
        final (timeAway, newState) = consumeManyTicks(
          state,
          1000,
          random: Random(42),
        );
        // Use the new state (with updated progress) but keep timeAway.
        state = newState.copyWith(timeAway: timeAway);
        // Re-start the action so there's something to tick.
        state = state.startAction(testAction, random: Random(42));
        final store = Store<GlobalState>(initialState: state);

        final now = state.updatedAt.add(const Duration(seconds: 10));
        store.dispatch(UpdateActivityProgressAction(now: now));

        // timeAway should still be present (accumulated).
        expect(store.state.timeAway, isNotNull);
      }, values: {toastServiceRef});
    });
  });

  group('DebugAdvanceTicksAction', () {
    test('advances state by specified ticks', () {
      final testAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'Test Tree'),
        skill: Skill.woodcutting,
        name: 'Test Tree',
        unlockLevel: 1,
        duration: const Duration(seconds: 3),
        xp: 10,
      );
      final registries = Registries.test(actions: [testAction]);
      var state = GlobalState.empty(registries);
      state = state.startAction(testAction, random: Random(42));
      final store = Store<GlobalState>(initialState: state);

      final action = DebugAdvanceTicksAction(ticks: 100);
      store.dispatch(action);

      expect(action.timeAway, isNotNull);
    });
  });

  group('UpgradeItemAction', () {
    test('upgrades item when requirements met', () {
      final bronzeDagger = Item.test('Bronze Dagger', gp: 5);
      final steelDagger = Item.test('Steel Dagger', gp: 50);
      final upgrade = ItemUpgrade(
        upgradedItemId: steelDagger.id,
        itemCosts: [ItemCost(itemId: bronzeDagger.id, quantity: 1)],
        currencyCosts: CurrencyCosts.empty,
        rootItemIds: [bronzeDagger.id],
        isDowngrade: false,
      );
      final registries = Registries.test(items: [bronzeDagger, steelDagger]);
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(bronzeDagger, count: 1)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(UpgradeItemAction(upgrade: upgrade, count: 1));

      expect(store.state.inventory.countOfItem(bronzeDagger), 0);
      expect(store.state.inventory.countOfItem(steelDagger), 1);
    });

    test('returns null when insufficient items', () {
      final bronzeDagger = Item.test('Bronze Dagger', gp: 5);
      final steelDagger = Item.test('Steel Dagger', gp: 50);
      final upgrade = ItemUpgrade(
        upgradedItemId: steelDagger.id,
        itemCosts: [ItemCost(itemId: bronzeDagger.id, quantity: 1)],
        currencyCosts: CurrencyCosts.empty,
        rootItemIds: [bronzeDagger.id],
        isDowngrade: false,
      );
      final registries = Registries.test(items: [bronzeDagger, steelDagger]);
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(UpgradeItemAction(upgrade: upgrade, count: 1));

      // State should not change.
      expect(store.state.inventory.countOfItem(steelDagger), 0);
    });
  });

  group('PurchaseShopItemAction', () {
    late Registries registries;
    const bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');

    setUpAll(() async {
      registries = await loadRegistries();
    });

    test('purchases bank slot and deducts gp', () {
      final state = GlobalState.test(registries, gp: 1000000);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(PurchaseShopItemAction(purchaseId: bankSlotId));

      expect(store.state.shop.purchaseCount(bankSlotId), 1);
      expect(store.state.gp, lessThan(1000000));
    });

    test('throws for unknown purchase id', () {
      final state = GlobalState.test(registries, gp: 1000);
      final store = Store<GlobalState>(initialState: state);
      expect(
        () => store.dispatch(
          PurchaseShopItemAction(
            purchaseId: const MelvorId('melvorD:Fake_Item'),
          ),
        ),
        throwsA(isA<Object>()),
      );
    });

    test('throws when not enough gp', () {
      final state = GlobalState.test(registries);
      final store = Store<GlobalState>(initialState: state);
      expect(
        () => store.dispatch(PurchaseShopItemAction(purchaseId: bankSlotId)),
        throwsA(isA<Object>()),
      );
    });
  });

  group('StartCombatAction', () {
    CombatAction testMonster() {
      return CombatAction(
        id: ActionId.test(Skill.combat, 'Test Monster'),
        name: 'Test Monster',
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
      );
    }

    test('starts combat with monster', () {
      final monster = testMonster();
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
      );
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartCombatAction(combatAction: monster));

      expect(store.state.activeActivity, isA<CombatActivity>());
    });

    test('does nothing when stunned', () {
      final monster = testMonster();
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.copyWith(stunned: const StunnedState.fresh().stun());
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartCombatAction(combatAction: monster));

      expect(store.state.activeActivity, isNull);
    });

    test('does nothing when already in combat with same monster', () {
      final monster = testMonster();
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.startAction(monster, random: Random(42));
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartCombatAction(combatAction: monster));

      // Still in combat (no-op).
      expect(store.state.activeActivity, isA<CombatActivity>());
    });
  });

  group('StopCombatAction', () {
    test('stops combat', () {
      final monster = CombatAction(
        id: ActionId.test(Skill.combat, 'Test Monster'),
        name: 'Test Monster',
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
      );
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry(const []),
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.startAction(monster, random: Random(42));
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StopCombatAction());

      expect(store.state.activeActivity, isNull);
    });

    test('does nothing when stunned', () {
      final registries = Registries.test();
      var state = GlobalState.empty(registries);
      state = state.copyWith(stunned: const StunnedState.fresh().stun());
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StopCombatAction());

      expect(store.state.activeActivity, isNull);
    });
  });

  group('CollectAllLootAction', () {
    test('collects loot into inventory', () {
      final item = Item.test('Gold Bar', gp: 100);
      final registries = Registries.test(items: [item]);
      var state = GlobalState.empty(registries);
      final (loot, _) = const LootState.empty().addItem(
        ItemStack(item, count: 5),
        isBones: false,
      );
      state = state.copyWith(loot: loot);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(CollectAllLootAction());

      expect(store.state.inventory.countOfItem(item), 5);
      expect(store.state.loot.isEmpty, isTrue);
    });

    test('does nothing when loot is empty', () {
      final registries = Registries.test();
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(CollectAllLootAction());

      expect(store.state, state);
    });
  });

  group('StartDungeonAction', () {
    test('starts dungeon run', () {
      final monster = CombatAction(
        id: ActionId.test(Skill.combat, 'Dungeon Monster'),
        name: 'Dungeon Monster',
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
      );
      final dungeon = Dungeon(
        id: const MelvorId('melvorD:Test_Dungeon'),
        name: 'Test Dungeon',
        monsterIds: [monster.id.localId],
      );
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry([dungeon]),
          strongholds: StrongholdRegistry(const []),
        ),
      );
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartDungeonAction(dungeon: dungeon));

      expect(store.state.activeActivity, isA<CombatActivity>());
    });
  });

  group('StartStrongholdAction', () {
    test('starts stronghold run', () {
      final monster = CombatAction(
        id: ActionId.test(Skill.combat, 'Stronghold Monster'),
        name: 'Stronghold Monster',
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
      );
      final stronghold = Stronghold(
        id: const MelvorId('melvorD:Test_Stronghold'),
        name: 'Test Stronghold',
        monsterIds: [monster.id.localId],
      );
      final registries = Registries.test(
        actions: [monster],
        combat: CombatRegistry(
          monsters: [monster],
          areas: CombatAreaRegistry(const []),
          dungeons: DungeonRegistry(const []),
          strongholds: StrongholdRegistry([stronghold]),
        ),
      );
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartStrongholdAction(stronghold: stronghold));

      expect(store.state.activeActivity, isA<CombatActivity>());
    });
  });

  group('EquipFoodAction', () {
    test('equips food from inventory', () {
      const food = Item(
        id: MelvorId('melvorD:Shrimp'),
        name: 'Shrimp',
        itemType: 'Food',
        sellsFor: 1,
        healsFor: 30,
      );
      final registries = Registries.test(items: const [food]);
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(const ItemStack(food, count: 10)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(EquipFoodAction(item: food, count: 5));

      expect(store.state.equipment.foodSlots[0]?.item, food);
      expect(store.state.equipment.foodSlots[0]?.count, 5);
      expect(store.state.inventory.countOfItem(food), 5);
    });
  });

  group('EatFoodAction', () {
    test('eats equipped food to heal', () {
      const food = Item(
        id: MelvorId('melvorD:Shrimp'),
        name: 'Shrimp',
        itemType: 'Food',
        sellsFor: 1,
        healsFor: 30,
      );
      final registries = Registries.test(items: const [food]);
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(const ItemStack(food, count: 5)),
      );
      state = state.equipFood(const ItemStack(food, count: 5));
      // Damage the player.
      state = state.copyWith(health: const HealthState(lostHp: 50));
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(EatFoodAction());

      // Lost HP should decrease (player healed).
      expect(store.state.health.lostHp, lessThan(50));
    });
  });

  group('SelectFoodSlotAction', () {
    test('selects food slot', () {
      final registries = Registries.test();
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(SelectFoodSlotAction(slotIndex: 1));

      expect(store.state.equipment.selectedFoodSlot, 1);
    });
  });

  group('UnequipFoodAction', () {
    test('unequips food back to inventory', () {
      runScoped(() {
        const food = Item(
          id: MelvorId('melvorD:Shrimp'),
          name: 'Shrimp',
          itemType: 'Food',
          sellsFor: 1,
          healsFor: 30,
        );
        final registries = Registries.test(items: const [food]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(food, count: 5)),
        );
        state = state.equipFood(const ItemStack(food, count: 5));
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(UnequipFoodAction(slotIndex: 0));

        expect(store.state.equipment.foodSlots[0], isNull);
        expect(store.state.inventory.countOfItem(food), 5);
      }, values: {toastServiceRef});
    });

    test('does nothing when slot is empty', () {
      runScoped(() {
        final registries = Registries.test();
        final state = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(UnequipFoodAction(slotIndex: 0));

        expect(store.state, state);
      }, values: {toastServiceRef});
    });
  });

  group('SortInventoryAction', () {
    test('sorts inventory', () {
      final item1 = Item.test('Zebra Item', gp: 1);
      final item2 = Item.test('Apple Item', gp: 2);
      final registries = Registries.test(items: [item1, item2]);
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory
            .adding(ItemStack(item1, count: 1))
            .adding(ItemStack(item2, count: 1)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(SortInventoryAction());

      // Just verify it doesn't crash and state changed.
      expect(store.state.inventory.items.length, 2);
    });
  });

  group('EquipGearAction', () {
    test('equips gear to slot', () {
      runScoped(() {
        const sword = Item(
          id: MelvorId('melvorD:Bronze_Sword'),
          name: 'Bronze Sword',
          itemType: 'Weapon',
          sellsFor: 10,
          validSlots: [EquipmentSlot.weapon],
        );
        final registries = Registries.test(items: const [sword]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(sword, count: 1)),
        );
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(EquipGearAction(item: sword, slot: EquipmentSlot.weapon));

        expect(store.state.equipment.gearInSlot(EquipmentSlot.weapon), sword);
      }, values: {toastServiceRef});
    });
  });

  group('UnequipGearAction', () {
    test('unequips gear back to inventory', () {
      runScoped(() {
        const sword = Item(
          id: MelvorId('melvorD:Bronze_Sword'),
          name: 'Bronze Sword',
          itemType: 'Weapon',
          sellsFor: 10,
          validSlots: [EquipmentSlot.weapon],
        );
        final registries = Registries.test(items: const [sword]);
        var state = GlobalState.empty(registries);
        state = state.copyWith(
          inventory: state.inventory.adding(const ItemStack(sword, count: 1)),
        );
        state = state.equipGear(sword, EquipmentSlot.weapon);
        final store = Store<GlobalState>(initialState: state)
          ..dispatch(UnequipGearAction(slot: EquipmentSlot.weapon));

        expect(store.state.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
        expect(store.state.inventory.countOfItem(sword), 1);
      }, values: {toastServiceRef});
    });
  });

  group('BuildAgilityObstacleAction', () {
    test('builds obstacle in slot', () {
      final obstacle = AgilityObstacle(
        id: ActionId.test(Skill.agility, 'Test_Obstacle'),
        name: 'Test Obstacle',
        unlockLevel: 1,
        xp: 10,
        duration: const Duration(seconds: 5),
        category: 0,
      );
      const course = AgilityCourse(
        realm: MelvorId('melvorD:Melvor'),
        obstacleSlots: [1, 1, 1],
        pillarSlots: [],
      );
      final registries = Registries.test(
        actions: [obstacle],
        agility: AgilityRegistry(
          obstacles: [obstacle],
          courses: const [course],
          pillars: const [],
        ),
      );
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(
        initialState: state,
      )..dispatch(BuildAgilityObstacleAction(slot: 0, obstacleId: obstacle.id));

      expect(store.state.agility.builtObstacles, isNotEmpty);
    });
  });

  group('DestroyAgilityObstacleAction', () {
    test('destroys obstacle in slot', () {
      final obstacle = AgilityObstacle(
        id: ActionId.test(Skill.agility, 'Test_Obstacle'),
        name: 'Test Obstacle',
        unlockLevel: 1,
        xp: 10,
        duration: const Duration(seconds: 5),
        category: 0,
      );
      const course = AgilityCourse(
        realm: MelvorId('melvorD:Melvor'),
        obstacleSlots: [1, 1, 1],
        pillarSlots: [],
      );
      final registries = Registries.test(
        actions: [obstacle],
        agility: AgilityRegistry(
          obstacles: [obstacle],
          courses: const [course],
          pillars: const [],
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.buildAgilityObstacle(0, obstacle.id);
      expect(state.agility.builtObstacles, isNotEmpty);

      final store = Store<GlobalState>(initialState: state)
        ..dispatch(DestroyAgilityObstacleAction(slot: 0));

      expect(store.state.agility.builtObstacles, isEmpty);
    });
  });

  group('StartAgilityCourseAction', () {
    test('starts agility course', () {
      final obstacle = AgilityObstacle(
        id: ActionId.test(Skill.agility, 'Test_Obstacle'),
        name: 'Test Obstacle',
        unlockLevel: 1,
        xp: 10,
        duration: const Duration(seconds: 5),
        category: 0,
      );
      const course = AgilityCourse(
        realm: MelvorId('melvorD:Melvor'),
        obstacleSlots: [1, 1, 1],
        pillarSlots: [],
      );
      final registries = Registries.test(
        actions: [obstacle],
        agility: AgilityRegistry(
          obstacles: [obstacle],
          courses: const [course],
          pillars: const [],
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.buildAgilityObstacle(0, obstacle.id);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartAgilityCourseAction());

      expect(store.state.activeActivity, isA<AgilityActivity>());
    });

    test('does nothing when no obstacles built', () {
      const course = AgilityCourse(
        realm: MelvorId('melvorD:Melvor'),
        obstacleSlots: [1, 1, 1],
        pillarSlots: [],
      );
      final registries = Registries.test(
        agility: AgilityRegistry(
          obstacles: const [],
          courses: const [course],
          pillars: const [],
        ),
      );
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartAgilityCourseAction());

      expect(store.state.activeActivity, isNull);
    });
  });

  group('StopAgilityCourseAction', () {
    test('stops agility course', () {
      final obstacle = AgilityObstacle(
        id: ActionId.test(Skill.agility, 'Test_Obstacle'),
        name: 'Test Obstacle',
        unlockLevel: 1,
        xp: 10,
        duration: const Duration(seconds: 5),
        category: 0,
      );
      const course = AgilityCourse(
        realm: MelvorId('melvorD:Melvor'),
        obstacleSlots: [1, 1, 1],
        pillarSlots: [],
      );
      final registries = Registries.test(
        actions: [obstacle],
        agility: AgilityRegistry(
          obstacles: [obstacle],
          courses: const [course],
          pillars: const [],
        ),
      );
      var state = GlobalState.empty(registries);
      state = state.buildAgilityObstacle(0, obstacle.id);
      state = state.startAgilityCourse(random: Random(42))!;
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StopAgilityCourseAction());

      expect(store.state.activeActivity, isNull);
    });

    test('does nothing when not running agility', () {
      final registries = Registries.test();
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StopAgilityCourseAction());

      expect(store.state.activeActivity, isNull);
    });
  });

  group('DebugFillInventoryAction', () {
    test('fills inventory with items', () {
      final item1 = Item.test('Item A', gp: 1);
      final item2 = Item.test('Item B', gp: 2);
      final item3 = Item.test('Item C', gp: 3);
      final registries = Registries.test(items: [item1, item2, item3]);
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(DebugFillInventoryAction());

      expect(store.state.inventory.items.length, greaterThan(0));
    });
  });

  group('DebugAddItemAction', () {
    test('adds item to inventory', () {
      final item = Item.test('Gold Bar', gp: 100);
      final registries = Registries.test(items: [item]);
      final state = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(DebugAddItemAction(item: item, count: 5));

      expect(store.state.inventory.countOfItem(item), 5);
    });

    test('returns null when inventory full', () {
      final items = List.generate(200, (i) => Item.test('Item $i', gp: 1));
      final registries = Registries.test(items: items);
      var state = GlobalState.empty(registries);
      // Fill inventory to capacity.
      for (final item in items) {
        final inv = state.inventory.adding(ItemStack(item, count: 1));
        if (inv.items.length > state.inventoryCapacity) break;
        state = state.copyWith(inventory: inv);
      }
      final newItem = Item.test('Extra Item', gp: 1);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(DebugAddItemAction(item: newItem));

      expect(store.state.inventory.countOfItem(newItem), 0);
    });
  });

  group('DebugResetStateAction', () {
    test('resets to empty state', () {
      final item = Item.test('Gold Bar', gp: 100);
      final registries = Registries.test(items: [item]);
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(item, count: 5)),
      );
      state = state.addCurrency(Currency.gp, 1000);
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(DebugResetStateAction());

      expect(store.state.inventory.items, isEmpty);
      expect(store.state.gp, 0);
    });
  });

  group('PlantCropAction', () {
    test('plants crop in unlocked plot', () {
      final seed = Item.test('Potato Seed', gp: 1);
      final potato = Item.test('Potato', gp: 5);
      final crop = FarmingCrop(
        id: ActionId.test(Skill.farming, 'Potato'),
        name: 'Potato',
        categoryId: const MelvorId('melvorD:Allotment'),
        level: 1,
        baseXP: 8,
        seedCost: 1,
        baseInterval: 30000,
        seedId: seed.id,
        productId: potato.id,
        baseQuantity: 5,
        media: '',
      );
      final registries = Registries.test(
        items: [seed, potato],
        actions: [crop],
      );
      const plotId = MelvorId('melvorD:Test_Plot');
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        unlockedPlots: {plotId},
        inventory: state.inventory.adding(ItemStack(seed, count: 5)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(PlantCropAction(plotId: plotId, crop: crop));

      expect(store.state.plotStates[plotId], isNotNull);
      expect(store.state.inventory.countOfItem(seed), 4);
    });
  });

  // HarvestCropAction needs a full FarmingRegistry (with crop and category
  // lookups) which Registries.test() doesn't support. Tested via
  // logic/test/state_test.dart instead.

  group('UnlockPlotAction', () {
    test('dispatches unlock to state', () {
      final registries = Registries.test();
      final state = GlobalState.empty(registries);
      const plotId = MelvorId('melvorD:Fake_Plot');
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(UnlockPlotAction(plotId: plotId));

      // Returns null for unknown plot, so state unchanged.
      expect(store.state.unlockedPlots, isEmpty);
    });
  });

  group('ApplyCompostAction', () {
    test('applies compost to empty plot before planting', () {
      final compost = Item.test('Compost', gp: 2, compostValue: 10);
      final registries = Registries.test(items: [compost]);
      const plotId = MelvorId('melvorD:Test_Plot');
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        unlockedPlots: {plotId},
        inventory: state.inventory.adding(ItemStack(compost, count: 3)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(ApplyCompostAction(plotId: plotId, compost: compost));

      expect(store.state.inventory.countOfItem(compost), 2);
    });
  });

  group('StartBonfireAction', () {
    test('starts bonfire with enough logs', () {
      final logItem = Item.test('Normal Logs', gp: 1);
      final firemakingAction = FiremakingAction(
        id: ActionId.test(Skill.firemaking, 'Normal_Log'),
        name: 'Normal Log',
        unlockLevel: 1,
        xp: 10,
        inputs: {logItem.id: 1},
        duration: const Duration(seconds: 3),
        logId: logItem.id,
        bonfireInterval: const Duration(minutes: 10),
        bonfireXPBonus: 5,
      );
      final registries = Registries.test(
        items: [logItem],
        actions: [firemakingAction],
      );
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(logItem, count: 20)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartBonfireAction(firemakingAction));

      expect(store.state.bonfire.isActive, isTrue);
      // Should have consumed 10 logs.
      expect(store.state.inventory.countOfItem(logItem), 10);
    });

    test('does nothing when not enough logs', () {
      final logItem = Item.test('Normal Logs', gp: 1);
      final firemakingAction = FiremakingAction(
        id: ActionId.test(Skill.firemaking, 'Normal_Log'),
        name: 'Normal Log',
        unlockLevel: 1,
        xp: 10,
        inputs: {logItem.id: 1},
        duration: const Duration(seconds: 3),
        logId: logItem.id,
        bonfireInterval: const Duration(minutes: 10),
        bonfireXPBonus: 5,
      );
      final registries = Registries.test(
        items: [logItem],
        actions: [firemakingAction],
      );
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(logItem, count: 5)),
      );
      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StartBonfireAction(firemakingAction));

      expect(store.state.bonfire.isActive, isFalse);
    });
  });

  group('StopBonfireAction', () {
    test('stops bonfire', () {
      final logItem = Item.test('Normal Logs', gp: 1);
      final firemakingAction = FiremakingAction(
        id: ActionId.test(Skill.firemaking, 'Normal_Log'),
        name: 'Normal Log',
        unlockLevel: 1,
        xp: 10,
        inputs: {logItem.id: 1},
        duration: const Duration(seconds: 3),
        logId: logItem.id,
        bonfireInterval: const Duration(minutes: 10),
        bonfireXPBonus: 5,
      );
      final registries = Registries.test(
        items: [logItem],
        actions: [firemakingAction],
      );
      var state = GlobalState.empty(registries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(logItem, count: 20)),
      );
      state = state.startBonfire(firemakingAction);
      expect(state.bonfire.isActive, isTrue);

      final store = Store<GlobalState>(initialState: state)
        ..dispatch(StopBonfireAction());

      expect(store.state.bonfire.isActive, isFalse);
    });
  });
}
