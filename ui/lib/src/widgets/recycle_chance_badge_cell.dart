import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';

/// A small square widget displaying a recycle icon with a chance
/// percentage badge.
///
/// Shows a recycle icon centered on a light-grey background with a
/// dark-grey border. The chance percentage is displayed in a pill-shaped
/// badge overlapping the bottom border.
class RecycleChanceBadgeCell extends StatelessWidget {
  const RecycleChanceBadgeCell({required this.chance, super.key});

  final String chance;

  @override
  Widget build(BuildContext context) {
    return TextBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      text: chance,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.recycling, size: 24, color: Style.xpBadgeIconColor),
      ),
    );
  }
}
