import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/step_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('GoalReached', () {
    test('describe returns human-readable string', () {
      const boundary = GoalReached();
      expect(boundary.describe(), 'Goal reached');
    });

    test('isExpected is true', () {
      const boundary = GoalReached();
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is false', () {
      const boundary = GoalReached();
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('InputsDepleted', () {
    test('describe includes action and missing item', () {
      final boundary = InputsDepleted(
        actionId: ActionId.test(Skill.firemaking, 'Burn Oak Logs'),
        missingItemId: const MelvorId('melvorD:Oak_Logs'),
      );
      expect(boundary.describe(), contains('Burn_Oak_Logs'));
      expect(boundary.describe(), contains('Oak Logs'));
    });

    test('isExpected is true', () {
      final boundary = InputsDepleted(
        actionId: ActionId.test(Skill.firemaking, 'Burn Oak Logs'),
        missingItemId: const MelvorId('melvorD:Oak_Logs'),
      );
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      final boundary = InputsDepleted(
        actionId: ActionId.test(Skill.firemaking, 'Burn Oak Logs'),
        missingItemId: const MelvorId('melvorD:Oak_Logs'),
      );
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('InventoryFull', () {
    test('describe returns human-readable string', () {
      const boundary = InventoryFull();
      expect(boundary.describe(), 'Inventory full');
    });

    test('isExpected is true', () {
      const boundary = InventoryFull();
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      const boundary = InventoryFull();
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('Death', () {
    test('describe returns human-readable string', () {
      const boundary = Death();
      expect(boundary.describe(), 'Player died');
    });

    test('isExpected is true', () {
      const boundary = Death();
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is false', () {
      const boundary = Death();
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('WaitConditionSatisfied', () {
    test('describe returns human-readable string', () {
      const boundary = WaitConditionSatisfied();
      expect(boundary.describe(), 'Wait condition satisfied');
    });

    test('isExpected is true', () {
      const boundary = WaitConditionSatisfied();
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is false', () {
      const boundary = WaitConditionSatisfied();
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('UpgradeAffordableEarly', () {
    test('describe includes purchase name', () {
      const boundary = UpgradeAffordableEarly(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
      );
      expect(boundary.describe(), contains('Auto Eat Tier I'));
    });

    test('isExpected is true', () {
      const boundary = UpgradeAffordableEarly(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
      );
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is false', () {
      const boundary = UpgradeAffordableEarly(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
      );
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('UnexpectedUnlock', () {
    test('describe includes action name', () {
      final boundary = UnexpectedUnlock(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.describe(), contains('Cut Oak'));
    });

    test('isExpected is true', () {
      final boundary = UnexpectedUnlock(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      final boundary = UnexpectedUnlock(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('CannotAfford', () {
    test('describe includes purchase, cost, and available', () {
      const boundary = CannotAfford(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
        cost: 5000,
        available: 1000,
      );
      expect(boundary.describe(), contains('Auto Eat Tier I'));
      expect(boundary.describe(), contains('5000'));
      expect(boundary.describe(), contains('1000'));
    });

    test('isExpected is false', () {
      const boundary = CannotAfford(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
        cost: 5000,
        available: 1000,
      );
      expect(boundary.isExpected, isFalse);
    });

    test('causesReplan is true', () {
      const boundary = CannotAfford(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
        cost: 5000,
        available: 1000,
      );
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('ActionUnavailable', () {
    test('describe includes action name', () {
      final boundary = ActionUnavailable(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.describe(), contains('Cut Oak'));
    });

    test('describe includes reason when provided', () {
      final boundary = ActionUnavailable(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
        reason: 'Level too low',
      );
      expect(boundary.describe(), contains('Cut Oak'));
      expect(boundary.describe(), contains('Level too low'));
    });

    test('describe works without reason', () {
      final boundary = ActionUnavailable(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      // When no reason is provided, description ends with "unavailable"
      expect(boundary.describe(), endsWith('unavailable'));
    });

    test('isExpected is false', () {
      final boundary = ActionUnavailable(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.isExpected, isFalse);
    });

    test('causesReplan is true', () {
      final boundary = ActionUnavailable(
        actionId: ActionId.test(Skill.woodcutting, 'Cut Oak'),
      );
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('NoProgressPossible', () {
    test('describe works without reason', () {
      const boundary = NoProgressPossible();
      expect(boundary.describe(), 'No progress possible');
    });

    test('describe includes reason when provided', () {
      const boundary = NoProgressPossible(reason: 'No available actions');
      expect(boundary.describe(), contains('No available actions'));
    });

    test('isExpected is false', () {
      const boundary = NoProgressPossible();
      expect(boundary.isExpected, isFalse);
    });

    test('causesReplan is true', () {
      const boundary = NoProgressPossible();
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('PlannedSegmentStop', () {
    test('describe includes wrapped boundary info', () {
      const boundary = PlannedSegmentStop('HorizonCapBoundary(1000)');
      expect(boundary.describe(), contains('Planned stop'));
      expect(boundary.describe(), contains('HorizonCapBoundary'));
    });

    test('isExpected is true', () {
      const boundary = PlannedSegmentStop('test');
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      const boundary = PlannedSegmentStop('test');
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('UnlockObserved', () {
    test('describe includes skill and level when provided', () {
      const boundary = UnlockObserved(
        skill: Skill.woodcutting,
        level: 15,
        unlocks: 'Oak Trees',
      );
      expect(boundary.describe(), contains('Woodcutting'));
      expect(boundary.describe(), contains('L15'));
      expect(boundary.describe(), contains('Oak Trees'));
    });

    test('describe works with minimal info', () {
      const boundary = UnlockObserved();
      expect(boundary.describe(), 'Unlock observed');
    });

    test('describe works with partial info', () {
      const boundary = UnlockObserved(skill: Skill.mining);
      expect(boundary.describe(), contains('Mining'));
    });

    test('isExpected is true', () {
      const boundary = UnlockObserved();
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      const boundary = UnlockObserved();
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('InventoryPressure', () {
    test('describe includes slot counts', () {
      const boundary = InventoryPressure(usedSlots: 18, totalSlots: 20);
      expect(boundary.describe(), contains('18'));
      expect(boundary.describe(), contains('20'));
    });

    test('pressure returns correct ratio', () {
      const boundary = InventoryPressure(usedSlots: 18, totalSlots: 20);
      expect(boundary.pressure, closeTo(0.9, 0.001));
    });

    test('isExpected is true', () {
      const boundary = InventoryPressure(usedSlots: 18, totalSlots: 20);
      expect(boundary.isExpected, isTrue);
    });

    test('causesReplan is true', () {
      const boundary = InventoryPressure(usedSlots: 18, totalSlots: 20);
      expect(boundary.causesReplan, isTrue);
    });
  });

  group('ReplanLimitExceeded', () {
    test('describe includes limit', () {
      const boundary = ReplanLimitExceeded(10);
      expect(boundary.describe(), contains('10'));
      expect(boundary.describe(), contains('exceeded'));
    });

    test('isExpected is false', () {
      const boundary = ReplanLimitExceeded(10);
      expect(boundary.isExpected, isFalse);
    });

    test('causesReplan is false', () {
      const boundary = ReplanLimitExceeded(10);
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('TimeBudgetExceeded', () {
    test('describe includes budget and actual', () {
      const boundary = TimeBudgetExceeded(1000, 1500);
      expect(boundary.describe(), contains('1000'));
      expect(boundary.describe(), contains('1500'));
      expect(boundary.describe(), contains('exceeded'));
    });

    test('isExpected is false', () {
      const boundary = TimeBudgetExceeded(1000, 1500);
      expect(boundary.isExpected, isFalse);
    });

    test('causesReplan is false', () {
      const boundary = TimeBudgetExceeded(1000, 1500);
      expect(boundary.causesReplan, isFalse);
    });
  });

  group('segmentBoundaryToReplan', () {
    test('GoalReachedBoundary converts to GoalReached', () {
      const segmentBoundary = GoalReachedBoundary();
      final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
      expect(replanBoundary, isA<GoalReached>());
    });

    test('UpgradeAffordableBoundary converts to UpgradeAffordableEarly', () {
      const segmentBoundary = UpgradeAffordableBoundary(
        MelvorId('melvorD:Auto_Eat_Tier_I'),
        'Auto Eat Tier I',
      );
      final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
      expect(replanBoundary, isA<UpgradeAffordableEarly>());
      final upgrade = replanBoundary as UpgradeAffordableEarly;
      expect(upgrade.purchaseId, const MelvorId('melvorD:Auto_Eat_Tier_I'));
    });

    test('UnlockBoundary converts to UnlockObserved (not GoalReached)', () {
      const segmentBoundary = UnlockBoundary(
        Skill.woodcutting,
        15,
        'Oak Trees',
      );
      final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
      // Key test: UnlockBoundary should NOT convert to GoalReached
      expect(replanBoundary, isNot(isA<GoalReached>()));
      expect(replanBoundary, isA<UnlockObserved>());
      final unlock = replanBoundary as UnlockObserved;
      expect(unlock.skill, Skill.woodcutting);
      expect(unlock.level, 15);
      expect(unlock.unlocks, 'Oak Trees');
    });

    test('InputsDepletedBoundary converts to InputsDepleted', () {
      final actionId = ActionId.test(Skill.firemaking, 'Burn Logs');
      const missingItem = MelvorId('melvorD:Normal_Logs');
      final segmentBoundary = InputsDepletedBoundary(actionId, missingItem);
      final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
      expect(replanBoundary, isA<InputsDepleted>());
      final inputsDepleted = replanBoundary as InputsDepleted;
      expect(inputsDepleted.actionId, actionId);
      expect(inputsDepleted.missingItemId, missingItem);
    });

    test(
      'HorizonCapBoundary converts to PlannedSegmentStop (not GoalReached)',
      () {
        const segmentBoundary = HorizonCapBoundary(10000);
        final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
        // Key test: HorizonCapBoundary should NOT convert to GoalReached
        expect(replanBoundary, isNot(isA<GoalReached>()));
        expect(replanBoundary, isA<PlannedSegmentStop>());
      },
    );

    test('InventoryPressureBoundary converts to InventoryPressure '
        '(not InventoryFull)', () {
      const segmentBoundary = InventoryPressureBoundary(18, 20);
      final replanBoundary = segmentBoundaryToReplan(segmentBoundary);
      // Key test: InventoryPressureBoundary should NOT convert to InventoryFull
      expect(replanBoundary, isNot(isA<InventoryFull>()));
      expect(replanBoundary, isA<InventoryPressure>());
      final pressure = replanBoundary as InventoryPressure;
      expect(pressure.usedSlots, 18);
      expect(pressure.totalSlots, 20);
    });
  });
}
