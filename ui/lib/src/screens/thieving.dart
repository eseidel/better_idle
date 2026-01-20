import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/hp_bar.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/tweened_progress_indicator.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class ThievingPage extends StatefulWidget {
  const ThievingPage({super.key});

  @override
  State<ThievingPage> createState() => _ThievingPageState();
}

class _ThievingPageState extends State<ThievingPage> {
  ThievingAction? _selectedAction;
  final Set<String> _collapsedAreas = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.thieving;
    final skillState = context.state.skillState(skill);
    final playerHp = context.state.playerHp;
    final maxPlayerHp = context.state.maxPlayerHp;
    final registries = context.state.registries;

    // Get all thieving actions from the registry
    final thievingActions = registries.thieving.actions;

    // Default to first action if none selected
    final selectedAction = _selectedAction ?? thievingActions.first;

    // Group actions by area (each action already stores its area reference)
    final actionsByArea = <ThievingArea, List<ThievingAction>>{};
    for (final action in thievingActions) {
      actionsByArea.putIfAbsent(action.area, () => []).add(action);
    }

    return GameScaffold(
      title: const Text('Thieving'),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MasteryUnlocksButton(skill: skill),
              SkillMilestonesButton(skill: skill),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HpBar(currentHp: playerHp, maxHp: maxPlayerHp),
                const SizedBox(height: 4),
                Text('HP: $playerHp / $maxPlayerHp'),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SelectedActionDisplay(
                    action: selectedAction,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _ActionList(
                    actionsByArea: actionsByArea,
                    selectedAction: selectedAction,
                    collapsedAreas: _collapsedAreas,
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
                      });
                    },
                    onToggleArea: (areaName) {
                      setState(() {
                        if (_collapsedAreas.contains(areaName)) {
                          _collapsedAreas.remove(areaName);
                        } else {
                          _collapsedAreas.add(areaName);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedActionDisplay extends StatelessWidget {
  const _SelectedActionDisplay({required this.action, required this.onStart});

  final ThievingAction action;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final isActive = state.isActionActive(action);
    final canStart = state.canStartAction(action);
    final isStunned = state.isStunned;
    final canToggle = (canStart || isActive) && !isStunned;

    // Calculate stealth and success chance
    final thievingLevel = levelForXp(state.skillState(Skill.thieving).xp);
    final masteryLevel = levelForXp(actionState.masteryXp);
    final stealth = calculateStealth(thievingLevel, masteryLevel);
    final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
      0.0,
      1.0,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? Style.activeColorLight
            : isStunned
            ? Style.errorColorLight
            : Style.containerBackgroundLight,
        border: Border.all(
          color: isActive
              ? Style.activeColor
              : isStunned
              ? Style.errorColor
              : Style.iconColorDefault,
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isStunned) ...[
            Text(
              'Stunned',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Style.stunnedTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
          ],
          // Header: NPC Image + Pickpocket + NPC Name
          if (action.media != null) ...[
            Center(child: CachedImage(assetPath: action.media, size: 64)),
            const SizedBox(height: 8),
          ],
          const Text(
            'Pickpocket',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
          ),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          XpBadgesRow(action: action),
          const SizedBox(height: 16),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text(
                    'Success',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  Text(
                    percentToString(successChance),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'Max Gold',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  Text(
                    '${action.maxGold}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'Stealth',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  Text(
                    '$stealth',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          _ThievingProgressBar(action: action),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: canToggle ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : 'Pickpocket'),
          ),
        ],
      ),
    );
  }
}

class _ThievingProgressBar extends StatelessWidget {
  const _ThievingProgressBar({required this.action});

  final ThievingAction action;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isActive = state.isActionActive(action);
    final isStunned = state.isStunned;

    // Calculate progress and styling
    ProgressAt progress;
    bool animate;
    Color barColor;
    String label;

    if (isStunned) {
      // Show stun countdown progress
      final stunTicksRemaining = state.stunned.ticksRemaining;
      progress = ProgressAt(
        lastUpdateTime: state.updatedAt,
        progressTicks: stunnedDurationTicks - stunTicksRemaining,
        totalTicks: stunnedDurationTicks,
      );
      animate = true;
      barColor = Style.progressForegroundColorError;
      label = 'Stunned';
    } else if (isActive) {
      // Show action progress
      final progressTicks = state.activeProgress(action);
      final totalTicks = ticksFromDuration(thievingDuration);
      progress = ProgressAt(
        lastUpdateTime: state.updatedAt,
        progressTicks: progressTicks,
        totalTicks: totalTicks,
      );
      animate = true;
      barColor = Style.progressForegroundColorWarning;
      label = 'Pickpocketing...';
    } else {
      // Idle state
      progress = ProgressAt.zero(state.updatedAt);
      animate = false;
      barColor = Style.iconColorDefault;
      label = 'Idle';
    }

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Stack(
            children: [
              TweenedProgressIndicator(
                progress: progress,
                animate: animate,
                height: 24,
                backgroundColor: Style.progressBackgroundColor,
                color: barColor,
              ),
              Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: progress.progress > 0.5
                        ? Style.textColorPrimary
                        : Style.progressTextDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actionsByArea,
    required this.selectedAction,
    required this.collapsedAreas,
    required this.onSelect,
    required this.onToggleArea,
  });

  final Map<ThievingArea, List<ThievingAction>> actionsByArea;
  final ThievingAction selectedAction;
  final Set<String> collapsedAreas;
  final void Function(ThievingAction) onSelect;
  final void Function(String) onToggleArea;

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(Skill.thieving);
    final skillLevel = levelForXp(skillState.xp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'NPCs',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actionsByArea.entries.map((entry) {
          final area = entry.key;
          final actions = entry.value;
          final isCollapsed = collapsedAreas.contains(area.name);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Area header with collapse toggle
              InkWell(
                onTap: () => onToggleArea(area.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Style.categoryHeaderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: 24,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        area.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions list (if not collapsed)
              if (!isCollapsed)
                ...actions.map((action) {
                  final isSelected = action.name == selectedAction.name;
                  final isUnlocked = skillLevel >= action.unlockLevel;

                  if (!isUnlocked) {
                    return Card(
                      margin: const EdgeInsets.only(
                        left: 16,
                        top: 4,
                        bottom: 4,
                      ),
                      color: Style.cellBackgroundColorLocked,
                      child: ListTile(
                        leading: const Icon(
                          Icons.lock,
                          color: Style.textColorSecondary,
                        ),
                        title: Row(
                          children: [
                            const Text(
                              'Unlocked at ',
                              style: TextStyle(color: Style.textColorSecondary),
                            ),
                            const SkillImage(skill: Skill.thieving, size: 14),
                            Text(
                              ' Level ${action.unlockLevel}',
                              style: const TextStyle(
                                color: Style.textColorSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Calculate success chance for this action
                  final state = context.state;
                  final actionState = state.actionState(action.id);
                  final thievingLevel = levelForXp(
                    state.skillState(Skill.thieving).xp,
                  );
                  final masteryLevel = levelForXp(actionState.masteryXp);
                  final stealth = calculateStealth(thievingLevel, masteryLevel);
                  final successChance = thievingSuccessChance(
                    stealth,
                    action.perception,
                  );

                  return Card(
                    margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    color: isSelected ? Style.selectedColorLight : null,
                    child: ListTile(
                      leading: action.media != null
                          ? CachedImage(assetPath: action.media)
                          : null,
                      title: Text(action.name),
                      subtitle: Text(
                        'Perception ${action.perception} • '
                        '${percentToString(successChance)} Success • '
                        'Max Hit ${action.maxHit}',
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Style.selectedColor,
                            )
                          : null,
                      onTap: () => onSelect(action),
                    ),
                  );
                }),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }
}
