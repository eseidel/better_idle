import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool_xp_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_xp_badge_cell.dart';
import 'package:better_idle/src/widgets/xp_badge_cell.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A row of XP badge cells showing skill XP, mastery XP, and mastery pool XP.
///
/// Computes XP values from the current state and action.
class XpBadgesRow extends StatelessWidget {
  const XpBadgesRow({required this.action, super.key});

  final SkillAction action;

  @override
  Widget build(BuildContext context) {
    final perAction = xpPerAction(registries.actions, context.state, action);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        XpBadgeCell(xp: perAction.xp),
        const SizedBox(width: 8),
        MasteryXpBadgeCell(masteryXp: perAction.masteryXp),
        const SizedBox(width: 8),
        MasteryPoolXpBadgeCell(masteryPoolXp: perAction.masteryPoolXp),
      ],
    );
  }
}
