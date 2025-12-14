import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏆'),
          Expanded(
            child: Column(
              children: [
                LinearProgressIndicator(value: xpProgress.progress),
                const SizedBox(height: 8),
                if (nextLevelXpNeeded != null)
                  Text(
                    '${preciseNumberString(currentXp)} / ${preciseNumberString(nextLevelXpNeeded)} '
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
  const MasteryProgressCell({required this.masteryXp, super.key});
  final int masteryXp;

  @override
  Widget build(BuildContext context) {
    final progress = xpProgressForXp(masteryXp);
    return Row(
      children: [
        Text('🏆 ${progress.level}'),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              Text(
                '${preciseNumberString(masteryXp)} / '
                '${preciseNumberString(progress.nextLevelXp ?? 0)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: progress.progress),
            ],
          ),
        ),
      ],
    );
  }
}
