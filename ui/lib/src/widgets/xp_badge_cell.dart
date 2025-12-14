import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:flutter/material.dart';

/// A small square widget displaying "XP" with an xp count badge.
///
/// Shows "XP" text centered on a light-grey background with a dark-grey
/// border. The xp amount is displayed in a pill-shaped badge overlapping
/// the bottom border.
class XpBadgeCell extends StatelessWidget {
  const XpBadgeCell({required this.xp, super.key});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CountBadgeCell(
        backgroundColor: Colors.grey.shade200,
        borderColor: Colors.grey.shade600,
        count: xp,
        child: const Center(
          child: Text(
            'XP',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
