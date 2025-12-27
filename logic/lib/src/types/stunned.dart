import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Duration of the stunned effect (3 seconds).
const Duration stunnedDuration = Duration(seconds: 3);

/// Ticks required for the stunned effect to wear off.
final Tick stunnedDurationTicks = ticksFromDuration(stunnedDuration);

/// Exception thrown when attempting to do something while stunned.
class StunnedException implements Exception {
  const StunnedException([this.message = 'Cannot do that while stunned']);

  final String message;

  @override
  String toString() => message;
}

/// Represents the player's stunned state.
/// When stunned, the player cannot start or stop activities.
@immutable
class StunnedState {
  const StunnedState({required this.ticksRemaining});

  factory StunnedState.fromJson(Map<String, dynamic> json) {
    return StunnedState(ticksRemaining: json['ticksRemaining'] as int? ?? 0);
  }

  const StunnedState.fresh() : ticksRemaining = 0;

  static StunnedState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return StunnedState.fromJson(json as Map<String, dynamic>);
  }

  /// Ticks remaining until the stunned effect wears off.
  /// 0 means not stunned.
  final Tick ticksRemaining;

  /// Whether the player is currently stunned.
  bool get isStunned => ticksRemaining > 0;

  /// Returns the remaining duration of the stun effect.
  Duration get remainingDuration =>
      Duration(milliseconds: ticksRemaining * tickDuration.inMilliseconds);

  /// Creates a new stunned state with the full stun duration.
  StunnedState stun() => StunnedState(ticksRemaining: stunnedDurationTicks);

  /// Applies ticks to reduce the remaining stun duration.
  /// Returns a new state with the reduced duration.
  StunnedState applyTicks(Tick ticks) {
    if (!isStunned) return this;
    final newRemaining = (ticksRemaining - ticks).clamp(0, ticksRemaining);
    return StunnedState(ticksRemaining: newRemaining);
  }

  StunnedState copyWith({Tick? ticksRemaining}) {
    return StunnedState(ticksRemaining: ticksRemaining ?? this.ticksRemaining);
  }

  Map<String, dynamic> toJson() {
    return {'ticksRemaining': ticksRemaining};
  }
}
