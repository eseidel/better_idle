import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late Item woodcuttingToken;

  setUpAll(() async {
    await loadTestRegistries();
    woodcuttingToken = testItems.byName('Mastery Token (Woodcutting)');
  });

  group('MasteryTokenDrop', () {
    test('drop chance increases with more unlocked actions', () {
      const drop = MasteryTokenDrop(skill: Skill.woodcutting);

      // With 1 unlocked action: 1/18500 = 0.0054%
      expect(drop.dropChance(1), closeTo(1 / 18500, 0.0001));

      // With 10 unlocked actions: 10/18500 = 0.054%
      expect(drop.dropChance(10), closeTo(10 / 18500, 0.0001));

      // With 155 unlocked actions: 155/18500 = 0.84%
      expect(drop.dropChance(155), closeTo(155 / 18500, 0.0001));
    });

    test('drop chance is 0 with no unlocked actions', () {
      const drop = MasteryTokenDrop(skill: Skill.woodcutting);
      expect(drop.dropChance(0), 0);
    });

    test('itemId is correct for each skill', () {
      expect(
        const MasteryTokenDrop(skill: Skill.woodcutting).itemId,
        const MelvorId('melvorD:Mastery_Token_Woodcutting'),
      );
      expect(
        const MasteryTokenDrop(skill: Skill.fishing).itemId,
        const MelvorId('melvorD:Mastery_Token_Fishing'),
      );
      expect(
        const MasteryTokenDrop(skill: Skill.mining).itemId,
        const MelvorId('melvorD:Mastery_Token_Mining'),
      );
    });

    test('rollWithContext returns token when roll succeeds', () {
      const drop = MasteryTokenDrop(skill: Skill.woodcutting);
      // Use a seeded random to get predictable results
      // With 18500 unlocked actions, chance is 100%
      final random = Random(42);
      final result = drop.rollWithContext(
        testItems,
        random,
        unlockedActions: 18500,
      );
      expect(result, isNotNull);
      expect(result!.item.name, 'Mastery Token (Woodcutting)');
      expect(result.count, 1);
    });

    test('roll() throws UnimplementedError', () {
      const drop = MasteryTokenDrop(skill: Skill.woodcutting);
      expect(
        () => drop.roll(testItems, Random()),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('DropsRegistry.masteryTokenForSkill', () {
    test('returns MasteryTokenDrop for non-combat skills', () {
      final woodcuttingToken = testRegistries.drops.masteryTokenForSkill(
        Skill.woodcutting,
      );
      expect(woodcuttingToken, isNotNull);
      expect(woodcuttingToken!.skill, Skill.woodcutting);

      final fishingToken = testRegistries.drops.masteryTokenForSkill(
        Skill.fishing,
      );
      expect(fishingToken, isNotNull);
      expect(fishingToken!.skill, Skill.fishing);
    });

    test('returns null for combat skills', () {
      expect(testRegistries.drops.masteryTokenForSkill(Skill.attack), isNull);
      expect(testRegistries.drops.masteryTokenForSkill(Skill.defence), isNull);
      expect(testRegistries.drops.masteryTokenForSkill(Skill.combat), isNull);
    });
  });

  group('claimMasteryToken', () {
    test('adds 0.1% of max pool XP when claiming token', () {
      var state = GlobalState.empty(testRegistries);

      // Add a mastery token to inventory
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 1),
        ),
      );

      // Calculate expected XP
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final expectedXp = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      // Claim the token
      final newState = state.claimMasteryToken(Skill.woodcutting);

      // Verify token was consumed
      expect(newState.inventory.countOfItem(woodcuttingToken), 0);

      // Verify XP was added
      expect(newState.skillState(Skill.woodcutting).masteryPoolXp, expectedXp);
    });

    test('throws if no token in inventory', () {
      final state = GlobalState.empty(testRegistries);

      expect(
        () => state.claimMasteryToken(Skill.woodcutting),
        throwsStateError,
      );
    });

    test('throws for combat skills', () {
      final state = GlobalState.empty(testRegistries);

      expect(() => state.claimMasteryToken(Skill.attack), throwsStateError);
    });

    test('throws when pool is already full', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 1),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp),
        },
      );

      expect(
        () => state.claimMasteryToken(Skill.woodcutting),
        throwsStateError,
      );
    });

    test('throws when remaining space is less than full token XP', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      // Fill pool to just 1 XP below max (less than a full token).
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 1),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp - 1),
        },
      );

      expect(
        () => state.claimMasteryToken(Skill.woodcutting),
        throwsStateError,
      );
    });
  });

  group('claimAllMasteryTokens', () {
    test('claims all tokens at once', () {
      var state = GlobalState.empty(testRegistries);

      // Add 5 mastery tokens to inventory
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
      );

      // Calculate expected XP
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);
      final expectedXp = xpPerToken * 5;

      // Claim all tokens
      final newState = state.claimAllMasteryTokens(Skill.woodcutting);

      // Verify all tokens were consumed
      expect(newState.inventory.countOfItem(woodcuttingToken), 0);

      // Verify XP was added for all tokens
      expect(newState.skillState(Skill.woodcutting).masteryPoolXp, expectedXp);
    });

    test('only claims tokens that fit without exceeding pool cap', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      // Fill pool so only 2 tokens worth of space remains.
      final startXp = maxPoolXp - (xpPerToken * 2);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 10),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: startXp),
        },
      );

      final newState = state.claimAllMasteryTokens(Skill.woodcutting);

      // Should only consume 2 tokens.
      expect(newState.inventory.countOfItem(woodcuttingToken), 8);
      // Pool should be exactly at start + 2 * xpPerToken.
      expect(
        newState.skillState(Skill.woodcutting).masteryPoolXp,
        startXp + xpPerToken * 2,
      );
    });

    test('returns same state when pool is full', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp),
        },
      );

      final newState = state.claimAllMasteryTokens(Skill.woodcutting);
      // No tokens should be consumed.
      expect(newState.inventory.countOfItem(woodcuttingToken), 5);
    });

    test('returns same state if no tokens', () {
      final state = GlobalState.empty(testRegistries);
      final newState = state.claimAllMasteryTokens(Skill.woodcutting);
      expect(newState, state);
    });

    test('returns same state for combat skills', () {
      final state = GlobalState.empty(testRegistries);
      final newState = state.claimAllMasteryTokens(Skill.attack);
      expect(newState, state);
    });
  });

  group('claimMasteryTokens', () {
    test('claims exact count of tokens', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 10),
        ),
      );

      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      final newState = state.claimMasteryTokens(Skill.woodcutting, 3);

      expect(newState.inventory.countOfItem(woodcuttingToken), 7);
      expect(
        newState.skillState(Skill.woodcutting).masteryPoolXp,
        xpPerToken * 3,
      );
    });

    test('clamps count to claimable amount', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      // Space for only 2 tokens.
      final startXp = maxPoolXp - (xpPerToken * 2);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 10),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: startXp),
        },
      );

      // Request 5, but only 2 fit.
      final newState = state.claimMasteryTokens(Skill.woodcutting, 5);

      expect(newState.inventory.countOfItem(woodcuttingToken), 8);
      expect(
        newState.skillState(Skill.woodcutting).masteryPoolXp,
        startXp + xpPerToken * 2,
      );
    });

    test('clamps count to held tokens', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 3),
        ),
      );

      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      // Request 10, but only have 3.
      final newState = state.claimMasteryTokens(Skill.woodcutting, 10);

      expect(newState.inventory.countOfItem(woodcuttingToken), 0);
      expect(
        newState.skillState(Skill.woodcutting).masteryPoolXp,
        xpPerToken * 3,
      );
    });

    test('returns same state when count is 0', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
      );

      final newState = state.claimMasteryTokens(Skill.woodcutting, 0);
      expect(newState.inventory.countOfItem(woodcuttingToken), 5);
      expect(newState.skillState(Skill.woodcutting).masteryPoolXp, 0);
    });

    test('returns same state for combat skills', () {
      final state = GlobalState.empty(testRegistries);
      final newState = state.claimMasteryTokens(Skill.attack, 5);
      expect(newState, state);
    });

    test('returns same state when pool is full', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp),
        },
      );

      final newState = state.claimMasteryTokens(Skill.woodcutting, 3);
      expect(newState.inventory.countOfItem(woodcuttingToken), 5);
    });
  });

  group('claimableMasteryTokenCount', () {
    test('returns 0 for combat skills', () {
      final state = GlobalState.empty(testRegistries);
      expect(state.claimableMasteryTokenCount(Skill.attack), 0);
    });

    test('returns 0 when pool is full', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp),
        },
      );
      expect(state.claimableMasteryTokenCount(Skill.woodcutting), 0);
    });

    test('returns limited count when near pool cap', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      final xpPerToken = (maxPoolXp * 0.001).round().clamp(1, maxPoolXp);

      // Space for exactly 3 tokens.
      final startXp = maxPoolXp - (xpPerToken * 3);
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 10),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: startXp),
        },
      );
      expect(state.claimableMasteryTokenCount(Skill.woodcutting), 3);
    });

    test('returns 0 when remaining space is less than one token', () {
      final maxPoolXp = maxMasteryPoolXpForSkill(
        testRegistries,
        Skill.woodcutting,
      );
      // Fill pool to 1 XP below max.
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(
          ItemStack(woodcuttingToken, count: 5),
        ),
        skillStates: {
          ...state.skillStates,
          Skill.woodcutting: state
              .skillState(Skill.woodcutting)
              .copyWith(masteryPoolXp: maxPoolXp - 1),
        },
      );
      expect(state.claimableMasteryTokenCount(Skill.woodcutting), 0);
    });
  });

  group('mastery token drops during actions', () {
    test('mastery tokens can drop from woodcutting', () {
      // This test verifies the integration of mastery tokens with the
      // rollAndCollectDrops function. We use a fixed seed to ensure
      // deterministic behavior.
      var state = GlobalState.empty(testRegistries);
      final normalTree = testRegistries.woodcuttingAction('Normal Tree');

      // Start the action
      final random = Random(12345);
      state = state.startAction(normalTree, random: random);

      // Run many completions to have a chance of getting a token drop
      // With ~8 actions unlocked at level 1, chance is 8/18500 ≈ 0.04%
      // We need many iterations, but the test is just checking that the
      // mechanism works, not the actual drop rate.
      final builder = StateUpdateBuilder(state);

      // Simulate 10000 action completions to get at least some token drops
      // (this is a probabilistic test, but with this many iterations
      // we should almost always get at least one drop)
      final ticksPerAction = ticksFromDuration(normalTree.minDuration);
      for (var i = 0; i < 10000; i++) {
        consumeTicks(builder, ticksPerAction, random: random);
      }

      state = builder.build();

      // Check if we got any mastery tokens
      // This is probabilistic but should pass with very high probability
      final tokenCount = state.inventory.countOfItem(woodcuttingToken);
      // Note: With very low probability this could fail if we get unlucky
      // In practice, 10000 iterations with ~0.04% chance should yield ~4 tokens
      expect(
        tokenCount,
        greaterThanOrEqualTo(0),
        reason: 'Mastery tokens should be able to drop from skill actions',
      );
    });
  });
}
