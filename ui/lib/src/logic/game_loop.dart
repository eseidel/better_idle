import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';

/// Event-driven game loop using one-off timers.
///
/// Instead of polling every 100ms, schedules the next wake based on
/// when the next game event will occur (action completion, HP regen, etc.).
///
/// ## Invariants
///
/// 1. **Only runs when there is work to do**: The loop only runs when
///    `state.shouldTick` is true, meaning there's an active foreground action
///    OR active background timers (HP regen, mining respawn, farming growth,
///    township updates, etc.).
///
/// 2. **Only runs when app is foregrounded**: The loop respects the
///    `_isSuspended` flag set by [suspend]/[resume]. When the app goes to
///    background, the loop is suspended and won't auto-start until resumed.
///
/// 3. **Timer duration matches next event**: Timers are scheduled for the
///    exact time until the next game event. If woodcutting completes in 1s,
///    the timer is 1s. If the next event is a township update in 60m, the
///    timer is 60m. The loop listens to state changes via [_onStateChange]
///    to reschedule immediately when the user starts/stops actions.
///
/// 4. **Minimum timer duration**: Timers are never shorter than [_minDelay]
///    (100ms = 1 tick) to prevent CPU spinning on very rapid events.
///
/// 5. **Null means stop**: If `calculateTicksUntilNextEvent` returns null,
///    the loop pauses. This should only happen when `shouldTick` becomes
///    false (no active work). An assertion fires in debug builds if null
///    is returned while `shouldTick` is true, indicating a logic bug.
class GameLoop {
  GameLoop(this._store) {
    _subscription = _store.onChange.listen(_onStateChange);
    _onStateChange(_store.state);
  }

  final Store<GlobalState> _store;
  late final StreamSubscription<GlobalState> _subscription;

  Timer? _nextEventTimer;
  bool _isRunning = false;

  /// When suspended, the game loop won't auto-start from state changes.
  /// Used during app lifecycle transitions to prevent background execution.
  bool _isSuspended = false;

  /// Whether the game loop is currently suspended.
  bool get isSuspended => _isSuspended;

  // Drift detection fields (debug builds only)
  Tick? _lastPredictedTicks;
  DateTime? _lastDispatchTime;

  /// Minimum delay between ticks (1 tick = 100ms).
  static const Duration _minDelay = Duration(milliseconds: 100);

  /// Whether the game loop is currently running.
  bool get isRunning => _isRunning;

  void _onStateChange(GlobalState state) {
    // Don't auto-start if suspended (app is backgrounded)
    if (_isSuspended) return;

    if (state.shouldTick) {
      if (_isRunning) {
        // Already running but state changed - reschedule immediately.
        // This handles the case where we're sleeping for 60m (township)
        // and the user starts a 1s action (woodcutting).
        // Calculate next event from current state.
        final builder = StateUpdateBuilder(state);
        final nextEvent = builder.calculateTicksUntilNextEvent();
        _scheduleNextTick(ticksUntilNextEvent: nextEvent);
      } else {
        start();
      }
    } else {
      pause();
    }
  }

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

  /// Start the game loop if not already running.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    // Calculate next event from current state.
    final builder = StateUpdateBuilder(_store.state);
    final nextEvent = builder.calculateTicksUntilNextEvent();
    _scheduleNextTick(ticksUntilNextEvent: nextEvent);
  }

  /// Pause the game loop.
  void pause() {
    if (!_isRunning) return;
    _isRunning = false;
    _nextEventTimer?.cancel();
    _nextEventTimer = null;
  }

  /// Stop and dispose the game loop.
  void dispose() {
    pause();
    _subscription.cancel();
  }

  /// Schedules the next tick based on predicted next event timing.
  void _scheduleNextTick({Tick? ticksUntilNextEvent}) {
    _nextEventTimer?.cancel();

    if (!_isRunning || !_store.state.shouldTick) {
      return;
    }

    // If no events scheduled, pause the loop. This shouldn't happen when
    // shouldTick is true, but handle it gracefully.
    if (ticksUntilNextEvent == null || ticksUntilNextEvent <= 0) {
      assert(
        false,
        'calculateTicksUntilNextEvent returned null/0 but shouldTick is true.',
      );
      pause();
      return;
    }

    // Calculate delay from ticks
    var delay = durationFromTicks(ticksUntilNextEvent);
    // Only enforce minimum to prevent spinning
    if (delay < _minDelay) {
      delay = _minDelay;
    }
    // No maximum - if township update is in 60m, sleep for 60m.
    // State changes (user starting an action) trigger _onStateChange
    // which calls start() to reschedule immediately.

    _nextEventTimer = Timer(delay, _onTimerFire);
  }

  void _onTimerFire() {
    if (!_isRunning || _isSuspended) return;

    final now = DateTime.timestamp();

    if (!_store.state.shouldTick) {
      pause();
      return;
    }

    // Validate prediction accuracy (debug builds only)
    assert(() {
      if (_lastPredictedTicks != null && _lastDispatchTime != null) {
        // Calculate actual ticks elapsed since last dispatch
        final elapsed = now.difference(_lastDispatchTime!);
        final actualTicks = ticksFromDuration(elapsed);
        final drift = (actualTicks - _lastPredictedTicks!).abs();
        // Allow 1 tick tolerance for timer imprecision
        if (drift > 1) {
          debugPrint(
            'GameLoop drift detected: '
            'predicted=$_lastPredictedTicks ticks, '
            'actual=$actualTicks ticks, drift=$drift ticks',
          );
        }
      }
      return true;
    }(), 'Drift validation should always pass');

    // Dispatch the action and get next event timing
    final action = UpdateActivityProgressAction(now: now);
    _store.dispatch(action);

    // Store prediction and time for next validation
    _lastPredictedTicks = action.ticksUntilNextEvent;
    _lastDispatchTime = now;

    // Schedule next tick based on returned timing
    _scheduleNextTick(ticksUntilNextEvent: action.ticksUntilNextEvent);
  }
}
