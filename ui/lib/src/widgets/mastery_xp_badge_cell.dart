import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';

/// A small square displaying a trophy emoji with a mastery xp count badge.
///
/// Shows a trophy emoji centered on a light-grey background with a dark-grey
/// border. The mastery xp amount is displayed in a pill-shaped badge
/// overlapping the bottom border.
class MasteryXpBadgeCell extends StatelessWidget {
  const MasteryXpBadgeCell({required this.masteryXp, super.key});

  final int masteryXp;

  @override
  Widget build(BuildContext context) {
    return CountBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      count: masteryXp,
      child: const Center(child: Text('🏆', style: TextStyle(fontSize: 18))),
    );
  }
}
