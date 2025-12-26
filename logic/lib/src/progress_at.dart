import 'package:logic/src/state.dart';

/// Represents progress at a specific point in time.
///
/// Used for estimating progress at a rate higher than the game tick based
/// on time elapsed since the last update.
class ProgressAt {
  const ProgressAt({
    required this.lastUpdateTime,
    required this.progressTicks,
    required this.totalTicks,
  });

  /// The timestamp when the progress was last updated
  final DateTime lastUpdateTime;

  /// Current progress in ticks
  final int progressTicks;

  /// Total ticks needed for completion
  final int totalTicks;

  /// Calculate the base progress (0.0 to 1.0) from the tick values
  double get progress {
    if (totalTicks <= 0) return 0;
    return (progressTicks / totalTicks).clamp(0, 1).toDouble();
  }

  /// Estimate the current progress at a given time.
  ///
  /// Extrapolates progress based on elapsed time since [lastUpdateTime],
  /// assuming steady progress.
  double estimateProgressAt(
    DateTime now, {
    Duration tickDuration = const Duration(milliseconds: 100),
  }) {
    final baseProgress = progress;

    // If we're already complete, don't advance further
    if (baseProgress >= 1) return 1;

    // Calculate how much time has elapsed since the last update
    final elapsed = now.difference(lastUpdateTime);

    // Estimate how many ticks have passed since the last update
    final estimatedTicksPassed =
        elapsed.inMilliseconds / tickDuration.inMilliseconds;

    // Calculate estimated progress
    final estimatedProgressTicks = progressTicks + estimatedTicksPassed;
    final estimatedProgress = (estimatedProgressTicks / totalTicks)
        .clamp(0, 1)
        .toDouble();

    return estimatedProgress;
  }
}

/// Extension methods for converting ActiveAction to ProgressAt.
extension ActiveActionProgressAt on ActiveAction {
  /// Converts this ActiveAction to a ProgressAt for progress estimation.
  ProgressAt toProgressAt(DateTime lastUpdateTime) {
    return ProgressAt(
      lastUpdateTime: lastUpdateTime,
      progressTicks: totalTicks - remainingTicks,
      totalTicks: totalTicks,
    );
  }
}
