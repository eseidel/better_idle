import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:flutter/material.dart';

/// A small square widget displaying a trophy-in-circle icon with a mastery
/// pool xp count badge.
///
/// Shows a trophy emoji inside a circular border (like a coin) centered on a
/// light-grey background with a dark-grey border. The mastery pool xp amount
/// is displayed in a pill-shaped badge overlapping the bottom border.
class MasteryPoolXpBadgeCell extends StatelessWidget {
  const MasteryPoolXpBadgeCell({required this.masteryPoolXp, super.key});

  final int masteryPoolXp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CountBadgeCell(
        backgroundColor: Colors.grey.shade200,
        borderColor: Colors.grey.shade600,
        count: masteryPoolXp,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber.shade700, width: 2),
              color: Colors.amber.shade100,
            ),
            child: const Center(
              child: Text('🏆', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
    );
  }
}
