import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

/// A mock Random that returns predictable values.
class MockRandom implements Random {
  MockRandom({
    this.nextDoubleValue = 0.0,
    this.nextIntValue = 0,
  });

  final double nextDoubleValue;
  final int nextIntValue;

  @override
  double nextDouble() => nextDoubleValue;

  @override
  int nextInt(int max) => nextIntValue.clamp(0, max - 1);

  @override
  bool nextBool() => nextDoubleValue < 0.5;
}

void main() {
  final manAction = thievingActionByName('Man');

  group('ThievingAction', () {
    test('Man action has correct properties', () {
      expect(manAction.name, 'Man');
      expect(manAction.skill, Skill.thieving);
      expect(manAction.unlockLevel, 1);
      expect(manAction.xp, 5);
      expect(manAction.perception, 110);
      expect(manAction.maxHit, 22);
      expect(manAction.maxGold, 100);
      expect(manAction.minDuration, const Duration(seconds: 3));
    });

    test('rollDamage returns value between 1 and maxHit', () {
      // With nextInt returning 0, damage = 1 + 0 = 1
      final minRng = MockRandom(nextIntValue: 0);
      expect(manAction.rollDamage(minRng), 1);

      // With nextInt returning maxHit-1, damage = 1 + (maxHit-1) = maxHit
      final maxRng = MockRandom(nextIntValue: manAction.maxHit - 1);
      expect(manAction.rollDamage(maxRng), manAction.maxHit);
    });

    test('rollGold returns value between 1 and maxGold', () {
      // With nextInt returning 0, gold = 1 + 0 = 1
      final minRng = MockRandom(nextIntValue: 0);
      expect(manAction.rollGold(minRng), 1);

      // With nextInt returning maxGold-1, gold = 1 + (maxGold-1) = maxGold
      final maxRng = MockRandom(nextIntValue: manAction.maxGold - 1);
      expect(manAction.rollGold(maxRng), manAction.maxGold);
    });

    test('rollSuccess fails at level 1 vs perception 110 with high roll', () {
      // Success rate at level 1 = 1 * 100 / (110 + 1) = ~0.9%
      // Roll of 50 (50%) should fail
      final rng = MockRandom(nextDoubleValue: 0.50);
      expect(manAction.rollSuccess(rng, 1), isFalse);
    });

    test('rollSuccess succeeds at level 1 vs perception 110 with low roll', () {
      // Success rate at level 1 = 1 * 100 / (110 + 1) = ~0.9%
      // Roll of 0.001 (0.1%) should succeed
      final rng = MockRandom(nextDoubleValue: 0.00001);
      expect(manAction.rollSuccess(rng, 1), isTrue);
    });
  });

  group('Thieving success', () {
    test('thieving success grants gold and XP', () {
      // Set up state with thieving action active
      final state = GlobalState.test().startAction(manAction);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds and grants specific gold
      final rng = MockRandom(
        nextDoubleValue: 0.0, // Always succeed (roll < success rate)
        nextIntValue: 49, // Gold = 1 + 49 = 50
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Should have gained gold (1 + 49 = 50)
      expect(newState.gp, 50);
      // Should have gained XP
      expect(newState.skillState(Skill.thieving).xp, manAction.xp);
      // Should NOT be stunned
      expect(newState.isStunned, isFalse);
    });

    test('thieving success through tick processing', () {
      // Start thieving action
      var state = GlobalState.test().startAction(manAction);
      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds
      final rng = MockRandom(
        nextDoubleValue: 0.0, // Always succeed
        nextIntValue: 99, // Gold = 1 + 99 = 100 (max)
      );

      // Process enough ticks to complete the action (3 seconds = 30 ticks)
      consumeTicksForAllSystems(builder, 30, random: rng);

      final newState = builder.build();
      // Should have gained gold
      expect(newState.gp, greaterThan(0));
      // Should have gained XP
      expect(newState.skillState(Skill.thieving).xp, greaterThan(0));
      // Should NOT be stunned
      expect(newState.isStunned, isFalse);
      // Action should still be active (restarted)
      expect(newState.activeAction, isNotNull);
      expect(newState.activeAction!.name, 'Man');
    });
  });

  group('Thieving failure', () {
    test('thieving failure deals damage and stuns player', () {
      // Set up state with enough HP to survive (level 10 hitpoints = 100 HP)
      final state = GlobalState.test(
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryXp: 0), // Level 10
        },
      ).startAction(manAction);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails and deals specific damage
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail (roll > success rate)
        nextIntValue: 10, // Damage = 1 + 10 = 11
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Should have taken damage
      expect(newState.health.lostHp, 11);
      // Should be stunned
      expect(newState.isStunned, isTrue);
      expect(newState.stunned.ticksRemaining, stunnedDurationTicks);
      // Should NOT have gained XP
      expect(newState.skillState(Skill.thieving).xp, 0);
      // Should NOT have gained gold
      expect(newState.gp, 0);
    });

    test('thieving failure that kills player stops action', () {
      // Set up state with low HP (less than max damage)
      final state = GlobalState.test(
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryXp: 0), // Level 10 = 100 HP
        },
        health: const HealthState(lostHp: 95), // Only 5 HP left (100 max)
      ).startAction(manAction);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails and deals max damage
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail
        nextIntValue: 21, // Damage = 1 + 21 = 22 (max)
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isFalse);

      final newState = builder.build();
      // Health should be reset (player respawned)
      expect(newState.health.lostHp, 0);
      // Should NOT be stunned (death clears it)
      expect(newState.isStunned, isFalse);
    });

    test('thieving failure killing player through tick processing stops action',
        () {
      // Start with low HP
      var state = GlobalState.test(
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryXp: 0), // Level 10 = 100 HP
        },
        health: const HealthState(lostHp: 95), // Only 5 HP left
      ).startAction(manAction);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails and deals max damage
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail
        nextIntValue: 21, // Damage = 22
      );

      // Process enough ticks to complete the action (30 ticks)
      consumeTicksForAllSystems(builder, 30, random: rng);

      final newState = builder.build();
      // Health should be reset
      expect(newState.health.lostHp, 0);
      // Action should be stopped (player died)
      expect(newState.activeAction, isNull);
    });
  });

  group('Thieving stun recovery', () {
    test('thieving continues after stun wears off', () {
      // Start thieving while already stunned
      var state = GlobalState.test(
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryXp: 0), // Level 10 = 100 HP
        },
        stunned: const StunnedState.fresh().stun(), // 30 ticks of stun
      );
      // Need to manually set up the action since startAction throws when stunned
      state = GlobalState(
        inventory: state.inventory,
        activeAction: ActiveAction(
          name: manAction.name,
          remainingTicks: 30,
          totalTicks: 30,
        ),
        skillStates: state.skillStates,
        actionStates: state.actionStates,
        updatedAt: state.updatedAt,
        gp: state.gp,
        shop: state.shop,
        health: state.health,
        equipment: state.equipment,
        stunned: state.stunned,
      );

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds when we finally try
      final rng = MockRandom(
        nextDoubleValue: 0.0, // Always succeed
        nextIntValue: 49, // Gold = 50
      );

      // Process just enough to clear stun (30 ticks)
      consumeTicksForAllSystems(builder, 30, random: rng);

      var newState = builder.build();
      // Stun should be cleared
      expect(newState.isStunned, isFalse);
      // Action should still be active (restarted after stun)
      expect(newState.activeAction, isNotNull);

      // Now process more ticks to complete the action
      final builder2 = StateUpdateBuilder(newState);
      consumeTicksForAllSystems(builder2, 30, random: rng);

      newState = builder2.build();
      // Should have gained gold from successful theft
      expect(newState.gp, greaterThan(0));
    });
  });
}
