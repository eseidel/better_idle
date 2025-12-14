/// A tick is the smallest unit of time in the game (100ms).
typedef Tick = int;

/// Duration of a single tick.
const Duration tickDuration = Duration(milliseconds: 100);

/// Converts a Duration to ticks.
Tick ticksFromDuration(Duration duration) {
  return duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

/// Converts ticks to a Duration.
Duration durationFromTicks(Tick ticks) {
  return Duration(milliseconds: ticks * tickDuration.inMilliseconds);
}
