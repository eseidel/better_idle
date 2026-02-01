import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that lets the player spend mastery pool XP to level up action
/// mastery levels.
class SpendMasteryDialog extends StatelessWidget {
  const SpendMasteryDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<GlobalState, GlobalState>(
      converter: (store) => store.state,
      builder: (context, state) {
        final actions = state.registries.actionsForSkill(skill);
        final skillState = state.skillState(skill);
        final maxPoolXp = maxMasteryPoolXpForSkill(state.registries, skill);

        return AlertDialog(
          title: Row(
            children: [
              const CachedImage(
                assetPath: 'assets/media/main/mastery_pool.png',
                size: 28,
              ),
              const SizedBox(width: 8),
              SkillImage(skill: skill, size: 28),
              const SizedBox(width: 8),
              Expanded(child: Text('Spend ${skill.name} Mastery')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pool summary
                Text(
                  'Pool: ${preciseNumberString(skillState.masteryPoolXp)}'
                  ' / ${preciseNumberString(maxPoolXp)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final action in actions)
                          _ActionMasteryRow(
                            skill: skill,
                            action: action,
                            state: state,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _ActionMasteryRow extends StatelessWidget {
  const _ActionMasteryRow({
    required this.skill,
    required this.action,
    required this.state,
  });

  final Skill skill;
  final SkillAction action;
  final GlobalState state;

  @override
  Widget build(BuildContext context) {
    final actionState = state.actionState(action.id);
    final cost = state.masteryLevelUpCost(action.id);
    final pool = state.skillState(skill).masteryPoolXp;
    final isMaxLevel = cost == null;
    final canAfford = !isMaxLevel && pool >= cost;
    final crossedCheckpoint = !isMaxLevel
        ? state.masteryPoolCheckpointCrossed(skill, cost)
        : null;

    // Green if affordable without crossing checkpoint, yellow if crossing,
    // red if insufficient.
    final Color buttonColor;
    if (isMaxLevel) {
      buttonColor = Style.textColorSecondary;
    } else if (!canAfford) {
      buttonColor = Style.errorColor;
    } else if (crossedCheckpoint != null) {
      buttonColor = Style.warningColor;
    } else {
      buttonColor = Style.successColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.name),
                MasteryProgressCell(masteryXp: actionState.masteryXp),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isMaxLevel)
            const Text('MAX', style: TextStyle(color: Style.textColorSecondary))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SpendButton(
                  skill: skill,
                  action: action,
                  buttonColor: buttonColor,
                  canAfford: canAfford,
                  crossedCheckpoint: crossedCheckpoint,
                ),
                Text(
                  '${preciseNumberString(cost)} XP',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: canAfford ? null : Style.textColorSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SpendButton extends StatelessWidget {
  const _SpendButton({
    required this.skill,
    required this.action,
    required this.buttonColor,
    required this.canAfford,
    required this.crossedCheckpoint,
  });

  final Skill skill;
  final SkillAction action;
  final Color buttonColor;
  final bool canAfford;
  final int? crossedCheckpoint;

  void _spend(BuildContext context) {
    if (crossedCheckpoint != null) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Warning'),
          content: Text(
            'This will drop your mastery pool below the '
            '$crossedCheckpoint% checkpoint. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Spend'),
            ),
          ],
        ),
      ).then((confirmed) {
        if ((confirmed ?? false) && context.mounted) {
          context.dispatch(
            SpendMasteryPoolAction(skill: skill, actionId: action.id),
          );
        }
      });
    } else {
      context.dispatch(
        SpendMasteryPoolAction(skill: skill, actionId: action.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.add_circle, color: buttonColor),
      onPressed: canAfford ? () => _spend(context) : null,
      tooltip: canAfford ? 'Level up mastery' : 'Insufficient pool XP',
      iconSize: 28,
    );
  }
}

/// A button that opens the spend mastery pool dialog for a skill.
class SpendMasteryButton extends StatelessWidget {
  const SpendMasteryButton({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => SpendMasteryDialog(skill: skill),
      ),
      icon: const CachedImage(
        assetPath: 'assets/media/main/mastery_pool.png',
        size: 20,
      ),
      label: const Text('Spend Mastery'),
    );
  }
}
