import 'package:logic/logic.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:test/test.dart';

void main() {
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
}
