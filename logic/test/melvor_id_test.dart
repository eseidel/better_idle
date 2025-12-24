import 'package:logic/src/data/melvor_id.dart';
import 'package:test/test.dart';

void main() {
  group('MelvorId', () {
    test('namespace extracts namespace from fullId', () {
      final id = MelvorId('melvorD:Woodcutting');
      expect(id.namespace, 'melvorD');
    });

    test('namespace works with different namespaces', () {
      expect(MelvorId('melvorF:SomeAction').namespace, 'melvorF');
      expect(MelvorId('test:Item').namespace, 'test');
      expect(MelvorId('custom:Thing').namespace, 'custom');
    });

    test('localId extracts local part from fullId', () {
      final id = MelvorId('melvorD:Woodcutting');
      expect(id.localId, 'Woodcutting');
    });

    test('localId works with underscores', () {
      final id = MelvorId('melvorD:Normal_Logs');
      expect(id.localId, 'Normal_Logs');
    });

    test('name converts underscores to spaces', () {
      expect(MelvorId('melvorD:Normal_Logs').name, 'Normal Logs');
      expect(MelvorId('melvorD:Raw_Shrimp').name, 'Raw Shrimp');
      expect(MelvorId('melvorD:Woodcutting').name, 'Woodcutting');
    });

    test('equality with same fullId', () {
      final id1 = MelvorId('melvorD:Woodcutting');
      final id2 = MelvorId('melvorD:Woodcutting');
      expect(id1, equals(id2));
      expect(id1.hashCode, equals(id2.hashCode));
    });

    test('inequality with different fullId', () {
      final id1 = MelvorId('melvorD:Woodcutting');
      final id2 = MelvorId('melvorD:Fishing');
      expect(id1, isNot(equals(id2)));
    });

    test('inequality with different namespace', () {
      final id1 = MelvorId('melvorD:Woodcutting');
      final id2 = MelvorId('melvorF:Woodcutting');
      expect(id1, isNot(equals(id2)));
    });

    test('toString returns fullId', () {
      final id = MelvorId('melvorD:Woodcutting');
      expect(id.toString(), 'melvorD:Woodcutting');
    });

    test('fromJson creates MelvorId', () {
      final id = MelvorId.fromJson('melvorD:Woodcutting');
      expect(id.fullId, 'melvorD:Woodcutting');
    });

    test('toJson returns fullId', () {
      final id = MelvorId('melvorD:Woodcutting');
      expect(id.toJson(), 'melvorD:Woodcutting');
    });

    test('maybeFromJson returns null for null input', () {
      expect(MelvorId.maybeFromJson(null), isNull);
    });

    test('maybeFromJson returns MelvorId for valid input', () {
      final id = MelvorId.maybeFromJson('melvorD:Woodcutting');
      expect(id, isNotNull);
      expect(id!.fullId, 'melvorD:Woodcutting');
    });

    test('fromJsonWithNamespace uses existing namespace', () {
      final id = MelvorId.fromJsonWithNamespace(
        'melvorF:SomeAction',
        defaultNamespace: 'melvorD',
      );
      expect(id.fullId, 'melvorF:SomeAction');
      expect(id.namespace, 'melvorF');
    });

    test('fromJsonWithNamespace adds namespace when missing', () {
      final id = MelvorId.fromJsonWithNamespace(
        'Woodcutting',
        defaultNamespace: 'melvorD',
      );
      expect(id.fullId, 'melvorD:Woodcutting');
      expect(id.namespace, 'melvorD');
    });

    test('fromName converts name to MelvorId', () {
      final id = MelvorId.fromName('Normal Logs');
      expect(id.fullId, 'melvorD:Normal_Logs');
      expect(id.namespace, 'melvorD');
      expect(id.localId, 'Normal_Logs');
    });
  });
}
