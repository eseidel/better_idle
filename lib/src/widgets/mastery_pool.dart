import 'package:better_idle/src/data/xp.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MasteryPoolProgress extends StatelessWidget {
  const MasteryPoolProgress({required this.xp, super.key});
  final int xp;
  @override
  Widget build(BuildContext context) {
    final xpProgress = xpProgressForXp(xp);
    final currentXp = xp - xpProgress.lastLevelXp;
    final nextLevelXpNeeded = xpProgress.nextLevelXp != null
        ? xpProgress.nextLevelXp! - xpProgress.lastLevelXp
        : null;
    final numberFormat = NumberFormat.decimalPattern();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🏆'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                LinearProgressIndicator(value: xpProgress.progress),
                const SizedBox(height: 8),
                if (nextLevelXpNeeded != null)
                  Text(
                    '${numberFormat.format(currentXp)} / ${numberFormat.format(nextLevelXpNeeded)} '
                    '(${(xpProgress.progress * 100).toStringAsFixed(1)}%) XP',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  Text(
                    'Level ${xpProgress.level} (Max)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MasteryProgressCell extends StatelessWidget {
  const MasteryProgressCell({super.key, required this.masteryXp});
  final int masteryXp;

  @override
  Widget build(BuildContext context) {
    final progress = xpProgressForXp(masteryXp);
    return Row(
      children: [
        Text('🏆 ${progress.level}'),
        SizedBox(width: 8),
        Column(
          children: [
            Text('$masteryXp / ${progress.nextLevelXp}'),
            // LinearProgressIndicator(value: progress.progress),
          ],
        ),
      ],
    );
  }
}
