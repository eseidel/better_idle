import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/types/resolved_modifiers.dart';
import 'package:test/test.dart';

void main() {
  group('ResolvedModifiers', () {
    test('empty has no values', () {
      expect(ResolvedModifiers.empty.isEmpty, isTrue);
      expect(ResolvedModifiers.empty.skillInterval, 0);
      expect(ResolvedModifiers.empty.flatSkillInterval, 0);
    });

    test('stores and retrieves values by name', () {
      final modifiers = ResolvedModifiers({'skillInterval': -5, 'skillXP': 10});
      expect(modifiers.skillInterval, -5);
      expect(modifiers.skillXP, 10);
      expect(modifiers.isEmpty, isFalse);
    });

    test('combine merges values', () {
      final a = ResolvedModifiers({'skillInterval': -5, 'skillXP': 10});
      final b = ResolvedModifiers({
        'skillInterval': -3,
        'flatSkillInterval': -200,
      });
      final combined = a.combine(b);

      expect(combined.skillInterval, -8); // -5 + -3
      expect(combined.skillXP, 10);
      expect(combined.flatSkillInterval, -200);
    });

    test('combine with empty returns original', () {
      final a = ResolvedModifiers({'skillInterval': -5});
      expect(a.combine(ResolvedModifiers.empty), same(a));
      expect(ResolvedModifiers.empty.combine(a), same(a));
    });
  });

  group('ResolvedModifiersBuilder', () {
    test('accumulates values for same modifier', () {
      final builder = ResolvedModifiersBuilder()
        ..add('skillInterval', -5)
        ..add('skillInterval', -3)
        ..add('skillXP', 10);

      final result = builder.build();
      expect(result.skillInterval, -8);
      expect(result.skillXP, 10);
    });
  });

  group('resolveModifiers', () {
    // Create fake IDs for testing
    final fakeActionId = MelvorId('test:FakeAction');
    final fakeShopPurchaseId = MelvorId('test:FakePurchase');

    // Helper to create a fake SkillAction
    SkillAction createFakeAction({required Skill skill, MelvorId? id}) {
      return SkillAction(
        id: id ?? fakeActionId,
        skill: skill,
        name: 'Fake Action',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );
    }

    test('returns empty when no modifiers apply', () {
      final registries = Registries.test();
      final action = createFakeAction(skill: Skill.woodcutting);
      final state = GlobalState.test(registries);
      final modifiers = state.resolveModifiers(action);

      expect(modifiers.isEmpty, isTrue);
    });

    test('resolves mastery bonus with skill-scoped modifier', () {
      // Create a mastery bonus that applies to woodcutting at level 99
      final masteryBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'flatSkillInterval',
            entries: [
              ModifierEntry(
                value: -200, // -200ms
                scope: ModifierScope(skillId: Skill.woodcutting.id),
              ),
            ],
          ),
        ]),
        level: 99,
      );

      final registries = Registries.test(
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [masteryBonus],
          ),
        ]),
      );

      final action = createFakeAction(skill: Skill.woodcutting);

      // At level 98, bonus should not apply
      final stateLevel98 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(98))},
      );
      final modifiersLevel98 = stateLevel98.resolveModifiers(action);
      expect(modifiersLevel98.flatSkillInterval, 0);

      // At level 99, bonus should apply
      final stateLevel99 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(99))},
      );
      final modifiersLevel99 = stateLevel99.resolveModifiers(action);
      expect(modifiersLevel99.flatSkillInterval, -200);
    });

    test(
      'global mastery modifier applies to skills not specifically targeted',
      () {
        // Create a global mastery bonus (autoScopeToAction: false)
        // This simulates something like Firemaking's level 99 bonus that gives
        // +0.25% Mastery XP to ALL skills, not just Firemaking
        final globalMasteryBonus = MasteryLevelBonus(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'masteryXP',
              entries: [const ModifierEntry(value: 0.25)], // Global, no scope
            ),
          ]),
          level: 99,
          autoScopeToAction: false, // This makes it apply globally
        );

        final registries = Registries.test(
          masteryBonuses: MasteryBonusRegistry([
            SkillMasteryBonuses(
              skillId: Skill.firemaking.id,
              bonuses: [globalMasteryBonus],
            ),
          ]),
        );

        // Create a Firemaking action
        final firemakingAction = createFakeAction(
          skill: Skill.firemaking,
          id: MelvorId('test:FiremakingAction'),
        );

        // At level 99, the global bonus should apply
        final state = GlobalState.test(
          registries,
          actionStates: {
            firemakingAction.id: ActionState(masteryXp: startXpForLevel(99)),
          },
        );
        final modifiers = state.resolveModifiers(firemakingAction);
        expect(modifiers.masteryXP, 0.25);
      },
    );

    test('scaling mastery bonus accumulates with level', () {
      // Create a scaling bonus that triggers every 10 levels
      // Like woodcutting's doubling chance: +5% at levels 10, 20, 30, etc.
      final scalingBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillItemDoublingChance',
            entries: [
              ModifierEntry(
                value: 5,
                scope: ModifierScope(skillId: Skill.woodcutting.id),
              ),
            ],
          ),
        ]),
        level: 10,
        levelScalingSlope: 10,
        levelScalingMax: 90,
      );

      final registries = Registries.test(
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [scalingBonus],
          ),
        ]),
      );

      final action = createFakeAction(skill: Skill.woodcutting);

      // At level 5, bonus should not apply (below threshold)
      final stateLevel5 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(5))},
      );
      expect(stateLevel5.resolveModifiers(action).skillItemDoublingChance, 0);

      // At level 10, bonus applies once (5%)
      final stateLevel10 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(10))},
      );
      expect(stateLevel10.resolveModifiers(action).skillItemDoublingChance, 5);

      // At level 50, bonus applies 5 times (25%)
      final stateLevel50 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(50))},
      );
      expect(stateLevel50.resolveModifiers(action).skillItemDoublingChance, 25);

      // At level 90 (max), bonus applies 9 times (45%)
      final stateLevel90 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(90))},
      );
      expect(stateLevel90.resolveModifiers(action).skillItemDoublingChance, 45);

      // At level 99 (past max), bonus still only applies 9 times (45%)
      final stateLevel99 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(99))},
      );
      expect(stateLevel99.resolveModifiers(action).skillItemDoublingChance, 45);
    });

    test('shop purchase modifiers are resolved', () {
      // Create a fake shop purchase with skillInterval modifier
      final shopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Test Axe',
        category: MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: [],
        purchaseRequirements: [],
        contains: ShopContents(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'skillInterval',
              entries: [
                ModifierEntry(
                  value: -5,
                  scope: ModifierScope(skillId: Skill.woodcutting.id),
                ),
              ],
            ),
          ]),
        ),
        buyLimit: 1,
      );

      final registries = Registries.test(
        shop: ShopRegistry([shopPurchase], []),
      );

      final action = createFakeAction(skill: Skill.woodcutting);

      // Without purchase, no modifier
      final stateNoPurchase = GlobalState.test(registries);
      expect(stateNoPurchase.resolveModifiers(action).skillInterval, 0);

      // With purchase, modifier applies
      final stateWithPurchase = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
      );
      expect(stateWithPurchase.resolveModifiers(action).skillInterval, -5);
    });

    test('global scope within skillInterval modifier applies', () {
      // Create a shop purchase with a skillInterval modifier that has no scope
      // (global). This tests that entries with null scope are included.
      final globalShopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Global Speed Boost',
        category: MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: [],
        purchaseRequirements: [],
        contains: ShopContents(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'skillInterval',
              entries: [
                // First entry scoped to woodcutting
                ModifierEntry(
                  value: -5,
                  scope: ModifierScope(skillId: Skill.woodcutting.id),
                ),
                // Second entry is global (no scope)
                const ModifierEntry(value: -2),
              ],
            ),
          ]),
        ),
        buyLimit: 1,
      );

      final registries = Registries.test(
        shop: ShopRegistry([globalShopPurchase], []),
      );

      final woodcuttingAction = createFakeAction(
        skill: Skill.woodcutting,
        id: MelvorId('test:WoodcuttingAction'),
      );

      final stateWithPurchase = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
      );

      // Both the woodcutting-scoped (-5) and global (-2) entries should apply
      final modifiers = stateWithPurchase.resolveModifiers(woodcuttingAction);
      expect(modifiers.skillInterval, -7);
    });

    test('combines modifiers from multiple sources', () {
      // Create both shop and mastery modifiers that affect the same skill
      final shopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Test Axe',
        category: MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: [],
        purchaseRequirements: [],
        contains: ShopContents(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'skillInterval',
              entries: [
                ModifierEntry(
                  value: -5,
                  scope: ModifierScope(skillId: Skill.woodcutting.id),
                ),
              ],
            ),
          ]),
        ),
        buyLimit: 1,
      );

      final masteryBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -3,
                scope: ModifierScope(skillId: Skill.woodcutting.id),
              ),
            ],
          ),
          ModifierData(
            name: 'flatSkillInterval',
            entries: [
              ModifierEntry(
                value: -200,
                scope: ModifierScope(skillId: Skill.woodcutting.id),
              ),
            ],
          ),
        ]),
        level: 50,
      );

      final registries = Registries.test(
        shop: ShopRegistry([shopPurchase], []),
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [masteryBonus],
          ),
        ]),
      );

      final action = createFakeAction(skill: Skill.woodcutting);

      final state = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(50))},
      );

      final modifiers = state.resolveModifiers(action);

      // Shop (-5) + Mastery (-3) = -8
      expect(modifiers.skillInterval, -8);
      // Only from mastery
      expect(modifiers.flatSkillInterval, -200);
    });

    test('modifier scoped to different skill does not apply', () {
      // Create a mastery bonus scoped to fishing, then test with woodcutting
      final fishingBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -10,
                scope: ModifierScope(skillId: Skill.fishing.id),
              ),
            ],
          ),
        ]),
        level: 10,
      );

      final registries = Registries.test(
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id, // Bonus is in woodcutting's registry
            bonuses: [fishingBonus], // But scoped to fishing
          ),
        ]),
      );

      final woodcuttingAction = createFakeAction(skill: Skill.woodcutting);

      final state = GlobalState.test(
        registries,
        actionStates: {
          woodcuttingAction.id: ActionState(masteryXp: startXpForLevel(50)),
        },
      );

      // The fishing-scoped modifier should NOT apply to woodcutting
      final modifiers = state.resolveModifiers(woodcuttingAction);
      expect(modifiers.skillInterval, 0);
    });
  });

  group('rollDurationWithModifiers integration', () {
    test('applies resolved modifiers to duration correctly', () {
      // Create a shop modifier and mastery modifier
      final shopPurchaseId = MelvorId('test:TestAxe');

      final shopPurchase = ShopPurchase(
        id: shopPurchaseId,
        name: 'Test Axe',
        category: MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: [],
        purchaseRequirements: [],
        contains: ShopContents(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'skillInterval',
              entries: [
                ModifierEntry(
                  value: -10, // -10%
                  scope: ModifierScope(skillId: Skill.woodcutting.id),
                ),
              ],
            ),
          ]),
        ),
        buyLimit: 1,
      );

      final masteryBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'flatSkillInterval',
            entries: [
              ModifierEntry(
                value: -200, // -200ms = -2 ticks
                scope: ModifierScope(skillId: Skill.woodcutting.id),
              ),
            ],
          ),
        ]),
        level: 99,
      );

      final registries = Registries.test(
        shop: ShopRegistry([shopPurchase], []),
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [masteryBonus],
          ),
        ]),
      );

      // 3 second action = 30 ticks
      final action = SkillAction(
        id: MelvorId('test:TestAction'),
        skill: Skill.woodcutting,
        name: 'Test Action',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      final random = Random(42);

      // With shop (-10%) and mastery 99 (-2 ticks):
      // 30 * 0.90 - 2 = 27 - 2 = 25 ticks
      final state = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {shopPurchaseId: 1}),
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(99))},
      );

      final ticks = state.rollDurationWithModifiers(
        action,
        random,
        registries.shop,
      );

      expect(ticks, 25);
    });
  });
}
