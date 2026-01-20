import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/duration_badge_cell.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/recycle_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class FiremakingPage extends StatefulWidget {
  const FiremakingPage({super.key});

  @override
  State<FiremakingPage> createState() => _FiremakingPageState();
}

class _FiremakingPageState extends State<FiremakingPage> {
  FiremakingAction? _selectedAction;

  @override
  Widget build(BuildContext context) {
    const skill = Skill.firemaking;
    final state = context.state;
    final registries = state.registries;
    final actions = registries.firemaking.actions;
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Sort actions by unlock level
    final sortedActions = List<FiremakingAction>.from(actions)
      ..sort(
        (FiremakingAction a, FiremakingAction b) =>
            a.unlockLevel.compareTo(b.unlockLevel),
      );

    // Get unlocked actions
    final unlockedActions = sortedActions
        .where((FiremakingAction a) => skillLevel >= a.unlockLevel)
        .toList();

    // Default to first unlocked action if none selected
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty
            ? unlockedActions.first
            : sortedActions.first);

    return GameScaffold(
      title: const Text('Firemaking'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SkillProgress(xp: skillState.xp),
            MasteryPoolProgress(xp: skillState.masteryPoolXp),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MasteryUnlocksButton(skill: skill),
                SkillMilestonesButton(skill: skill),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _FiremakingDisplay(
                action: selectedAction,
                skillLevel: skillLevel,
                actions: sortedActions,
                onSelectLog: () {
                  _showLogSelectionDialog(
                    context: context,
                    actions: sortedActions,
                    selectedAction: selectedAction,
                    skillLevel: skillLevel,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogSelectionDialog({
    required BuildContext context,
    required List<FiremakingAction> actions,
    required FiremakingAction selectedAction,
    required int skillLevel,
  }) async {
    final result = await showDialog<FiremakingAction>(
      context: context,
      builder: (dialogContext) => _LogSelectionDialog(
        actions: actions,
        selectedAction: selectedAction,
        skillLevel: skillLevel,
      ),
    );
    if (result != null && mounted) {
      // If we're currently burning a different log, stop that action
      final state = this.context.state;
      final currentActionId = state.currentActionId;
      if (currentActionId != null && currentActionId != result.id) {
        final currentAction = state.registries.actionById(currentActionId);
        if (currentAction is FiremakingAction) {
          // Stop the current firemaking action
          this.context.dispatch(StopCombatAction());
        }
      }
      setState(() {
        _selectedAction = result;
      });
    }
  }
}

class _FiremakingDisplay extends StatelessWidget {
  const _FiremakingDisplay({
    required this.action,
    required this.skillLevel,
    required this.actions,
    required this.onSelectLog,
  });

  final FiremakingAction action;
  final int skillLevel;
  final List<FiremakingAction> actions;
  final VoidCallback onSelectLog;

  bool get _isUnlocked => skillLevel >= action.unlockLevel;

  @override
  Widget build(BuildContext context) {
    if (!_isUnlocked) {
      return _buildLocked(context);
    }
    return _buildUnlocked(context);
  }

  Widget _buildLocked(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 48, color: Style.textColorSecondary),
          const SizedBox(height: 8),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Unlocked at '),
              const SkillImage(skill: Skill.firemaking, size: 16),
              Text(' Level ${action.unlockLevel}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final isActive = state.isActionActive(action);
    final canStart = state.canStartAction(action);

    // Get the log item for display
    final logItem = state.registries.items.byId(action.logId);
    final logCount = state.inventory.countOfItem(logItem);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? Style.activeColorLight
            : Style.containerBackgroundLight,
        border: Border.all(
          color: isActive ? Style.activeColor : Style.iconColorDefault,
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with select button
          _buildHeaderRow(context, logItem, logCount),
          const SizedBox(height: 12),

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          // Produces | You Have
          _buildProducesHaveRow(context, logItem, logCount),
          const SizedBox(height: 12),

          // Grants (centered)
          _buildGrantsRow(context),
          const SizedBox(height: 16),

          // Action button with duration
          _buildButtonRow(context, isActive, canStart),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Item logItem, int logCount) {
    return Row(
      children: [
        // Log icon with count badge
        CountBadgeCell(
          count: logCount > 0 ? logCount : null,
          inradius: 64,
          child: CachedImage(assetPath: logItem.media ?? '', size: 40),
        ),
        const SizedBox(width: 12),
        // Name and badges
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Burn',
                style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
              ),
              Text(
                logItem.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  RecycleChanceBadgeCell(chance: '0%'),
                  SizedBox(width: 8),
                  DoubleChanceBadgeCell(chance: '0%'),
                ],
              ),
            ],
          ),
        ),
        // Select Log button
        ElevatedButton(onPressed: onSelectLog, child: const Text('Select Log')),
      ],
    );
  }

  Widget _buildProducesHaveRow(
    BuildContext context,
    Item logItem,
    int logCount,
  ) {
    final state = context.state;
    final skillDrops = state.registries.drops.forSkill(Skill.firemaking);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Produces (skill drops with percentages)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Produces:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (skillDrops.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: skillDrops.whereType<Drop>().map((drop) {
                    final item = state.registries.items.byId(drop.itemId);
                    final percent = (drop.rate * 100).toStringAsFixed(0);
                    return _DropBadge(item: item, percent: '$percent%');
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right column: You Have (drop item counts)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You Have:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (skillDrops.isEmpty)
                const Text(
                  'N/A',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: skillDrops.whereType<Drop>().map((drop) {
                    final item = state.registries.items.byId(drop.itemId);
                    final count = state.inventory.countOfItem(item);
                    return ItemCountBadgeCell(item: item, count: count);
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrantsRow(BuildContext context) {
    return Column(
      children: [
        const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        XpBadgesRow(action: action),
      ],
    );
  }

  Widget _buildButtonRow(BuildContext context, bool isActive, bool canStart) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: canStart || isActive
              ? () {
                  context.dispatch(ToggleActionAction(action: action));
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? Style.activeColor : null,
          ),
          child: Text(isActive ? 'Stop' : 'Burn'),
        ),
        const SizedBox(width: 16),
        DurationBadgeCell(seconds: action.minDuration.inSeconds),
      ],
    );
  }
}

class _LogSelectionDialog extends StatelessWidget {
  const _LogSelectionDialog({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
  });

  final List<FiremakingAction> actions;
  final FiremakingAction selectedAction;
  final int skillLevel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Log to Burn'),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: actions.map((action) {
              return _LogCard(
                action: action,
                isSelected: action.id == selectedAction.id,
                isUnlocked: skillLevel >= action.unlockLevel,
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.action,
    required this.isSelected,
    required this.isUnlocked,
  });

  final FiremakingAction action;
  final bool isSelected;
  final bool isUnlocked;

  static const double _cardWidth = 380;

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return SizedBox(
        width: _cardWidth,
        child: Card(
          color: Style.cellBackgroundColorLocked,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.lock, color: Style.textColorSecondary),
                const SizedBox(width: 8),
                const Text(
                  'Unlocked at ',
                  style: TextStyle(color: Style.textColorSecondary),
                ),
                const SkillImage(skill: Skill.firemaking, size: 14),
                Text(
                  ' Level ${action.unlockLevel}',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = context.state;
    final logItem = state.registries.items.byId(action.logId);
    final actionState = state.actionState(action.id);
    final masteryProgress = xpProgressForXp(actionState.masteryXp);
    final perAction = xpPerAction(
      state,
      action,
      state.createActionModifierProvider(action),
    );
    final durationSeconds = action.minDuration.inSeconds;

    return SizedBox(
      width: _cardWidth,
      child: Card(
        color: isSelected ? Style.selectedColorLight : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Title + Select button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      action.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Style.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(action);
                    },
                    child: const Text('Select'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Main content row: Image with mastery + details
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Log image with mastery below
                  Column(
                    children: [
                      ItemImage(item: logItem, size: 64),
                      const SizedBox(height: 8),
                      // Mastery level with trophy
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${masteryProgress.level}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        '(${_formatPercent(masteryProgress.progress)})',
                        style: const TextStyle(
                          color: Style.textColorSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Details column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Duration badge + Input item badge
                        Row(
                          children: [
                            DurationBadgeCell(
                              seconds: durationSeconds,
                              inradius: TextBadgeCell.smallInradius,
                            ),
                            const SizedBox(width: 8),
                            ItemCountBadgeCell(
                              item: logItem,
                              count: 1,
                              inradius: TextBadgeCell.smallInradius,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Skill XP
                        Row(
                          children: [
                            const SkillImage(skill: Skill.firemaking, size: 14),
                            const SizedBox(width: 4),
                            Text('${perAction.xp} Skill XP'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Bonfire bonus info
                        Row(
                          children: [
                            const CachedImage(
                              assetPath:
                                  'assets/media/skills/firemaking/firemaking.png',
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text('+${action.bonfireXPBonus}% Bonfire XP'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatPercent(double progress) {
  return '${(progress * 100).toStringAsFixed(2)}%';
}

/// A badge showing an item with its drop percentage.
class _DropBadge extends StatelessWidget {
  const _DropBadge({required this.item, required this.percent});

  final Item item;
  final String percent;

  @override
  Widget build(BuildContext context) {
    const iconSize = TextBadgeCell.defaultInradius * 0.6;

    return TextBadgeCell(
      backgroundColor: Style.xpBadgeBackgroundColor,
      text: percent,
      child: Center(child: ItemImage(item: item, size: iconSize)),
    );
  }
}
