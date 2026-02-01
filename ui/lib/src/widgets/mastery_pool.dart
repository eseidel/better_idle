import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
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
    final progress = maxXp > 0 ? (currentXp / maxXp).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  '${preciseNumberString(currentXp)} / ${preciseNumberString(maxXp)} '
                  '(${percentToString(progress)})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
          if (state.claimableMasteryTokenCount(skill) > 0)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => _ClaimMasteryTokensDialog(skill: skill),
              ),
              child: const Text('Claim Tokens'),
            ),
        ],
      ),
    );
  }
}

class _ClaimMasteryTokensDialog extends StatelessWidget {
  const _ClaimMasteryTokensDialog({required this.skill});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final claimable = state.claimableMasteryTokenCount(skill);
    final xpPerToken = state.masteryTokenXpPerClaim(skill);
    final maxPoolXp = maxMasteryPoolXpForSkill(state.registries, skill);
    final currentPoolXp = state.skillState(skill).masteryPoolXp;

    return AlertDialog(
      title: const Text('Claim Mastery Tokens'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each token adds ${preciseNumberString(xpPerToken)} XP to the '
            '${skill.name} mastery pool.',
          ),
          const SizedBox(height: 8),
          Text(
            'Pool: ${preciseNumberString(currentPoolXp)} / '
            '${preciseNumberString(maxPoolXp)}',
          ),
          const SizedBox(height: 8),
          Text('Claimable tokens: $claimable'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: claimable > 0
              ? () {
                  context.dispatch(ClaimAllMasteryTokensAction(skill: skill));
                  Navigator.of(context).pop();
                }
              : null,
          child: Text('Claim All ($claimable)'),
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
    final progress = xpProgressForXp(masteryXp);
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
