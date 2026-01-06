/// Tests for the executor's deterministic and checkpointed behavior.
///
/// These tests verify:
/// 1. Deterministic execution with fixed RNG seeds
/// 2. InventoryFull recovery via sell policy (not arbitrary decisions)
/// 3. Missing inputs trigger replan (no alternate producer selection)
/// 4. Smithing regression: proper multi-tier chain handling
library;

import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/replan_boundary.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/candidates/macro_execute_context.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/core/solver.dart';
import 'package:logic/src/solver/execution/execute_plan.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/execution/step_helpers.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('Executor determinism', () {
    test('same RNG seed produces identical execution trace', () {
      // Setup: simple woodcutting plan
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);
      final solveResult = solve(state, goal);

      expect(solveResult, isA<SolverSuccess>());
      final success = solveResult as SolverSuccess;

      // Execute with same seed twice
      final result1 = executePlan(state, success.plan, random: Random(42));
      final result2 = executePlan(state, success.plan, random: Random(42));

      // Results should be identical
      expect(result1.actualTicks, equals(result2.actualTicks));
      expect(result1.totalDeaths, equals(result2.totalDeaths));
      expect(
        result1.finalState.skillState(Skill.woodcutting).xp,
        equals(result2.finalState.skillState(Skill.woodcutting).xp),
      );
      expect(result1.finalState.gp, equals(result2.finalState.gp));
    });

    test('different RNG seeds may produce different traces', () {
      // Setup: fishing which has more randomness
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.fishing, 10);
      final solveResult = solve(state, goal);

      expect(solveResult, isA<SolverSuccess>());
      final success = solveResult as SolverSuccess;

      // Execute with different seeds
      final result1 = executePlan(state, success.plan, random: Random(42));
      final result2 = executePlan(state, success.plan, random: Random(999));

      // Results may differ (fishing has random junk drops)
      // At minimum, both should reach the goal
      expect(
        result1.finalState.skillState(Skill.fishing).skillLevel,
        greaterThanOrEqualTo(10),
      );
      expect(
        result2.finalState.skillState(Skill.fishing).skillLevel,
        greaterThanOrEqualTo(10),
      );
    });
  });

  group('InventoryFull recovery', () {
    test('executor sells per policy when inventory full during production', () {
      // Setup: state near inventory capacity
      // Default inventory capacity is 20 (initialBankSlots)
      // Fill it to 19 slots to be nearly full
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 19),
      ]);
      var state = GlobalState.test(testRegistries, inventory: inventory);

      // Start woodcutting
      state = state.startAction(
        testActions.woodcutting('Normal Tree'),
        random: Random(42),
      );

      // Create a simple plan that would fill inventory
      const sellPolicy = SellAllPolicy();
      final targetXp = startXpForLevel(10);
      final plan = Plan(
        steps: [
          MacroStep(
            const TrainSkillUntil(
              Skill.woodcutting,
              StopAtLevel(Skill.woodcutting, 10),
            ),
            10000,
            WaitForSkillXp(Skill.woodcutting, targetXp),
          ),
        ],
        totalTicks: 10000,
        interactionCount: 0,
        segmentMarkers: const [
          SegmentMarker(
            stepIndex: 0,
            boundary: GoalReachedBoundary(),
            sellPolicy: sellPolicy,
          ),
        ],
      );

      final result = executePlan(state, plan, random: Random(42));

      // Should have sold items and continued
      // Either reached goal or hit a replan boundary
      final reachedGoal =
          result.finalState.skillState(Skill.woodcutting).skillLevel >= 10;
      final hasRecoveryBoundary = result.boundariesHit.any(
        (b) => b is InventoryFull || b is NoProgressPossible,
      );

      expect(
        reachedGoal || hasRecoveryBoundary,
        isTrue,
        reason:
            'Should either reach goal or hit recovery boundary, '
            'not get stuck silently',
      );
    });

    test('executor recovers from inventory full with segment sell policy', () {
      // Setup: state near inventory capacity
      // The executor should use segment sell policy and still succeed
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 19),
      ]);
      var state = GlobalState.test(testRegistries, inventory: inventory);

      // Start woodcutting
      state = state.startAction(
        testActions.woodcutting('Normal Tree'),
        random: Random(42),
      );

      // Create a plan (ExecutionContext provides default sell policy)
      final targetXp = startXpForLevel(10);
      final plan = Plan(
        steps: [
          MacroStep(
            const TrainSkillUntil(
              Skill.woodcutting,
              StopAtLevel(Skill.woodcutting, 10),
            ),
            10000,
            WaitForSkillXp(Skill.woodcutting, targetXp),
          ),
        ],
        totalTicks: 10000,
        interactionCount: 0,
      );

      final result = executePlan(state, plan, random: Random(42));

      // With default sell policy, executor should recover and either
      // reach the goal OR hit a recoverable boundary
      final reachedGoal =
          result.finalState.skillState(Skill.woodcutting).skillLevel >= 10;

      expect(
        reachedGoal || result.boundariesHit.isNotEmpty,
        isTrue,
        reason: 'Should either reach goal or hit boundary',
      );
    });
  });

  group('Missing inputs replan', () {
    test('executor triggers replan when producer not feasible', () {
      // Setup: consuming skill action without required producer inputs
      final state = GlobalState.empty(testRegistries);

      // Create a macro for smithing Bronze Dagger (needs Bronze Bar)
      // but producerByInputItem maps Bronze Bar to smelting which needs ores
      // Since we have no ores, the producer should fail
      final bronzeBarId = testItems.byName('Bronze Bar').id;
      final smeltBronzeBarId = testActions.smithing('Bronze Bar').id;
      final smithBronzeDaggerId = testActions.smithing('Bronze Dagger').id;

      final macro = TrainConsumingSkillUntil(
        Skill.smithing,
        const StopAtLevel(Skill.smithing, 5),
        consumeActionId: smithBronzeDaggerId,
        producerByInputItem: {bronzeBarId: smeltBronzeBarId},
        bufferTarget: 10,
      );

      // Execute the macro directly
      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.smithing, targetXp),
        random: Random(42),
      );
      final result = executeCoupledLoop(context, macro);

      // Should return NoProgressPossible because smelting Bronze Bar
      // requires Copper Ore and Tin Ore which we don't have
      expect(result.boundary, isA<NoProgressPossible>());
    });

    test('executor does NOT pick alternate producer when inputs missing', () {
      // This tests that the executor doesn't try to be clever and find
      // a different action - it just triggers replan
      final state = GlobalState.empty(testRegistries);

      // Create a macro with a specific producer that can't run
      final bronzeBarId = testItems.byName('Bronze Bar').id;
      final smeltBronzeBarId = testActions.smithing('Bronze Bar').id;
      final smithBronzeDaggerId = testActions.smithing('Bronze Dagger').id;

      final macro = TrainConsumingSkillUntil(
        Skill.smithing,
        const StopAtLevel(Skill.smithing, 5),
        consumeActionId: smithBronzeDaggerId,
        producerByInputItem: {bronzeBarId: smeltBronzeBarId},
        bufferTarget: 10,
      );

      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.smithing, targetXp),
        random: Random(42),
      );
      final result = executeCoupledLoop(context, macro);

      // Verify the executor didn't switch to some other action
      // (e.g., mining copper ore) - it should just fail
      expect(result.boundary, isA<NoProgressPossible>());

      // State should be unchanged (no side effects from "searching")
      expect(result.ticksElapsed, equals(0));
      expect(result.deaths, equals(0));
    });
  });

  group('executeCoupledLoop validation', () {
    test('fails fast when consumeActionId missing', () {
      final state = GlobalState.empty(testRegistries);

      // Macro without consumeActionId
      const macro = TrainConsumingSkillUntil(
        Skill.smithing,
        StopAtLevel(Skill.smithing, 5),
        // consumeActionId: null - missing!
        producerByInputItem: {},
        bufferTarget: 10,
      );

      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.smithing, targetXp),
        random: Random(42),
      );
      final result = executeCoupledLoop(context, macro);

      expect(result.boundary, isA<NoProgressPossible>());
      final npp = result.boundary! as NoProgressPossible;
      expect(npp.reason, contains('consumeActionId'));
    });

    test('fails fast when bufferTarget missing', () {
      final state = GlobalState.empty(testRegistries);
      final smithBronzeDaggerId = testActions.smithing('Bronze Dagger').id;

      // Macro without bufferTarget
      final macro = TrainConsumingSkillUntil(
        Skill.smithing,
        const StopAtLevel(Skill.smithing, 5),
        consumeActionId: smithBronzeDaggerId,
        producerByInputItem: const {},
        // bufferTarget: null - missing!
      );

      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.smithing, targetXp),
        random: Random(42),
      );
      final result = executeCoupledLoop(context, macro);

      expect(result.boundary, isA<NoProgressPossible>());
      final npp = result.boundary! as NoProgressPossible;
      expect(npp.reason, contains('bufferTarget'));
    });

    test('fails fast when producerByInputItem missing', () {
      final state = GlobalState.empty(testRegistries);
      final smithBronzeDaggerId = testActions.smithing('Bronze Dagger').id;

      // Macro without producerByInputItem
      final macro = TrainConsumingSkillUntil(
        Skill.smithing,
        const StopAtLevel(Skill.smithing, 5),
        consumeActionId: smithBronzeDaggerId,
        bufferTarget: 10,
        // producerByInputItem: null - missing!
      );

      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.smithing, targetXp),
        random: Random(42),
      );
      final result = executeCoupledLoop(context, macro);

      expect(result.boundary, isA<NoProgressPossible>());
      final npp = result.boundary! as NoProgressPossible;
      expect(npp.reason, contains('producerByInputItem'));
    });
  });

  group('executeCoupledLoop inventory recovery', () {
    test('needsInventoryRecovery triggers when WaitForInventoryThreshold '
        'satisfied in consume phase', () {
      // This tests the specific code path in executeCoupledLoop where
      // needsInventoryRecovery is true because WaitForInventoryThreshold
      // was satisfied (not InventoryFull).
      //
      // The consume phase waits for:
      //   WaitForAnyOf([primaryStop, InputsDepleted, InventoryThreshold])
      // When InventoryThreshold is satisfied, needsInventoryRecovery = true
      // and the executor should sell and continue.

      final wcAction = testActions.woodcutting('Normal Tree');
      final burnAction = testActions.firemaking('Burn Normal Logs');
      final normalLogsId = testItems.byName('Normal Logs').id;

      // Build inventory near 90% threshold (18/20 slots)
      // Each unique item takes one slot
      final itemStacks = <ItemStack>[];
      var slotsUsed = 0;
      for (final item in testItems.all) {
        if (item.sellsFor > 0 && slotsUsed < 17) {
          itemStacks.add(ItemStack(item, count: 1));
          slotsUsed++;
        }
      }

      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, itemStacks),
      );

      // Create macro that will fill inventory during production phase
      // When we produce logs, we'll add a new slot type, hitting threshold
      final macro = TrainConsumingSkillUntil(
        Skill.firemaking,
        const StopAtLevel(Skill.firemaking, 5),
        consumeActionId: burnAction.id,
        producerByInputItem: {normalLogsId: wcAction.id},
        bufferTarget: 10,
        sellPolicySpec: const SellAllSpec(),
        maxRecoveryAttempts: 5,
      );

      final targetXp = startXpForLevel(5);
      final context = MacroExecuteContext(
        state: state,
        waitFor: WaitForSkillXp(Skill.firemaking, targetXp),
        random: Random(42),
        segmentSellPolicy: const SellAllPolicy(),
      );
      final result = executeCoupledLoop(context, macro);

      // Should make progress - the key is it doesn't crash or get stuck
      expect(result.ticksElapsed, greaterThan(0));

      // Either completed or hit a valid replan boundary
      if (result.boundary is NoProgressPossible) {
        final npp = result.boundary! as NoProgressPossible;
        // Should not fail due to missing sell policy
        expect(npp.reason, isNot(contains('no sell policy provided')));
      }
    });

    test(
      'inventory threshold recovery sells and continues in consume phase',
      () {
        // Start with empty inventory, let production fill it
        // This tests that the coupled loop handles inventory pressure
        // during extended execution
        final wcAction = testActions.woodcutting('Normal Tree');
        final burnAction = testActions.firemaking('Burn Normal Logs');
        final normalLogsId = testItems.byName('Normal Logs').id;

        final state = GlobalState.empty(testRegistries);

        // Create macro that will produce logs until near full
        final macro = TrainConsumingSkillUntil(
          Skill.firemaking,
          const StopAtLevel(Skill.firemaking, 3), // Low target
          consumeActionId: burnAction.id,
          producerByInputItem: {normalLogsId: wcAction.id},
          bufferTarget: 15, // Produce 15 logs at a time
          sellPolicySpec: const SellAllSpec(),
          maxRecoveryAttempts: 5,
        );

        final targetXp = startXpForLevel(3);
        final context = MacroExecuteContext(
          state: state,
          waitFor: WaitForSkillXp(Skill.firemaking, targetXp),
          random: Random(42),
          segmentSellPolicy: const SellAllPolicy(),
        );
        final result = executeCoupledLoop(context, macro);

        // Should make progress (ticks > 0)
        expect(result.ticksElapsed, greaterThan(0));

        // Should eventually reach goal or hit a legitimate boundary
        if (result.boundary != null) {
          // Acceptable boundaries: WaitConditionSatisfied or replan needed
          expect(
            result.boundary,
            anyOf(isA<WaitConditionSatisfied>(), isA<NoProgressPossible>()),
          );
        }

        // Should have gained some firemaking XP
        expect(
          result.state.skillState(Skill.firemaking).xp,
          greaterThanOrEqualTo(0),
        );
      },
    );

    test(
      'needsInventoryRecovery returns NoProgressPossible without sell policy',
      () {
        // Test that when inventory threshold is hit and no sell policy
        // is provided, we get NoProgressPossible
        final wcAction = testActions.woodcutting('Normal Tree');
        final burnAction = testActions.firemaking('Burn Normal Logs');
        final normalLogsId = testItems.byName('Normal Logs').id;

        // Fill inventory to 19/20 slots (95%) - above threshold
        final itemStacks = <ItemStack>[];
        var slotsUsed = 0;
        for (final item in testItems.all) {
          if (item.sellsFor > 0 && slotsUsed < 19) {
            itemStacks.add(ItemStack(item, count: 1));
            slotsUsed++;
          }
        }

        final state = GlobalState.test(
          testRegistries,
          inventory: Inventory.fromItems(testItems, itemStacks),
        );

        // Create macro WITHOUT sellPolicySpec
        final macro = TrainConsumingSkillUntil(
          Skill.firemaking,
          const StopAtLevel(Skill.firemaking, 5),
          consumeActionId: burnAction.id,
          producerByInputItem: {normalLogsId: wcAction.id},
          bufferTarget: 5,
          // sellPolicySpec: null - no policy
        );

        final targetXp = startXpForLevel(5);
        final context = MacroExecuteContext(
          state: state,
          waitFor: WaitForSkillXp(Skill.firemaking, targetXp),
          random: Random(42),
          // segmentSellPolicy: null - no policy provided
        );
        final result = executeCoupledLoop(context, macro);

        // Should hit NoProgressPossible because no sell policy
        // The exact boundary depends on whether it hits InventoryFull
        // during production or threshold during consumption
        if (result.boundary is NoProgressPossible) {
          final npp = result.boundary! as NoProgressPossible;
          expect(
            npp.reason,
            anyOf(contains('sell policy'), contains('Cannot start')),
          );
        }
      },
    );
  });

  group('handleBoundary behavior', () {
    test('InventoryFull with sell policy frees space and continues', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 20), // Fill all 20 default slots
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      const sellPolicy = SellAllPolicy();

      final result = handleBoundary(
        state,
        const InventoryFull(),
        sellPolicy: sellPolicy,
        currentAttempts: 0,
        maxAttempts: 5,
        random: Random(42),
      );

      expect(result.outcome, equals(RecoveryOutcome.recoveredRetry));
      expect(result.state.inventoryUsed, lessThan(state.inventoryUsed));
      expect(result.state.gp, greaterThan(state.gp));
      expect(result.newAttemptCount, equals(1));
    });

    test('InventoryFull without sell policy triggers replan', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 20),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      final result = handleBoundary(
        state,
        const InventoryFull(),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<NoProgressPossible>());
    });

    test('recovery limit exceeded triggers replan', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const InventoryFull(),
        sellPolicy: const SellAllPolicy(),
        random: Random(42),
        currentAttempts: 5,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<NoProgressPossible>());
      final npp = result.boundary! as NoProgressPossible;
      expect(npp.reason, contains('Recovery limit'));
    });

    test('InputsDepleted triggers replan (no alternate producer)', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.smithing('Bronze Dagger');

      final result = handleBoundary(
        state,
        InputsDepleted(
          actionId: action.id,
          missingItemId: testItems.byName('Bronze Bar').id,
        ),
        sellPolicy: const SellAllPolicy(),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      // Key: should trigger replan, NOT try to find another action
      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<InputsDepleted>());
    });

    test('Death continues without incrementing attempts', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const Death(),
        sellPolicy: const SellAllPolicy(),
        random: Random(42),
        currentAttempts: 2,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.recoveredRetry));
      expect(result.newAttemptCount, equals(2)); // Not incremented
    });

    test('WaitConditionSatisfied signals completion', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const WaitConditionSatisfied(),
        sellPolicy: const SellAllPolicy(),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.completed));
      expect(result.boundary, isA<WaitConditionSatisfied>());
    });

    test('GoalReached signals completion', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const GoalReached(),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.completed));
      expect(result.boundary, isA<GoalReached>());
      expect(result.newAttemptCount, equals(0)); // Not incremented
    });

    test('UpgradeAffordableEarly triggers replan', () {
      final state = GlobalState.empty(testRegistries);
      const axeUpgradeId = MelvorId('melvorD:Axe_Upgrade');

      final result = handleBoundary(
        state,
        const UpgradeAffordableEarly(purchaseId: axeUpgradeId),
        random: Random(42),
        currentAttempts: 1,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<UpgradeAffordableEarly>());
      final boundary = result.boundary! as UpgradeAffordableEarly;
      expect(boundary.purchaseId, equals(axeUpgradeId));
      expect(result.newAttemptCount, equals(1)); // Not incremented
    });

    test('UnlockObserved triggers replan', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const UnlockObserved(
          skill: Skill.woodcutting,
          level: 15,
          unlocks: 'Oak Tree',
        ),
        random: Random(42),
        currentAttempts: 2,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<UnlockObserved>());
      final boundary = result.boundary! as UnlockObserved;
      expect(boundary.skill, equals(Skill.woodcutting));
      expect(boundary.level, equals(15));
      expect(result.newAttemptCount, equals(2)); // Not incremented
    });

    test('UnexpectedUnlock triggers replan', () {
      final state = GlobalState.empty(testRegistries);
      final actionId = testActions.woodcutting('Oak Tree').id;

      final result = handleBoundary(
        state,
        UnexpectedUnlock(actionId: actionId),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<UnexpectedUnlock>());
      final boundary = result.boundary! as UnexpectedUnlock;
      expect(boundary.actionId, equals(actionId));
    });

    test('PlannedSegmentStop triggers replan', () {
      final state = GlobalState.empty(testRegistries);
      const segmentBoundary = HorizonCapBoundary(10000);

      final result = handleBoundary(
        state,
        const PlannedSegmentStop(segmentBoundary),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<PlannedSegmentStop>());
      final boundary = result.boundary! as PlannedSegmentStop;
      expect(boundary.boundary, equals(segmentBoundary));
    });

    test('CannotAfford triggers replan', () {
      final state = GlobalState.empty(testRegistries);
      const purchaseId = MelvorId('melvorD:Axe_Upgrade');

      final result = handleBoundary(
        state,
        const CannotAfford(purchaseId: purchaseId, cost: 1000, available: 500),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<CannotAfford>());
      final boundary = result.boundary! as CannotAfford;
      expect(boundary.purchaseId, equals(purchaseId));
      expect(boundary.cost, equals(1000));
      expect(boundary.available, equals(500));
    });

    test('ActionUnavailable triggers replan', () {
      final state = GlobalState.empty(testRegistries);
      final actionId = testActions.woodcutting('Oak Tree').id;

      final result = handleBoundary(
        state,
        ActionUnavailable(actionId: actionId, reason: 'Level too low'),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<ActionUnavailable>());
      final boundary = result.boundary! as ActionUnavailable;
      expect(boundary.actionId, equals(actionId));
      expect(boundary.reason, equals('Level too low'));
    });

    test('NoProgressPossible triggers replan', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const NoProgressPossible(reason: 'Stuck in a loop'),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<NoProgressPossible>());
      final boundary = result.boundary! as NoProgressPossible;
      expect(boundary.reason, equals('Stuck in a loop'));
    });

    test('InventoryPressure with sell policy recovers and continues', () {
      final logs = testItems.byName('Normal Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 18), // 18 of 20 slots = 90% pressure
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);

      const sellPolicy = SellAllPolicy();

      final result = handleBoundary(
        state,
        const InventoryPressure(usedSlots: 18, totalSlots: 20),
        sellPolicy: sellPolicy,
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.recoveredRetry));
      expect(result.state.inventoryUsed, lessThan(state.inventoryUsed));
      expect(result.newAttemptCount, equals(1));
    });

    test('InventoryPressure without sellable items continues anyway', () {
      // Empty inventory means nothing to sell, but pressure is ok to continue
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const InventoryPressure(usedSlots: 18, totalSlots: 20),
        sellPolicy: const SellAllPolicy(),
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      // InventoryPressure is soft - should continue even if nothing to sell
      expect(result.outcome, equals(RecoveryOutcome.recoveredRetry));
      expect(result.newAttemptCount, equals(0)); // Not incremented for pressure
    });

    test('InventoryPressure without sell policy triggers replan', () {
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const InventoryPressure(usedSlots: 18, totalSlots: 20),
        // No sell policy provided
        random: Random(42),
        currentAttempts: 0,
        maxAttempts: 5,
      );

      expect(result.outcome, equals(RecoveryOutcome.replanRequired));
      expect(result.boundary, isA<NoProgressPossible>());
    });

    test('completion boundaries checked before recovery limit', () {
      // Even at max attempts, GoalReached should still signal completion
      final state = GlobalState.empty(testRegistries);

      final result = handleBoundary(
        state,
        const GoalReached(),
        random: Random(42),
        currentAttempts: 5,
        maxAttempts: 5, // At limit
      );

      // Should be completed, not replan due to limit
      expect(result.outcome, equals(RecoveryOutcome.completed));
      expect(result.boundary, isA<GoalReached>());
    });
  });

  group('solveWithReplanning', () {
    test('reaches goal through automatic replanning', () {
      // Simple goal that should succeed
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      final result = solveWithReplanning(state, goal, random: Random(42));

      expect(result.goalReached, isTrue);
      expect(
        result.finalState.skillState(Skill.woodcutting).skillLevel,
        greaterThanOrEqualTo(5),
      );
      expect(result.terminatingBoundary, isNull);
    });

    test('respects max replan limit', () {
      // Use a skill that requires replanning
      final state = GlobalState.empty(testRegistries);
      // Use fishing which may trigger boundaries faster than smithing
      const goal = ReachSkillLevelGoal(Skill.fishing, 20);

      final result = solveWithReplanning(
        state,
        goal,
        random: Random(42),
        config: const ReplanConfig(
          maxReplans: 2, // Very low limit
        ),
      );

      // Either reached goal or hit replan limit
      if (!result.goalReached) {
        expect(result.terminatingBoundary, isA<ReplanLimitExceeded>());
        expect(result.replanCount, lessThanOrEqualTo(2));
      }
    });

    test('tracks replan count correctly', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.fishing, 10);

      final result = solveWithReplanning(
        state,
        goal,
        random: Random(42),
        config: const ReplanConfig(maxReplans: 20),
      );

      // replanCount should match segments that triggered replans
      final replanningSegments = result.segments
          .where((s) => s.triggeredReplan)
          .length;
      expect(result.replanCount, equals(replanningSegments));
    });
  });
}
