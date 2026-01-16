import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_pool_xp_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_xp_badge_cell.dart';
import 'package:better_idle/src/widgets/xp_badge_cell.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A row of XP badge cells showing skill XP, mastery XP, and mastery pool XP.
///
/// Computes XP values from the current state and action.
class XpBadgesRow extends StatelessWidget {
  const XpBadgesRow({
    required this.action,
    this.inradius = TextBadgeCell.defaultInradius,
    this.trailing,
    super.key,
  });

  final SkillAction action;

  /// The size of each badge cell (width and height). Defaults to 48.
  final double inradius;

  /// Optional widget to append after the mastery pool XP badge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final perAction = xpPerAction(
      context.state,
      action,
      context.state.createModifierProvider(currentActionId: action.id),
    );
    final spacing = inradius * 8 / TextBadgeCell.defaultInradius;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        XpBadgeCell(xp: perAction.xp, inradius: inradius),
        SizedBox(width: spacing),
        MasteryXpBadgeCell(masteryXp: perAction.masteryXp, inradius: inradius),
        SizedBox(width: spacing),
        MasteryPoolXpBadgeCell(
          masteryPoolXp: perAction.masteryPoolXp,
          inradius: inradius,
        ),
        if (trailing != null) ...[SizedBox(width: spacing), trailing!],
      ],
    );
  }
}
