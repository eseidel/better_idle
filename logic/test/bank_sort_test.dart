import 'package:logic/logic.dart';
import 'package:logic/src/data/bank_sort.dart';
import 'package:test/test.dart';

void main() {
  group('BankSortInsertType', () {
    test('fromString parses Start', () {
      expect(BankSortInsertType.fromString('Start'), BankSortInsertType.start);
    });

    test('fromString parses After', () {
      expect(BankSortInsertType.fromString('After'), BankSortInsertType.after);
    });

    test('fromString throws on unknown type', () {
      expect(
        () => BankSortInsertType.fromString('Unknown'),
        throwsArgumentError,
      );
    });
  });

  group('BankSortEntry', () {
    test('fromJson parses Start entry', () {
      final json = {
        'insertAt': 'Start',
        'ids': ['Normal_Logs', 'Oak_Logs', 'Willow_Logs'],
      };

      final entry = BankSortEntry.fromJson(json, namespace: 'melvorD');

      expect(entry.insertAt, BankSortInsertType.start);
      expect(entry.afterId, isNull);
      expect(entry.ids.length, 3);
      expect(entry.ids[0], MelvorId('melvorD:Normal_Logs'));
      expect(entry.ids[1], MelvorId('melvorD:Oak_Logs'));
      expect(entry.ids[2], MelvorId('melvorD:Willow_Logs'));
    });

    test('fromJson parses After entry', () {
      final json = {
        'insertAt': 'After',
        'afterID': 'melvorD:Redwood_Logs',
        'ids': ['Ash'],
      };

      final entry = BankSortEntry.fromJson(json, namespace: 'melvorF');

      expect(entry.insertAt, BankSortInsertType.after);
      expect(entry.afterId, MelvorId('melvorD:Redwood_Logs'));
      expect(entry.ids.length, 1);
      expect(entry.ids[0], MelvorId('melvorF:Ash'));
    });

    test('fromJson handles fully qualified IDs in ids list', () {
      final json = {
        'insertAt': 'After',
        'afterID': 'melvorD:Sword',
        'ids': ['melvorF:Dragon_Claw', 'Ancient_Claw'],
      };

      final entry = BankSortEntry.fromJson(json, namespace: 'melvorF');

      expect(entry.ids[0], MelvorId('melvorF:Dragon_Claw'));
      expect(entry.ids[1], MelvorId('melvorF:Ancient_Claw'));
    });
  });

  group('computeBankSortOrder', () {
    test('processes Start entry as base order', () {
      final entries = [
        BankSortEntry(
          insertAt: BankSortInsertType.start,
          ids: [
            MelvorId('melvorD:A'),
            MelvorId('melvorD:B'),
            MelvorId('melvorD:C'),
          ],
        ),
      ];

      final result = computeBankSortOrder(entries);

      expect(result, [
        MelvorId('melvorD:A'),
        MelvorId('melvorD:B'),
        MelvorId('melvorD:C'),
      ]);
    });

    test('inserts After entry items after reference', () {
      final entries = [
        BankSortEntry(
          insertAt: BankSortInsertType.start,
          ids: [
            MelvorId('melvorD:A'),
            MelvorId('melvorD:B'),
            MelvorId('melvorD:C'),
          ],
        ),
        BankSortEntry(
          insertAt: BankSortInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [MelvorId('melvorF:X')],
        ),
      ];

      final result = computeBankSortOrder(entries);

      expect(result, [
        MelvorId('melvorD:A'),
        MelvorId('melvorF:X'), // Inserted after A
        MelvorId('melvorD:B'),
        MelvorId('melvorD:C'),
      ]);
    });

    test('inserts multiple items in order', () {
      final entries = [
        BankSortEntry(
          insertAt: BankSortInsertType.start,
          ids: [MelvorId('melvorD:A'), MelvorId('melvorD:B')],
        ),
        BankSortEntry(
          insertAt: BankSortInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [
            MelvorId('melvorF:X'),
            MelvorId('melvorF:Y'),
            MelvorId('melvorF:Z'),
          ],
        ),
      ];

      final result = computeBankSortOrder(entries);

      expect(result, [
        MelvorId('melvorD:A'),
        MelvorId('melvorF:X'),
        MelvorId('melvorF:Y'),
        MelvorId('melvorF:Z'),
        MelvorId('melvorD:B'),
      ]);
    });

    test('handles chained After entries', () {
      final entries = [
        BankSortEntry(
          insertAt: BankSortInsertType.start,
          ids: [MelvorId('melvorD:A'), MelvorId('melvorD:B')],
        ),
        BankSortEntry(
          insertAt: BankSortInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [MelvorId('melvorF:X')],
        ),
        BankSortEntry(
          insertAt: BankSortInsertType.after,
          afterId: MelvorId('melvorF:X'),
          ids: [MelvorId('melvorF:Y')],
        ),
      ];

      final result = computeBankSortOrder(entries);

      expect(result, [
        MelvorId('melvorD:A'),
        MelvorId('melvorF:X'),
        MelvorId('melvorF:Y'), // Inserted after X (which was inserted after A)
        MelvorId('melvorD:B'),
      ]);
    });

    test('appends to end when afterId not found', () {
      final entries = [
        BankSortEntry(
          insertAt: BankSortInsertType.start,
          ids: [MelvorId('melvorD:A')],
        ),
        BankSortEntry(
          insertAt: BankSortInsertType.after,
          afterId: MelvorId('melvorD:NotFound'),
          ids: [MelvorId('melvorF:X')],
        ),
      ];

      final result = computeBankSortOrder(entries);

      expect(result, [
        MelvorId('melvorD:A'),
        MelvorId('melvorF:X'), // Appended to end
      ]);
    });

    test('handles empty entries', () {
      final result = computeBankSortOrder([]);
      expect(result, isEmpty);
    });
  });

  group('buildBankSortIndex', () {
    test('creates index map from sort order', () {
      final sortOrder = [
        MelvorId('melvorD:A'),
        MelvorId('melvorD:B'),
        MelvorId('melvorD:C'),
      ];

      final index = buildBankSortIndex(sortOrder);

      expect(index[MelvorId('melvorD:A')], 0);
      expect(index[MelvorId('melvorD:B')], 1);
      expect(index[MelvorId('melvorD:C')], 2);
      expect(index[MelvorId('melvorD:NotInList')], isNull);
    });

    test('handles empty list', () {
      final index = buildBankSortIndex([]);
      expect(index, isEmpty);
    });
  });
}
