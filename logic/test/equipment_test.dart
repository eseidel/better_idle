import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item shrimp; // Consumable (healsFor: 30)
  late Item lobster; // Consumable (healsFor: 110)
  late Item crab; // Consumable (healsFor: 150)
  late Item sardine; // Consumable (healsFor: 40)
  late Item normalLogs; // Non-consumable

  setUpAll(() async {
    await ensureItemsInitialized();
    shrimp = itemRegistry.byName('Shrimp');
    lobster = itemRegistry.byName('Lobster');
    crab = itemRegistry.byName('Crab');
    sardine = itemRegistry.byName('Sardine');
    normalLogs = itemRegistry.byName('Normal Logs');
  });

  group('Equipment', () {
    group('canEquipFood', () {
      test('returns true for consumable item with empty slots', () {
        const equipment = Equipment.empty();
        expect(equipment.canEquipFood(shrimp), isTrue);
      });

      test('returns false for non-consumable item', () {
        const equipment = Equipment.empty();
        expect(equipment.canEquipFood(normalLogs), isFalse);
      });

      test('returns false when all slots are full with different items', () {
        // Create 3 different consumable items to fill all slots
        final equipment = Equipment(
          foodSlots: [
            ItemStack(shrimp, count: 5),
            ItemStack(lobster, count: 5),
            ItemStack(crab, count: 5),
          ],
          selectedFoodSlot: 0,
        );
        // Shrimp is already equipped, so we can add more
        expect(equipment.canEquipFood(shrimp), isTrue);
        // But we can't equip a 4th item
        expect(equipment.canEquipFood(sardine), isFalse);
      });
    });

    group('equipFood', () {
      test('adds consumable to empty slot', () {
        const equipment = Equipment.empty();
        final updated = equipment.equipFood(ItemStack(shrimp, count: 5));

        expect(updated.foodSlots[0]?.item, shrimp);
        expect(updated.foodSlots[0]?.count, 5);
        expect(updated.foodSlots[1], isNull);
        expect(updated.foodSlots[2], isNull);
      });

      test('stacks with existing item in slot', () {
        final equipment = const Equipment.empty().equipFood(
          ItemStack(shrimp, count: 5),
        );
        final updated = equipment.equipFood(ItemStack(shrimp, count: 3));

        expect(updated.foodSlots[0]?.item, shrimp);
        expect(updated.foodSlots[0]?.count, 8);
        expect(updated.foodSlots[1], isNull);
      });

      test('throws ArgumentError for non-consumable item', () {
        const equipment = Equipment.empty();
        expect(
          () => equipment.equipFood(ItemStack(normalLogs, count: 1)),
          throwsArgumentError,
        );
      });

      test('uses first empty slot when item not already equipped', () {
        // Fill slot 0 with shrimp
        var equipment = const Equipment.empty().equipFood(
          ItemStack(shrimp, count: 5),
        );

        // Since we only have one consumable type, verify slot 0 is used
        expect(equipment.foodSlots[0]?.item, shrimp);
        expect(equipment.firstEmptyFoodSlot, 1);
      });
    });
  });
}
