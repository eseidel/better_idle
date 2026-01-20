import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A progress indicator that smoothly tweens between updates.
///
/// This widget takes discrete progress updates (from the game's 10Hz tick rate)
/// and smoothly interpolates the progress bar to eliminate stuttering.
///
/// When [animate] is true, the widget automatically advances the
/// progress based on elapsed time since the last update, making it appear as if
/// the progress is updating at 60fps even though the underlying data only
/// updates at 10Hz.
///
/// When [animate] is false, it displays a static empty progress bar.
///
/// When [countdown] is true, the progress is inverted to show remaining time
/// (bar starts full and drains to empty).
class TweenedProgressIndicator extends StatefulWidget {
  const TweenedProgressIndicator({
    required this.progress,
    required this.animate,
    this.countdown = false,
    this.height = 8.0,
    this.borderRadius,
    this.backgroundColor,
    this.color,
    this.tickDuration = const Duration(milliseconds: 100),
    super.key,
  });

  /// The current progress data
  final ProgressAt progress;

  /// Whether to animate the progress bar
  final bool animate;

  /// Whether to show countdown mode (bar drains from full to empty)
  final bool countdown;

  /// Height of the progress bar
  final double height;

  /// Border radius for the progress bar
  final BorderRadius? borderRadius;

  /// Background color of the progress bar
  final Color? backgroundColor;

  /// Foreground color of the progress bar
  final Color? color;

  /// Duration of one tick (default: 100ms)
  final Duration tickDuration;

  @override
  State<TweenedProgressIndicator> createState() =>
      _TweenedProgressIndicatorState();
}

class _TweenedProgressIndicatorState extends State<TweenedProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps update rate
    );

    // Start the animation loop
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Calculate the estimated current progress based on elapsed time
  double _calculateEstimatedProgress() {
    if (!widget.animate) return widget.countdown ? 1.0 : 0.0;

    var progress = widget.progress.estimateProgressAt(
      DateTime.timestamp(),
      tickDuration: widget.tickDuration,
    );

    // In countdown mode, invert the progress (remaining = 1 - consumed)
    if (widget.countdown) {
      progress = 1.0 - progress;
    }

    return progress.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // If not animating OR the progress itself says it's not advancing, show
    // static progress at the CURRENT estimated position (or base progress).
    // Note: We still use AnimatedBuilder if it's "animating" in the widget
    // sense, but the estimation will be frozen if progress.  In that case,
    // isAdvancing is false.

    if (!widget.animate) {
      var progress = widget.progress.progress;
      if (widget.countdown) {
        progress = 1.0 - progress;
      }
      return ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
        child: SizedBox(
          height: widget.height,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: widget.backgroundColor,
            color: widget.color,
          ),
        ),
      );
    }

    // Otherwise, show animated progress
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Simply show the estimated current progress
        // No need for additional interpolation - the estimation itself
        // provides smooth advancement
        final progress = _calculateEstimatedProgress();

        return ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
          child: SizedBox(
            height: widget.height,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: widget.backgroundColor,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}
