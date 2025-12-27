import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:better_idle/src/logic/game_loop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic/logic.dart';

/// A simple test action for making shouldTick return true.
const _testAction = SkillAction(
  id: ActionId(MelvorId('melvorD:Woodcutting'), MelvorId('test:TestAction')),
  skill: Skill.woodcutting,
  name: 'Test Action',
  duration: Duration(seconds: 1),
  xp: 10,
  unlockLevel: 1,
);

void main() {
  final registries = Registries.test(actions: const [_testAction]);

  group('GameLoop suspend/resume', () {
    testWidgets('suspend prevents auto-start from state changes', (
      tester,
    ) async {
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
      final gameLoop = GameLoop(tester, store);
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

    testWidgets('resume re-enables auto-start', (tester) async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);
      // Start an action to make shouldTick = true
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(tester, store);
      expect(gameLoop.isRunning, isTrue);

      // Suspend
      gameLoop.suspend();
      expect(gameLoop.isRunning, isFalse);

      // Resume - should auto-start because shouldTick is still true
      gameLoop.resume();
      expect(gameLoop.isRunning, isTrue);

      gameLoop.dispose();
    });

    testWidgets('suspend stops running loop', (tester) async {
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      final testRandom = Random(42);
      // Start an action
      store.dispatch(
        _SetStateAction(
          initialState.startAction(_testAction, random: testRandom),
        ),
      );

      final gameLoop = GameLoop(tester, store);
      expect(gameLoop.isRunning, isTrue);

      // Suspend should stop the running loop
      gameLoop.suspend();
      expect(gameLoop.isRunning, isFalse);

      gameLoop.dispose();
    });

    testWidgets('resume does not start loop if shouldTick is false', (
      tester,
    ) async {
      // Create store with no active action (shouldTick = false)
      final initialState = GlobalState.empty(registries);
      final store = Store<GlobalState>(initialState: initialState);
      expect(store.state.shouldTick, isFalse);

      final gameLoop = GameLoop(tester, store);
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
}

/// Simple action to set state directly for testing.
class _SetStateAction extends ReduxAction<GlobalState> {
  _SetStateAction(this.newState);
  final GlobalState newState;

  @override
  GlobalState reduce() => newState;
}
