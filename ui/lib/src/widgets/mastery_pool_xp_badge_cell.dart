import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';

/// A small square widget displaying a mastery pool icon with a mastery
/// pool xp count badge.
///
/// Shows a mastery pool icon centered on a light-grey background with a
/// dark-grey border. The mastery pool xp amount is displayed in a pill-shaped
/// badge overlapping the bottom border.
class MasteryPoolXpBadgeCell extends StatelessWidget {
  const MasteryPoolXpBadgeCell({required this.masteryPoolXp, super.key});

  final int masteryPoolXp;

  @override
  Widget build(BuildContext context) {
    return CountBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      count: masteryPoolXp,
      child: const Center(
        child: CachedImage(
          assetPath: 'assets/media/main/mastery_pool.png',
          size: 28,
        ),
      ),
    );
  }
}
