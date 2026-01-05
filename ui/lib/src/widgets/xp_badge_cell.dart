import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';

/// A small square widget displaying an XP icon with an xp count badge.
///
/// Shows an XP icon centered on a light-grey background with a dark-grey
/// border. The xp amount is displayed in a pill-shaped badge overlapping
/// the bottom border.
class XpBadgeCell extends StatelessWidget {
  const XpBadgeCell({
    required this.xp,
    this.inradius = TextBadgeCell.defaultInradius,
    super.key,
  });

  final int xp;

  /// The size of the cell (width and height). Defaults to 48.
  final double inradius;

  @override
  Widget build(BuildContext context) {
    final iconSize = inradius * 28 / TextBadgeCell.defaultInradius;
    return CountBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      count: xp,
      inradius: inradius,
      child: Center(
        child: CachedImage(
          assetPath: 'assets/media/main/xp.png',
          size: iconSize,
        ),
      ),
    );
  }
}
