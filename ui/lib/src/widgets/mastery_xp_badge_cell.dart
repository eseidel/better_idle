import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';

/// A small square displaying a mastery icon with a mastery xp count badge.
///
/// Shows a mastery icon centered on a light-grey background with a dark-grey
/// border. The mastery xp amount is displayed in a pill-shaped badge
/// overlapping the bottom border.
class MasteryXpBadgeCell extends StatelessWidget {
  const MasteryXpBadgeCell({
    required this.masteryXp,
    this.inradius = TextBadgeCell.defaultInradius,
    super.key,
  });

  final int masteryXp;

  /// The size of the cell (width and height). Defaults to 48.
  final double inradius;

  @override
  Widget build(BuildContext context) {
    final iconSize = inradius * 28 / TextBadgeCell.defaultInradius;
    return CountBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      count: masteryXp,
      inradius: inradius,
      child: Center(
        child: CachedImage(
          assetPath: 'assets/media/main/mastery_header.png',
          size: iconSize,
        ),
      ),
    );
  }
}
