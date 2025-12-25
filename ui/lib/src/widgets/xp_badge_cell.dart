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
  const XpBadgeCell({required this.xp, super.key});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return CountBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      count: xp,
      child: const Center(
        child: CachedImage(assetPath: 'assets/media/main/xp.png', size: 28),
      ),
    );
  }
}
