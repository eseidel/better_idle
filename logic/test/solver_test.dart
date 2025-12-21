// cspell:words bobbys
import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/apply_interaction.dart';
import 'package:logic/src/solver/enumerate_candidates.dart';
import 'package:logic/src/solver/estimate_rates.dart';
import 'package:logic/src/solver/goal.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:logic/src/solver/next_decision_delta.dart';
import 'package:logic/src/solver/plan.dart';
import 'package:logic/src/solver/solver.dart';
import 'package:logic/src/solver/value_model.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('applyInteraction', () {
    test('SwitchActivity switches to a new activity', () {
      final state = GlobalState.empty(testRegistries);
      const interaction = SwitchActivity('Normal Tree');

      final newState = applyInteraction(state, interaction);

      final action = testActions.byName('Normal Tree');
      expect(newState.activeAction?.id, action.id);
    });

    test('SwitchActivity clears existing action first', () {
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(
        testActions.byName('Raw Shrimp'),
        random: Random(0),
      );
      const interaction = SwitchActivity('Normal Tree');

      final newState = applyInteraction(state, interaction);

      final action = testActions.byName('Normal Tree');
      expect(newState.activeAction?.id, action.id);
    });

    test('BuyUpgrade purchases an upgrade', () {
      final state = GlobalState.empty(testRegistries).copyWith(gp: 100);
      const interaction = BuyUpgrade(UpgradeType.axe);

      final newState = applyInteraction(state, interaction);

      expect(newState.shop.axeLevel, 1);
      expect(newState.gp, 50); // Iron Axe costs 50
    });

    test('BuyUpgrade throws when cannot afford', () {
      final state = GlobalState.empty(testRegistries).copyWith(gp: 10);
      const interaction = BuyUpgrade(UpgradeType.axe);

      expect(
        () => applyInteraction(state, interaction),
        throwsA(isA<StateError>()),
      );
    });

    test('SellAll sells all items in inventory', () {
      final logs = testItems.byName('Normal Logs');
      final oak = testItems.byName('Oak Logs');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(logs, count: 10),
        ItemStack(oak, count: 5),
      ]);
      final state = GlobalState.empty(
        testRegistries,
      ).copyWith(inventory: inventory, gp: 0);
      const interaction = SellAll();

      final newState = applyInteraction(state, interaction);

      expect(newState.inventory.items, isEmpty);
      // Normal logs sell for 1, oak for 5
      expect(newState.gp, 10 * logs.sellsFor + 5 * oak.sellsFor);
    });
  });

  group('advance', () {
    test('advances state by specified ticks', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));
      final initialGp = state.gp;

      // advance uses expected-value model for rate-modelable activities
      // so we check that GP increases appropriately
      final result = advance(state, 100);

      // Normal Tree: 1 gold / 30 ticks = 0.033 gold/tick
      // After 100 ticks: expect ~3 gold
      expect(result.state.gp, greaterThan(initialGp));
    });

    test('is deterministic', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final result1 = advance(state, 100);
      final result2 = advance(state, 100);

      expect(result1.state.gp, result2.state.gp);
      // Skill XP should also match
      expect(
        result1.state.skillState(Skill.woodcutting).xp,
        result2.state.skillState(Skill.woodcutting).xp,
      );
    });

    test('returns same state when deltaTicks is 0', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final result = advance(state, 0);

      expect(
        result.state.activeAction?.remainingTicks,
        state.activeAction?.remainingTicks,
      );
    });
  });

  group('solveToCredits', () {
    test('returns empty plan when goal already met', () {
      final state = GlobalState.empty(testRegistries).copyWith(gp: 1000);

      final result = solveToCredits(state, 500);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.steps, isEmpty);
      expect(success.plan.totalTicks, 0);
      expect(success.plan.interactionCount, 0);
    });

    test('finds a plan to reach goal with single activity', () {
      var state = GlobalState.empty(testRegistries);
      // Start with an activity already running
      final action = testActions.byName('Normal Tree');
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
      final state = GlobalState.empty(testRegistries);

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
      var state = GlobalState.empty(testRegistries).copyWith(gp: 50);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      // Moderate goal - may or may not benefit from upgrade
      final result = solveToCredits(state, 200);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.plan.totalTicks, greaterThan(0));
    });

    test('respects maxExpandedNodes limit', () {
      final state = GlobalState.empty(testRegistries);

      // Set a very low limit (solver is now very efficient, so use limit of 2)
      final result = solveToCredits(
        state,
        1000000, // Very high goal
        maxExpandedNodes: 2,
      );

      expect(result, isA<SolverFailed>());
      final failure = result as SolverFailed;
      expect(failure.failure.reason, contains('max expanded nodes'));
    });

    test('produces deterministic results', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
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
      const testGoal = ReachGpGoal(100);
      const plan = Plan(
        steps: [
          InteractionStep(SwitchActivity('Normal Tree')),
          WaitStep(1000, WaitForGoal(testGoal)),
          InteractionStep(BuyUpgrade(UpgradeType.axe)),
          WaitStep(5000, WaitForGoal(testGoal)),
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
      const testGoal = ReachGpGoal(100);
      final steps = List.generate(
        50,
        (i) => WaitStep(i * 100, const WaitForGoal(testGoal)),
      );
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

  group('thieving death modeling', () {
    test('estimateRates returns hpLossPerTick for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man'); // Thieving action
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Thieving should have positive HP loss rate (player takes damage)
      expect(rates.hpLossPerTick, greaterThan(0));
      expect(defaultValueModel.valuePerTick(state, rates), greaterThan(0));
    });

    test('estimateRates returns zero hpLossPerTick for non-thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.hpLossPerTick, 0);
    });

    test('ticksUntilDeath returns positive value for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticks = ticksUntilDeath(state, rates);

      // At level 1 hitpoints (10 HP), player should die eventually
      expect(ticks, isNotNull);
      expect(ticks, greaterThan(0));
    });

    test('ticksUntilDeath returns null for non-thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticks = ticksUntilDeath(state, rates);

      expect(ticks, isNull);
    });

    test('advance stops activity on death for thieving', () {
      // Create state with low HP thieving
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      // Damage the player to have only 2 HP left
      final lostHp = state.maxPlayerHp - 2;
      state = state.copyWith(health: HealthState(lostHp: lostHp));

      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates);

      // Advance past death
      final result = advance(state, ticksToDeath! + 1000);

      // Activity should be stopped and HP should be reset
      expect(result.state.activeAction, isNull);
      expect(result.state.playerHp, result.state.maxPlayerHp); // Full HP
      expect(result.deaths, 1); // One death occurred
    });

    test('advance does not stop activity before death', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates);

      // Advance less than death time
      final result = advance(state, ticksToDeath! ~/ 2);

      // Activity should still be running
      expect(result.state.activeAction, isNotNull);
      expect(result.state.activeAction!.id, 'Man');
      expect(result.deaths, 0); // No death yet
    });

    test('nextDecisionDelta includes death timing for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      // Damage player to have only 5 HP left
      final lostHp = state.maxPlayerHp - 5;
      state = state.copyWith(health: HealthState(lostHp: lostHp));

      const goal = ReachGpGoal(100000); // High goal
      final candidates = enumerateCandidates(state, goal);

      final result = nextDecisionDelta(state, goal, candidates);

      // Delta should be less than or equal to ticks until death
      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates);

      expect(result.deltaTicks, lessThanOrEqualTo(ticksToDeath!));
    });
  });

  group('skill and mastery level timing', () {
    test('ticksUntilNextSkillLevel returns positive value when gaining XP', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticks = ticksUntilNextSkillLevel(state, rates);

      // Should return positive ticks to level 2
      expect(ticks, isNotNull);
      expect(ticks, greaterThan(0));
    });

    test('ticksUntilNextSkillLevel returns null when no XP gain', () {
      final state = GlobalState.empty(testRegistries);

      // No action active, no XP being gained
      final rates = estimateRates(state);
      final ticks = ticksUntilNextSkillLevel(state, rates);

      expect(ticks, isNull);
    });

    test(
      'ticksUntilNextMasteryLevel returns positive value for active action',
      () {
        var state = GlobalState.empty(testRegistries);
        final action = testActions.byName('Normal Tree');
        state = state.startAction(action, random: Random(0));

        final rates = estimateRates(state);
        final ticks = ticksUntilNextMasteryLevel(state, rates);

        // Should return positive ticks to mastery level 2
        expect(ticks, isNotNull);
        expect(ticks, greaterThan(0));
      },
    );

    test('ticksUntilNextMasteryLevel returns null when no action', () {
      final state = GlobalState.empty(testRegistries);

      final rates = estimateRates(state);
      final ticks = ticksUntilNextMasteryLevel(state, rates);

      expect(ticks, isNull);
    });

    test('nextDecisionDelta includes skill level timing', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      const goal = ReachGpGoal(100000); // High goal
      final candidates = enumerateCandidates(state, goal);

      final result = nextDecisionDelta(state, goal, candidates);

      // Delta should be limited by skill level up
      final rates = estimateRates(state);
      final ticksToLevel = ticksUntilNextSkillLevel(state, rates);

      expect(result.deltaTicks, lessThanOrEqualTo(ticksToLevel!));
    });

    test('nextDecisionDelta includes mastery level timing for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      const goal = ReachGpGoal(100000); // High goal
      final candidates = enumerateCandidates(state, goal);

      final result = nextDecisionDelta(state, goal, candidates);

      // Delta should be limited by mastery or skill level or death
      final rates = estimateRates(state);
      final ticksToMastery = ticksUntilNextMasteryLevel(state, rates);
      final ticksToSkill = ticksUntilNextSkillLevel(state, rates);
      final ticksToDeath = ticksUntilDeath(state, rates);

      // Should be bounded by smallest of the three
      final minBound = [
        ticksToMastery,
        ticksToSkill,
        ticksToDeath,
      ].whereType<int>().reduce((a, b) => a < b ? a : b);

      expect(result.deltaTicks, lessThanOrEqualTo(minBound));
    });

    test('estimateRates includes mastery XP rate', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.masteryXpPerTick, greaterThan(0));
      expect(rates.actionName, 'Normal Tree');
    });

    test('estimateRates includes mastery XP rate for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.masteryXpPerTick, greaterThan(0));
      expect(rates.actionName, 'Man');
    });

    test('itemFlowsPerTick includes action outputs via allDropsForAction', () {
      // Verify that action outputs (like Normal Logs from Normal Tree) are
      // included in itemFlowsPerTick via allDropsForAction, not double-counted.
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Normal Tree outputs Normal Logs
      expect(
        rates.itemFlowsPerTick,
        contains('Normal Logs'),
        reason: 'itemFlowsPerTick should include action outputs',
      );

      // Verify the rate is correct (1 log per action, not doubled)
      // Normal Tree has 3s duration = 30 ticks
      final expectedTicks = ticksFromDuration(const Duration(seconds: 3));
      final expectedLogsPerTick = 1.0 / expectedTicks;
      expect(
        rates.itemFlowsPerTick['Normal Logs'],
        closeTo(expectedLogsPerTick, 0.0001),
        reason: 'Normal Logs rate should be 1 per action duration',
      );
    });

    test('itemFlowsPerTick includes skill-level drops (Bird Nest)', () {
      // Verify that skill-level drops are included in itemFlowsPerTick
      // Woodcutting has Bird Nest as a skill-level drop (0.5% rate)
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Bird Nest is a skill-level drop for woodcutting
      expect(
        rates.itemFlowsPerTick,
        contains('Bird Nest'),
        reason: 'itemFlowsPerTick should include skill-level drops',
      );

      // Verify the rate is correct (0.5% per action)
      final expectedTicks = ticksFromDuration(const Duration(seconds: 3));
      final expectedBirdNestPerTick = 0.005 / expectedTicks;
      expect(
        rates.itemFlowsPerTick['Bird Nest'],
        closeTo(expectedBirdNestPerTick, 0.00001),
        reason: 'Bird Nest rate should match skill drop rate',
      );
    });

    test('estimateRates includes skill-level drops in item flows', () {
      // Thieving has Bobby's Pocket as a skill-level drop (1/120 rate, 4000 GP)
      // This should appear in itemFlowsPerTick and affect valuePerTick
      var state = GlobalState.empty(testRegistries);
      final action = thievingActionByName('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Verify Bobby's Pocket is included in item flows
      expect(
        rates.itemFlowsPerTick,
        contains("Bobby's Pocket"),
        reason: "itemFlowsPerTick should include Bobby's Pocket drop",
      );

      // Calculate expected gold from skill-level drops
      // Bobby's Pocket: rate=1/120, sellsFor=4000
      // Expected GP per action from drop = (1/120) * 4000 = 33.33
      const bobbysPocketRate = 1 / 120;
      const bobbysPocketValue = 4000;
      const expectedDropGpPerAction = bobbysPocketRate * bobbysPocketValue;

      // Get the base thieving duration in ticks
      final baseTicks = ticksFromDuration(thievingDuration).toDouble();

      // Account for stun time on failure (same calculation as estimateRates)
      final thievingLevel = state.skillState(Skill.thieving).skillLevel;
      final mastery = state.actionState(action.name).masteryLevel;
      final stealth = calculateStealth(thievingLevel, mastery);
      final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
        0.0,
        1.0,
      );
      final failureChance = 1.0 - successChance;
      final effectiveTicks = baseTicks + failureChance * stunnedDurationTicks;

      // Calculate expected gold WITHOUT drops (just thieving gold)
      // Expected thieving gold = successChance * (1 + maxGold) / 2
      final expectedThievingGold = successChance * (1 + action.maxGold) / 2;
      final expectedGoldPerTickWithoutDrops =
          expectedThievingGold / effectiveTicks;

      // Calculate expected gold WITH drops
      final expectedGoldPerTickWithDrops =
          (expectedThievingGold + expectedDropGpPerAction) / effectiveTicks;

      // The actual valuePerTick should be higher than gold without drops
      // if skill-level drops are being included via the ValueModel
      final actualValuePerTick = defaultValueModel.valuePerTick(state, rates);
      expect(
        actualValuePerTick,
        greaterThan(expectedGoldPerTickWithoutDrops),
        reason:
            "valuePerTick ($actualValuePerTick) should be higher than "
            "gold from thieving alone ($expectedGoldPerTickWithoutDrops) "
            "because skill-level drops like Bobby's Pocket should be included. "
            "Expected with drops: $expectedGoldPerTickWithDrops",
      );
    });
  });

  group('consumeUntil', () {
    test('reaches woodcutting XP goal in reasonable time', () {
      // Setup: start woodcutting Normal Tree
      var state = GlobalState.empty(testRegistries);
      final action = testActions.byName('Normal Tree');
      state = state.startAction(action, random: Random(42));

      // Normal Tree: 3 seconds (30 ticks), 10 XP per action
      // To get 10 XP, we need 1 action = 30 ticks
      const waitFor = WaitForSkillXp(Skill.woodcutting, 10);
      final result = consumeUntil(state, waitFor, random: Random(42));

      // Should complete in roughly 30 ticks (1 action), not thousands
      expect(
        result.ticksElapsed,
        lessThan(100),
        reason:
            'Should reach 10 woodcutting XP in ~30 ticks (1 action), '
            'not ${result.ticksElapsed} ticks',
      );
      expect(
        result.state.skillState(Skill.woodcutting).xp,
        greaterThanOrEqualTo(10),
      );
    });
  });

  group('executePlan', () {
    test('executes empty plan and returns initial state', () {
      final state = GlobalState.empty(testRegistries).copyWith(gp: 500);
      const plan = Plan.empty();

      final result = executePlan(state, plan, random: Random(42));

      expect(result.finalState.gp, 500);
      expect(result.actualTicks, 0);
      expect(result.totalDeaths, 0);
    });

    test('executes plan with switch activity step', () {
      final state = GlobalState.empty(testRegistries);
      final plan = Plan(
        steps: [
          const InteractionStep(SwitchActivity('Normal Tree')),
          WaitStep(30, WaitForSkillXp(Skill.woodcutting, 10)),
        ],
        totalTicks: 30,
        interactionCount: 1,
      );

      final result = executePlan(state, plan, random: Random(42));

      // Should have woodcutting XP from the wait
      expect(
        result.finalState.skillState(Skill.woodcutting).xp,
        greaterThan(0),
      );
      expect(result.actualTicks, greaterThan(0));
      expect(result.totalDeaths, 0);
    });

    test('tracks deaths during thieving execution', () {
      // Create a plan that does thieving for a long time (will cause deaths)
      final state = GlobalState.empty(testRegistries);
      final plan = Plan(
        steps: [
          const InteractionStep(SwitchActivity('Man')),
          // Wait for a very high GP goal - will take many iterations and deaths
          WaitStep(50000, WaitForGoal(const ReachGpGoal(5000))),
        ],
        totalTicks: 50000,
        interactionCount: 1,
      );

      final result = executePlan(state, plan, random: Random(42));

      // Should have some GP from thieving
      expect(result.finalState.gp, greaterThan(0));
      // Should have experienced deaths during the long thieving session
      expect(result.totalDeaths, greaterThan(0));
    });

    test('reports planned vs actual ticks correctly', () {
      final state = GlobalState.empty(testRegistries);
      final plan = Plan(
        steps: [
          const InteractionStep(SwitchActivity('Normal Tree')),
          WaitStep(60, WaitForSkillXp(Skill.woodcutting, 20)),
        ],
        totalTicks: 60,
        interactionCount: 1,
      );

      final result = executePlan(state, plan, random: Random(42));

      // plannedTicks should match plan.totalTicks
      expect(result.plannedTicks, 60);
      // actualTicks should be close but may vary due to simulation
      expect(result.actualTicks, greaterThan(0));
      // ticksDelta is the difference
      expect(result.ticksDelta, result.actualTicks - result.plannedTicks);
    });

    test('executes plan from solve result', () {
      // Solve for a small GP goal
      final state = GlobalState.empty(testRegistries);
      const goal = ReachGpGoal(100);
      final solveResult = solve(state, goal);

      expect(solveResult, isA<SolverSuccess>());
      final success = solveResult as SolverSuccess;

      // Execute the plan
      final execResult = executePlan(state, success.plan, random: Random(42));

      // Should reach the goal (or close to it due to simulation variance)
      expect(execResult.finalState.gp, greaterThan(50));
    });
  });
}
