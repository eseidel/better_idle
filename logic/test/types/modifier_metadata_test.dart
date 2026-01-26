import 'package:logic/src/types/modifier_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierMetadataRegistry.formatDescription', () {
    test('returns fallback for unknown modifier', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(
        name: 'unknownModifier',
        value: 5,
      );
      expect(result, '+5% Unknown Modifier');
    });

    test('fallback includes skill context', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(
        name: 'bonusXp',
        value: 10,
        skillName: 'Woodcutting',
      );
      expect(result, '+10% Bonus Xp (Woodcutting)');
    });

    test('fallback includes currency context', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(
        name: 'currencyGain',
        value: 15,
        currencyName: 'GP',
      );
      expect(result, '+15% Currency Gain (GP)');
    });

    test('fallback handles negative values with sign', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(name: 'bonusXp', value: -5);
      expect(result, '-5% Bonus Xp');
    });

    test('fallback handles interval modifiers with ms suffix', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(
        name: 'skillInterval',
        value: -100,
      );
      expect(result, '-100ms Skill Interval');
    });

    test('fallback handles flat modifiers without percent', () {
      const registry = ModifierMetadataRegistry.empty();
      final result = registry.formatDescription(name: 'flatDamage', value: 20);
      expect(result, '+20 Flat Damage');
    });

    test('uses template from metadata when available', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'skillXP',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(text: r'+${value}% Skill XP', lang: ''),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(name: 'skillXP', value: 10);
      expect(result, '+10% Skill XP');
    });

    test('substitutes skillName placeholder', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'skillXP',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'skill'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${skillName} Skill XP',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'skillXP',
        value: 15,
        skillName: 'Fishing',
      );
      expect(result, '+15% Fishing Skill XP');
    });

    test('substitutes currencyName placeholder', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'currencyGain',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'currency'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${currencyName} gained',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'currencyGain',
        value: 20,
        currencyName: 'Gold',
      );
      expect(result, '+20% Gold gained');
    });

    test('substitutes actionName placeholder', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'actionSuccess',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'action'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${actionName} success rate',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'actionSuccess',
        value: 5,
        actionName: 'Oak Tree',
      );
      expect(result, '+5% Oak Tree success rate');
    });

    test('resolves positive alias', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'currencyGain',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% currency gained',
                  lang: '',
                ),
              ],
              posAliases: [ModifierAlias(key: 'increasedGPGlobal')],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'increasedGPGlobal',
        value: 10,
      );
      expect(result, '+10% currency gained');
    });

    test('resolves negative alias and inverts value', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'currencyGain',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% currency gained',
                  lang: '',
                  above: 0,
                ),
                ModifierDescription(
                  text: r'-${value}% currency gained',
                  lang: '',
                  below: 0,
                ),
              ],
              negAliases: [ModifierAlias(key: 'decreasedGPGlobal')],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'decreasedGPGlobal',
        value: 10,
      );
      expect(result, '-10% currency gained');
    });

    test('alias with currencyId provides default currency name', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'currencyGain',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'currency'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${currencyName} gained',
                  lang: '',
                ),
              ],
              posAliases: [
                ModifierAlias(
                  key: 'increasedGPGlobal',
                  currencyId: 'melvorD:GP',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'increasedGPGlobal',
        value: 10,
      );
      expect(result, '+10% GP gained');
    });

    test('explicit currencyName overrides alias currencyId', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'currencyGain',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'currency'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${currencyName} gained',
                  lang: '',
                ),
              ],
              posAliases: [
                ModifierAlias(
                  key: 'increasedGPGlobal',
                  currencyId: 'melvorD:GP',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'increasedGPGlobal',
        value: 10,
        currencyName: 'Slayer Coins',
      );
      expect(result, '+10% Slayer Coins gained');
    });

    test('selects description based on value with above condition', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'test',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% (positive)',
                  lang: '',
                  above: 0,
                ),
                ModifierDescription(
                  text: r'-${value}% (negative)',
                  lang: '',
                  below: 0,
                ),
                ModifierDescription(text: r'${value}% (zero)', lang: ''),
              ],
            ),
          ],
        ),
      ]);
      expect(
        registry.formatDescription(name: 'test', value: 5),
        '+5% (positive)',
      );
      expect(
        registry.formatDescription(name: 'test', value: -5),
        '-5% (negative)',
      );
    });

    test('selects most specific scope definition', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'skillXP',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(text: r'+${value}% global XP', lang: ''),
              ],
            ),
            ModifierScopeDefinition(
              scopes: {'skill'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${skillName} XP',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      // Without skill, uses global scope
      expect(
        registry.formatDescription(name: 'skillXP', value: 10),
        '+10% global XP',
      );
      // With skill, uses skill-specific scope
      expect(
        registry.formatDescription(
          name: 'skillXP',
          value: 10,
          skillName: 'Mining',
        ),
        '+10% Mining XP',
      );
    });

    test('substitutes categoryName and subcategoryName placeholders', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'categoryBonus',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'category'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${categoryName} bonus',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'categoryBonus',
        value: 25,
        categoryName: 'Trees',
      );
      expect(result, '+25% Trees bonus');
    });

    test('substitutes realmName placeholder', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'realmBonus',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'realm'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${realmName} bonus',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'realmBonus',
        value: 30,
        realmName: 'Abyssal',
      );
      expect(result, '+30% Abyssal bonus');
    });

    test('substitutes damageType placeholder', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'damageBonus',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {'damageType'},
              descriptions: [
                ModifierDescription(
                  text: r'+${value}% ${damageType} damage',
                  lang: '',
                ),
              ],
            ),
          ],
        ),
      ]);
      final result = registry.formatDescription(
        name: 'damageBonus',
        value: 15,
        damageTypeName: 'Fire',
      );
      expect(result, '+15% Fire damage');
    });

    test('uses absolute value in template substitution', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'test',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(text: r'-${value}% penalty', lang: ''),
              ],
            ),
          ],
        ),
      ]);
      // The template already includes the sign, so ${value} is the absolute
      final result = registry.formatDescription(name: 'test', value: -10);
      expect(result, '-10% penalty');
    });
  });

  group('ModifierDescription.matchesValue', () {
    test('matches any value when no conditions set', () {
      const desc = ModifierDescription(text: 'test', lang: '');
      expect(desc.matchesValue(0), isTrue);
      expect(desc.matchesValue(100), isTrue);
      expect(desc.matchesValue(-100), isTrue);
    });

    test('matches value above threshold', () {
      const desc = ModifierDescription(text: 'test', lang: '', above: 0);
      expect(desc.matchesValue(1), isTrue);
      expect(desc.matchesValue(0), isFalse);
      expect(desc.matchesValue(-1), isFalse);
    });

    test('matches value below threshold', () {
      const desc = ModifierDescription(text: 'test', lang: '', below: 0);
      expect(desc.matchesValue(-1), isTrue);
      expect(desc.matchesValue(0), isFalse);
      expect(desc.matchesValue(1), isFalse);
    });

    test('matches value in range', () {
      const desc = ModifierDescription(
        text: 'test',
        lang: '',
        above: -10,
        below: 10,
      );
      expect(desc.matchesValue(0), isTrue);
      expect(desc.matchesValue(5), isTrue);
      expect(desc.matchesValue(-5), isTrue);
      expect(desc.matchesValue(10), isFalse);
      expect(desc.matchesValue(-10), isFalse);
    });
  });

  group('ModifierScopeDefinition.matchesScopes', () {
    test('empty scopes matches anything', () {
      const scopeDef = ModifierScopeDefinition(scopes: {}, descriptions: []);
      expect(scopeDef.matchesScopes(), isTrue);
      expect(scopeDef.matchesScopes(hasSkill: true), isTrue);
      expect(scopeDef.matchesScopes(hasCurrency: true), isTrue);
    });

    test('skill scope requires skill', () {
      const scopeDef = ModifierScopeDefinition(
        scopes: {'skill'},
        descriptions: [],
      );
      expect(scopeDef.matchesScopes(), isFalse);
      expect(scopeDef.matchesScopes(hasSkill: true), isTrue);
      expect(scopeDef.matchesScopes(hasCurrency: true), isFalse);
    });

    test('multiple scopes require all', () {
      const scopeDef = ModifierScopeDefinition(
        scopes: {'skill', 'action'},
        descriptions: [],
      );
      expect(scopeDef.matchesScopes(hasSkill: true), isFalse);
      expect(scopeDef.matchesScopes(hasAction: true), isFalse);
      expect(scopeDef.matchesScopes(hasSkill: true, hasAction: true), isTrue);
    });
  });
}
