import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('EquipmentStatModifier', () {
    test('offensive and defensive are mutually exclusive and exhaustive', () {
      final offensive =
          EquipmentStatModifier.values.where((m) => m.isOffensive).toSet();
      final defensive =
          EquipmentStatModifier.values.where((m) => !m.isOffensive).toSet();
      expect(offensive.intersection(defensive), isEmpty);
      expect(
        offensive.length + defensive.length,
        EquipmentStatModifier.values.length,
      );
    });

    test('expected offensive stats', () {
      expect(EquipmentStatModifier.equipmentAttackSpeed.isOffensive, isTrue);
      expect(EquipmentStatModifier.flatStabAttackBonus.isOffensive, isTrue);
      expect(EquipmentStatModifier.flatMeleeStrengthBonus.isOffensive, isTrue);
      expect(EquipmentStatModifier.magicDamageBonus.isOffensive, isTrue);
    });

    test('expected defensive stats', () {
      expect(EquipmentStatModifier.flatMeleeDefenceBonus.isOffensive, isFalse);
      expect(
        EquipmentStatModifier.flatRangedDefenceBonus.isOffensive,
        isFalse,
      );
      expect(EquipmentStatModifier.flatMagicDefenceBonus.isOffensive, isFalse);
      expect(EquipmentStatModifier.flatResistance.isOffensive, isFalse);
    });

    test('all values have a non-empty displayName', () {
      for (final modifier in EquipmentStatModifier.values) {
        expect(modifier.displayName, isNotEmpty, reason: modifier.name);
      }
    });
  });

  group('Item', () {
    test('open throws StateError when not openable', () {
      final item = Item.test('Test Item', gp: 10);
      expect(item.isOpenable, isFalse);
      expect(() => item.open(testItems, Random()), throwsA(isA<StateError>()));
    });
  });

  group('ItemRegistry', () {
    test('byName throws StateError for non-existent item', () {
      expect(
        () => testItems.byName('Non Existent Item'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DropTableEntry', () {
    test('equality compares all fields', () {
      const entry1 = DropTableEntry(
        itemID: MelvorId('melvorD:Normal_Logs'),
        minQuantity: 1,
        maxQuantity: 5,
        weight: 10,
      );
      const entry2 = DropTableEntry(
        itemID: MelvorId('melvorD:Normal_Logs'),
        minQuantity: 1,
        maxQuantity: 5,
        weight: 10,
      );
      const different = DropTableEntry(
        itemID: MelvorId('melvorD:Oak_Logs'),
        minQuantity: 1,
        maxQuantity: 5,
        weight: 10,
      );

      expect(entry1, equals(entry2));
      expect(entry1, isNot(equals(different)));
    });
    test('name extracts item name from itemID', () {
      const entry = DropTableEntry(
        itemID: MelvorId('melvorD:Normal_Logs'),
        minQuantity: 1,
        maxQuantity: 5,
        weight: 10,
      );

      expect(entry.itemID.name, 'Normal Logs');
    });

    test('expectedCount returns average of min and max', () {
      const entry = DropTableEntry(
        itemID: MelvorId('melvorD:Test'),
        minQuantity: 2,
        maxQuantity: 10,
        weight: 1,
      );

      expect(entry.expectedCount, 6.0);
    });

    test('fromJson parses correctly', () {
      final json = {
        'itemID': 'melvorD:Oak_Logs',
        'minQuantity': 3,
        'maxQuantity': 7,
        'weight': 25,
      };

      final entry = DropTableEntry.fromJson(json);

      expect(entry.itemID, const MelvorId('melvorD:Oak_Logs'));
      expect(entry.minQuantity, 3);
      expect(entry.maxQuantity, 7);
      expect(entry.weight, 25);
    });
  });
}
