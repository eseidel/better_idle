import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ModifierProvider', () {
    // Create fake IDs for testing
    const fakeLocalId = 'FakeAction';
    const fakeShopPurchaseId = MelvorId('test:FakePurchase');

    // Helper to create a fake SkillAction
    SkillAction createFakeAction({required Skill skill, String? localId}) {
      return SkillAction(
        id: ActionId(skill.id, MelvorId('test:${localId ?? fakeLocalId}')),
        skill: skill,
        name: 'Fake Action',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );
    }

    test('returns zero when no modifiers apply', () {
      final registries = Registries.test();
      final action = createFakeAction(skill: Skill.woodcutting);
      final state = GlobalState.test(registries);
      final modifiers = state.createActionModifierProvider(action);

      expect(modifiers.skillInterval(skillId: action.skill.id), 0);
      expect(modifiers.flatSkillInterval(skillId: action.skill.id), 0);
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
      final modifiersLevel98 = stateLevel98.createActionModifierProvider(
        action,
      );
      expect(modifiersLevel98.flatSkillInterval(skillId: action.skill.id), 0);

      // At level 99, bonus should apply
      final stateLevel99 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(99))},
      );
      final modifiersLevel99 = stateLevel99.createActionModifierProvider(
        action,
      );
      expect(
        modifiersLevel99.flatSkillInterval(skillId: action.skill.id),
        -200,
      );
    });

    test(
      'global mastery modifier applies to skills not specifically targeted',
      () {
        // Create a global mastery bonus (autoScopeToAction: false)
        // This simulates something like Firemaking's level 99 bonus that gives
        // +0.25% Mastery XP to ALL skills, not just Firemaking
        const globalMasteryBonus = MasteryLevelBonus(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'masteryXP',
              entries: [ModifierEntry(value: 0.25)], // Global, no scope
            ),
          ]),
          level: 99,
          autoScopeToAction: false, // This makes it apply globally
        );

        final registries = Registries.test(
          masteryBonuses: MasteryBonusRegistry([
            SkillMasteryBonuses(
              skillId: Skill.firemaking.id,
              bonuses: const [globalMasteryBonus],
            ),
          ]),
        );

        // Create a Firemaking action
        final firemakingAction = createFakeAction(
          skill: Skill.firemaking,
          localId: 'FiremakingAction',
        );

        // At level 99, the global bonus should apply
        final state = GlobalState.test(
          registries,
          actionStates: {
            firemakingAction.id: ActionState(masteryXp: startXpForLevel(99)),
          },
        );
        final modifiers = state.createActionModifierProvider(firemakingAction);
        expect(modifiers.masteryXP(skillId: firemakingAction.skill.id), 0.25);
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
      final skillId = action.skill.id;

      // At level 5, bonus should not apply (below threshold)
      final stateLevel5 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(5))},
      );
      expect(
        stateLevel5
            .createActionModifierProvider(action)
            .skillItemDoublingChance(skillId: skillId),
        0,
      );

      // At level 10, bonus applies once (5%)
      final stateLevel10 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(10))},
      );
      expect(
        stateLevel10
            .createActionModifierProvider(action)
            .skillItemDoublingChance(skillId: skillId),
        5,
      );

      // At level 50, bonus applies 5 times (25%)
      final stateLevel50 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(50))},
      );
      expect(
        stateLevel50
            .createActionModifierProvider(action)
            .skillItemDoublingChance(skillId: skillId),
        25,
      );

      // At level 90 (max), bonus applies 9 times (45%)
      final stateLevel90 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(90))},
      );
      expect(
        stateLevel90
            .createActionModifierProvider(action)
            .skillItemDoublingChance(skillId: skillId),
        45,
      );

      // At level 99 (past max), bonus still only applies 9 times (45%)
      final stateLevel99 = GlobalState.test(
        registries,
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(99))},
      );
      expect(
        stateLevel99
            .createActionModifierProvider(action)
            .skillItemDoublingChance(skillId: skillId),
        45,
      );
    });

    test('shop purchase modifiers are resolved', () {
      // Create a fake shop purchase with skillInterval modifier
      final shopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Test Axe',
        category: const MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: const [],
        purchaseRequirements: const [],
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
        shop: ShopRegistry([shopPurchase], const []),
      );

      final action = createFakeAction(skill: Skill.woodcutting);
      final skillId = action.skill.id;

      // Without purchase, no modifier
      final stateNoPurchase = GlobalState.test(registries);
      expect(
        stateNoPurchase
            .createActionModifierProvider(action)
            .skillInterval(skillId: skillId),
        0,
      );

      // With purchase, modifier applies
      final stateWithPurchase = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
      );
      expect(
        stateWithPurchase
            .createActionModifierProvider(action)
            .skillInterval(skillId: skillId),
        -5,
      );
    });

    test('global scope within skillInterval modifier applies', () {
      // Create a shop purchase with a skillInterval modifier that has no scope
      // (global). This tests that entries with null scope are included.
      final globalShopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Global Speed Boost',
        category: const MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: const [],
        purchaseRequirements: const [],
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
        shop: ShopRegistry([globalShopPurchase], const []),
      );

      final woodcuttingAction = createFakeAction(
        skill: Skill.woodcutting,
        localId: 'WoodcuttingAction',
      );

      final stateWithPurchase = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
      );

      // Both the woodcutting-scoped (-5) and global (-2) entries should apply
      final modifiers = stateWithPurchase.createActionModifierProvider(
        woodcuttingAction,
      );
      expect(modifiers.skillInterval(skillId: woodcuttingAction.skill.id), -7);
    });

    test('combines modifiers from multiple sources', () {
      // Create both shop and mastery modifiers that affect the same skill
      final shopPurchase = ShopPurchase(
        id: fakeShopPurchaseId,
        name: 'Test Axe',
        category: const MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: const [],
        purchaseRequirements: const [],
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
        shop: ShopRegistry([shopPurchase], const []),
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [masteryBonus],
          ),
        ]),
      );

      final action = createFakeAction(skill: Skill.woodcutting);
      final skillId = action.skill.id;

      final state = GlobalState.test(
        registries,
        shop: ShopState(purchaseCounts: {fakeShopPurchaseId: 1}),
        actionStates: {action.id: ActionState(masteryXp: startXpForLevel(50))},
      );

      final modifiers = state.createActionModifierProvider(action);

      // Shop (-5) + Mastery (-3) = -8
      expect(modifiers.skillInterval(skillId: skillId), -8);
      // Only from mastery
      expect(modifiers.flatSkillInterval(skillId: skillId), -200);
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
      final modifiers = state.createActionModifierProvider(woodcuttingAction);
      expect(modifiers.skillInterval(skillId: woodcuttingAction.skill.id), 0);
    });
  });

  group('firemaking mastery interval', () {
    // Firemaking mastery grants -0.1% skillInterval per mastery level
    // This test verifies the modifier is being applied correctly
    test('firemaking mastery applies skillInterval modifier per level', () {
      // Create the firemaking mastery bonus that grants -0.1% per level
      // This is the structure from Melvor data:
      // level: 1, levelScalingSlope: 1, levelScalingMax: 99
      // meaning it applies at levels 1, 2, 3, ... up to 99
      final firemakingMasteryBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -0.1, // -0.1% per level
                scope: ModifierScope(skillId: Skill.firemaking.id),
              ),
            ],
          ),
        ]),
        level: 1,
        levelScalingSlope: 1,
        levelScalingMax: 99,
      );

      final registries = Registries.test(
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.firemaking.id,
            bonuses: [firemakingMasteryBonus],
          ),
        ]),
      );

      final firemakingAction = SkillAction(
        id: ActionId(
          Skill.firemaking.id,
          const MelvorId('test:BurnNormalLogs'),
        ),
        skill: Skill.firemaking,
        name: 'Burn Normal Logs',
        duration: const Duration(seconds: 2),
        xp: 10,
        unlockLevel: 1,
      );

      final skillId = firemakingAction.skill.id;

      // At mastery level 1, bonus applies once: -0.1%
      final stateLevel1 = GlobalState.test(
        registries,
        actionStates: {
          firemakingAction.id: ActionState(masteryXp: startXpForLevel(1)),
        },
      );
      final modifiersLevel1 = stateLevel1.createActionModifierProvider(
        firemakingAction,
      );
      expect(
        modifiersLevel1.skillInterval(skillId: skillId),
        closeTo(-0.1, 0.001),
      );

      // At mastery level 50, bonus applies 50 times: -5%
      final stateLevel50 = GlobalState.test(
        registries,
        actionStates: {
          firemakingAction.id: ActionState(masteryXp: startXpForLevel(50)),
        },
      );
      final modifiersLevel50 = stateLevel50.createActionModifierProvider(
        firemakingAction,
      );
      expect(
        modifiersLevel50.skillInterval(skillId: skillId),
        closeTo(-5.0, 0.001),
      );

      // At mastery level 99, bonus applies 99 times: -9.9%
      final stateLevel99 = GlobalState.test(
        registries,
        actionStates: {
          firemakingAction.id: ActionState(masteryXp: startXpForLevel(99)),
        },
      );
      final modifiersLevel99 = stateLevel99.createActionModifierProvider(
        firemakingAction,
      );
      expect(
        modifiersLevel99.skillInterval(skillId: skillId),
        closeTo(-9.9, 0.001),
      );
    });

    test('firemaking mastery modifier is applied to action duration', () {
      // Create the firemaking mastery bonus that grants -0.1% per level
      final firemakingMasteryBonus = MasteryLevelBonus(
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -0.1, // -0.1% per level
                scope: ModifierScope(skillId: Skill.firemaking.id),
              ),
            ],
          ),
        ]),
        level: 1,
        levelScalingSlope: 1,
        levelScalingMax: 99,
      );

      final registries = Registries.test(
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.firemaking.id,
            bonuses: [firemakingMasteryBonus],
          ),
        ]),
      );

      // 2 second action = 20 ticks
      final firemakingAction = SkillAction(
        id: ActionId(
          Skill.firemaking.id,
          const MelvorId('test:BurnNormalLogs'),
        ),
        skill: Skill.firemaking,
        name: 'Burn Normal Logs',
        duration: const Duration(seconds: 2),
        xp: 10,
        unlockLevel: 1,
      );

      final random = Random(42);

      // At mastery level 50, we get -5% skillInterval
      // 20 ticks * 0.95 = 19 ticks
      final state = GlobalState.test(
        registries,
        actionStates: {
          firemakingAction.id: ActionState(masteryXp: startXpForLevel(50)),
        },
      );

      final ticks = state.rollDurationWithModifiers(
        firemakingAction,
        random,
        registries.shop,
      );

      expect(ticks, 19);
    });
  });

  group('rollDurationWithModifiers integration', () {
    test('applies resolved modifiers to duration correctly', () {
      // Create a shop modifier and mastery modifier
      const shopPurchaseId = MelvorId('test:TestAxe');

      final shopPurchase = ShopPurchase(
        id: shopPurchaseId,
        name: 'Test Axe',
        category: const MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: const [],
        purchaseRequirements: const [],
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
        shop: ShopRegistry([shopPurchase], const []),
        masteryBonuses: MasteryBonusRegistry([
          SkillMasteryBonuses(
            skillId: Skill.woodcutting.id,
            bonuses: [masteryBonus],
          ),
        ]),
      );

      // 3 second action = 30 ticks
      final action = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'TestAction'),
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

  group('skillXP modifier', () {
    test('skillXP modifier increases XP gain', () {
      final action = SkillAction(
        id: ActionId.test(Skill.firemaking, 'TestBurn'),
        skill: Skill.firemaking,
        name: 'Test Burn',
        duration: const Duration(seconds: 2),
        xp: 100,
        unlockLevel: 1,
      );

      final registries = Registries.test(actions: [action]);
      final state = GlobalState.test(registries);

      // Without modifier, XP should be base value
      final modifiersNoMod = state.createActionModifierProvider(action);
      final xpNoMod = xpPerAction(state, action, modifiersNoMod);
      expect(xpNoMod.xp, 100);

      // With +20% skillXP modifier via shop purchase
      const shopPurchaseId = MelvorId('test:XpBoost');
      final shopPurchase = ShopPurchase(
        id: shopPurchaseId,
        name: 'XP Boost',
        category: const MelvorId('test:TestCategory'),
        cost: const ShopCost(currencies: [], items: []),
        unlockRequirements: const [],
        purchaseRequirements: const [],
        contains: ShopContents(
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'skillXP',
              entries: [
                ModifierEntry(
                  value: 20,
                  scope: ModifierScope(skillId: Skill.firemaking.id),
                ),
              ],
            ),
          ]),
        ),
        buyLimit: 1,
      );

      final registriesWithShop = Registries.test(
        actions: [action],
        shop: ShopRegistry([shopPurchase], const []),
      );
      final stateWithMod = GlobalState.test(
        registriesWithShop,
        shop: ShopState(purchaseCounts: {shopPurchaseId: 1}),
      );
      final modifiersWithMod = stateWithMod.createActionModifierProvider(
        action,
      );
      final xpWithMod = xpPerAction(stateWithMod, action, modifiersWithMod);
      expect(xpWithMod.xp, 120); // 100 * 1.20 = 120
    });

    test('equipment with skillXP modifier resolves correctly', () {
      // Create an amulet with -10% skillXP for firemaking
      final amulet = Item(
        id: const MelvorId('test:BurningAmuletOfGold'),
        name: 'Burning Amulet of Gold',
        itemType: 'Equipment',
        sellsFor: 12000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillXP',
            entries: [
              ModifierEntry(
                value: -10, // -10%
                scope: ModifierScope(skillId: Skill.firemaking.id),
              ),
            ],
          ),
        ]),
      );

      final firemakingAction = SkillAction(
        id: ActionId.test(Skill.firemaking, 'TestBurn'),
        skill: Skill.firemaking,
        name: 'Burn Test Logs',
        duration: const Duration(seconds: 2),
        xp: 100,
        unlockLevel: 1,
      );

      final registries = Registries.test(
        items: [amulet],
        actions: [firemakingAction],
      );

      // Equip the amulet
      final (equipment, _) = const Equipment.empty().equipGear(
        amulet,
        EquipmentSlot.amulet,
      );
      final state = GlobalState.test(registries, equipment: equipment);

      // Resolve modifiers for firemaking action
      final modifiers = state.createActionModifierProvider(firemakingAction);
      expect(modifiers.skillXP(skillId: firemakingAction.skill.id), -10);

      // XP should be reduced
      final xp = xpPerAction(state, firemakingAction, modifiers);
      expect(xp.xp, 90); // 100 * 0.90 = 90
    });

    test('skillXP modifier scoped to one skill does not affect others', () {
      // Create an amulet with -10% skillXP for firemaking only
      final amulet = Item(
        id: const MelvorId('test:BurningAmuletOfGold'),
        name: 'Burning Amulet of Gold',
        itemType: 'Equipment',
        sellsFor: 12000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillXP',
            entries: [
              ModifierEntry(
                value: -10,
                scope: ModifierScope(skillId: Skill.firemaking.id),
              ),
            ],
          ),
        ]),
      );

      final registries = Registries.test(items: [amulet]);

      final woodcuttingAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'TestChop'),
        skill: Skill.woodcutting,
        name: 'Chop Test Tree',
        duration: const Duration(seconds: 3),
        xp: 100,
        unlockLevel: 1,
      );

      // Equip the amulet
      final (equipment, _) = const Equipment.empty().equipGear(
        amulet,
        EquipmentSlot.amulet,
      );
      final state = GlobalState.test(registries, equipment: equipment);

      // Resolve modifiers for woodcutting (should NOT be affected)
      final modifiers = state.createActionModifierProvider(woodcuttingAction);
      // No skillXP modifier for woodcutting
      expect(modifiers.skillXP(skillId: woodcuttingAction.skill.id), 0);
    });
  });

  group('currencyGain modifier', () {
    test('currencyGain modifier resolves from equipment', () {
      // Create an amulet with +20% currencyGain for firemaking
      final amulet = Item(
        id: const MelvorId('test:BurningAmuletOfGold'),
        name: 'Burning Amulet of Gold',
        itemType: 'Equipment',
        sellsFor: 12000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'currencyGain',
            entries: [
              ModifierEntry(
                value: 20, // +20%
                scope: ModifierScope(skillId: Skill.firemaking.id),
              ),
            ],
          ),
        ]),
      );

      final registries = Registries.test(items: [amulet]);

      final firemakingAction = SkillAction(
        id: ActionId.test(Skill.firemaking, 'TestBurn'),
        skill: Skill.firemaking,
        name: 'Burn Test Logs',
        duration: const Duration(seconds: 2),
        xp: 100,
        unlockLevel: 1,
      );

      // Equip the amulet
      final (equipment, _) = const Equipment.empty().equipGear(
        amulet,
        EquipmentSlot.amulet,
      );
      final state = GlobalState.test(registries, equipment: equipment);

      // Resolve modifiers for firemaking action
      final modifiers = state.createActionModifierProvider(firemakingAction);
      expect(modifiers.currencyGain(skillId: firemakingAction.skill.id), 20);
    });

    test(
      'currencyGain modifier scoped to one skill does not affect others',
      () {
        // Create an amulet with +20% currencyGain for firemaking only
        final amulet = Item(
          id: const MelvorId('test:BurningAmuletOfGold'),
          name: 'Burning Amulet of Gold',
          itemType: 'Equipment',
          sellsFor: 12000,
          validSlots: const [EquipmentSlot.amulet],
          modifiers: ModifierDataSet([
            ModifierData(
              name: 'currencyGain',
              entries: [
                ModifierEntry(
                  value: 20,
                  scope: ModifierScope(skillId: Skill.firemaking.id),
                ),
              ],
            ),
          ]),
        );

        final registries = Registries.test(items: [amulet]);

        // Use a woodcutting action instead of thieving to avoid constructor
        // complexity
        final woodcuttingAction = SkillAction(
          id: ActionId.test(Skill.woodcutting, 'TestChop'),
          skill: Skill.woodcutting,
          name: 'Chop Test Tree',
          duration: const Duration(seconds: 3),
          xp: 10,
          unlockLevel: 1,
        );

        // Equip the amulet
        final (equipment, _) = const Equipment.empty().equipGear(
          amulet,
          EquipmentSlot.amulet,
        );
        final state = GlobalState.test(registries, equipment: equipment);

        // Resolve modifiers for woodcutting (should NOT be affected)
        final modifiers = state.createActionModifierProvider(woodcuttingAction);
        // No currencyGain for woodcutting
        expect(modifiers.currencyGain(skillId: woodcuttingAction.skill.id), 0);
      },
    );
  });

  group('equipment modifiers', () {
    test('equipped item modifiers are applied to action duration', () {
      // Create a fishing amulet with -15% skillInterval for fishing
      final fishingAmulet = Item(
        id: const MelvorId('test:FishingAmulet'),
        name: 'Fishing Amulet',
        itemType: 'Equipment',
        sellsFor: 100000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -15, // -15%
                scope: ModifierScope(skillId: Skill.fishing.id),
              ),
            ],
          ),
        ]),
      );

      final registries = Registries.test(items: [fishingAmulet]);

      // 3 second fishing action = 30 ticks
      final fishingAction = SkillAction(
        id: ActionId.test(Skill.fishing, 'TestFish'),
        skill: Skill.fishing,
        name: 'Catch Test Fish',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      final random = Random(42);

      // Without equipment, duration is 30 ticks
      final stateNoEquipment = GlobalState.test(registries);
      final ticksNoEquipment = stateNoEquipment.rollDurationWithModifiers(
        fishingAction,
        random,
        registries.shop,
      );
      expect(ticksNoEquipment, 30);

      // With fishing amulet equipped, duration is reduced by 15%
      // 30 * 0.85 = 25.5, rounds to 26 ticks
      final (equipment, _) = const Equipment.empty().equipGear(
        fishingAmulet,
        EquipmentSlot.amulet,
      );
      final stateWithAmulet = GlobalState.test(
        registries,
        equipment: equipment,
      );
      final ticksWithAmulet = stateWithAmulet.rollDurationWithModifiers(
        fishingAction,
        random,
        registries.shop,
      );
      expect(ticksWithAmulet, 26);
    });

    test('equipment modifier is removed when item is unequipped', () {
      // Create a fishing amulet with -15% skillInterval for fishing
      final fishingAmulet = Item(
        id: const MelvorId('test:FishingAmulet'),
        name: 'Fishing Amulet',
        itemType: 'Equipment',
        sellsFor: 100000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -15, // -15%
                scope: ModifierScope(skillId: Skill.fishing.id),
              ),
            ],
          ),
        ]),
      );

      final registries = Registries.test(items: [fishingAmulet]);

      final fishingAction = SkillAction(
        id: ActionId.test(Skill.fishing, 'TestFish'),
        skill: Skill.fishing,
        name: 'Catch Test Fish',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      final random = Random(42);

      // Equip the amulet
      final (equippedState, _) = const Equipment.empty().equipGear(
        fishingAmulet,
        EquipmentSlot.amulet,
      );
      final stateWithAmulet = GlobalState.test(
        registries,
        equipment: equippedState,
      );
      final ticksWithAmulet = stateWithAmulet.rollDurationWithModifiers(
        fishingAction,
        random,
        registries.shop,
      );
      expect(ticksWithAmulet, 26); // 30 * 0.85 = 25.5 → 26

      // Unequip the amulet
      final (_, unequippedState) = equippedState.unequipGear(
        EquipmentSlot.amulet,
      )!;
      final stateWithoutAmulet = GlobalState.test(
        registries,
        equipment: unequippedState,
      );
      final ticksWithoutAmulet = stateWithoutAmulet.rollDurationWithModifiers(
        fishingAction,
        random,
        registries.shop,
      );
      expect(ticksWithoutAmulet, 30); // Back to base duration
    });

    test('equipment modifier does not affect other skills', () {
      // Create a fishing amulet with -15% skillInterval for fishing
      final fishingAmulet = Item(
        id: const MelvorId('test:FishingAmulet'),
        name: 'Fishing Amulet',
        itemType: 'Equipment',
        sellsFor: 100000,
        validSlots: const [EquipmentSlot.amulet],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillInterval',
            entries: [
              ModifierEntry(
                value: -15, // -15%
                scope: ModifierScope(skillId: Skill.fishing.id),
              ),
            ],
          ),
        ]),
      );

      final registries = Registries.test(items: [fishingAmulet]);

      // Create a woodcutting action
      final woodcuttingAction = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'TestTree'),
        skill: Skill.woodcutting,
        name: 'Cut Test Tree',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      final random = Random(42);

      // Equip the fishing amulet
      final (equipment, _) = const Equipment.empty().equipGear(
        fishingAmulet,
        EquipmentSlot.amulet,
      );
      final stateWithAmulet = GlobalState.test(
        registries,
        equipment: equipment,
      );

      // Woodcutting should not be affected by fishing amulet
      final ticksWoodcutting = stateWithAmulet.rollDurationWithModifiers(
        woodcuttingAction,
        random,
        registries.shop,
      );
      expect(ticksWoodcutting, 30); // No reduction
    });
  });
}
