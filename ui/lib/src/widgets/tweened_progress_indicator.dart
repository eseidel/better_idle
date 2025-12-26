import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A progress indicator that smoothly tweens between updates.
///
/// This widget takes discrete progress updates (from the game's 10Hz tick rate)
/// and smoothly interpolates the progress bar to eliminate stuttering.
///
/// When [activeAction] is provided, the widget automatically advances the
/// progress based on elapsed time since the last update, making it appear as if
/// the progress is updating at 60fps even though the underlying data only
/// updates at 10Hz.
///
/// When [activeAction] is null, it displays a static empty progress bar.
class TweenedProgressIndicator extends StatefulWidget {
  const TweenedProgressIndicator({
    required this.lastUpdateTime,
    required this.activeAction,
    this.height = 8.0,
    this.borderRadius,
    this.backgroundColor,
    this.color,
    this.tickDuration = const Duration(milliseconds: 100),
    super.key,
  });

  /// The timestamp when the state was last updated
  final DateTime lastUpdateTime;

  /// The currently active action, or null if no action is running
  final ActiveAction? activeAction;

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

  /// Calculate the base progress (0.0 to 1.0) from the active action
  double _calculateBaseProgress() {
    final activeAction = widget.activeAction;
    if (activeAction == null) return 0;

    final totalTicks = activeAction.totalTicks;
    if (totalTicks <= 0) return 0;

    final progressTicks = activeAction.totalTicks - activeAction.remainingTicks;
    return (progressTicks / totalTicks).clamp(0, 1).toDouble();
  }

  /// Calculate the estimated current progress based on elapsed time
  double _calculateEstimatedProgress() {
    final activeAction = widget.activeAction;
    if (activeAction == null) return 0;

    final baseProgress = _calculateBaseProgress();

    // If we're already complete, don't advance further
    if (baseProgress >= 1) return 1;

    // Calculate how much time has elapsed since the last update
    final now = DateTime.now();
    final elapsed = now.difference(widget.lastUpdateTime);

    // Estimate how many ticks have passed since the last update
    final estimatedTicksPassed =
        elapsed.inMilliseconds / widget.tickDuration.inMilliseconds;

    // Calculate estimated progress
    final progressTicks = activeAction.totalTicks - activeAction.remainingTicks;
    final estimatedProgressTicks = progressTicks + estimatedTicksPassed;
    final estimatedProgress = (estimatedProgressTicks / activeAction.totalTicks)
        .clamp(0, 1)
        .toDouble();

    return estimatedProgress;
  }

  @override
  Widget build(BuildContext context) {
    // If no active action, show static empty progress
    if (widget.activeAction == null) {
      return ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
        child: SizedBox(
          height: widget.height,
          child: LinearProgressIndicator(
            value: 0,
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
