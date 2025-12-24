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
      final scope2 = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      expect(scope1, isNot(equals(scope2)));
    });

    test('scope with null field differs from scope with value', () {
      final scope1 = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
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

      final scopeWithAction = ModifierScope(actionId: MelvorId('melvorD:Oak'));
      expect(scopeWithAction.isGlobal, isFalse);

      final scopeWithRealm = ModifierScope(realmId: MelvorId('melvorD:Melvor'));
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

  group('ModifierEntry', () {
    test('entries with same value and no scope are equal', () {
      const entry1 = ModifierEntry(value: 5);
      const entry2 = ModifierEntry(value: 5);
      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
    });

    test('entries with different values are not equal', () {
      const entry1 = ModifierEntry(value: 5);
      const entry2 = ModifierEntry(value: 10);
      expect(entry1, isNot(equals(entry2)));
    });

    test('entries with same value and scope are equal', () {
      final scope = ModifierScope(skillId: MelvorId('melvorD:Woodcutting'));
      final entry1 = ModifierEntry(value: 5, scope: scope);
      final entry2 = ModifierEntry(value: 5, scope: scope);
      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
    });

    test('entries with same value but different scope are not equal', () {
      final entry1 = ModifierEntry(
        value: 5,
        scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
      );
      final entry2 = ModifierEntry(
        value: 5,
        scope: ModifierScope(skillId: MelvorId('melvorD:Fishing')),
      );
      expect(entry1, isNot(equals(entry2)));
    });

    test('entry with scope differs from entry without scope', () {
      const entry1 = ModifierEntry(value: 5);
      final entry2 = ModifierEntry(
        value: 5,
        scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
      );
      expect(entry1, isNot(equals(entry2)));
    });

    test('appliesToSkill with null scope returns true for any skill', () {
      const entry = ModifierEntry(value: 5);
      expect(entry.appliesToSkill(MelvorId('melvorD:Woodcutting')), isTrue);
      expect(entry.appliesToSkill(MelvorId('melvorD:Fishing')), isTrue);
    });

    test('appliesToSkill delegates to scope', () {
      final entry = ModifierEntry(
        value: 5,
        scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
      );
      expect(entry.appliesToSkill(MelvorId('melvorD:Woodcutting')), isTrue);
      expect(entry.appliesToSkill(MelvorId('melvorD:Fishing')), isFalse);
    });
  });

  group('ModifierData', () {
    test('equality with same name and entries', () {
      const data1 = ModifierData(
        name: 'skillXP',
        entries: [ModifierEntry(value: 5)],
      );
      const data2 = ModifierData(
        name: 'skillXP',
        entries: [ModifierEntry(value: 5)],
      );
      expect(data1, equals(data2));
      expect(data1.hashCode, equals(data2.hashCode));
    });

    test('inequality with different name', () {
      const data1 = ModifierData(
        name: 'skillXP',
        entries: [ModifierEntry(value: 5)],
      );
      const data2 = ModifierData(
        name: 'skillInterval',
        entries: [ModifierEntry(value: 5)],
      );
      expect(data1, isNot(equals(data2)));
    });

    test('isScalar true for single unscoped entry', () {
      const data = ModifierData(
        name: 'skillXP',
        entries: [ModifierEntry(value: 5)],
      );
      expect(data.isScalar, isTrue);
    });

    test('isScalar false for multiple entries', () {
      const data = ModifierData(
        name: 'skillXP',
        entries: [ModifierEntry(value: 5), ModifierEntry(value: 3)],
      );
      expect(data.isScalar, isFalse);
    });

    test('isScalar false for scoped entry', () {
      final data = ModifierData(
        name: 'skillXP',
        entries: [
          ModifierEntry(
            value: 5,
            scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
          ),
        ],
      );
      expect(data.isScalar, isFalse);
    });

    test('totalValue sums all entries', () {
      const data = ModifierData(
        name: 'skillXP',
        entries: [
          ModifierEntry(value: 5),
          ModifierEntry(value: 3),
          ModifierEntry(value: 2),
        ],
      );
      expect(data.totalValue, 10);
    });
  });

  group('ModifierDataSet', () {
    test('equality with same modifiers', () {
      const set1 = ModifierDataSet([
        ModifierData(name: 'skillXP', entries: [ModifierEntry(value: 5)]),
      ]);
      const set2 = ModifierDataSet([
        ModifierData(name: 'skillXP', entries: [ModifierEntry(value: 5)]),
      ]);
      expect(set1, equals(set2));
      expect(set1.hashCode, equals(set2.hashCode));
    });

    test('byName returns modifier when found', () {
      const set = ModifierDataSet([
        ModifierData(name: 'skillXP', entries: [ModifierEntry(value: 5)]),
        ModifierData(
          name: 'skillInterval',
          entries: [ModifierEntry(value: -3)],
        ),
      ]);
      final mod = set.byName('skillXP');
      expect(mod, isNotNull);
      expect(mod!.name, 'skillXP');
    });

    test('byName returns null when not found', () {
      const set = ModifierDataSet([
        ModifierData(name: 'skillXP', entries: [ModifierEntry(value: 5)]),
      ]);
      expect(set.byName('skillInterval'), isNull);
    });

    test('skillIntervalForSkill returns value for matching skill', () {
      final set = ModifierDataSet([
        ModifierData(
          name: 'skillInterval',
          entries: [
            ModifierEntry(
              value: -5,
              scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
            ),
            ModifierEntry(
              value: -3,
              scope: ModifierScope(skillId: MelvorId('melvorD:Fishing')),
            ),
          ],
        ),
      ]);
      expect(set.skillIntervalForSkill(MelvorId('melvorD:Woodcutting')), -5);
      expect(set.skillIntervalForSkill(MelvorId('melvorD:Fishing')), -3);
    });

    test('skillIntervalForSkill returns 0 when no modifier', () {
      const set = ModifierDataSet([]);
      expect(set.skillIntervalForSkill(MelvorId('melvorD:Woodcutting')), 0);
    });

    test('hasSkillIntervalFor returns true when skill has modifier', () {
      final set = ModifierDataSet([
        ModifierData(
          name: 'skillInterval',
          entries: [
            ModifierEntry(
              value: -5,
              scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
            ),
          ],
        ),
      ]);
      expect(set.hasSkillIntervalFor(MelvorId('melvorD:Woodcutting')), isTrue);
      expect(set.hasSkillIntervalFor(MelvorId('melvorD:Fishing')), isFalse);
    });

    test('skillIntervalSkillIds returns all skills with modifiers', () {
      final set = ModifierDataSet([
        ModifierData(
          name: 'skillInterval',
          entries: [
            ModifierEntry(
              value: -5,
              scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
            ),
            ModifierEntry(
              value: -3,
              scope: ModifierScope(skillId: MelvorId('melvorD:Fishing')),
            ),
          ],
        ),
      ]);
      expect(set.skillIntervalSkillIds, [
        MelvorId('melvorD:Woodcutting'),
        MelvorId('melvorD:Fishing'),
      ]);
    });

    test('totalSkillInterval sums all skill interval entries', () {
      final set = ModifierDataSet([
        ModifierData(
          name: 'skillInterval',
          entries: [
            ModifierEntry(
              value: -5,
              scope: ModifierScope(skillId: MelvorId('melvorD:Woodcutting')),
            ),
            ModifierEntry(
              value: -3,
              scope: ModifierScope(skillId: MelvorId('melvorD:Fishing')),
            ),
          ],
        ),
      ]);
      expect(set.totalSkillInterval, -8);
    });
  });
}
