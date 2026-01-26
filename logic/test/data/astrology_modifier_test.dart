import 'package:logic/src/data/actions.dart';
import 'package:logic/src/types/modifier_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('AstrologyModifier.formatDescriptionLines', () {
    test('shows current total at different levels', () {
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

      final modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'skillXP',
        skills: [Skill.woodcutting.id],
        maxCount: 5,
        costs: const [1, 2, 3, 4, 5],
        unlockMasteryLevel: 1,
      );

      expect(modifier.formatDescriptionLines(registry, currentLevel: 0), [
        '0% Woodcutting Skill XP',
      ]);

      expect(modifier.formatDescriptionLines(registry, currentLevel: 3), [
        '+3% Woodcutting Skill XP',
      ]);

      expect(modifier.formatDescriptionLines(registry, currentLevel: 5), [
        '+5% Woodcutting Skill XP',
      ]);
    });

    test('formats multiple skills as separate lines', () {
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

      final modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'skillXP',
        skills: [Skill.woodcutting.id, Skill.fishing.id],
        maxCount: 5,
        costs: const [1, 2, 3, 4, 5],
        unlockMasteryLevel: 1,
      );

      expect(modifier.formatDescriptionLines(registry, currentLevel: 2), [
        '+2% Woodcutting Skill XP',
        '+2% Fishing Skill XP',
      ]);
    });

    test('formats without skill name when skills list is empty', () {
      final registry = ModifierMetadataRegistry(const [
        ModifierMetadata(
          id: 'globalXP',
          allowedScopes: [
            ModifierScopeDefinition(
              scopes: {},
              descriptions: [
                ModifierDescription(text: r'+${value}% Global XP', lang: ''),
              ],
            ),
          ],
        ),
      ]);

      const modifier = AstrologyModifier(
        type: AstrologyModifierType.unique,
        modifierKey: 'globalXP',
        skills: [],
        maxCount: 3,
        costs: [10, 20, 30],
        unlockMasteryLevel: 1,
      );

      expect(modifier.formatDescriptionLines(registry, currentLevel: 1), [
        '+1% Global XP',
      ]);
    });
  });

  group('AstrologyModifier.formatIncrementDescription', () {
    test('extracts increment from template', () {
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

      final modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'skillXP',
        skills: [Skill.woodcutting.id],
        maxCount: 5,
        costs: const [1, 2, 3, 4, 5],
        unlockMasteryLevel: 1,
      );

      expect(modifier.formatIncrementDescription(registry), '(+1% per level)');
    });

    test('uses fallback for unknown modifier', () {
      const registry = ModifierMetadataRegistry.empty();

      const modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'unknownModifier',
        skills: [],
        maxCount: 2,
        costs: [5, 10],
        unlockMasteryLevel: 1,
      );

      expect(modifier.formatIncrementDescription(registry), '(+1% per level)');
    });
  });

  group('AstrologyModifier.costForLevel', () {
    test('returns first cost at level 0', () {
      const modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'test',
        skills: [],
        maxCount: 3,
        costs: [10, 20, 30],
        unlockMasteryLevel: 1,
      );

      expect(modifier.costForLevel(0), 10);
    });

    test('returns correct cost at each level', () {
      const modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'test',
        skills: [],
        maxCount: 5,
        costs: [5, 15, 30, 50, 75],
        unlockMasteryLevel: 1,
      );

      expect(modifier.costForLevel(0), 5);
      expect(modifier.costForLevel(1), 15);
      expect(modifier.costForLevel(2), 30);
      expect(modifier.costForLevel(3), 50);
      expect(modifier.costForLevel(4), 75);
    });

    test('returns null when at max level', () {
      const modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'test',
        skills: [],
        maxCount: 3,
        costs: [10, 20, 30],
        unlockMasteryLevel: 1,
      );

      expect(modifier.costForLevel(3), isNull);
    });

    test('returns null when beyond max level', () {
      const modifier = AstrologyModifier(
        type: AstrologyModifierType.standard,
        modifierKey: 'test',
        skills: [],
        maxCount: 2,
        costs: [10, 20],
        unlockMasteryLevel: 1,
      );

      expect(modifier.costForLevel(5), isNull);
      expect(modifier.costForLevel(100), isNull);
    });
  });
}
