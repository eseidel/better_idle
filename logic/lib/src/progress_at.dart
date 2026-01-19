import 'package:logic/src/activity/active_activity.dart';
import 'package:meta/meta.dart';

/// Represents progress at a specific point in time.
///
/// Used for estimating progress at a rate higher than the game tick based
/// on time elapsed since the last update.
@immutable
class ProgressAt {
  const ProgressAt({
    required this.lastUpdateTime,
    required this.progressTicks,
    required this.totalTicks,
    this.isAdvancing = true,
  });

  factory ProgressAt.zero(DateTime? lastUpdateTime) => ProgressAt(
    lastUpdateTime: lastUpdateTime ?? DateTime.timestamp(),
    progressTicks: 0,
    totalTicks: 1,
    isAdvancing: false,
  );

  /// The timestamp when the progress was last updated
  final DateTime lastUpdateTime;

  /// Current progress in ticks
  final int progressTicks;

  /// Total ticks needed for completion
  final int totalTicks;

  /// Whether the progress is currently advancing
  final bool isAdvancing;

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

    // If we're already complete or not advancing, don't advance further
    if (baseProgress >= 1 || !isAdvancing) return baseProgress;

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

/// Extension methods for converting ActiveActivity to ProgressAt.
extension ActiveActivityProgressAt on ActiveActivity {
  /// Converts this ActiveActivity to a ProgressAt for progress estimation.
  ProgressAt toProgressAt(DateTime lastUpdateTime) {
    return ProgressAt(
      lastUpdateTime: lastUpdateTime,
      progressTicks: progressTicks,
      totalTicks: totalTicks,
    );
  }
}
