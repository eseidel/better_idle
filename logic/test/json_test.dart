import 'package:logic/src/json.dart';
import 'package:test/test.dart';

void main() {
  group('maybeList', () {
    test('returns null for null input', () {
      expect(maybeList<int>(null, (e) => e['value'] as int), isNull);
    });

    test('parses list of objects', () {
      final json = [
        {'value': 1},
        {'value': 2},
        {'value': 3},
      ];
      final result = maybeList<int>(json, (e) => e['value'] as int);
      expect(result, [1, 2, 3]);
    });
  });

  group('maybeMap', () {
    test('returns null for null input', () {
      expect(maybeMap<String, int>(null), isNull);
    });

    test('parses map with default key/value conversion', () {
      final json = {'a': 1, 'b': 2};
      final result = maybeMap<String, int>(json);
      expect(result, {'a': 1, 'b': 2});
    });

    test('parses map with custom key conversion', () {
      final json = {'1': 'one', '2': 'two'};
      final result = maybeMap<int, String>(json, toKey: int.parse);
      expect(result, {1: 'one', 2: 'two'});
    });

    test('parses map with custom value conversion', () {
      final json = {'a': '1', 'b': '2'};
      final result = maybeMap<String, int>(
        json,
        toValue: (v) => int.parse(v as String),
      );
      expect(result, {'a': 1, 'b': 2});
    });

    test('parses map with both custom conversions', () {
      final json = {'1': '10', '2': '20'};
      final result = maybeMap<int, int>(
        json,
        toKey: int.parse,
        toValue: (v) => int.parse(v as String),
      );
      expect(result, {1: 10, 2: 20});
    });
  });
}
