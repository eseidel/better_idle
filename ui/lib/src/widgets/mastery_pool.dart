import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/mastery_pool_checkpoints_dialog.dart';
import 'package:ui/src/widgets/spend_mastery_dialog.dart';

/// Shows progress toward filling the mastery pool for a skill.
///
/// The mastery pool fills as you gain mastery XP on any action within the
/// skill. Progress is shown as a percentage of the total pool capacity.
class MasteryPoolProgress extends StatelessWidget {
  const MasteryPoolProgress({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillState = state.skillState(skill);
    final currentXp = skillState.masteryPoolXp;
    final maxXp = maxMasteryPoolXpForSkill(state.registries, skill);
    final buttons = [
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => MasteryPoolCheckpointsDialog(skill: skill),
        ),
        child: const Text('View Checkpoints'),
      ),
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => SpendMasteryDialog(skill: skill),
        ),
        child: const Text('Spend XP'),
      ),
    ];

    final bar = MasteryPoolBar(currentXp: currentXp, maxXp: maxXp);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 500) {
            return Row(
              children: [
                Expanded(child: bar),
                const SizedBox(width: 8),
                ...buttons,
              ],
            );
          }
          return Column(
            children: [
              bar,
              Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
            ],
          );
        },
      ),
    );
  }
}

class MasteryPoolBar extends StatelessWidget {
  const MasteryPoolBar({
    required this.currentXp,
    required this.maxXp,
    super.key,
  });

  final int currentXp;
  final int maxXp;

  @override
  Widget build(BuildContext context) {
    final progress = maxXp > 0 ? (currentXp / maxXp).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        const CachedImage(
          assetPath: 'assets/media/main/mastery_pool.png',
          size: 24,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress),
              ),
              const SizedBox(height: 4),
              Text(
                '${preciseNumberString(currentXp)}'
                ' / ${preciseNumberString(maxXp)}'
                ' (${percentToString(progress)})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MasteryProgressCell extends StatelessWidget {
  const MasteryProgressCell({required this.masteryXp, super.key});
  final int masteryXp;

  @override
  Widget build(BuildContext context) {
    final progress = masteryProgressForXp(masteryXp);
    return Row(
      children: [
        const CachedImage(
          assetPath: 'assets/media/main/mastery_header.png',
          size: 16,
        ),
        const SizedBox(width: 4),
        Text('${progress.level}'),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress.progress),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
