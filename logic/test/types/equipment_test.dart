import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

/// A predictable random number generator for testing.
class FakeRandom implements Random {
  FakeRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  int nextInt(int max) {
    final value = _values[_index % _values.length];
    _index++;
    return value % max;
  }

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000.0;
}

void main() {
  late Item shrimp; // Consumable (healsFor: 30)
  late Item lobster; // Consumable (healsFor: 110)
  late Item crab; // Consumable (healsFor: 150)
  late Item sardine; // Consumable (healsFor: 40)
  late Item normalLogs; // Non-consumable

  setUpAll(() async {
    await loadTestRegistries();
    shrimp = testItems.byName('Shrimp');
    lobster = testItems.byName('Lobster');
    crab = testItems.byName('Crab');
    sardine = testItems.byName('Sardine');
    normalLogs = testItems.byName('Normal Logs');
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
        final equipment = const Equipment.empty().equipFood(
          ItemStack(shrimp, count: 5),
        );

        // Since we only have one consumable type, verify slot 0 is used
        expect(equipment.foodSlots[0]?.item, shrimp);
        expect(equipment.firstEmptyFoodSlot, 1);
      });
    });

    group('applyDeathPenalty', () {
      late Item bronzeSword;
      late Item bronzeHelmet;

      setUpAll(() async {
        bronzeSword = testItems.byName('Bronze Sword');
        bronzeHelmet = testItems.byName('Bronze Helmet');
      });

      test('returns wasLucky=true when rolled slot is empty', () {
        const equipment = Equipment.empty();
        // Roll slot 0 (weapon), which is empty
        final rng = FakeRandom([0]);
        final result = equipment.applyDeathPenalty(rng);

        expect(result.wasLucky, isTrue);
        expect(result.itemLost, isNull);
        expect(result.slotRolled, EquipmentSlot.weapon);
        expect(result.equipment, equipment);
      });

      test('removes item from equipment when rolled slot has item', () {
        // Equip a sword in the weapon slot
        final (equipment, _) = const Equipment.empty().equipGear(
          bronzeSword,
          EquipmentSlot.weapon,
        );

        // Roll slot 0 (weapon)
        final rng = FakeRandom([0]);
        final result = equipment.applyDeathPenalty(rng);

        expect(result.wasLucky, isFalse);
        expect(result.itemLost?.item, bronzeSword);
        expect(result.itemLost?.count, 1);
        expect(result.slotRolled, EquipmentSlot.weapon);
        // Item should be removed from equipment
        expect(result.equipment.gearInSlot(EquipmentSlot.weapon), isNull);
      });

      test('only removes item from rolled slot, keeps others', () {
        // Equip sword and helmet
        var (equipment, _) = const Equipment.empty().equipGear(
          bronzeSword,
          EquipmentSlot.weapon,
        );
        (equipment, _) = equipment.equipGear(
          bronzeHelmet,
          EquipmentSlot.helmet,
        );

        // Roll slot 2 (helmet)
        final rng = FakeRandom([2]);
        final result = equipment.applyDeathPenalty(rng);

        expect(result.wasLucky, isFalse);
        expect(result.itemLost?.item, bronzeHelmet);
        expect(result.slotRolled, EquipmentSlot.helmet);
        // Helmet should be removed, sword should remain
        expect(result.equipment.gearInSlot(EquipmentSlot.helmet), isNull);
        expect(result.equipment.gearInSlot(EquipmentSlot.weapon), bronzeSword);
      });

      test('does not affect food slots', () {
        // Equip food and gear
        var equipment = const Equipment.empty().equipFood(
          ItemStack(shrimp, count: 10),
        );
        final (updatedEquipment, _) = equipment.equipGear(
          bronzeSword,
          EquipmentSlot.weapon,
        );
        equipment = updatedEquipment;

        // Roll weapon slot (0)
        final rng = FakeRandom([0]);
        final result = equipment.applyDeathPenalty(rng);

        // Sword lost, but food remains
        expect(result.itemLost?.item, bronzeSword);
        expect(result.equipment.foodSlots[0]?.item, shrimp);
        expect(result.equipment.foodSlots[0]?.count, 10);
      });
    });
  });
}
