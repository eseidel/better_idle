import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await ensureItemsInitialized();
  });
  group('StunnedState', () {
    test('fresh state is not stunned', () {
      const state = StunnedState.fresh();
      expect(state.isStunned, isFalse);
      expect(state.ticksRemaining, 0);
    });

    test('stun() creates a stunned state with full duration', () {
      const state = StunnedState.fresh();
      final stunned = state.stun();
      expect(stunned.isStunned, isTrue);
      expect(stunned.ticksRemaining, stunnedDurationTicks);
    });

    test('applyTicks reduces remaining time', () {
      final state = const StunnedState.fresh().stun();
      final after10Ticks = state.applyTicks(10);
      expect(after10Ticks.ticksRemaining, stunnedDurationTicks - 10);
      expect(after10Ticks.isStunned, isTrue);
    });

    test('applyTicks clears stun when duration expires', () {
      final state = const StunnedState.fresh().stun();
      final afterAllTicks = state.applyTicks(stunnedDurationTicks);
      expect(afterAllTicks.isStunned, isFalse);
      expect(afterAllTicks.ticksRemaining, 0);
    });

    test('applyTicks does not go negative', () {
      final state = const StunnedState.fresh().stun();
      final afterTooManyTicks = state.applyTicks(stunnedDurationTicks + 100);
      expect(afterTooManyTicks.ticksRemaining, 0);
      expect(afterTooManyTicks.isStunned, isFalse);
    });

    test('applyTicks on non-stunned state is a no-op', () {
      const state = StunnedState.fresh();
      final afterTicks = state.applyTicks(10);
      expect(afterTicks.ticksRemaining, 0);
      expect(afterTicks.isStunned, isFalse);
    });

    test('stunnedDuration is 3 seconds', () {
      expect(stunnedDuration, const Duration(seconds: 3));
    });

    test('stunnedDurationTicks is 30 ticks', () {
      // 3 seconds = 3000ms, 1 tick = 100ms, so 30 ticks
      expect(stunnedDurationTicks, 30);
    });

    test('toJson/fromJson round-trip', () {
      final original = const StunnedState.fresh().stun();
      final json = original.toJson();
      final restored = StunnedState.fromJson(json);
      expect(restored.ticksRemaining, original.ticksRemaining);
      expect(restored.isStunned, original.isStunned);
    });

    test('maybeFromJson returns null for null input', () {
      expect(StunnedState.maybeFromJson(null), isNull);
    });

    test('maybeFromJson parses valid json', () {
      final json = {'ticksRemaining': 15};
      final state = StunnedState.maybeFromJson(json);
      expect(state, isNotNull);
      expect(state!.ticksRemaining, 15);
    });
  });

  group('GlobalState stunned behavior', () {
    late SkillAction normalTree;

    setUpAll(() {
      normalTree = actionRegistry.byName('Normal Tree') as SkillAction;
    });

    test('isStunned returns false when not stunned', () {
      final state = GlobalState.test();
      expect(state.isStunned, isFalse);
    });

    test('isStunned returns true when stunned', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      expect(state.isStunned, isTrue);
    });

    test('startAction throws StunnedException when stunned', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      final random = Random(0);
      expect(
        () => state.startAction(normalTree, random: random),
        throwsA(isA<StunnedException>()),
      );
    });

    test('clearAction throws StunnedException when stunned', () {
      final state = GlobalState.test(
        activeAction: const ActiveAction(
          name: 'Normal Tree',
          remainingTicks: 10,
          totalTicks: 30,
        ),
        stunned: const StunnedState.fresh().stun(),
      );
      expect(() => state.clearAction(), throwsA(isA<StunnedException>()));
    });

    test('startAction works when not stunned', () {
      final state = GlobalState.test();
      final random = Random(0);
      final newState = state.startAction(normalTree, random: random);
      expect(newState.activeAction, isNotNull);
      expect(newState.activeAction!.name, 'Normal Tree');
    });

    test('clearAction works when not stunned', () {
      final state = GlobalState.test(
        activeAction: const ActiveAction(
          name: 'Normal Tree',
          remainingTicks: 10,
          totalTicks: 30,
        ),
      );
      final newState = state.clearAction();
      expect(newState.activeAction, isNull);
    });

    test('shouldTick returns true when stunned', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      expect(state.shouldTick, isTrue);
    });

    test('hasActiveBackgroundTimers returns true when stunned', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      expect(state.hasActiveBackgroundTimers, isTrue);
    });
  });

  group('Stunned countdown via tick processing', () {
    test('stunned state decreases over ticks', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      final builder = StateUpdateBuilder(state);

      // Process 10 ticks (1 second)
      final random = Random(0);
      consumeTicks(builder, 10, random: random);
      final afterTicks = builder.build();

      expect(afterTicks.stunned.ticksRemaining, stunnedDurationTicks - 10);
      expect(afterTicks.isStunned, isTrue);
    });

    test('stunned state clears after full duration', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      final builder = StateUpdateBuilder(state);

      // Process all stun ticks (3 seconds = 30 ticks)
      final random = Random(0);
      consumeTicks(builder, stunnedDurationTicks, random: random);
      final afterTicks = builder.build();

      expect(afterTicks.stunned.ticksRemaining, 0);
      expect(afterTicks.isStunned, isFalse);
    });

    test('stunned clears after exactly 3 seconds of ticks', () {
      final state = GlobalState.test(
        stunned: const StunnedState.fresh().stun(),
      );
      final builder = StateUpdateBuilder(state);

      // Process exactly 30 ticks (3 seconds)
      final random = Random(0);
      consumeTicks(builder, 30, random: random);
      final afterTicks = builder.build();

      expect(afterTicks.isStunned, isFalse);
    });
  });

  group('StunnedException', () {
    test('has default message', () {
      const exception = StunnedException();
      expect(exception.message, 'Cannot do that while stunned');
      expect(exception.toString(), 'Cannot do that while stunned');
    });

    test('can have custom message', () {
      const exception = StunnedException('Custom stunned message');
      expect(exception.message, 'Custom stunned message');
      expect(exception.toString(), 'Custom stunned message');
    });
  });
}
