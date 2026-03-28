import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  // Shared test constants and helpers
  const categoryId = MelvorId('test:allotment');
  const plotId = MelvorId('test:plot_1');

  late FarmingCategory category;
  late Item seed;
  late Item product;
  late FarmingCrop crop;

  setUp(() {
    category = const FarmingCategory.test(id: categoryId);
    seed = Item.test('Potato Seed', gp: 5);
    product = Item.test('Potato', gp: 10);
    crop = FarmingCrop(
      id: ActionId.test(Skill.farming, 'Potato'),
      name: 'Potato',
      categoryId: categoryId,
      seedId: seed.id,
      productId: product.id,
      seedCost: 3,
      level: 1,
      baseXP: 8,
      baseInterval: 10000,
      baseQuantity: 5,
      media: '',
    );
  });

  GlobalState createState({Item? modifierItem, int seedCount = 10}) {
    final items = [seed, product];
    if (modifierItem != null) items.add(modifierItem);
    final farming = FarmingRegistry(
      crops: [crop],
      categories: [category],
      plots: const [FarmingPlot(id: plotId, categoryId: categoryId, level: 1)],
    );
    final registries = Registries.test(items: items, farming: farming);
    final inventory = Inventory.empty(
      registries.items,
    ).adding(ItemStack(seed, count: seedCount));
    final equipment = modifierItem != null
        ? Equipment(
            foodSlots: const [null, null, null],
            selectedFoodSlot: 0,
            gearSlots: {EquipmentSlot.ring: modifierItem},
          )
        : const Equipment.empty();
    return GlobalState.test(
      registries,
      inventory: inventory,
      unlockedPlots: {plotId},
      equipment: equipment,
    );
  }

  /// Plants a crop and immediately marks it as ready to harvest.
  GlobalState plantAndGrow(GlobalState state) {
    final s = state.plantCrop(plotId, crop);
    final plotState = s.plotStates[plotId]!;
    final grownPlot = plotState.copyWith(growthTicksRemaining: 0);
    return s.copyWith(plotStates: {plotId: grownPlot});
  }

  group('farmingCropsCannotDie', () {
    test('crop dies on failed harvest without modifier', () {
      // Use no compost (50% base success) and a random that always fails.
      // Random returning 0.99 will always fail (0.99 >= 0.5 threshold).
      final state = plantAndGrow(createState());
      final failRandom = _FixedRandom(0.99);
      final (newState, changes) = state.harvestCrop(plotId, failRandom);
      // Crop died - plot should be cleared, no items gained
      expect(newState.plotStates[plotId], isNull);
      expect(changes, equals(const Changes.empty()));
    });

    test('crop survives failed roll with farmingCropsCannotDie modifier', () {
      const modifierItem = Item(
        id: MelvorId('test:farming_amulet'),
        name: 'Farming Amulet',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'farmingCropsCannotDie',
            entries: [ModifierEntry(value: 1)],
          ),
        ]),
      );

      final state = plantAndGrow(createState(modifierItem: modifierItem));
      // Random returning 0.99 would normally fail (>= 0.5 success threshold)
      final failRandom = _FixedRandom(0.99);
      final (newState, changes) = state.harvestCrop(plotId, failRandom);
      // Crop should survive - plot cleared but items gained
      expect(newState.plotStates[plotId], isNull);
      // Should have harvested product
      expect(newState.inventory.countOfItem(product), greaterThan(0));
      expect(changes.inventoryChanges.isNotEmpty, isTrue);
    });
  });

  group('farmingSeedReturn', () {
    test('farmingSeedReturn modifier increases seed return chance', () {
      // Create item with 70% farmingSeedReturn bonus
      const modifierItem = Item(
        id: MelvorId('test:seed_return_ring'),
        name: 'Seed Return Ring',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'farmingSeedReturn',
            entries: [ModifierEntry(value: 70)],
          ),
        ]),
      );

      final state = plantAndGrow(createState(modifierItem: modifierItem));
      // Use a random that succeeds for harvest (< 0.5) but is near the edge
      // for seed return. Base chance is 30%, + 70% modifier = 100%.
      // So every seed roll should succeed.
      final random = _FixedRandom(0.01); // succeeds for both harvest and seeds
      final (newState, _) = state.harvestCrop(plotId, random);

      // With 100% seed return chance, should get seeds back equal to quantity
      // Quantity = baseQuantity(5) * harvestMultiplier(1) = 5 (approx)
      final seedsInInventory = newState.inventory.countOfItem(seed);
      // Started with 10, used 3 for planting, should get some back
      expect(seedsInInventory, greaterThan(10 - 3));
    });
  });

  group('flatFarmingSeedCost', () {
    test('reduces seed cost when planting', () {
      const modifierItem = Item(
        id: MelvorId('test:seed_saver_ring'),
        name: 'Seed Saver Ring',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'flatFarmingSeedCost',
            entries: [
              ModifierEntry(
                value: -2,
                scope: ModifierScope(categoryId: categoryId),
              ),
            ],
          ),
        ]),
      );

      // Crop needs 3 seeds normally, with -2 reduction needs 1
      final state = createState(modifierItem: modifierItem, seedCount: 2);
      final newState = state.plantCrop(plotId, crop);

      // Should have consumed only 1 seed (3 + (-2) = 1)
      expect(newState.inventory.countOfItem(seed), equals(1));
    });

    test('seed cost cannot go below 1', () {
      const modifierItem = Item(
        id: MelvorId('test:seed_saver_ring_big'),
        name: 'Big Seed Saver Ring',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'flatFarmingSeedCost',
            entries: [
              ModifierEntry(
                value: -100,
                scope: ModifierScope(categoryId: categoryId),
              ),
            ],
          ),
        ]),
      );

      // Even with huge reduction, should still cost 1 seed
      final state = createState(modifierItem: modifierItem, seedCount: 5);
      final newState = state.plantCrop(plotId, crop);

      // Should have consumed exactly 1 seed (min)
      expect(newState.inventory.countOfItem(seed), equals(4));
    });

    test('no reduction without modifier', () {
      final state = createState();
      final newState = state.plantCrop(plotId, crop);

      // Should have consumed 3 seeds (normal cost)
      expect(newState.inventory.countOfItem(seed), equals(7));
    });
  });
}

/// A Random implementation that returns a fixed value for nextDouble().
class _FixedRandom implements Random {
  _FixedRandom(this._value);

  final double _value;

  @override
  double nextDouble() => _value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}
