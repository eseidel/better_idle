import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/game_loop.dart';

/// A simple test action for making shouldTick return true.
const _testAction = SkillAction(
  id: ActionId(MelvorId('melvorD:Woodcutting'), MelvorId('test:TestAction')),
  skill: Skill.woodcutting,
  name: 'Test Action',
  duration: Duration(seconds: 1),
  xp: 10,
  unlockLevel: 1,
);

/// A longer test action for testing timer scheduling.
const _longAction = SkillAction(
  id: ActionId(MelvorId('melvorD:Woodcutting'), MelvorId('test:LongAction')),
  skill: Skill.woodcutting,
  name: 'Long Action',
  duration: Duration(seconds: 10),
  xp: 50,
  unlockLevel: 1,
);

/// A very short action for testing timer firing (minimum 1 tick = 100ms).
const _quickAction = SkillAction(
  id: ActionId(MelvorId('melvorD:Woodcutting'), MelvorId('test:QuickAction')),
  skill: Skill.woodcutting,
  name: 'Quick Action',
  duration: Duration(milliseconds: 100), // 1 tick
  xp: 1,
  unlockLevel: 1,
);

void main() {
  final registries = Registries.test(
    actions: const [_testAction, _longAction, _quickAction],
  );

  group('GameLoop suspend/resume', () {
    test('suspend prevents auto-start from state changes', () {
      // Create a store with an active action (shouldTick = true)
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);
      // Start an action to make shouldTick = true
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );
      expect(store.state.shouldTick, isTrue);

      // Create game loop - it should auto-start because shouldTick is true
      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Suspend the game loop
      gameLoop.suspend();
      expect(gameLoop.isRunning, isFalse);

      // Trigger a state change that would normally auto-start the loop
      store.dispatch(_SetStateAction(store.state));

      // Loop should remain paused because it's suspended
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('resume re-enables auto-start', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);
      // Start an action to make shouldTick = true
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Suspend
      gameLoop.suspend();
      expect(gameLoop.isRunning, isFalse);

      // Resume - should auto-start because shouldTick is still true
      gameLoop.resume();
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });

    test('suspend stops running loop', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);
      // Start an action
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Suspend should stop the running loop
      gameLoop.suspend();
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('resume does not start loop if shouldTick is false', () {
      // Create store with no active action and no deity (shouldTick = false)
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      expect(store.state.shouldTick, isFalse);

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isFalse);

      // Suspend then resume
      gameLoop
        ..suspend()
        ..resume();

      // Should still not be running because shouldTick is false
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });
  });

  group('GameLoop event scheduling', () {
    test('loop does not start without deity or active action', () {
      // Empty state has no deity, so township timers are not active
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      // shouldTick is false - no deity, no active action
      expect(store.state.shouldTick, isFalse);

      // Verify that calculateTicksUntilNextEvent returns null
      final builder = StateUpdateBuilder(store.state);
      expect(builder.calculateTicksUntilNextEvent(), isNull);

      // Game loop should not auto-start
      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('loop pauses when action stops and no other timers', () async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      // Start an action
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );
      expect(store.state.shouldTick, isTrue);

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Stop the action - shouldTick becomes false (no deity either)
      store.dispatch(_SetStateAction(store.state.clearAction()));
      expect(store.state.shouldTick, isFalse);

      // Wait for stream event to propagate
      await Future<void>.delayed(Duration.zero);

      // Loop should auto-pause
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('loop starts when action is started', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      // Start a 1-second action
      final stateWithAction = initialState.startAction(
        _testAction,
        random: testRandom,
      );
      store.dispatch(_SetStateAction(stateWithAction));

      // Next event should be the action completion (~10 ticks = 1s)
      final actionBuilder = StateUpdateBuilder(store.state);
      final actionTicks = actionBuilder.calculateTicksUntilNextEvent()!;
      expect(actionTicks, lessThanOrEqualTo(10)); // 1 second = 10 ticks

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });
  });

  group('GameLoop constructor', () {
    test('auto-starts when shouldTick is true on creation', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      // Set up state with active action before creating GameLoop
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });

    test('does not auto-start when shouldTick is false on creation', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      // No action started, shouldTick is false
      expect(store.state.shouldTick, isFalse);

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('subscribes to store changes', () async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      // Create loop with no active action
      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isFalse);

      // Start an action after GameLoop is created
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      // Wait for stream event to propagate
      await Future<void>.delayed(Duration.zero);

      // Loop should have auto-started
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });
  });

  group('GameLoop start/pause', () {
    test('start is idempotent', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Calling start again should not cause issues
      gameLoop.start();
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });

    test('pause is idempotent', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isFalse);

      // Calling pause when already paused should not cause issues
      gameLoop.pause();
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('pause stops running loop', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      gameLoop.pause();
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    test('start after pause resumes loop', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      gameLoop.pause();
      expect(gameLoop.isRunning, isFalse);

      gameLoop.start();
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });
  });

  group('GameLoop dispose', () {
    test('dispose stops running loop', () {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
      expect(gameLoop.isRunning, isFalse);
    });

    test('dispose unsubscribes from store', () async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      final gameLoop = GameLoop(store)..dispose();

      // Start an action after dispose
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      // Wait for any potential stream event
      await Future<void>.delayed(Duration.zero);

      // Loop should remain stopped (subscription cancelled)
      expect(gameLoop.isRunning, isFalse);
    });
  });

  group('GameLoop state change rescheduling', () {
    test('reschedules when new action started while running', () async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      // Start with a long action (10 seconds)
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_longAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Get initial next event timing
      final initialBuilder = StateUpdateBuilder(store.state);
      final initialTicks = initialBuilder.calculateTicksUntilNextEvent()!;
      expect(initialTicks, greaterThan(50)); // Long action should be > 5s

      // Switch to a shorter action
      final clearedState = store.state.clearAction();
      store.dispatch(
        _SetStateAction(
          clearedState.startAction(_testAction, random: testRandom),
        ),
      );

      // Wait for stream event
      await Future<void>.delayed(Duration.zero);

      // Verify the loop is still running
      expect(gameLoop.isRunning, isTrue);

      // New next event should be shorter
      final newBuilder = StateUpdateBuilder(store.state);
      final newTicks = newBuilder.calculateTicksUntilNextEvent()!;
      expect(newTicks, lessThan(initialTicks));
      expect(newTicks, lessThanOrEqualTo(10)); // 1 second = 10 ticks

      gameLoop.dispose();
    });

    test('pauses when action cleared and no background timers', () async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);

      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(store);
      expect(gameLoop.isRunning, isTrue);

      // Clear the action
      store.dispatch(_SetStateAction(store.state.clearAction()));

      // Wait for stream event
      await Future<void>.delayed(Duration.zero);

      // Should pause since shouldTick is now false
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });
  });

  group('GameLoop timer firing', () {
    // Note: These tests use fakeAsync to control timer execution.
    // However, DateTime.timestamp() is not controlled by fakeAsync,
    // so we test behavior (timer fires, loop state) rather than time-based
    // state changes.

    test('timer fires when time elapses', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        // Start a quick action (100ms = 1 tick)
        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        final gameLoop = GameLoop(store);
        expect(gameLoop.isRunning, isTrue);

        // Initial dispatch from setting up action
        final initialDispatchCount = dispatchCount;

        // Advance time past the timer (minimum delay is 100ms)
        async.elapse(const Duration(milliseconds: 150));

        // A dispatch should have occurred from timer firing
        expect(dispatchCount, greaterThan(initialDispatchCount));

        gameLoop.dispose();
      });
    });

    test('timer does not fire when loop is paused', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        final gameLoop = GameLoop(store);
        expect(gameLoop.isRunning, isTrue);

        // Pause immediately before timer can fire
        gameLoop.pause();
        expect(gameLoop.isRunning, isFalse);

        final dispatchCountAfterPause = dispatchCount;

        // Advance time past when the timer would have fired
        async.elapse(const Duration(milliseconds: 200));

        // No additional dispatches should have occurred
        expect(dispatchCount, equals(dispatchCountAfterPause));

        gameLoop.dispose();
      });
    });

    test('timer does not fire when loop is suspended', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        final gameLoop = GameLoop(store);
        expect(gameLoop.isRunning, isTrue);

        // Suspend immediately before timer can fire
        gameLoop.suspend();
        expect(gameLoop.isRunning, isFalse);

        final dispatchCountAfterSuspend = dispatchCount;

        // Advance time past when the timer would have fired
        async.elapse(const Duration(milliseconds: 200));

        // No additional dispatches should have occurred
        expect(dispatchCount, equals(dispatchCountAfterSuspend));

        gameLoop.dispose();
      });
    });

    test('timer reschedules after firing (loop stays running)', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        // Start a 1-second action that will need multiple timer fires
        store.dispatch(
          _SetStateAction(
            initialState.startAction(_testAction, random: testRandom),
          ),
        );

        final gameLoop = GameLoop(store);
        expect(gameLoop.isRunning, isTrue);

        // Advance time for one tick (100ms)
        async.elapse(const Duration(milliseconds: 150));

        // Loop should still be running (timer rescheduled)
        expect(gameLoop.isRunning, isTrue);

        // Advance more time
        async.elapse(const Duration(milliseconds: 150));

        // Loop should still be running
        expect(gameLoop.isRunning, isTrue);

        gameLoop.dispose();
      });
    });

    test('loop handles shouldTick becoming false via state change', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        // Start a quick action
        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        final gameLoop = GameLoop(store);
        expect(gameLoop.isRunning, isTrue);

        // Clear the action - this will cause shouldTick to be false
        store.dispatch(_SetStateAction(store.state.clearAction()));

        // Flush microtasks so the state change listener fires
        async.flushMicrotasks();

        // Loop should have paused since shouldTick is now false
        expect(gameLoop.isRunning, isFalse);

        // Advance time - timer should not fire since loop is paused
        async.elapse(const Duration(milliseconds: 200));

        // Still paused
        expect(gameLoop.isRunning, isFalse);

        gameLoop.dispose();
      });
    });

    test('timer fires at scheduled time based on next event', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        // Subscribe to changes before any dispatches
        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        // Start a 1-second action (10 ticks = 1000ms)
        store.dispatch(
          _SetStateAction(
            initialState.startAction(_testAction, random: testRandom),
          ),
        );

        // Flush microtasks to count the initial dispatch
        async.flushMicrotasks();
        final initialCount = dispatchCount;

        final gameLoop = GameLoop(store);

        // The timer should be scheduled for ~1 second (action duration)
        // Advance time by 500ms - timer should NOT have fired yet
        async.elapse(const Duration(milliseconds: 500));
        expect(dispatchCount, equals(initialCount));

        // Advance past the 1 second mark - timer should fire
        async.elapse(const Duration(milliseconds: 600));
        expect(dispatchCount, greaterThan(initialCount));

        gameLoop.dispose();
      });
    });

    test('timer callback checks isRunning before dispatching', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        final gameLoop = GameLoop(store);

        // Advance partway to timer
        async.elapse(const Duration(milliseconds: 50));

        // Pause while timer is pending
        gameLoop.pause();
        final countAfterPause = dispatchCount;

        // Advance past when timer would fire
        async.elapse(const Duration(milliseconds: 100));

        // No dispatch should occur because we paused
        expect(dispatchCount, equals(countAfterPause));

        gameLoop.dispose();
      });
    });

    test('timer callback checks isSuspended before dispatching', () {
      fakeAsync((async) {
        final initialState = GlobalState.empty(registries);
        final store = Store<GlobalState>(initialState: initialState);
        final testRandom = Random(42);

        store.dispatch(
          _SetStateAction(
            initialState.startAction(_quickAction, random: testRandom),
          ),
        );

        var dispatchCount = 0;
        store.onChange.listen((_) => dispatchCount++);

        final gameLoop = GameLoop(store);

        // Advance partway to timer
        async.elapse(const Duration(milliseconds: 50));

        // Suspend while timer is pending
        gameLoop.suspend();
        final countAfterSuspend = dispatchCount;

        // Advance past when timer would fire
        async.elapse(const Duration(milliseconds: 100));

        // No dispatch should occur because we suspended
        expect(dispatchCount, equals(countAfterSuspend));

        gameLoop.dispose();
      });
    });
  });

  group('GameLoop calculateTicksUntilNextEvent consistency', () {
    test('returns null when no work to do', () {
      final initialState = GlobalState.empty(registries);
      final builder = StateUpdateBuilder(initialState);

      expect(builder.calculateTicksUntilNextEvent(), isNull);
      expect(initialState.shouldTick, isFalse);
    });

    test('returns positive value when action is active', () {
      final initialState = GlobalState.empty(registries);
      final testRandom = Random(42);
      final stateWithAction = initialState.startAction(
        _testAction,
        random: testRandom,
      );

      final builder = StateUpdateBuilder(stateWithAction);
      final ticks = builder.calculateTicksUntilNextEvent();

      expect(ticks, isNotNull);
      expect(ticks, greaterThan(0));
      expect(stateWithAction.shouldTick, isTrue);
    });

    test('tracks action remaining ticks correctly', () {
      final initialState = GlobalState.empty(registries);
      final testRandom = Random(42);

      // Start action - 1 second = 10 ticks
      final stateWithAction = initialState.startAction(
        _testAction,
        random: testRandom,
      );

      final builder = StateUpdateBuilder(stateWithAction);
      final ticks = builder.calculateTicksUntilNextEvent()!;

      // Should be around 10 ticks for 1 second action
      expect(ticks, lessThanOrEqualTo(10));
      expect(ticks, greaterThan(0));
    });

    test('returns correct ticks for longer actions', () {
      final initialState = GlobalState.empty(registries);
      final testRandom = Random(42);

      // Start long action - 10 seconds = 100 ticks
      final stateWithAction = initialState.startAction(
        _longAction,
        random: testRandom,
      );

      final builder = StateUpdateBuilder(stateWithAction);
      final ticks = builder.calculateTicksUntilNextEvent()!;

      // Should be around 100 ticks for 10 second action
      expect(ticks, lessThanOrEqualTo(100));
      expect(ticks, greaterThan(50)); // At least half the duration
    });
  });
}

/// Simple action to set state directly for testing.
class _SetStateAction extends ReduxAction<GlobalState> {
  _SetStateAction(this.newState);
  final GlobalState newState;

  @override
  GlobalState reduce() => newState;
}
