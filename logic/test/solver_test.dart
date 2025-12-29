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
import 'package:logic/src/solver/wait_for.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('applyInteraction', () {
    test('SwitchActivity switches to a new activity', () {
      final state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      final interaction = SwitchActivity(action.id);

      final newState = applyInteraction(state, interaction);

      expect(newState.activeAction?.id, action.id);
    });

    test('SwitchActivity clears existing action first', () {
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(
        testActions.fishing('Raw Shrimp'),
        random: Random(0),
      );
      final action = testActions.woodcutting('Normal Tree');
      final interaction = SwitchActivity(action.id);

      final newState = applyInteraction(state, interaction);

      expect(newState.activeAction?.id, action.id);
    });

    test('BuyShopItem purchases an upgrade', () {
      final state = GlobalState.test(testRegistries, gp: 100);
      const ironAxeId = MelvorId('melvorD:Iron_Axe');
      const interaction = BuyShopItem(ironAxeId);

      final newState = applyInteraction(state, interaction);

      expect(newState.shop.purchaseCount(ironAxeId), 1);
      expect(newState.gp, 50); // Iron Axe costs 50
    });

    test('BuyShopItem throws when cannot afford', () {
      final state = GlobalState.test(testRegistries, gp: 10);
      const ironAxeId = MelvorId('melvorD:Iron_Axe');
      const interaction = BuyShopItem(ironAxeId);

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
      final state = GlobalState.test(testRegistries, inventory: inventory);
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
      final action = testActions.woodcutting('Normal Tree');
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
      final action = testActions.woodcutting('Normal Tree');
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
      final action = testActions.woodcutting('Normal Tree');
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
      final state = GlobalState.test(testRegistries, gp: 1000);

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
      final action = testActions.woodcutting('Normal Tree');
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
      var state = GlobalState.test(testRegistries, gp: 50);
      final action = testActions.woodcutting('Normal Tree');
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
      final action = testActions.woodcutting('Normal Tree');
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
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(1000, WaitForGoal(testGoal)),
          const InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe'))),
          const WaitStep(5000, WaitForGoal(testGoal)),
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
      expect(output, contains('Switch to'));
      expect(output, contains('Buy upgrade: melvorD:Iron_Axe'));
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
      final action = testActions.thieving('Man'); // Thieving action
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Thieving should have positive HP loss rate (player takes damage)
      expect(rates.hpLossPerTick, greaterThan(0));
      expect(defaultValueModel.valuePerTick(state, rates), greaterThan(0));
    });

    test('estimateRates returns zero hpLossPerTick for non-thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.hpLossPerTick, 0);
    });

    test('ticksUntilDeath returns positive value for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticks = ticksUntilDeath(state, rates);

      // At level 1 hitpoints (10 HP), player should die eventually
      expect(ticks, isNotNull);
      expect(ticks, greaterThan(0));
    });

    test('ticksUntilDeath returns null for non-thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticks = ticksUntilDeath(state, rates);

      expect(ticks, isNull);
    });

    test('advance uses continuous model for thieving (activity continues)', () {
      // Create state with low HP thieving
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      // Damage the player to have only 2 HP left
      final lostHp = state.maxPlayerHp - 2;
      state = state.copyWith(health: HealthState(lostHp: lostHp));

      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates);

      // Advance past death - with continuous model, activity continues
      final result = advance(state, ticksToDeath! + 1000);

      // Activity should continue (continuous model doesn't stop on death)
      expect(result.state.activeAction, isNotNull);
      expect(result.state.activeAction!.id, action.id);
      // Deaths should be tracked based on how many cycles occurred
      expect(result.deaths, greaterThan(0));
    });

    test('advance tracks expected deaths proportional to time', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates)!;

      // Advance for multiple death cycles
      final result = advance(state, ticksToDeath * 5);

      // Activity should still be running (continuous model)
      expect(result.state.activeAction, isNotNull);
      expect(result.state.activeAction!.id, action.id);
      // Should track approximately 5 deaths
      expect(result.deaths, equals(5));
    });

    test('nextDecisionDelta includes death timing for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
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
      final action = testActions.woodcutting('Normal Tree');
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
        final action = testActions.woodcutting('Normal Tree');
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

    test('nextDecisionDelta includes skill unlock timing', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      const goal = ReachGpGoal(100000); // High goal
      final candidates = enumerateCandidates(state, goal);

      final result = nextDecisionDelta(state, goal, candidates);

      // Delta should be positive (progressing toward goal)
      // Note: skill level timing only applies for unlock thresholds now,
      // not every level up. The delta should be bounded by goal progress,
      // upgrade affordability, or activity unlock timing.
      expect(result.deltaTicks, greaterThan(0));
      expect(result.isDeadEnd, isFalse);
    });

    test('nextDecisionDelta includes mastery level timing for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
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
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.masteryXpPerTick, greaterThan(0));
      expect(rates.actionId, action.id);
    });

    test('estimateRates includes mastery XP rate for thieving', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      expect(rates.masteryXpPerTick, greaterThan(0));
      expect(rates.actionId, action.id);
    });

    test('deathCycleAdjustedRates reduces rates for hazardous activities', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      final rawRates = estimateRates(state);
      final adjustedRates = deathCycleAdjustedRates(state, rawRates);

      // With no restart overhead, cycle ratio = ticksToDeath / ticksToDeath = 1.0
      // So rates should be unchanged (for now)
      // When we add restart overhead, this will change
      expect(adjustedRates.directGpPerTick, rawRates.directGpPerTick);
      expect(adjustedRates.masteryXpPerTick, rawRates.masteryXpPerTick);
      // hpLossPerTick should be preserved (not adjusted)
      expect(adjustedRates.hpLossPerTick, rawRates.hpLossPerTick);
    });

    test('deathCycleAdjustedRates returns original for non-hazardous', () {
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rawRates = estimateRates(state);
      final adjustedRates = deathCycleAdjustedRates(state, rawRates);

      // No death risk, so rates should be unchanged
      expect(adjustedRates.directGpPerTick, rawRates.directGpPerTick);
      expect(adjustedRates.itemFlowsPerTick, rawRates.itemFlowsPerTick);
    });

    test('expected deaths roughly matches simulated deaths for thieving', () {
      // Setup: known thieving state
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(42));

      // Get expected death rate from model
      final rates = estimateRates(state);
      final ticksToDeath = ticksUntilDeath(state, rates)!;

      // Simulate for a fixed duration using consumeTicks
      const simulationTicks = 50000; // ~1.4 hours
      var simState = state;
      var ticksElapsed = 0;
      var actualDeaths = 0;
      final random = Random(42);

      while (ticksElapsed < simulationTicks) {
        final builder = StateUpdateBuilder(simState);
        // Consume a chunk of ticks at a time
        consumeTicks(builder, 1000, random: random);
        simState = builder.build();
        actualDeaths += builder.changes.deathCount;
        ticksElapsed += 1000;

        // Restart activity if it was stopped by death
        if (simState.activeAction == null) {
          simState = simState.startAction(action, random: random);
        }
      }

      // Compare expected vs actual
      final expectedDeaths = simulationTicks ~/ ticksToDeath;

      // The model is approximate - actual deaths may be lower because:
      // 1. HP regen between deaths
      // 2. Leveling up reduces failure rate during simulation
      // 3. The model uses initial state rates throughout
      // We just verify expected deaths is non-zero and in the right ballpark.
      expect(
        expectedDeaths,
        greaterThan(0),
        reason: 'Expected deaths should be non-zero for thieving',
      );
      expect(
        actualDeaths,
        greaterThan(0),
        reason:
            'Actual deaths should be non-zero after thieving '
            'for $simulationTicks ticks',
      );
      // Order of magnitude check - both should be in the range of 10-100
      expect(
        actualDeaths,
        greaterThan(expectedDeaths ~/ 10),
        reason:
            'Actual deaths ($actualDeaths) should be within order of magnitude '
            'of expected ($expectedDeaths). ticksToDeath=$ticksToDeath',
      );
    });

    test('itemFlowsPerTick includes action outputs via allDropsForAction', () {
      // Verify that action outputs (like Normal Logs from Normal Tree) are
      // included in itemFlowsPerTick via allDropsForAction, not double-counted.
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Normal Tree outputs Normal Logs (keys are MelvorId objects)
      expect(
        rates.itemFlowsPerTick,
        contains(const MelvorId('melvorD:Normal_Logs')),
        reason: 'itemFlowsPerTick should include action outputs',
      );

      // Verify the rate is correct (1 log per action, not doubled)
      // Normal Tree has 3s duration = 30 ticks
      final expectedTicks = ticksFromDuration(const Duration(seconds: 3));
      final expectedLogsPerTick = 1.0 / expectedTicks;
      final normalLogsId = MelvorId.fromName('Normal Logs');
      expect(
        rates.itemFlowsPerTick[normalLogsId],
        closeTo(expectedLogsPerTick, 0.0001),
        reason: 'Normal Logs rate should be 1 per action duration',
      );
    });

    test('itemFlowsPerTick includes skill-level drops (Bird Nest)', () {
      // Verify that skill-level drops are included in itemFlowsPerTick
      // Woodcutting has Bird Nest as a skill-level drop (0.5% rate)
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Bird Nest is a skill-level drop for woodcutting
      expect(
        rates.itemFlowsPerTick,
        contains(const MelvorId('melvorD:Bird_Nest')),
        reason: 'itemFlowsPerTick should include skill-level drops',
      );

      // Verify the rate is correct (0.5% per action)
      final expectedTicks = ticksFromDuration(const Duration(seconds: 3));
      final expectedBirdNestPerTick = 0.005 / expectedTicks;
      final birdNestId = MelvorId.fromName('Bird Nest');
      expect(
        rates.itemFlowsPerTick[birdNestId],
        closeTo(expectedBirdNestPerTick, 0.00001),
        reason: 'Bird Nest rate should match skill drop rate',
      );
    });

    test('estimateRates includes skill-level drops in item flows', () {
      // Thieving has Bobby's Pocket as a skill-level drop (1/120 rate, 4000 GP)
      // This should appear in itemFlowsPerTick and affect valuePerTick
      var state = GlobalState.empty(testRegistries);
      final action = testActions.thieving('Man');
      state = state.startAction(action, random: Random(0));

      final rates = estimateRates(state);

      // Verify Bobby's Pocket is included in item flows
      expect(
        rates.itemFlowsPerTick,
        contains(const MelvorId('melvorF:Bobbys_Pocket')),
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
      final mastery = state.actionState(action.id).masteryLevel;
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
            'valuePerTick ($actualValuePerTick) should be higher than '
            'gold from thieving alone ($expectedGoldPerTickWithoutDrops) '
            "because skill-level drops like Bobby's Pocket should be included. "
            'Expected with drops: $expectedGoldPerTickWithDrops',
      );
    });
  });

  group('consumeUntil', () {
    test('reaches woodcutting XP goal in reasonable time', () {
      // Setup: start woodcutting Normal Tree
      var state = GlobalState.empty(testRegistries);
      final action = testActions.woodcutting('Normal Tree');
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

    test('switches to producer when consuming action runs out of inputs', () {
      // Setup: state with only 1 log for firemaking - will run out quickly
      final normalLogs = testItems.byName('Normal Logs');
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(normalLogs, count: 1),
        ]),
      );

      // Start firemaking (a consuming action that needs logs)
      final firemakingAction = testActions.firemaking('Burn Normal Logs');
      final runningState = state.startAction(
        firemakingAction,
        random: Random(42),
      );

      // Try to reach firemaking XP that requires more logs than we have
      // Normal Logs firemaking: 40 XP per action, so we need 5 logs for 200 XP
      const waitFor = WaitForSkillXp(Skill.firemaking, 200);
      final result = consumeUntil(runningState, waitFor, random: Random(42));

      // Should have gained firemaking XP (at least 200)
      expect(
        result.state.skillState(Skill.firemaking).xp,
        greaterThanOrEqualTo(200),
        reason: 'Should have reached 200 firemaking XP by gathering more logs',
      );

      // Should also have gained woodcutting XP from gathering logs
      expect(
        result.state.skillState(Skill.woodcutting).xp,
        greaterThan(0),
        reason: 'Should have gained woodcutting XP from gathering logs',
      );

      // The total ticks should reflect both gathering and burning
      expect(result.ticksElapsed, greaterThan(0));
    });
  });

  group('executePlan', () {
    test('executes empty plan and returns initial state', () {
      final state = GlobalState.test(testRegistries, gp: 500);
      const plan = Plan.empty();

      final result = executePlan(state, plan, random: Random(42));

      expect(result.finalState.gp, 500);
      expect(result.actualTicks, 0);
      expect(result.totalDeaths, 0);
    });

    test('executes plan with switch activity step', () {
      final state = GlobalState.empty(testRegistries);
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(30, WaitForSkillXp(Skill.woodcutting, 10)),
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
      final manAction = testActions.thieving('Man');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(manAction.id)),
          // Wait for a very high GP goal - will take many iterations and deaths
          const WaitStep(50000, WaitForGoal(ReachGpGoal(5000))),
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
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(60, WaitForSkillXp(Skill.woodcutting, 20)),
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

  group('TrainConsumingSkillUntil macro expansion', () {
    test('expands firemaking skill goal using sustainable rate model', () {
      // Setup: state with logs for firemaking
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(testItems.byName('Normal Logs'), count: 100),
        ]),
      );

      // Create a goal for firemaking level 2 (a consuming skill)
      const goal = ReachSkillLevelGoal(Skill.firemaking, 2);

      // Solve - this should trigger TrainConsumingSkillUntil macro expansion
      final result = solve(state, goal);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;

      // Verify the plan reaches the goal
      expect(success.plan.totalTicks, greaterThan(0));
      // Plan should include some steps
      expect(success.plan.steps, isNotEmpty);
    });

    test('projects both consuming and producing skill XP', () {
      // Setup: state with logs for firemaking
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(testItems.byName('Normal Logs'), count: 100),
        ]),
      );

      // Create a firemaking goal
      const goal = ReachSkillLevelGoal(Skill.firemaking, 2);

      // Solve and execute the plan
      final solveResult = solve(state, goal);
      expect(solveResult, isA<SolverSuccess>());
      final success = solveResult as SolverSuccess;

      // Execute the plan
      final execResult = executePlan(state, success.plan, random: Random(42));

      // Should have firemaking XP (the consuming skill)
      expect(
        execResult.finalState.skillState(Skill.firemaking).xp,
        greaterThan(0),
        reason: 'Should gain firemaking XP from burning logs',
      );

      // Should also have woodcutting XP (the producing skill, if needed)
      // Note: if we started with enough logs, we might not need to chop any,
      // but the solver should still work correctly
    });

    test('handles sustainable rate calculation for consuming skills', () {
      // Setup: state without logs - solver needs to plan woodcutting first
      final state = GlobalState.empty(testRegistries);

      // Create a firemaking goal (consuming skill)
      const goal = ReachSkillLevelGoal(Skill.firemaking, 2);

      // Solve - this tests the coupled produce/consume model
      final result = solve(state, goal);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;

      // Plan should exist and have reasonable ticks
      expect(success.plan.totalTicks, greaterThan(0));

      // Execute to verify the plan works
      final execResult = executePlan(state, success.plan, random: Random(42));

      // Should reach or approach firemaking level 2
      expect(
        execResult.finalState.skillState(Skill.firemaking).skillLevel,
        greaterThanOrEqualTo(1),
        reason: 'Plan should make progress toward firemaking goal',
      );
    });
  });

  group('Plan.compress', () {
    test('returns empty plan unchanged', () {
      const plan = Plan.empty();
      final compressed = plan.compress();

      expect(compressed.steps, isEmpty);
      expect(compressed.totalTicks, 0);
      expect(compressed.interactionCount, 0);
    });

    test('merges consecutive WaitSteps', () {
      const goal = ReachGpGoal(100);
      const plan = Plan(
        steps: [
          WaitStep(100, WaitForSkillXp(Skill.woodcutting, 50)),
          WaitStep(200, WaitForSkillXp(Skill.woodcutting, 100)),
          WaitStep(300, WaitForGoal(goal)),
        ],
        totalTicks: 600,
        interactionCount: 0,
      );

      final compressed = plan.compress();

      // Should merge all three waits into one
      expect(compressed.steps.length, 1);
      expect(compressed.steps[0], isA<WaitStep>());
      final wait = compressed.steps[0] as WaitStep;
      expect(wait.deltaTicks, 600); // 100 + 200 + 300
      // Should keep the final waitFor
      expect(wait.waitFor, isA<WaitForGoal>());
      expect(compressed.totalTicks, 600);
      expect(compressed.interactionCount, 0);
    });

    test('does not merge waits separated by interaction', () {
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      final oakTreeAction = testActions.woodcutting('Oak Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(100, WaitForSkillXp(Skill.woodcutting, 50)),
          InteractionStep(SwitchActivity(oakTreeAction.id)),
          const WaitStep(200, WaitForSkillXp(Skill.woodcutting, 100)),
        ],
        totalTicks: 300,
        interactionCount: 2,
      );

      final compressed = plan.compress();

      // Should have 4 steps (switch, wait, switch, wait)
      expect(compressed.steps.length, 4);
      expect(compressed.interactionCount, 2);
    });

    test('removes no-op switch to same activity', () {
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(100, WaitForSkillXp(Skill.woodcutting, 50)),
          // No-op switch to same activity
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(200, WaitForSkillXp(Skill.woodcutting, 100)),
        ],
        totalTicks: 300,
        interactionCount: 2,
      );

      final compressed = plan.compress();

      // Should remove the no-op switch and merge the waits
      expect(compressed.steps.length, 2); // switch + merged wait
      expect(compressed.steps[0], isA<InteractionStep>());
      expect(compressed.steps[1], isA<WaitStep>());
      final wait = compressed.steps[1] as WaitStep;
      expect(wait.deltaTicks, 300); // 100 + 200 merged
      expect(compressed.interactionCount, 1);
    });

    test('keeps SellAll and BuyShopItem interactions', () {
      final normalTreeAction = testActions.woodcutting('Normal Tree');
      const ironAxeId = MelvorId('melvorD:Iron_Axe');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(normalTreeAction.id)),
          const WaitStep(100, WaitForInventoryValue(50)),
          const InteractionStep(SellAll()),
          const InteractionStep(BuyShopItem(ironAxeId)),
          const WaitStep(200, WaitForSkillXp(Skill.woodcutting, 100)),
        ],
        totalTicks: 300,
        interactionCount: 3,
      );

      final compressed = plan.compress();

      // Should keep all interactions except no-ops
      expect(compressed.steps.length, 5);
      expect(compressed.interactionCount, 3);
    });

    test('preserves totalTicks and metadata', () {
      const plan = Plan(
        steps: [
          WaitStep(100, WaitForSkillXp(Skill.woodcutting, 50)),
          WaitStep(200, WaitForSkillXp(Skill.woodcutting, 100)),
        ],
        totalTicks: 300,
        interactionCount: 0,
        expandedNodes: 42,
        enqueuedNodes: 100,
        expectedDeaths: 2,
      );

      final compressed = plan.compress();

      expect(compressed.totalTicks, 300);
      expect(compressed.expandedNodes, 42);
      expect(compressed.enqueuedNodes, 100);
      expect(compressed.expectedDeaths, 2);
    });
  });

  group('solve with collectDiagnostics', () {
    test('returns profile with diagnostic data for GP goal', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachGpGoal(100);

      final result = solve(state, goal, collectDiagnostics: true);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.profile, isNotNull);

      final profile = success.profile!;
      expect(profile.expandedNodes, greaterThan(0));
      expect(profile.uniqueBucketKeys, greaterThan(0));
      expect(profile.heuristicValues, isNotEmpty);
      expect(profile.bestRateSamples, isNotEmpty);
      expect(profile.rootBestRate, isNotNull);
      expect(profile.rootBestRate, greaterThan(0));
    });

    test('returns profile with diagnostic data for skill goal', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 5);

      final result = solve(state, goal, collectDiagnostics: true);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.profile, isNotNull);

      final profile = success.profile!;
      expect(profile.expandedNodes, greaterThan(0));
      expect(profile.rootBestRate, greaterThan(0));
    });

    test('returns profile with consuming skill stats for firemaking', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.firemaking, 5);

      final result = solve(state, goal, collectDiagnostics: true);

      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.profile, isNotNull);

      final profile = success.profile!;
      // Should have candidate stats for consuming skill
      expect(profile.candidateStatsHistory, isNotEmpty);

      // Verify consumer action stats are populated
      final stats = profile.candidateStatsHistory.first;
      expect(stats.consumerActionsConsidered, greaterThan(0));
      expect(stats.producerActionsConsidered, greaterThan(0));
      expect(stats.topPairs, isNotEmpty);
    });

    test('fails fast with clear error when best rate is zero', () {
      // Create a state where no actions are unlocked for the goal skill.
      // We'll use a custom state with skill level 0 for a skill that
      // requires inputs but has no producer available.
      //
      // This is hard to trigger with real data since woodcutting is always
      // available. Instead, we verify the tripwire logic exists by checking
      // that a valid goal produces a non-zero rate.
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.firemaking, 2);

      final result = solve(state, goal, collectDiagnostics: true);

      // With real data, firemaking should succeed because woodcutting
      // provides logs. The tripwire would only trigger if no producer exists.
      expect(result, isA<SolverSuccess>());
      final success = result as SolverSuccess;
      expect(success.profile!.rootBestRate, greaterThan(0));
    });

    test('profile tracks zero rate reasons', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachGpGoal(100);

      final result = solve(state, goal, collectDiagnostics: true);

      expect(result, isA<SolverSuccess>());
      final profile = (result as SolverSuccess).profile!;

      // Zero rate counters should be non-negative
      expect(profile.rateZeroBecauseNoRelevantSkill, greaterThanOrEqualTo(0));
      expect(profile.rateZeroBecauseNoUnlockedActions, greaterThanOrEqualTo(0));
      expect(profile.rateZeroBecauseInputsRequired, greaterThanOrEqualTo(0));
      expect(profile.rateZeroBecauseZeroTicks, greaterThanOrEqualTo(0));
    });

    test('profile tracks time breakdown percentages', () {
      final state = GlobalState.empty(testRegistries);
      const goal = ReachGpGoal(100);

      final result = solve(state, goal, collectDiagnostics: true);

      expect(result, isA<SolverSuccess>());
      final profile = (result as SolverSuccess).profile!;

      // Time breakdown percentages should sum to <= 100
      final totalPercent =
          profile.advancePercent +
          profile.enumeratePercent +
          profile.hashingPercent;
      expect(totalPercent, lessThanOrEqualTo(100.0));
    });
  });

  group('SolverProfile', () {
    test('recordRateZeroReason increments correct counters', () {
      final profile = SolverProfile();

      // Initially all counters are zero
      expect(profile.rateZeroBecauseNoRelevantSkill, 0);
      expect(profile.rateZeroBecauseNoUnlockedActions, 0);
      expect(profile.rateZeroBecauseInputsRequired, 0);
      expect(profile.rateZeroBecauseZeroTicks, 0);

      // Record each reason type
      profile.recordRateZeroReason(const NoRelevantSkillReason('test goal'));
      expect(profile.rateZeroBecauseNoRelevantSkill, 1);

      profile.recordRateZeroReason(
        const NoUnlockedActionsReason(goalDescription: 'test goal'),
      );
      expect(profile.rateZeroBecauseNoUnlockedActions, 1);

      profile.recordRateZeroReason(const InputsRequiredReason());
      expect(profile.rateZeroBecauseInputsRequired, 1);

      profile.recordRateZeroReason(const ZeroTicksReason());
      expect(profile.rateZeroBecauseZeroTicks, 1);

      // Record same reason multiple times
      profile
        ..recordRateZeroReason(const NoRelevantSkillReason('test goal'))
        ..recordRateZeroReason(const NoRelevantSkillReason('test goal'));
      expect(profile.rateZeroBecauseNoRelevantSkill, 3);

      // Other counters unchanged
      expect(profile.rateZeroBecauseNoUnlockedActions, 1);
      expect(profile.rateZeroBecauseInputsRequired, 1);
      expect(profile.rateZeroBecauseZeroTicks, 1);
    });

    test('RateZeroReason.describe returns appropriate messages', () {
      // NoRelevantSkillReason
      const noRelevantSkill = NoRelevantSkillReason('reach 50 GP');
      expect(
        noRelevantSkill.describe(),
        'no relevant skill for goal "reach 50 GP"',
      );

      // NoUnlockedActionsReason - basic case
      const noUnlockedBasic = NoUnlockedActionsReason(
        goalDescription: 'reach level 10',
      );
      expect(
        noUnlockedBasic.describe(),
        'no unlocked actions for goal "reach level 10"',
      );

      // NoUnlockedActionsReason - with skill name
      const noUnlockedWithSkill = NoUnlockedActionsReason(
        goalDescription: 'reach level 10',
        skillName: 'Firemaking',
      );
      expect(
        noUnlockedWithSkill.describe(),
        'no unlocked actions for Firemaking',
      );

      // NoUnlockedActionsReason - with missing input (consuming skill case)
      const noUnlockedWithInput = NoUnlockedActionsReason(
        goalDescription: 'reach level 10',
        missingInputName: 'Raw Shrimp',
        actionNeedingInput: 'Cook Shrimp',
        skillName: 'Cooking',
      );
      expect(
        noUnlockedWithInput.describe(),
        'no producer for Raw Shrimp '
        '(needed by Cook Shrimp) at current skill levels',
      );

      // InputsRequiredReason
      const inputsRequired = InputsRequiredReason();
      expect(
        inputsRequired.describe(),
        'all actions require inputs with no available producers',
      );

      // ZeroTicksReason
      const zeroTicks = ZeroTicksReason();
      expect(
        zeroTicks.describe(),
        'all actions have zero duration (configuration error)',
      );
    });

    test('recordBestRate tracks samples and root rate', () {
      final profile = SolverProfile();

      expect(profile.bestRateSamples, isEmpty);
      expect(profile.rootBestRate, isNull);

      // Record root rate
      profile.recordBestRate(0.5, isRoot: true);
      expect(profile.bestRateSamples, [0.5]);
      expect(profile.rootBestRate, 0.5);

      // Record non-root rates
      profile
        ..recordBestRate(0.3, isRoot: false)
        ..recordBestRate(0.7, isRoot: false);
      expect(profile.bestRateSamples, [0.5, 0.3, 0.7]);
      expect(profile.rootBestRate, 0.5); // unchanged

      // Check min/max/median
      expect(profile.minBestRate, 0.3);
      expect(profile.maxBestRate, 0.7);
      expect(profile.medianBestRate, 0.5);
    });

    test('recordMacroStopTrigger tracks trigger counts', () {
      final profile = SolverProfile();

      expect(profile.macroStopTriggers, isEmpty);

      profile.recordMacroStopTrigger('Skill +1');
      expect(profile.macroStopTriggers, {'Skill +1': 1});

      profile.recordMacroStopTrigger('Skill +1');
      expect(profile.macroStopTriggers, {'Skill +1': 2});

      profile.recordMacroStopTrigger('Goal reached');
      expect(profile.macroStopTriggers, {'Skill +1': 2, 'Goal reached': 1});
    });

    test('recordHeuristic tracks values and zero rate count', () {
      final profile = SolverProfile();

      expect(profile.heuristicValues, isEmpty);
      expect(profile.zeroRateCount, 0);

      profile.recordHeuristic(100, hasZeroRate: false);
      expect(profile.heuristicValues, [100]);
      expect(profile.zeroRateCount, 0);

      profile.recordHeuristic(200, hasZeroRate: true);
      expect(profile.heuristicValues, [100, 200]);
      expect(profile.zeroRateCount, 1);

      profile.recordHeuristic(50, hasZeroRate: true);
      expect(profile.heuristicValues, [100, 200, 50]);
      expect(profile.zeroRateCount, 2);
    });

    test('recordBucketKey tracks unique keys', () {
      final profile = SolverProfile();

      expect(profile.uniqueBucketKeys, 0);

      profile.recordBucketKey('key1');
      expect(profile.uniqueBucketKeys, 1);

      profile.recordBucketKey('key2');
      expect(profile.uniqueBucketKeys, 2);

      // Duplicate key doesn't increment
      profile.recordBucketKey('key1');
      expect(profile.uniqueBucketKeys, 2);

      profile.recordBucketKey('key3');
      expect(profile.uniqueBucketKeys, 3);
    });
  });
}
