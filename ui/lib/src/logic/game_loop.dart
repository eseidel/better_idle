import 'dart:async';

import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:flutter/scheduler.dart';
import 'package:logic/logic.dart';

/// Converts Ticker updates into onTick calls, throttled to the updateInterval.
class GameLoop {
  GameLoop(this._tickerProvider, this._store) {
    _ticker = _tickerProvider.createTicker(_onTick);
    _subscription = _store.onChange.listen(_onStateChange);
    _onStateChange(_store.state);
  }

  void _onStateChange(GlobalState state) {
    // Don't auto-start if suspended (app is backgrounded)
    if (_isSuspended) return;

    if (state.shouldTick) {
      start();
    }
    if (!state.shouldTick) {
      pause();
    }
  }

  final TickerProvider _tickerProvider;
  final Store<GlobalState> _store;
  late final Ticker _ticker;

  bool _isRunning = false;

  /// When suspended, the game loop won't auto-start from state changes.
  /// Used during app lifecycle transitions to prevent background execution.
  bool _isSuspended = false;

  /// Whether the game loop is currently running
  bool get isRunning => _isRunning;

  /// Suspend the game loop, preventing it from auto-starting.
  /// Call this when the app goes to background.
  void suspend() {
    _isSuspended = true;
    pause();
  }

  /// Resume from suspension, allowing auto-start again.
  /// Call this when the app comes to foreground.
  void resume() {
    _isSuspended = false;
    // Re-evaluate state to potentially auto-start
    _onStateChange(_store.state);
  }

  /// The duration between game updates
  Duration updateInterval = const Duration(milliseconds: 100);

  DateTime _lastUpdate = DateTime.timestamp();

  late final StreamSubscription<GlobalState> _subscription;

  /// Start the game loop if not already running
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _lastUpdate = DateTime.timestamp();
    _ticker.start();
  }

  /// Pause the game loop
  void pause() {
    if (!_isRunning) return;

    _isRunning = false;
    _ticker.stop();
  }

  /// Stop and dispose the game loop
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    _subscription.cancel();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.timestamp();
    if (now.difference(_lastUpdate) < updateInterval) {
      return;
    }
    _lastUpdate = now;

    if (!_store.state.shouldTick) {
      // Safety check - should not happen when loop is managed correctly
      return;
    }

    _store.dispatch(UpdateActivityProgressAction(now: now));
  }
}
