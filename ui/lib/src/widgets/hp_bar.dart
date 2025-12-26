import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/tweened_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A horizontal progress bar for displaying HP (health points).
///
/// Used by Combat and Thieving screens to display player/monster health.
class HpBar extends StatelessWidget {
  const HpBar({
    required this.currentHp,
    required this.maxHp,
    this.color,
    this.height = 20,
    super.key,
  });

  final int currentHp;
  final int maxHp;

  /// The color of the filled portion. Defaults to player HP bar color.
  final Color? color;

  /// The height of the bar. Defaults to 20.
  final double height;

  @override
  Widget build(BuildContext context) {
    final progress = maxHp > 0 ? (currentHp / maxHp).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Style.progressBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: color ?? Style.playerHpBarColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// A horizontal progress bar for displaying attack cooldown.
///
/// Used by Combat screen to show attack charging progress.
class AttackBar extends StatelessWidget {
  const AttackBar({
    required this.ticksRemaining,
    required this.totalTicks,
    this.height = 12,
    super.key,
  });

  final int? ticksRemaining;
  final int? totalTicks;

  /// The height of the bar. Defaults to 12.
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = totalTicks;
    final remaining = ticksRemaining;

    // Create ProgressAt for tweened animation
    final progress = (total != null && total > 0 && remaining != null)
        ? progressAtFromTicks(
            lastUpdateTime: context.state.updatedAt,
            progressTicks: total - remaining,
            totalTicks: total,
          )
        : null;

    return TweenedProgressIndicator(
      progress: progress,
      height: height,
      backgroundColor: Style.progressBackgroundColor,
      color: Style.attackBarColor,
    );
  }
}
