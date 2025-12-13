import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class SkillProgress extends StatelessWidget {
  const SkillProgress({required this.xp, super.key});
  final int xp;
  @override
  Widget build(BuildContext context) {
    final xpProgress = xpProgressForXp(xp);
    final currentXp = xp - xpProgress.lastLevelXp;
    final nextLevelXpNeeded = xpProgress.nextLevelXp != null
        ? xpProgress.nextLevelXp! - xpProgress.lastLevelXp
        : null;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(value: xpProgress.progress),
          const SizedBox(height: 8),
          if (nextLevelXpNeeded != null)
            Row(
              children: [
                Text('Skill Level', style: labelStyle),
                const SizedBox(width: 8),
                Text('${xpProgress.level} / $maxLevel', style: valueStyle),
                const SizedBox(width: 8),
                Text('Skill XP', style: labelStyle),
                const SizedBox(width: 8),
                Text(
                  '${preciseNumberString(currentXp)} / ${preciseNumberString(nextLevelXpNeeded)}',
                  style: valueStyle,
                ),
              ],
            )
          else
            Text(
              'Level ${xpProgress.level} (Max)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
