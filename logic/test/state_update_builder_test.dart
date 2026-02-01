import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('calculateTicksUntilNextEvent', () {
    test('includes township timers when deity is selected', () {
      // Set up a state with a deity selected.
      final deities = testRegistries.township.deities;
      // Skip if no deities available in test data.
      if (deities.isEmpty) {
        markTestSkipped('No deities in test registries');
        return;
      }
      final deityId = deities.first.id;
      var state = GlobalState.test(testRegistries);
      state = state.selectWorship(deityId);
      expect(state.township.worshipId, isNotNull);

      // Start some action so builder has an active activity (needed to exercise
      // the full method), but township timers should be included regardless.
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      state = state.startAction(normalTree, random: Random(42));

      final builder = StateUpdateBuilder(state);
      final ticks = builder.calculateTicksUntilNextEvent();

      // ticksUntilUpdate (1 hour = 36000) should be the township timer,
      // but the action timer might be smaller. Either way, the result
      // should be non-null and positive.
      expect(ticks, isNotNull);
      expect(ticks, greaterThan(0));

      // Verify township-specific: without deity, the ticks might differ.
      var stateNoDeity = GlobalState.test(testRegistries);
      stateNoDeity = stateNoDeity.startAction(normalTree, random: Random(42));
      final builderNoDeity = StateUpdateBuilder(stateNoDeity);
      final ticksNoDeity = builderNoDeity.calculateTicksUntilNextEvent();

      // Both should work, but with deity selected we potentially have more
      // timer sources. The key assertion is that the deity branch ran without
      // error and returned a valid value.
      expect(ticksNoDeity, isNotNull);
    });

    test('township timers are the minimum when no action is active', () {
      final deities = testRegistries.township.deities;
      if (deities.isEmpty) {
        markTestSkipped('No deities in test registries');
        return;
      }
      final deityId = deities.first.id;
      var state = GlobalState.test(testRegistries);
      state = state.selectWorship(deityId);

      // No active action — only township timers should contribute.
      final builder = StateUpdateBuilder(state);
      final ticks = builder.calculateTicksUntilNextEvent();

      expect(ticks, isNotNull);
      // Should be ticksUntilUpdate (36000) since that's smaller than
      // seasonTicksRemaining (259200).
      expect(ticks, ticksPerHour);
    });
  });

  group('markTabletCrafted', () {
    test('summoning action completion marks tablet as crafted', () {
      final summoningAction = testRegistries.summoning.actions.first;
      final productId = summoningAction.productId;

      // Set up marks so the player can craft.
      final summoningState = const SummoningState.empty().withMarks(
        productId,
        1,
      );

      // Give the player enough ingredients.
      var inventory = Inventory.empty(testItems);
      for (final input in summoningAction.inputs.entries) {
        final item = testItems.byId(input.key);
        inventory = inventory.adding(ItemStack(item, count: input.value * 100));
      }

      // Need summoning level to craft.
      final skillStates = <Skill, SkillState>{
        Skill.summoning: SkillState(
          xp: startXpForLevel(summoningAction.unlockLevel),
          masteryPoolXp: 0,
        ),
      };

      var state = GlobalState.test(
        testRegistries,
        summoning: summoningState,
        inventory: inventory,
        skillStates: skillStates,
      );

      // Verify the tablet is NOT crafted yet.
      expect(state.summoning.hasCrafted(productId), isFalse);

      // Start the summoning action.
      state = state.startAction(summoningAction, random: Random(42));

      // Run enough to complete at least one action (5 seconds = 50 ticks).
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 100, random: Random(42));
      state = builder.build();

      // Verify markTabletCrafted was called.
      expect(state.summoning.hasCrafted(productId), isTrue);
    });
  });
}
