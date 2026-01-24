import 'package:flutter/material.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/style.dart';

/// A small square widget displaying a preservation icon with a chance
/// percentage badge.
///
/// Shows a preservation icon centered on a light-grey background with a
/// dark-grey border. The chance percentage is displayed in a pill-shaped
/// badge overlapping the bottom border.
class RecycleChanceBadgeCell extends StatelessWidget {
  const RecycleChanceBadgeCell({required this.chance, super.key});

  final String chance;

  @override
  Widget build(BuildContext context) {
    // Icon size is roughly 60% of the inradius, matching item badges.
    const iconSize = TextBadgeCell.defaultInradius * 0.6;

    return TextBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      text: chance,
      child: const Center(
        child: CachedImage(
          assetPath: 'assets/media/main/preservation.png',
          size: iconSize,
        ),
      ),
    );
  }
}
