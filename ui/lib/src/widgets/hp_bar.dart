import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/style.dart';
import 'package:ui/src/widgets/tweened_progress_indicator.dart';

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

/// Displays the player's HP bar with text and optional autoEat indicator.
///
/// Shows: HP bar, "currentHp/maxHp [hp icon]", and when autoEat is active,
/// "[autoeat icon] thresholdHp" on the right.
class PlayerHpDisplay extends StatelessWidget {
  const PlayerHpDisplay({
    required this.currentHp,
    required this.maxHp,
    this.autoEatThresholdPercent,
    super.key,
  });

  final int currentHp;
  final int maxHp;

  /// AutoEat threshold percentage (0-100). If 0 or null, autoEat is not shown.
  final int? autoEatThresholdPercent;

  @override
  Widget build(BuildContext context) {
    final threshold = autoEatThresholdPercent;
    final hasAutoEat = threshold != null && threshold > 0;
    final thresholdHp = hasAutoEat ? (maxHp * threshold / 100).ceil() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HpBar(
          currentHp: currentHp,
          maxHp: maxHp,
          color: Style.playerHpBarColor,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('$currentHp/$maxHp'),
            const SizedBox(width: 4),
            const CachedImage(
              assetPath: 'assets/media/skills/hitpoints/hitpoints.png',
              size: 16,
            ),
            if (hasAutoEat) ...[
              const Spacer(),
              const CachedImage(
                assetPath: 'assets/media/shop/autoeat.png',
                size: 16,
              ),
              const SizedBox(width: 4),
              Text('$thresholdHp'),
            ],
          ],
        ),
      ],
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
    this.animate = true,
    this.height = 12,
    super.key,
  });

  final int? ticksRemaining;
  final int? totalTicks;
  final bool animate;

  /// The height of the bar. Defaults to 12.
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = totalTicks;
    final remaining = ticksRemaining;

    // Create ProgressAt for tweened animation
    final isActive = total != null && total > 0 && remaining != null;
    final progress = ProgressAt(
      lastUpdateTime: context.state.updatedAt,
      progressTicks: isActive ? total - remaining : 0,
      totalTicks: isActive ? total : 1,
      isAdvancing: animate && isActive,
    );

    return TweenedProgressIndicator(
      progress: progress,
      animate: isActive,
      height: height,
      backgroundColor: Style.progressBackgroundColor,
      color: Style.attackBarColor,
    );
  }
}
