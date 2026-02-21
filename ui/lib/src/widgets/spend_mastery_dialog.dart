import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/action_image.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that lets the player spend mastery pool XP to level up action
/// mastery levels.
class SpendMasteryDialog extends StatefulWidget {
  const SpendMasteryDialog({required this.skill, super.key});

  final Skill skill;

  @override
  State<SpendMasteryDialog> createState() => _SpendMasteryDialogState();
}

class _SpendMasteryDialogState extends State<SpendMasteryDialog> {
  int _selectedIncrement = 1;

  @override
  Widget build(BuildContext context) {
    return StoreConnector<GlobalState, GlobalState>(
      converter: (store) => store.state,
      builder: (context, state) {
        final actions = state.registries
            .actionsForSkill(widget.skill)
            .where((a) => state.actionState(a.id).masteryLevel < 99)
            .toList();
        final skillState = state.skillState(widget.skill);
        final maxPoolXp = maxMasteryPoolXpForSkill(
          state.registries,
          widget.skill,
        );

        return AlertDialog(
          constraints: const BoxConstraints(maxWidth: 600),
          title: const Text('Spend Mastery XP'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pool progress bar
                MasteryPoolBar(
                  currentXp: skillState.masteryPoolXp,
                  maxXp: maxPoolXp,
                ),
                const SizedBox(height: 12),
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.heldMasteryTokenCount(widget.skill) > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ElevatedButton(
                              onPressed:
                                  state.claimableMasteryTokenCount(
                                        widget.skill,
                                      ) >
                                      0
                                  ? () => context.dispatch(
                                      ClaimAllMasteryTokensAction(
                                        skill: widget.skill,
                                      ),
                                    )
                                  : null,
                              child: Text(
                                'Claim Tokens '
                                '(${state.heldMasteryTokenCount(widget.skill)})',
                              ),
                            ),
                          ),
                        _SpreadButton(skill: widget.skill, state: state),
                      ],
                    ),
                    _IncrementSelector(
                      selected: _selectedIncrement,
                      onChanged: (value) {
                        setState(() {
                          _selectedIncrement = value;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final action in actions)
                          _ActionMasteryRow(
                            skill: widget.skill,
                            action: action,
                            state: state,
                            increment: _selectedIncrement,
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

/// Selector for choosing level increment (+1, +5, +10).
class _IncrementSelector extends StatelessWidget {
  const _IncrementSelector({required this.selected, required this.onChanged});

  final int selected;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment<int>(value: 1, label: Text('+1')),
        ButtonSegment<int>(value: 5, label: Text('+5')),
        ButtonSegment<int>(value: 10, label: Text('+10')),
      ],
      selected: {selected},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        }
      },
    );
  }
}

class _ActionMasteryRow extends StatelessWidget {
  const _ActionMasteryRow({
    required this.skill,
    required this.action,
    required this.state,
    required this.increment,
  });

  final Skill skill;
  final SkillAction action;
  final GlobalState state;
  final int increment;

  @override
  Widget build(BuildContext context) {
    final actionState = state.actionState(action.id);
    final masteryXp = actionState.masteryXp;
    final progress = masteryProgressForXp(masteryXp);
    final currentLevel = actionState.masteryLevel;

    // Calculate actual levels we can add (might be less than increment if near
    // max level 99)
    const maxMasteryLevel = 99;
    final levelsUntilMax = (maxMasteryLevel - currentLevel).clamp(
      0,
      maxMasteryLevel,
    );
    final actualLevels = increment.clamp(0, levelsUntilMax);
    final isMaxLevel = currentLevel >= maxMasteryLevel;

    // Calculate total cost for all levels
    final totalCost = isMaxLevel
        ? null
        : state.masteryLevelUpCostForLevels(action.id, actualLevels);
    final pool = state.skillState(skill).masteryPoolXp;
    final canAfford = totalCost != null && pool >= totalCost;
    final crossedCheckpoint = totalCost != null
        ? state.masteryPoolCheckpointCrossed(skill, totalCost)
        : null;

    // Green if affordable without crossing checkpoint, yellow if crossing,
    // red if insufficient.
    final Color buttonColor;
    if (isMaxLevel || actualLevels == 0) {
      buttonColor = Style.textColorSecondary;
    } else if (!canAfford) {
      buttonColor = Style.errorColor;
    } else if (crossedCheckpoint != null) {
      buttonColor = Style.warningColor;
    } else {
      buttonColor = Style.successColor;
    }

    // Calculate XP needed to next level
    final xpToNextLevel = progress.nextLevelXp != null
        ? progress.nextLevelXp! - masteryXp
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: ActionImage(action: action)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  // Progress bar showing progress to next level only
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: isMaxLevel ? 1.0 : progress.progress,
                      backgroundColor: Style.progressBackgroundColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Level display and XP to next level
                  Row(
                    children: [
                      const CachedImage(
                        assetPath: 'assets/media/main/mastery_header.png',
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Level $currentLevel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      if (!isMaxLevel)
                        Text(
                          '${preciseNumberString(totalCost ?? xpToNextLevel)}'
                          ' XP for +$actualLevels'
                          ' level${actualLevels == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Style.textColorSecondary),
                        )
                      else
                        Text(
                          'MAX',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Style.textColorSecondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isMaxLevel || actualLevels == 0)
              const SizedBox(width: 80) // Placeholder for alignment
            else
              Center(
                child: _SpendButton(
                  skill: skill,
                  action: action,
                  levels: actualLevels,
                  buttonColor: buttonColor,
                  canAfford: canAfford,
                  crossedCheckpoint: crossedCheckpoint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpendButton extends StatelessWidget {
  const _SpendButton({
    required this.skill,
    required this.action,
    required this.levels,
    required this.buttonColor,
    required this.canAfford,
    required this.crossedCheckpoint,
  });

  final Skill skill;
  final SkillAction action;
  final int levels;
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
            SpendMasteryPoolAction(
              skill: skill,
              actionId: action.id,
              levels: levels,
            ),
          );
        }
      });
    } else {
      context.dispatch(
        SpendMasteryPoolAction(
          skill: skill,
          actionId: action.id,
          levels: levels,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: canAfford ? () => _spend(context) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: canAfford ? buttonColor : Style.textColorSecondary,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text('+$levels'),
    );
  }
}

class _SpreadButton extends StatelessWidget {
  const _SpreadButton({required this.skill, required this.state});
  final Skill skill;
  final GlobalState state;

  @override
  Widget build(BuildContext context) {
    // Check if any spread is possible at all (spend all mode).
    final anySpread = state.spreadMasteryPoolXp(skill);
    return ElevatedButton(
      onPressed: anySpread != null ? () => _showSpreadOptions(context) : null,
      child: const Text('Distribute'),
    );
  }

  void _showSpreadOptions(BuildContext context) {
    // Build preview for each checkpoint floor (from data) + "spend all".
    final bonuses = state.registries.masteryPoolBonuses.forSkill(skill.id);
    final checkpoints = [
      if (bonuses != null)
        for (final b in bonuses.bonuses.reversed) b.percent,
      0,
    ];
    final options = <({int floor, SpreadMasteryResult preview})>[];
    for (final floor in checkpoints) {
      final preview = state.spreadMasteryPoolXp(skill, floorPercent: floor);
      if (preview != null) {
        options.add((floor: floor, preview: preview));
      }
    }
    if (options.isEmpty) return;

    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribute Mastery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Spend pool XP on the lowest-level actions first. '
              'Raising total mastery increases XP gained on '
              'every action.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final option in options)
              ListTile(
                title: Text(
                  option.floor > 0 ? 'Spend to ${option.floor}%' : 'Spend all',
                ),
                subtitle: Text('+${option.preview.levelsAdded} levels'),
                onTap: () => Navigator.of(ctx).pop(option.floor),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((floor) {
      if (floor != null && context.mounted) {
        context.dispatch(
          SpreadMasteryPoolAction(skill: skill, floorPercent: floor),
        );
      }
    });
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
