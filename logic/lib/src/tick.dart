/// A tick is the smallest unit of time in the game (100ms).
typedef Tick = int;

/// Duration of a single tick.
const int msPerTick = 100;

/// Converts seconds to ticks, rounding to the nearest tick.
Tick secondsToTicks(double seconds) => (seconds * 1000 / msPerTick).round();

/// Converts milliseconds to ticks, rounding to the nearest tick.
Tick msToTicks(num ms) => (ms / msPerTick).round();

const Duration tickDuration = Duration(milliseconds: msPerTick);

/// Converts a Duration to ticks.
Tick ticksFromDuration(Duration duration) {
  return duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

/// Converts ticks to a Duration.
Duration durationFromTicks(Tick ticks) {
  return Duration(milliseconds: ticks * msPerTick);
}

/// Ticks required to regenerate 1 HP (10 seconds = 100 ticks).
final int ticksPer1Hp = ticksFromDuration(const Duration(seconds: 10));
