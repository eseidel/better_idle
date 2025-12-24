import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierScope equality', () {
    test('two empty scopes are equal', () {
      const scope1 = ModifierScope();
      const scope2 = ModifierScope();
      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));
    });

    test('scopes with same skillId are equal', () {
      final scope1 = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      final scope2 = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));
    });

    test('scopes with different skillId are not equal', () {
      final scope1 = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      final scope2 = ModifierScope(skillId: MelvorId('melvorD:Fishing'));
      expect(scope1, isNot(equals(scope2)));
    });

    test('scopes with same actionId are equal', () {
      final scope1 = ModifierScope(actionId: MelvorId('melvorD:Oak'));
      final scope2 = ModifierScope(actionId: MelvorId('melvorD:Oak'));
      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));
    });

    test('scopes with different actionId are not equal', () {
      final scope1 = ModifierScope(actionId: MelvorId('melvorD:Oak'));
      final scope2 = ModifierScope(actionId: MelvorId('melvorD:Willow'));
      expect(scope1, isNot(equals(scope2)));
    });

    test('scopes with same multiple fields are equal', () {
      final scope1 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
        realmId: MelvorId('melvorD:Melvor'),
      );
      final scope2 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
        realmId: MelvorId('melvorD:Melvor'),
      );
      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));
    });

    test('scopes with partially matching fields are not equal', () {
      final scope1 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
      );
      final scope2 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
      );
      expect(scope1, isNot(equals(scope2)));
    });

    test('scope with null field differs from scope with value', () {
      final scope1 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
      );
      final scope2 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
      );
      expect(scope1, isNot(equals(scope2)));
    });

    test('all scope fields can be compared', () {
      final scope1 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
        realmId: MelvorId('melvorD:Melvor'),
        categoryId: MelvorId('melvorD:Trees'),
        subcategoryId: MelvorId('melvorD:Normal'),
        itemId: MelvorId('melvorD:Oak_Logs'),
        currencyId: MelvorId('melvorD:GP'),
        damageTypeId: MelvorId('melvorD:Normal'),
        effectGroupId: MelvorId('melvorD:Burn'),
      );
      final scope2 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
        realmId: MelvorId('melvorD:Melvor'),
        categoryId: MelvorId('melvorD:Trees'),
        subcategoryId: MelvorId('melvorD:Normal'),
        itemId: MelvorId('melvorD:Oak_Logs'),
        currencyId: MelvorId('melvorD:GP'),
        damageTypeId: MelvorId('melvorD:Normal'),
        effectGroupId: MelvorId('melvorD:Burn'),
      );
      expect(scope1, equals(scope2));
      expect(scope1.hashCode, equals(scope2.hashCode));

      // Changing any field should make them unequal
      final scope3 = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
        actionId: MelvorId('melvorD:Oak'),
        realmId: MelvorId('melvorD:Melvor'),
        categoryId: MelvorId('melvorD:Trees'),
        subcategoryId: MelvorId('melvorD:Normal'),
        itemId: MelvorId('melvorD:Oak_Logs'),
        currencyId: MelvorId('melvorD:GP'),
        damageTypeId: MelvorId('melvorD:Normal'),
        effectGroupId: MelvorId('melvorD:Poison'), // Different
      );
      expect(scope1, isNot(equals(scope3)));
    });
  });

  group('ModifierScope.isGlobal', () {
    test('empty scope is global', () {
      const scope = ModifierScope();
      expect(scope.isGlobal, isTrue);
    });

    test('scope with any field set is not global', () {
      final scopeWithSkill = ModifierScope(
        skillId: MelvorId('melvorD:Woodcutting'),
      );
      expect(scopeWithSkill.isGlobal, isFalse);

      final scopeWithAction = ModifierScope(
        actionId: MelvorId('melvorD:Oak'),
      );
      expect(scopeWithAction.isGlobal, isFalse);

      final scopeWithRealm = ModifierScope(
        realmId: MelvorId('melvorD:Melvor'),
      );
      expect(scopeWithRealm.isGlobal, isFalse);
    });
  });

  group('ModifierScope.appliesToSkill', () {
    test('global scope applies to any skill', () {
      const scope = ModifierScope();
      expect(scope.appliesToSkill(MelvorId('melvorD:Woodcutting')), isTrue);
      expect(scope.appliesToSkill(MelvorId('melvorD:Fishing')), isTrue);
    });

    test('matching skillId applies', () {
      final scope = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      expect(scope.appliesToSkill(MelvorId('melvorD:Woodcutting')), isTrue);
    });

    test('non-matching skillId does not apply', () {
      final scope = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      expect(scope.appliesToSkill(MelvorId('melvorD:Fishing')), isFalse);
    });

    test('scope with only actionId applies to any skill', () {
      final scope = ModifierScope(actionId: MelvorId('melvorD:Oak'));
      expect(scope.appliesToSkill(MelvorId('melvorD:Woodcutting')), isTrue);
      expect(scope.appliesToSkill(MelvorId('melvorD:Fishing')), isTrue);
    });

    test('autoScopeToAction false makes scope apply globally', () {
      final scope = ModifierScope(
        skillId: MelvorId('melvorD:Firemaking'),
        actionId: MelvorId('melvorD:Normal_Logs'),
      );
      // With autoScopeToAction true (default), only applies to Firemaking
      expect(scope.appliesToSkill(MelvorId('melvorD:Firemaking')), isTrue);
      expect(scope.appliesToSkill(MelvorId('melvorD:Woodcutting')), isFalse);

      // With autoScopeToAction false, applies to all skills
      expect(
        scope.appliesToSkill(
          MelvorId('melvorD:Firemaking'),
          autoScopeToAction: false,
        ),
        isTrue,
      );
      expect(
        scope.appliesToSkill(
          MelvorId('melvorD:Woodcutting'),
          autoScopeToAction: false,
        ),
        isTrue,
      );
    });
  });

  group('ModifierScope.fromJson', () {
    test('parses empty json as global scope', () {
      final scope = ModifierScope.fromJson({}, namespace: 'melvorD');
      expect(scope.isGlobal, isTrue);
    });

    test('parses skillID', () {
      final scope = ModifierScope.fromJson({
        'skillID': 'melvorD:Woodcutting',
      }, namespace: 'melvorD');
      expect(scope.skillId, equals(MelvorId('melvorD:Woodcutting')));
    });

    test('adds namespace to unqualified ids', () {
      final scope = ModifierScope.fromJson({
        'skillID': 'Woodcutting',
      }, namespace: 'melvorD');
      expect(scope.skillId, equals(MelvorId('melvorD:Woodcutting')));
    });

    test('parses all scope keys', () {
      final scope = ModifierScope.fromJson({
        'skillID': 'melvorD:Woodcutting',
        'actionID': 'melvorD:Oak',
        'realmID': 'melvorD:Melvor',
        'categoryID': 'melvorD:Trees',
        'subcategoryID': 'melvorD:Normal',
        'itemID': 'melvorD:Oak_Logs',
        'currencyID': 'melvorD:GP',
        'damageTypeID': 'melvorD:Normal',
        'effectGroupID': 'melvorD:Burn',
      }, namespace: 'melvorD');

      expect(scope.skillId, equals(MelvorId('melvorD:Woodcutting')));
      expect(scope.actionId, equals(MelvorId('melvorD:Oak')));
      expect(scope.realmId, equals(MelvorId('melvorD:Melvor')));
      expect(scope.categoryId, equals(MelvorId('melvorD:Trees')));
      expect(scope.subcategoryId, equals(MelvorId('melvorD:Normal')));
      expect(scope.itemId, equals(MelvorId('melvorD:Oak_Logs')));
      expect(scope.currencyId, equals(MelvorId('melvorD:GP')));
      expect(scope.damageTypeId, equals(MelvorId('melvorD:Normal')));
      expect(scope.effectGroupId, equals(MelvorId('melvorD:Burn')));
    });
  });
}
