import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Returns the media path for an action, if available.
/// Different action subclasses store media in different ways.
String? _mediaForAction(SkillAction action) {
  if (action is WoodcuttingTree) return action.media;
  if (action is FishingAction) {
    final media = action.media;
    if (media.isNotEmpty) return media;
  }
  if (action is MiningAction) return action.media;
  if (action is ThievingAction) return action.media;
  if (action is AgilityObstacle) return 'assets/media/main/stamina.png';
  if (action is AstrologyAction) return action.media;
  if (action is AltMagicAction) return action.media;
  return null;
}

/// Returns the primary item ID for an action (output or input).
/// Used for looking up item images when the action has no direct media.
MelvorId? _primaryItemId(SkillAction action) {
  if (action is FishingAction) return action.productId;
  if (action is CookingAction) return action.productId;
  if (action is FiremakingAction) return action.logId;
  if (action is SummoningAction) return action.productId;
  if (action is SmithingAction) return action.productId;
  if (action is FletchingAction) return action.productId;
  if (action is CraftingAction) return action.productId;
  if (action is HerbloreAction) return action.productId;
  if (action is RunecraftingAction) return action.productId;
  if (action.outputs.isNotEmpty) return action.outputs.keys.first;
  if (action.inputs.isNotEmpty) return action.inputs.keys.first;
  return null;
}

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
        final actions = state.registries.actionsForSkill(widget.skill);
        final skillState = state.skillState(widget.skill);
        final maxPoolXp = maxMasteryPoolXpForSkill(
          state.registries,
          widget.skill,
        );

        return AlertDialog(
          title: Row(
            children: [
              const CachedImage(
                assetPath: 'assets/media/main/mastery_pool.png',
                size: 28,
              ),
              const SizedBox(width: 8),
              SkillImage(skill: widget.skill, size: 28),
              const SizedBox(width: 8),
              Expanded(child: Text('Spend ${widget.skill.name} Mastery')),
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
                const SizedBox(height: 12),
                // Increment selector
                _IncrementSelector(
                  selected: _selectedIncrement,
                  onChanged: (value) {
                    setState(() {
                      _selectedIncrement = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
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
    final progress = xpProgressForXp(masteryXp);
    final currentLevel = progress.level;

    // Calculate actual levels we can add (might be less than increment if near
    // max level 99)
    const maxMasteryLevel = 99;
    final levelsUntilMax = maxMasteryLevel - currentLevel;
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
      child: Row(
        children: [
          _ActionImage(action: action, state: state),
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
                    const SizedBox(width: 8),
                    if (!isMaxLevel)
                      Text(
                        '${preciseNumberString(xpToNextLevel)} XP to level '
                        '${currentLevel + 1}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Style.textColorSecondary,
                        ),
                      )
                    else
                      Text(
                        'MAX',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Style.textColorSecondary,
                        ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SpendButton(
                  skill: skill,
                  action: action,
                  levels: actualLevels,
                  buttonColor: buttonColor,
                  canAfford: canAfford,
                  crossedCheckpoint: crossedCheckpoint,
                ),
                Text(
                  '+$actualLevels (${preciseNumberString(totalCost!)} XP)',
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
    return IconButton(
      icon: Icon(Icons.add_circle, color: buttonColor),
      onPressed: canAfford ? () => _spend(context) : null,
      tooltip: canAfford
          ? 'Add $levels mastery level(s)'
          : 'Insufficient pool XP',
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

/// Displays an image for an action, using its media path if available.
class _ActionImage extends StatelessWidget {
  const _ActionImage({required this.action, required this.state});

  final SkillAction action;
  final GlobalState state;

  @override
  Widget build(BuildContext context) {
    // First try direct media path from action.
    final media = _mediaForAction(action);
    if (media != null && media.isNotEmpty) {
      return CachedImage(assetPath: media);
    }

    // Fall back to looking up the primary item's image.
    final itemId = _primaryItemId(action);
    if (itemId != null) {
      final item = state.registries.items.all
          .where((i) => i.id == itemId)
          .firstOrNull;
      if (item != null) {
        return ItemImage(item: item);
      }
    }

    // Last resort: show a generic icon.
    return const SizedBox(
      width: 32,
      height: 32,
      child: Icon(Icons.circle, size: 20, color: Style.iconColorDefault),
    );
  }
}
