import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('SmithingCategory', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'Bars',
        'name': 'Bars',
        'media': 'assets/media/bank/bronze_bar.png',
      };
      final category = SmithingCategory.fromJson(json, namespace: 'melvorD');
      expect(category.id, const MelvorId('melvorD:Bars'));
      expect(category.name, 'Bars');
      expect(category.media, 'assets/media/bank/bronze_bar.png');
    });

    test('toString returns name', () {
      const category = SmithingCategory(
        id: MelvorId('melvorD:Bars'),
        name: 'Bars',
        media: 'test.png',
      );
      expect(category.toString(), 'Bars');
    });
  });

  group('SmithingAction', () {
    test('Bronze Bar has correct properties', () {
      final action =
          testRegistries.smithingAction('Bronze Bar') as SmithingAction;
      expect(action.skill, Skill.smithing);
      expect(action.productId.localId, 'Bronze_Bar');
      expect(action.inputs, isNotEmpty);
    });
  });

  group('SmithingRegistry', () {
    test('actions list is not empty', () {
      expect(testRegistries.smithing.actions, isNotEmpty);
    });

    test('categories list is not empty', () {
      expect(testRegistries.smithing.categories, isNotEmpty);
    });

    test('byId returns action for known id', () {
      final actions = testRegistries.smithing.actions;
      final firstAction = actions.first;
      expect(
        testRegistries.smithing.byId(firstAction.id.localId),
        equals(firstAction),
      );
    });

    test('byId returns null for unknown id', () {
      expect(
        testRegistries.smithing.byId(const MelvorId('melvorD:Unknown')),
        isNull,
      );
    });

    test('categoryById returns category for known id', () {
      final categories = testRegistries.smithing.categories;
      final firstCategory = categories.first;
      expect(
        testRegistries.smithing.categoryById(firstCategory.id),
        equals(firstCategory),
      );
    });

    test('categoryById returns null for unknown id', () {
      expect(
        testRegistries.smithing.categoryById(const MelvorId('melvorD:Unknown')),
        isNull,
      );
    });
  });
}
