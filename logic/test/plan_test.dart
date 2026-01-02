import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });
  group('GoalReachedBoundary', () {
    test('describe returns human-readable string', () {
      const boundary = GoalReachedBoundary();
      expect(boundary.describe(), 'Goal reached');
    });
  });

  group('UpgradeAffordableBoundary', () {
    test('describe includes upgrade name', () {
      const boundary = UpgradeAffordableBoundary(
        MelvorId('melvorD:Auto_Eat_Tier_I'),
        'Auto Eat Tier I',
      );
      expect(boundary.describe(), 'Upgrade Auto Eat Tier I affordable');
    });

    test('stores purchaseId correctly', () {
      const purchaseId = MelvorId('melvorD:Bank_Slot');
      const boundary = UpgradeAffordableBoundary(purchaseId, 'Bank Slot');
      expect(boundary.purchaseId, purchaseId);
    });
  });

  group('UnlockBoundary', () {
    test('describe includes skill, level, and unlocks', () {
      const boundary = UnlockBoundary(Skill.woodcutting, 15, 'Oak Trees');
      expect(boundary.describe(), 'Woodcutting L15 unlocks Oak Trees');
    });

    test('stores skill, level, and unlocks correctly', () {
      const boundary = UnlockBoundary(Skill.fishing, 20, 'Trout');
      expect(boundary.skill, Skill.fishing);
      expect(boundary.level, 20);
      expect(boundary.unlocks, 'Trout');
    });
  });

  group('InputsDepletedBoundary', () {
    test('describe includes action name', () {
      final actionId = ActionId.test(Skill.firemaking, 'Burn Oak Logs');
      final boundary = InputsDepletedBoundary(actionId);
      expect(boundary.describe(), contains('Burn Oak Logs'));
    });

    test('stores actionId correctly', () {
      final actionId = ActionId.test(Skill.cooking, 'Cook Shrimp');
      final boundary = InputsDepletedBoundary(actionId);
      expect(boundary.actionId, actionId);
    });
  });

  group('HorizonCapBoundary', () {
    test('describe includes ticks elapsed', () {
      const boundary = HorizonCapBoundary(86400);
      expect(boundary.describe(), 'Horizon cap reached (86400 ticks)');
    });

    test('stores ticksElapsed correctly', () {
      const boundary = HorizonCapBoundary(50000);
      expect(boundary.ticksElapsed, 50000);
    });
  });

  group('InventoryPressureBoundary', () {
    test('describe includes used and total slots', () {
      const boundary = InventoryPressureBoundary(45, 50);
      expect(boundary.describe(), 'Inventory pressure (45/50 slots)');
    });

    test('stores usedSlots and totalSlots correctly', () {
      const boundary = InventoryPressureBoundary(30, 40);
      expect(boundary.usedSlots, 30);
      expect(boundary.totalSlots, 40);
    });
  });

  group('Plan.prettyPrint', () {
    test('prints header with plan stats', () {
      const plan = Plan(
        steps: [],
        totalTicks: 1000,
        interactionCount: 5,
        expandedNodes: 100,
        enqueuedNodes: 200,
      );

      final output = plan.prettyPrint();

      expect(output, contains('=== Plan ==='));
      expect(output, contains('Total ticks: 1000'));
      expect(output, contains('Interactions: 5'));
      expect(output, contains('Expanded nodes: 100'));
      expect(output, contains('Enqueued nodes: 200'));
      expect(output, contains('Steps (0 total)'));
    });

    test('formats SwitchActivity step with action registry', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [InteractionStep(SwitchActivity(action.id))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint(actions: testActions);

      expect(output, contains('Switch to Normal Tree (woodcutting)'));
    });

    test('formats SwitchActivity step without action registry', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [InteractionStep(SwitchActivity(action.id))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Switch to'));
      expect(output, contains(action.id.toString()));
    });

    test('formats BuyShopItem step', () {
      const purchaseId = MelvorId('melvorD:Iron_Axe');
      const plan = Plan(
        steps: [InteractionStep(BuyShopItem(purchaseId))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Buy Iron Axe'));
    });

    test('formats SellItems with SellAllPolicy', () {
      const plan = Plan(
        steps: [InteractionStep(SellItems(SellAllPolicy()))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Sell all'));
    });

    test('formats SellItems with SellExceptPolicy', () {
      final plan = Plan(
        steps: [
          InteractionStep(
            SellItems(
              SellExceptPolicy({
                const MelvorId('melvorD:Normal_Logs'),
                const MelvorId('melvorD:Oak_Logs'),
              }),
            ),
          ),
        ],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Sell all except'));
    });

    test('formats WaitStep with duration', () {
      // 6000 ticks = 600 seconds = 10 minutes
      const plan = Plan(
        steps: [WaitStep(6000, WaitForSkillXp(Skill.woodcutting, 1000))],
        totalTicks: 6000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('10m 0s'));
      expect(output, contains('Skill +1'));
    });

    test('formats WaitStep with expected action', () {
      final action = testActions.woodcutting('Oak Tree');
      final plan = Plan(
        steps: [
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 500),
            expectedAction: action.id,
          ),
        ],
        totalTicks: 3000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint(actions: testActions);

      expect(output, contains('Oak Tree'));
    });

    test('formats MacroStep for TrainSkillUntil', () {
      const macro = TrainSkillUntil(
        Skill.mining,
        StopAtNextBoundary(Skill.mining),
      );
      const plan = Plan(
        steps: [
          MacroStep(
            macro,
            36000, // 1 hour
            WaitForSkillXp(Skill.mining, 10000),
          ),
        ],
        totalTicks: 36000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Macro: Mining'));
      expect(output, contains('1h 0m'));
    });

    test('formats MacroStep for AcquireItem', () {
      const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);
      const plan = Plan(
        steps: [
          MacroStep(
            macro,
            1200,
            WaitForInventoryAtLeast(MelvorId('melvorD:Normal_Logs'), 50),
          ),
        ],
        totalTicks: 1200,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Macro: Acquire 50x Normal Logs'));
    });

    test('formats duration in hours and minutes', () {
      const plan = Plan(
        steps: [
          WaitStep(
            39600, // 3960 seconds = 1h 6m
            WaitForSkillXp(Skill.fishing, 50000),
          ),
        ],
        totalTicks: 39600,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('1h 6m'));
    });

    test('formats duration in minutes and seconds', () {
      const plan = Plan(
        steps: [
          WaitStep(
            1230, // 123 seconds = 2m 3s
            WaitForSkillXp(Skill.fishing, 500),
          ),
        ],
        totalTicks: 1230,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('2m 3s'));
    });

    test('formats duration in seconds only', () {
      const plan = Plan(
        steps: [
          WaitStep(
            450, // 45 seconds
            WaitForSkillXp(Skill.fishing, 100),
          ),
        ],
        totalTicks: 450,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('45s'));
    });

    test('respects maxSteps parameter', () {
      final steps = List.generate(
        50,
        (i) => InteractionStep(BuyShopItem(MelvorId('melvorD:Item_$i'))),
      );
      final plan = Plan(steps: steps, totalTicks: 0, interactionCount: 50);

      final output = plan.prettyPrint(maxSteps: 10);

      expect(output, contains('Steps (50 total)'));
      expect(output, contains('... and 40 more steps'));
    });

    test('numbers steps starting from 1', () {
      const plan = Plan(
        steps: [
          InteractionStep(SellItems(SellAllPolicy())),
          InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe'))),
        ],
        totalTicks: 0,
        interactionCount: 2,
      );

      final output = plan.prettyPrint();

      expect(output, contains('1. Sell all'));
      expect(output, contains('2. Buy Iron Axe'));
    });

    test('empty plan shows zero steps', () {
      const plan = Plan.empty();

      final output = plan.prettyPrint();

      expect(output, contains('Steps (0 total)'));
      expect(output, contains('Total ticks: 0'));
    });
  });
}
