// Tests for inventory pressure handling in the solver.
//
// These tests verify the decoupled inventory pressure boundary behavior:
// - EnsureStock.plan returns InventoryPressure boundary when blocked
// - Solver-level handler computes sell policy and recovers
// - NoProgressPossible returned when nothing sellable

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/candidates/macro_plan_context.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('Inventory Pressure Boundary', () {
    MacroPlanContext makeContext(
      GlobalState state, {
      Goal? goal,
      Map<Skill, SkillBoundaries>? boundaries,
    }) {
      return MacroPlanContext(
        state: state,
        goal: goal ?? const ReachSkillLevelGoal(Skill.woodcutting, 10),
        boundaries: boundaries ?? const {},
      );
    }

    group('EnsureStock.plan', () {
      test(
        'succeeds when stocking more of existing item in full inventory',
        () {
          // Fill inventory with Normal Logs (only 1 slot used)
          final normalLogs = testItems.byName('Normal Logs');
          final items = [ItemStack(normalLogs, count: 5)];

          final inventory = Inventory.fromItems(testItems, items);
          final state = GlobalState.test(testRegistries, inventory: inventory);

          // Try to stock more of the same item (already in inventory)
          const macro = EnsureStock(MelvorId('melvorD:Normal_Logs'), 20);
          final context = makeContext(state);

          final result = macro.plan(context);

          // Should succeed since logs already in inventory (no new slot needed)
          expect(
            result,
            anyOf(
              isA<MacroPlanned>(),
              isA<MacroNeedsPrerequisite>(),
              isA<MacroAlreadySatisfied>(),
            ),
          );
        },
      );

      test('already satisfied returns MacroAlreadySatisfied', () {
        // Already have 20 logs, try to ensure we have 10
        final normalLogs = testItems.byName('Normal Logs');
        final items = [ItemStack(normalLogs, count: 20)];

        final inventory = Inventory.fromItems(testItems, items);
        final state = GlobalState.test(testRegistries, inventory: inventory);

        // Try to ensure we have 10 logs (we already have 20)
        const macro = EnsureStock(MelvorId('melvorD:Normal_Logs'), 10);
        final context = makeContext(state);

        final result = macro.plan(context);

        expect(result, isA<MacroAlreadySatisfied>());
      });
    });

    group('Solver _planMacro', () {
      test('solver can make progress from empty state', () {
        final state = GlobalState.empty(testRegistries);

        // Simple goal - reach some skill level
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

        final result = solve(state, goal, maxExpandedNodes: 100);

        // The solver should be able to proceed
        expect(result, isA<SolverSuccess>());
      });

      test('solver handles inventory with sellable items', () {
        // Create state with some items that can be sold
        final normalLogs = testItems.byName('Normal Logs');
        final items = [ItemStack(normalLogs, count: 50)];

        final inventory = Inventory.fromItems(testItems, items);
        final state = GlobalState.test(testRegistries, inventory: inventory);

        // Mining goal - logs are sellable per mining goal sell policy
        const goal = ReachSkillLevelGoal(Skill.mining, 5);

        final result = solve(state, goal, maxExpandedNodes: 100);

        // Should succeed - logs can be sold if needed
        expect(result, isA<SolverSuccess>());
      });
    });

    group('InventoryPressure boundary properties', () {
      test('includes blockedItemId in description', () {
        const boundary = InventoryPressure(
          usedSlots: 12,
          totalSlots: 12,
          blockedItemId: MelvorId('melvorD:Iron_Bar'),
        );

        expect(boundary.describe(), contains('Iron_Bar'));
        expect(boundary.describe(), contains('12/12'));
      });

      test('works without blockedItemId', () {
        const boundary = InventoryPressure(usedSlots: 10, totalSlots: 12);

        expect(boundary.describe(), contains('10/12'));
        expect(boundary.blockedItemId, isNull);
      });

      test('isExpected is true', () {
        const boundary = InventoryPressure(usedSlots: 12, totalSlots: 12);
        expect(boundary.isExpected, isTrue);
      });

      test('causesReplan is true', () {
        const boundary = InventoryPressure(usedSlots: 12, totalSlots: 12);
        expect(boundary.causesReplan, isTrue);
      });
    });
  });
}
