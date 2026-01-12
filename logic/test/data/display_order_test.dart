import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('DisplayOrderInsertType', () {
    test('fromString parses Start', () {
      expect(
        DisplayOrderInsertType.fromString('Start'),
        DisplayOrderInsertType.start,
      );
    });

    test('fromString parses After', () {
      expect(
        DisplayOrderInsertType.fromString('After'),
        DisplayOrderInsertType.after,
      );
    });

    test('fromString throws on unknown type', () {
      expect(
        () => DisplayOrderInsertType.fromString('Unknown'),
        throwsArgumentError,
      );
    });
  });

  group('DisplayOrderEntry', () {
    test('fromJson parses Start entry', () {
      final json = {
        'insertAt': 'Start',
        'ids': ['Normal_Logs', 'Oak_Logs', 'Willow_Logs'],
      };

      final entry = DisplayOrderEntry.fromJson(json, namespace: 'melvorD');

      expect(entry.insertAt, DisplayOrderInsertType.start);
      expect(entry.afterId, isNull);
      expect(entry.ids.length, 3);
      expect(entry.ids[0], const MelvorId('melvorD:Normal_Logs'));
      expect(entry.ids[1], const MelvorId('melvorD:Oak_Logs'));
      expect(entry.ids[2], const MelvorId('melvorD:Willow_Logs'));
    });

    test('fromJson parses After entry', () {
      final json = {
        'insertAt': 'After',
        'afterID': 'melvorD:Redwood_Logs',
        'ids': ['Ash'],
      };

      final entry = DisplayOrderEntry.fromJson(json, namespace: 'melvorF');

      expect(entry.insertAt, DisplayOrderInsertType.after);
      expect(entry.afterId, const MelvorId('melvorD:Redwood_Logs'));
      expect(entry.ids.length, 1);
      expect(entry.ids[0], const MelvorId('melvorF:Ash'));
    });

    test('fromJson handles fully qualified IDs in ids list', () {
      final json = {
        'insertAt': 'After',
        'afterID': 'melvorD:Sword',
        'ids': ['melvorF:Dragon_Claw', 'Ancient_Claw'],
      };

      final entry = DisplayOrderEntry.fromJson(json, namespace: 'melvorF');

      expect(entry.ids[0], const MelvorId('melvorF:Dragon_Claw'));
      expect(entry.ids[1], const MelvorId('melvorF:Ancient_Claw'));
    });
  });

  group('computeDisplayOrder', () {
    test('processes Start entry as base order', () {
      final entries = [
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.start,
          ids: [
            MelvorId('melvorD:A'),
            MelvorId('melvorD:B'),
            MelvorId('melvorD:C'),
          ],
        ),
      ];

      final result = computeDisplayOrder(entries);

      expect(result, [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorD:B'),
        const MelvorId('melvorD:C'),
      ]);
    });

    test('inserts After entry items after reference', () {
      final entries = [
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.start,
          ids: [
            MelvorId('melvorD:A'),
            MelvorId('melvorD:B'),
            MelvorId('melvorD:C'),
          ],
        ),
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [MelvorId('melvorF:X')],
        ),
      ];

      final result = computeDisplayOrder(entries);

      expect(result, [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorF:X'), // Inserted after A
        const MelvorId('melvorD:B'),
        const MelvorId('melvorD:C'),
      ]);
    });

    test('inserts multiple items in order', () {
      final entries = [
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.start,
          ids: [MelvorId('melvorD:A'), MelvorId('melvorD:B')],
        ),
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [
            MelvorId('melvorF:X'),
            MelvorId('melvorF:Y'),
            MelvorId('melvorF:Z'),
          ],
        ),
      ];

      final result = computeDisplayOrder(entries);

      expect(result, [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorF:X'),
        const MelvorId('melvorF:Y'),
        const MelvorId('melvorF:Z'),
        const MelvorId('melvorD:B'),
      ]);
    });

    test('handles chained After entries', () {
      final entries = [
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.start,
          ids: [MelvorId('melvorD:A'), MelvorId('melvorD:B')],
        ),
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.after,
          afterId: MelvorId('melvorD:A'),
          ids: [MelvorId('melvorF:X')],
        ),
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.after,
          afterId: MelvorId('melvorF:X'),
          ids: [MelvorId('melvorF:Y')],
        ),
      ];

      final result = computeDisplayOrder(entries);

      expect(result, [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorF:X'),
        const MelvorId('melvorF:Y'), // Inserted after X (inserted after A)
        const MelvorId('melvorD:B'),
      ]);
    });

    test('appends to end when afterId not found', () {
      final entries = [
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.start,
          ids: [MelvorId('melvorD:A')],
        ),
        const DisplayOrderEntry(
          insertAt: DisplayOrderInsertType.after,
          afterId: MelvorId('melvorD:NotFound'),
          ids: [MelvorId('melvorF:X')],
        ),
      ];

      final result = computeDisplayOrder(entries);

      expect(result, [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorF:X'), // Appended to end
      ]);
    });

    test('handles empty entries', () {
      final result = computeDisplayOrder(<DisplayOrderEntry>[]);
      expect(result, isEmpty);
    });
  });

  group('buildDisplayOrderIndex', () {
    test('creates index map from sort order', () {
      final sortOrder = [
        const MelvorId('melvorD:A'),
        const MelvorId('melvorD:B'),
        const MelvorId('melvorD:C'),
      ];

      final index = buildDisplayOrderIndex(sortOrder);

      expect(index[const MelvorId('melvorD:A')], 0);
      expect(index[const MelvorId('melvorD:B')], 1);
      expect(index[const MelvorId('melvorD:C')], 2);
      expect(index[const MelvorId('melvorD:NotInList')], isNull);
    });

    test('handles empty list', () {
      final index = buildDisplayOrderIndex(<MelvorId>[]);
      expect(index, isEmpty);
    });
  });
}
