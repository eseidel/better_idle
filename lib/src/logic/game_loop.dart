import 'dart:async';

import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/state.dart';
import 'package:flutter/scheduler.dart';

/// Converts Ticker updates into onTick calls, throttled to the updateInterval.
class GameLoop {
  GameLoop(this._tickerProvider, this._store) {
    _ticker = _tickerProvider.createTicker(_onTick);
    _subscription = _store.onChange.listen(_onStateChange);
    _onStateChange(_store.state);
  }

  void _onStateChange(GlobalState state) {
    if (state.isActive) {
      start();
    }
    if (!state.isActive) {
      pause();
    }
  }

  final TickerProvider _tickerProvider;
  final Store<GlobalState> _store;
  late final Ticker _ticker;

  bool _isRunning = false;

  /// Whether the game loop is currently running
  bool get isRunning => _isRunning;

  /// The duration between game updates
  Duration updateInterval = const Duration(milliseconds: 100);

  DateTime _lastUpdate = DateTime.now();

  late final StreamSubscription<GlobalState> _subscription;

  /// Start the game loop if not already running
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _lastUpdate = DateTime.now();
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

    if (!_store.state.isActive) {
      // Safety check - should not happen when loop is managed correctly
      return;
    }

    _store.dispatch(UpdateActivityProgressAction(now: now));
  }
}
