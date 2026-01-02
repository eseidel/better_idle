import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/estimate_rates.dart';
import 'package:logic/src/solver/analysis/next_decision_delta.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/interactions/interaction.dart'
    show SellAllPolicy;
import 'package:test/test.dart';

import 'test_helper.dart';

/// Default sell policy for tests - sells everything.
const _testPolicy = SellAllPolicy();

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('WaitForEffectiveCredits', () {
    test('isSatisfied returns true when GP meets target', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when GP exceeds target', () {
      final state = GlobalState.test(testRegistries, gp: 150);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when GP is below target', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('isSatisfied includes inventory sell value', () {
      // Normal Logs sell for 1 GP each
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 50),
      ]);
      final state = GlobalState.test(
        testRegistries,
        gp: 50,
        inventory: inventory,
      );
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      // 50 GP + 50 logs * 1 GP = 100 total
      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no value rate', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('describe returns formatted string', () {
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);
      expect(waitFor.describe(), 'credits >= 100');
    });

    test('shortDescription includes reason', () {
      const waitFor = WaitForEffectiveCredits(
        100,
        sellPolicy: _testPolicy,
        reason: 'Iron Axe',
      );
      expect(waitFor.shortDescription, 'Iron Axe affordable');
    });

    test('shortDescription defaults to Upgrade', () {
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);
      expect(waitFor.shortDescription, 'Upgrade affordable');
    });

    test('progress returns effective credits', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 50),
      ]);
      final state = GlobalState.test(
        testRegistries,
        gp: 50,
        inventory: inventory,
      );
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      // 50 GP + 50 logs * 1 GP = 100 total
      expect(waitFor.progress(state), 100);
    });

    test('progress returns only GP when no items', () {
      final state = GlobalState.test(testRegistries, gp: 75);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      expect(waitFor.progress(state), 75);
    });
  });

  group('WaitForSkillXp', () {
    test('isSatisfied returns true when skill XP meets target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when skill XP exceeds target', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 150, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when skill XP is below target', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no XP rate', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates correctly with XP rate', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);
      const rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {},
        xpPerTickBySkill: {Skill.woodcutting: 10.0}, // 10 XP per tick
        itemTypesPerTick: 0,
      );

      // 100 XP / 10 XP per tick = 10 ticks
      expect(waitFor.estimateTicks(state, rates), 10);
    });

    test('describe returns formatted string', () {
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);
      expect(waitFor.describe(), 'Woodcutting XP >= 100');
    });

    test('shortDescription uses reason when provided', () {
      const waitFor = WaitForSkillXp(
        Skill.woodcutting,
        100,
        reason: 'Oak Tree unlocks',
      );
      expect(waitFor.shortDescription, 'Oak Tree unlocks');
    });

    test('shortDescription defaults to Skill +1', () {
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);
      expect(waitFor.shortDescription, 'Skill +1');
    });

    test('progress returns current skill XP', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 75, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.progress(state), 75);
    });

    test('progress returns 0 for empty skill state', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForMasteryXp', () {
    test('isSatisfied returns true when mastery XP meets target', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: const ActionState(masteryXp: 100)},
      );
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when mastery XP is below target', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: const ActionState(masteryXp: 100)},
      );
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no mastery rate', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates correctly with mastery rate', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForMasteryXp(action.id, 100);
      const rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {},
        xpPerTickBySkill: {},
        itemTypesPerTick: 0,
        masteryXpPerTick: 5, // 5 mastery XP per tick
      );

      // 100 XP / 5 XP per tick = 20 ticks
      expect(waitFor.estimateTicks(state, rates), 20);
    });

    test('describe returns formatted string', () {
      final action = testActions.woodcutting('Normal Tree');
      final waitFor = WaitForMasteryXp(action.id, 100);
      expect(waitFor.describe(), contains('mastery XP >= 100'));
    });

    test('shortDescription returns Mastery +1', () {
      final action = testActions.woodcutting('Normal Tree');
      final waitFor = WaitForMasteryXp(action.id, 100);
      expect(waitFor.shortDescription, 'Mastery +1');
    });

    test('progress returns current mastery XP', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.test(
        testRegistries,
        actionStates: {action.id: const ActionState(masteryXp: 75)},
      );
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.progress(state), 75);
    });

    test('progress returns 0 for empty action state', () {
      final action = testActions.woodcutting('Normal Tree');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForMasteryXp(action.id, 100);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForInventoryThreshold', () {
    test('isSatisfied returns true when threshold met', () {
      // Fill inventory to 50%
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 60), // Default capacity is 12 slots
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      // Assuming some inventory usage, check 50% threshold
      const waitFor = WaitForInventoryThreshold(0.5);

      // This depends on inventory capacity - need at least 50% full
      final usedFraction = state.inventoryUsed / state.inventoryCapacity;
      expect(waitFor.isSatisfied(state), usedFraction >= 0.5);
    });

    test('isSatisfied returns false when below threshold', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryThreshold(0.5);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('default state has positive inventory capacity', () {
      // This validates our test assumptions - capacity should be > 0
      final state = GlobalState.empty(testRegistries);
      expect(state.inventoryCapacity, greaterThan(0));
    });

    test('estimateTicks returns 0 when already at threshold', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 100),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      const waitFor = WaitForInventoryThreshold(0.5);

      if (waitFor.isSatisfied(state)) {
        expect(waitFor.estimateTicks(state, Rates.empty), 0);
      }
    });

    test('estimateTicks returns infTicks when no item rate', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryThreshold(0.5);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('describe returns formatted string', () {
      const waitFor = WaitForInventoryThreshold(0.5);
      expect(waitFor.describe(), 'inventory >= 50%');
    });

    test('shortDescription returns Inventory threshold', () {
      const waitFor = WaitForInventoryThreshold(0.5);
      expect(waitFor.shortDescription, 'Inventory threshold');
    });

    test('progress returns inventory used', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      const waitFor = WaitForInventoryThreshold(0.5);

      expect(waitFor.progress(state), state.inventoryUsed);
    });

    test('progress returns 0 for empty inventory', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryThreshold(0.5);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForInventoryFull', () {
    test('isSatisfied returns false when inventory has space', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryFull();

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns infTicks when no item rate', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryFull();

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates based on remaining slots', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryFull();
      const rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {},
        xpPerTickBySkill: {},
        itemTypesPerTick: 1, // 1 slot per tick
      );

      final remaining = state.inventoryRemaining;
      expect(waitFor.estimateTicks(state, rates), remaining);
    });

    test('describe returns formatted string', () {
      const waitFor = WaitForInventoryFull();
      expect(waitFor.describe(), 'inventory full');
    });

    test('shortDescription returns Inventory full', () {
      const waitFor = WaitForInventoryFull();
      expect(waitFor.shortDescription, 'Inventory full');
    });

    test('progress returns inventory used', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      const waitFor = WaitForInventoryFull();

      expect(waitFor.progress(state), state.inventoryUsed);
    });

    test('progress returns 0 for empty inventory', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForInventoryFull();

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForGoal', () {
    test('isSatisfied delegates to goal', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.isSatisfied(state), goal.isSatisfied(state));
    });

    test('isSatisfied returns false when goal not met', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when goal satisfied', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no progress rate', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('describe delegates to goal', () {
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.describe(), goal.describe());
    });

    test('shortDescription returns Goal reached', () {
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.shortDescription, 'Goal reached');
    });

    test('progress delegates to goal', () {
      final state = GlobalState.test(testRegistries, gp: 75);
      const goal = ReachGpGoal(100);
      const waitFor = WaitForGoal(goal);

      expect(waitFor.progress(state), goal.progress(state));
    });
  });

  group('WaitForInputsDepleted', () {
    test('isSatisfied returns false when inputs available', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('isSatisfied returns true when no inputs', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('estimateTicks returns infTicks for non-consuming action', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      final waitFor = WaitForInputsDepleted(action.id);

      // Woodcutting has no inputs, so returns infTicks
      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates based on consumption rate', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 30),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      // Should calculate ticks based on logs / consumption rate
      final ticks = waitFor.estimateTicks(state, Rates.empty);
      expect(ticks, greaterThan(0));
      expect(ticks, lessThan(infTicks));
    });

    test('describe returns formatted string', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      expect(waitFor.describe(), contains('inputs depleted'));
    });

    test('shortDescription returns Inputs depleted', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      expect(waitFor.shortDescription, 'Inputs depleted');
    });

    test('progress returns 0 (not goal-oriented)', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsDepleted(action.id);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForInputsAvailable', () {
    test('isSatisfied returns true when inputs available', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when no inputs', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when not satisfied', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      // Returns infTicks as a conservative fallback
      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('describe returns formatted string', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.describe(), contains('inputs available'));
    });

    test('shortDescription returns Inputs available', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.shortDescription, 'Inputs available');
    });

    test('progress returns 0 (binary condition)', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForInputsAvailable(action.id);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForInventoryAtLeast', () {
    test('isSatisfied returns true when count meets target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when count exceeds target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 20),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when count below target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('isSatisfied returns false when item not in inventory', () {
      final logs = testItems.byName('Normal Logs');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no production rate', () {
      final logs = testItems.byName('Normal Logs');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates correctly with production rate', () {
      final logs = testItems.byName('Normal Logs');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);
      final rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {logs.id: 2.0}, // 2 logs per tick
        xpPerTickBySkill: const {},
        itemTypesPerTick: 0,
      );

      // 10 logs / 2 logs per tick = 5 ticks
      expect(waitFor.estimateTicks(state, rates), 5);
    });

    test('describe returns formatted string', () {
      final logs = testItems.byName('Normal Logs');
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.describe(), contains('count >= 10'));
    });

    test('shortDescription includes count', () {
      final logs = testItems.byName('Normal Logs');
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.shortDescription, 'Inventory at least 10');
    });

    test('progress returns current item count', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 7),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.progress(state), 7);
    });

    test('progress returns 0 when item not in inventory', () {
      final logs = testItems.byName('Normal Logs');
      final state = GlobalState.empty(testRegistries);
      final waitFor = WaitForInventoryAtLeast(logs.id, 10);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForSufficientInputs', () {
    test('isSatisfied returns true when enough inputs', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 5);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when not enough inputs', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 2),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 10);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('isSatisfied returns false for non-skill action', () {
      final state = GlobalState.empty(testRegistries);
      // Use a combat action ID which is not a SkillAction
      final combatAction = testRegistries.actions.all
          .whereType<CombatAction>()
          .first;
      final waitFor = WaitForSufficientInputs(combatAction.id, 5);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 5);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks for non-skill action', () {
      final state = GlobalState.empty(testRegistries);
      final combatAction = testRegistries.actions.all
          .whereType<CombatAction>()
          .first;
      final waitFor = WaitForSufficientInputs(combatAction.id, 5);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('describe returns formatted string', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 10);

      expect(waitFor.describe(), contains('sufficient inputs (10)'));
    });

    test('shortDescription returns Sufficient inputs', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 10);

      expect(waitFor.shortDescription, 'Sufficient inputs');
    });

    test('progress returns minimum available input count', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 7),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final action = testActions.firemaking('Burn Normal Logs');
      final waitFor = WaitForSufficientInputs(action.id, 10);

      expect(waitFor.progress(state), 7);
    });

    test('progress returns 0 for non-skill action', () {
      final state = GlobalState.empty(testRegistries);
      final combatAction = testRegistries.actions.all
          .whereType<CombatAction>()
          .first;
      final waitFor = WaitForSufficientInputs(combatAction.id, 5);

      expect(waitFor.progress(state), 0);
    });

    test('progress returns 0 for action with no inputs', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      final waitFor = WaitForSufficientInputs(action.id, 5);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitForAnyOf', () {
    test('isSatisfied returns true when any condition met', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const waitFor = WaitForAnyOf([
        WaitForEffectiveCredits(200, sellPolicy: _testPolicy), // Not met
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy), // Met
        WaitForEffectiveCredits(300, sellPolicy: _testPolicy), // Not met
      ]);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when no conditions met', () {
      final state = GlobalState.test(testRegistries, gp: 50);
      const waitFor = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy),
        WaitForEffectiveCredits(200, sellPolicy: _testPolicy),
      ]);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('isSatisfied returns false for empty conditions', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const waitFor = WaitForAnyOf([]);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('estimateTicks returns minimum of all conditions', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForAnyOf([
        WaitForSkillXp(Skill.woodcutting, 100),
        WaitForSkillXp(Skill.fishing, 50),
      ]);
      const rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {},
        xpPerTickBySkill: {
          Skill.woodcutting: 10.0, // 100/10 = 10 ticks
          Skill.fishing: 10.0, // 50/10 = 5 ticks
        },
        itemTypesPerTick: 0,
      );

      // Should return minimum (5 ticks for fishing)
      expect(waitFor.estimateTicks(state, rates), 5);
    });

    test('estimateTicks returns infTicks for empty conditions', () {
      final state = GlobalState.empty(testRegistries);
      const waitFor = WaitForAnyOf([]);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks returns 0 when any condition already satisfied', () {
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 100, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForAnyOf([
        WaitForSkillXp(Skill.woodcutting, 100), // Already met
        WaitForSkillXp(Skill.fishing, 50),
      ]);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('describe joins condition descriptions', () {
      const waitFor = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy),
        WaitForSkillXp(Skill.woodcutting, 50),
      ]);

      expect(waitFor.describe(), contains('OR'));
      expect(waitFor.describe(), contains('credits >= 100'));
      expect(waitFor.describe(), contains('Woodcutting XP >= 50'));
    });

    test('shortDescription uses first condition', () {
      const waitFor = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy, reason: 'Axe'),
        WaitForSkillXp(Skill.woodcutting, 50),
      ]);

      expect(waitFor.shortDescription, 'Axe affordable');
    });

    test('shortDescription returns Any condition for empty list', () {
      const waitFor = WaitForAnyOf([]);

      expect(waitFor.shortDescription, 'Any condition');
    });

    test('progress returns max progress among all conditions', () {
      final state = GlobalState.test(
        testRegistries,
        gp: 50,
        skillStates: const {
          Skill.woodcutting: SkillState(xp: 75, masteryPoolXp: 0),
        },
      );
      const waitFor = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy), // progress = 50
        WaitForSkillXp(Skill.woodcutting, 100), // progress = 75
      ]);

      // Should return max (75 from woodcutting)
      expect(waitFor.progress(state), 75);
    });

    test('progress returns 0 for empty conditions', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const waitFor = WaitForAnyOf([]);

      expect(waitFor.progress(state), 0);
    });
  });

  group('WaitFor equality', () {
    test('WaitForEffectiveCredits equality', () {
      const a = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);
      const b = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);
      const c = WaitForEffectiveCredits(200, sellPolicy: _testPolicy);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('WaitForSkillXp equality', () {
      const a = WaitForSkillXp(Skill.woodcutting, 100);
      const b = WaitForSkillXp(Skill.woodcutting, 100);
      const c = WaitForSkillXp(Skill.fishing, 100);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('WaitForMasteryXp equality', () {
      final action = testActions.woodcutting('Normal Tree');
      final a = WaitForMasteryXp(action.id, 100);
      final b = WaitForMasteryXp(action.id, 100);
      final c = WaitForMasteryXp(action.id, 200);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('WaitForAnyOf equality', () {
      const a = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy),
      ]);
      const b = WaitForAnyOf([
        WaitForEffectiveCredits(100, sellPolicy: _testPolicy),
      ]);
      const c = WaitForAnyOf([
        WaitForEffectiveCredits(200, sellPolicy: _testPolicy),
      ]);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('WaitFor with real game state', () {
    test('estimateTicks works with estimateRates for woodcutting', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(42));

      final rates = estimateRates(state);
      const waitFor = WaitForSkillXp(Skill.woodcutting, 100);

      final ticks = waitFor.estimateTicks(state, rates);
      expect(ticks, greaterThan(0));
      expect(ticks, lessThan(infTicks));
    });

    test('estimateTicks works with estimateRates for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(42));

      final rates = estimateRates(state);
      const waitFor = WaitForEffectiveCredits(100, sellPolicy: _testPolicy);

      final ticks = waitFor.estimateTicks(state, rates);
      expect(ticks, greaterThan(0));
      expect(ticks, lessThan(infTicks));
    });
  });

  group('WaitForInventoryDelta', () {
    test('isSatisfied returns true when count reaches target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 15),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      // Started with 5, want 10 more, target is 15
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns true when count exceeds target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 20),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      // Started with 5, want 10 more, target is 15 (we have 20)
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.isSatisfied(state), isTrue);
    });

    test('isSatisfied returns false when count is below target', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      // Started with 5, want 10 more, target is 15 (we only have 10)
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.isSatisfied(state), isFalse);
    });

    test('fromState captures current inventory count', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final waitFor = WaitForInventoryDelta.fromState(state, logs.id, 10);

      expect(waitFor.startCount, 5);
      expect(waitFor.delta, 10);
      expect(waitFor.targetCount, 15);
    });

    test('targetCount is startCount plus delta', () {
      final logs = testItems.byName('Normal Logs');
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.targetCount, 15);
    });

    test('estimateTicks returns 0 when already satisfied', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 20),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.estimateTicks(state, Rates.empty), 0);
    });

    test('estimateTicks returns infTicks when no production rate', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.estimateTicks(state, Rates.empty), infTicks);
    });

    test('estimateTicks calculates correctly with production rate', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 5),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);
      final rates = Rates(
        directGpPerTick: 0,
        itemFlowsPerTick: {logs.id: 0.5}, // 0.5 logs per tick
        xpPerTickBySkill: const {},
        itemTypesPerTick: 0,
      );

      // Need 10 logs at 0.5/tick = 20 ticks
      expect(waitFor.estimateTicks(state, rates), 20);
    });

    test('describe shows delta semantics', () {
      final logs = testItems.byName('Normal Logs');
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.describe(), contains('5 + 10 = 15'));
    });

    test('shortDescription shows delta', () {
      final logs = testItems.byName('Normal Logs');
      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.shortDescription, 'Acquire +10');
    });

    test('progress returns current count', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 12),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final waitFor = WaitForInventoryDelta(logs.id, 10, startCount: 5);

      expect(waitFor.progress(state), 12);
    });

    test(
      'delta semantics prevents premature satisfaction with existing items',
      () {
        // This is the critical regression test for the Acquire bug
        // If we already have 100 items and want to acquire 10 more,
        // delta semantics means target is 110, not 10
        final logs = testItems.byName('Normal Logs');
        final inventory = Inventory.fromItems(testItems, [
          ItemStack(logs, count: 100),
        ]);
        final state = GlobalState.test(testRegistries, inventory: inventory);

        // With delta semantics: startCount=100, delta=10, target=110
        final deltaWaitFor = WaitForInventoryDelta(
          logs.id,
          10,
          startCount: 100,
        );

        // Should NOT be satisfied with 100 items
        expect(deltaWaitFor.isSatisfied(state), isFalse);
        expect(deltaWaitFor.targetCount, 110);

        // Compare to WaitForInventoryAtLeast which would be wrongly satisfied
        final absoluteWaitFor = WaitForInventoryAtLeast(logs.id, 10);
        // This would be true (the bug) - having 100 >= 10
        expect(absoluteWaitFor.isSatisfied(state), isTrue);
      },
    );
  });
}
