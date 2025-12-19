import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';
import 'package:test/test.dart';

void main() {
  group('applyInteraction', () {
    test('SwitchActivity switches to a new activity', () {
      final state = GlobalState.empty();
      const interaction = SwitchActivity('Normal Tree');

      final newState = applyInteraction(state, interaction);

      expect(newState.activeAction?.name, 'Normal Tree');
    });

    test('SwitchActivity clears existing action first', () {
      var state = GlobalState.empty();
      state = state.startAction(
        actionRegistry.byName('Raw Shrimp'),
        random: Random(0),
      );
      const interaction = SwitchActivity('Normal Tree');

      final newState = applyInteraction(state, interaction);

      expect(newState.activeAction?.name, 'Normal Tree');
    });

    test('BuyUpgrade purchases an upgrade', () {
      final state = GlobalState.empty().copyWith(gp: 100);
      const interaction = BuyUpgrade(UpgradeType.axe);

      final newState = applyInteraction(state, interaction);

      expect(newState.shop.axeLevel, 1);
      expect(newState.gp, 50); // Iron Axe costs 50
    });

    test('BuyUpgrade throws when cannot afford', () {
      final state = GlobalState.empty().copyWith(gp: 10);
      const interaction = BuyUpgrade(UpgradeType.axe);

      expect(
        () => applyInteraction(state, interaction),
        throwsA(isA<StateError>()),
      );
    });

    test('SellAll sells all items in inventory', () {
      final logs = itemRegistry.byName('Normal Logs');
      final oak = itemRegistry.byName('Oak Logs');
      final inventory = Inventory.fromItems([
        ItemStack(logs, count: 10),
        ItemStack(oak, count: 5),
      ]);
      final state = GlobalState.empty().copyWith(inventory: inventory, gp: 0);
      const interaction = SellAll();

      final newState = applyInteraction(state, interaction);

      expect(newState.inventory.items, isEmpty);
      // Normal logs sell for 1, oak for 5
      expect(newState.gp, 10 * logs.sellsFor + 5 * oak.sellsFor);
    });
  });

  group('advance', () {
    test('advances state by specified ticks', () {
      var state = GlobalState.empty();
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));
      final initialGp = state.gp;

      // advance uses expected-value model for rate-modelable activities
      // so we check that GP increases appropriately
      final newState = advance(state, 100);

      // Normal Tree: 1 gold / 30 ticks = 0.033 gold/tick
      // After 100 ticks: expect ~3 gold
      expect(newState.gp, greaterThan(initialGp));
    });

    test('is deterministic', () {
      var state = GlobalState.empty();
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final state1 = advance(state, 100);
      final state2 = advance(state, 100);

      expect(state1.gp, state2.gp);
      // Skill XP should also match
      expect(
        state1.skillState(Skill.woodcutting).xp,
        state2.skillState(Skill.woodcutting).xp,
      );
    });

    test('returns same state when deltaTicks is 0', () {
      var state = GlobalState.empty();
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final newState = advance(state, 0);

      expect(
        newState.activeAction?.remainingTicks,
        state.activeAction?.remainingTicks,
      );
    });
  });

  group('solveToCredits', () {
    test('returns empty plan when goal already met', () {
      final state = GlobalState.empty().copyWith(gp: 1000);

      final result = solveToCredits(state, 500);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.steps, isEmpty);
      expect(success.plan.totalTicks, 0);
      expect(success.plan.interactionCount, 0);
    });

    test('finds a plan to reach goal with single activity', () {
      var state = GlobalState.empty();
      // Start with an activity already running
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      // Small goal that should be reachable
      final result = solveToCredits(state, 10);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
      // Should just need to wait
      expect(success.plan.steps.whereType<WaitStep>(), isNotEmpty);
    });

    test('plan includes switching activity when beneficial', () {
      // Start with no activity - solver needs to switch
      final state = GlobalState.empty();

      final result = solveToCredits(state, 20);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      // Should include a switch activity step
      final switches = success.plan.steps.whereType<InteractionStep>().where(
        (step) => step.interaction is SwitchActivity,
      );
      expect(switches, isNotEmpty);
    });

    test('plan may include buying upgrade when it improves time-to-goal', () {
      // Start with enough money for Iron Axe and activity running
      var state = GlobalState.empty().copyWith(gp: 50);
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      // Moderate goal - may or may not benefit from upgrade
      final result = solveToCredits(state, 200);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
    });

    test('respects maxExpandedNodes limit', () {
      final state = GlobalState.empty();

      // Set a very low limit
      final result = solveToCredits(
        state,
        1000000, // Very high goal
        maxExpandedNodes: 10,
      );

      expect(result, isA<SolverFailed>());
      final failure = result as SolverFailed;
      expect(failure.failure.reason, contains('max expanded nodes'));
    });

    test('produces deterministic results', () {
      var state = GlobalState.empty();
      final action = actionRegistry.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final result1 = solveToCredits(state, 50);
      final result2 = solveToCredits(state, 50);

      expect(result1, isA<SolverSuccess>());
      expect(result2, isA<SolverSuccess>());

      final plan1 = (result1 as SolverSuccess).plan;
      final plan2 = (result2 as SolverSuccess).plan;

      expect(plan1.totalTicks, plan2.totalTicks);
      expect(plan1.interactionCount, plan2.interactionCount);
      expect(plan1.steps.length, plan2.steps.length);
    });
  });

  group('Plan', () {
    test('prettyPrint outputs plan summary', () {
      const plan = Plan(
        steps: [
          InteractionStep(SwitchActivity('Normal Tree')),
          WaitStep(1000),
          InteractionStep(BuyUpgrade(UpgradeType.axe)),
          WaitStep(5000),
        ],
        totalTicks: 6000,
        interactionCount: 2,
        expandedNodes: 100,
        enqueuedNodes: 200,
      );

      final output = plan.prettyPrint();

      expect(output, contains('=== Plan ==='));
      expect(output, contains('Total ticks: 6000'));
      expect(output, contains('Interactions: 2'));
      expect(output, contains('Switch to Normal Tree'));
      expect(output, contains('Buy upgrade: UpgradeType.axe'));
      expect(output, contains('Wait'));
    });

    test('prettyPrint limits steps shown', () {
      final steps = List.generate(50, (i) => WaitStep(i * 100));
      final plan = Plan(
        steps: steps,
        totalTicks: 50 * 100,
        interactionCount: 0,
      );

      final output = plan.prettyPrint(maxSteps: 10);

      expect(output, contains('... and 40 more steps'));
    });
  });

  group('SolverResult', () {
    test('SolverSuccess wraps plan', () {
      const plan = Plan.empty();
      const result = SolverSuccess(plan);

      expect(result.plan.steps, isEmpty);
    });

    test('SolverFailed wraps failure', () {
      const failure = SolverFailure(
        reason: 'test failure',
        expandedNodes: 10,
        enqueuedNodes: 20,
        bestCredits: 50,
      );
      const result = SolverFailed(failure);

      expect(result.failure.reason, 'test failure');
      expect(result.failure.expandedNodes, 10);
      expect(result.failure.enqueuedNodes, 20);
      expect(result.failure.bestCredits, 50);
    });
  });
}
