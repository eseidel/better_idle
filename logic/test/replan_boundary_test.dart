import 'package:logic/logic.dart';
import 'package:logic/src/solver/replan_boundary.dart';
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
  });

  group('UpgradeAffordableEarly', () {
    test('describe includes purchase and cost', () {
      const boundary = UpgradeAffordableEarly(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
        cost: 5000,
      );
      expect(boundary.describe(), contains('Auto Eat Tier I'));
      expect(boundary.describe(), contains('5000'));
    });

    test('isExpected is true', () {
      const boundary = UpgradeAffordableEarly(
        purchaseId: MelvorId('melvorD:Auto_Eat_Tier_I'),
        cost: 5000,
      );
      expect(boundary.isExpected, isTrue);
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
  });

  group('boundaryFromStopReason', () {
    test('stillRunning returns null', () {
      final boundary = boundaryFromStopReason(ActionStopReason.stillRunning);
      expect(boundary, isNull);
    });

    test('outOfInputs returns InputsDepleted', () {
      final actionId = ActionId.test(Skill.firemaking, 'Burn Logs');
      const missingItem = MelvorId('melvorD:Normal_Logs');
      final boundary = boundaryFromStopReason(
        ActionStopReason.outOfInputs,
        actionId: actionId,
        missingItemId: missingItem,
      );
      expect(boundary, isA<InputsDepleted>());
      final inputsDepleted = boundary! as InputsDepleted;
      expect(inputsDepleted.actionId, actionId);
      expect(inputsDepleted.missingItemId, missingItem);
    });

    test('outOfInputs uses unknown when missingItemId not provided', () {
      final actionId = ActionId.test(Skill.firemaking, 'Burn Logs');
      final boundary = boundaryFromStopReason(
        ActionStopReason.outOfInputs,
        actionId: actionId,
      );
      expect(boundary, isA<InputsDepleted>());
      final inputsDepleted = boundary! as InputsDepleted;
      expect(inputsDepleted.missingItemId, const MelvorId('unknown:unknown'));
    });

    test('inventoryFull returns InventoryFull', () {
      final boundary = boundaryFromStopReason(ActionStopReason.inventoryFull);
      expect(boundary, isA<InventoryFull>());
    });

    test('playerDied returns Death', () {
      final boundary = boundaryFromStopReason(ActionStopReason.playerDied);
      expect(boundary, isA<Death>());
    });
  });
}
