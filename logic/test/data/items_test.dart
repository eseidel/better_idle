import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
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
      final entry1 = DropTableEntry.test('Normal Logs', max: 5, weight: 10);
      final entry2 = DropTableEntry.test('Normal Logs', max: 5, weight: 10);
      final different = DropTableEntry.test('Oak Logs', max: 5, weight: 10);

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
      final entry = DropTableEntry.test('Test', min: 2, max: 10);

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
