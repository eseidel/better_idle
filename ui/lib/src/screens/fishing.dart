import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/skill_action_display.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class FishingPage extends StatefulWidget {
  const FishingPage({super.key});

  @override
  State<FishingPage> createState() => _FishingPageState();
}

class _FishingPageState extends State<FishingPage> {
  FishingAction? _selectedAction;
  final Set<String> _collapsedAreas = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.fishing;
    final skillState = context.state.skillState(skill);
    final skillLevel = levelForXp(skillState.xp);
    final registries = context.state.registries;

    // Get all fishing actions from registries.
    final fishingActions = registries.fishing.actions;

    // Get all fishing areas from registries.
    final fishingAreas = registries.fishingAreas;

    // Default to first unlocked action if none selected.
    final unlockedActions = fishingActions
        .where((FishingAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    // Group actions by area.
    final actionsByArea = <FishingArea, List<FishingAction>>{};
    for (final area in fishingAreas) {
      final actionsInArea = <FishingAction>[];
      for (final fishId in area.fishIDs) {
        final action = fishingActions.firstWhereOrNull(
          (a) => a.id.localId == fishId,
        );
        if (action != null) {
          actionsInArea.add(action);
        }
      }
      if (actionsInArea.isNotEmpty) {
        actionsByArea[area] = actionsInArea;
      }
    }

    return GameScaffold(
      title: const Text('Fishing'),
      actions: const [SkillOverflowMenu(skill: skill)],
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (selectedAction != null)
                    SkillActionDisplay(
                      action: selectedAction,
                      skill: skill,
                      skillLevel: skillLevel,
                      headerText: 'Fishing',
                      buttonText: 'Fish',
                      showInputsOutputs: false,
                      durationBuilder: (action) {
                        final fishingAction = action as FishingAction;
                        final min = _formatDuration(fishingAction.minDuration);
                        final max = _formatDuration(fishingAction.maxDuration);
                        final durationText = fishingAction.isFixedDuration
                            ? min
                            : '$min - $max';
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, size: 16),
                            const SizedBox(width: 4),
                            Text(durationText),
                          ],
                        );
                      },
                      onStart: () {
                        context.dispatch(
                          ToggleActionAction(action: selectedAction),
                        );
                      },
                    )
                  else
                    _NoUnlockedActionsDisplay(skillLevel: skillLevel),
                  const SizedBox(height: 24),
                  _ActionList(
                    actionsByArea: actionsByArea,
                    selectedAction: selectedAction,
                    skillLevel: skillLevel,
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

String _formatDuration(Duration d) {
  final seconds = d.inMilliseconds / 1000;
  // Round to at most 2 decimal places.
  final roundedSeconds = (seconds * 100).round() / 100;
  // Don't show the decimal point if it's a whole number.
  if (roundedSeconds % 1 == 0) {
    return '${roundedSeconds.toInt()}s';
  }
  return '${roundedSeconds}s';
}

class _NoUnlockedActionsDisplay extends StatelessWidget {
  const _NoUnlockedActionsDisplay({required this.skillLevel});

  final int skillLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock, size: 48, color: Style.textColorSecondary),
          const SizedBox(height: 8),
          const Text('No fishing actions unlocked yet'),
          Text('Current level: $skillLevel'),
        ],
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actionsByArea,
    required this.selectedAction,
    required this.skillLevel,
    required this.collapsedAreas,
    required this.onSelect,
    required this.onToggleArea,
  });

  final Map<FishingArea, List<FishingAction>> actionsByArea;
  final FishingAction? selectedAction;
  final int skillLevel;
  final Set<String> collapsedAreas;
  final void Function(FishingAction) onSelect;
  final void Function(String) onToggleArea;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fishing Spots',
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
                      Expanded(
                        child: Text(
                          area.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _AreaChances(area: area),
                    ],
                  ),
                ),
              ),
              // Actions list (if not collapsed)
              if (!isCollapsed)
                ...actions.map((action) {
                  final isSelected = action.id == selectedAction?.id;
                  final isUnlocked = skillLevel >= action.unlockLevel;
                  final durationText = action.isFixedDuration
                      ? _formatDuration(action.minDuration)
                      : '${_formatDuration(action.minDuration)} - '
                            '${_formatDuration(action.maxDuration)}';

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
                            const SkillImage(skill: Skill.fishing, size: 14),
                            Text(
                              ' Level ${action.unlockLevel}',
                              style: const TextStyle(
                                color: Style.textColorSecondary,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => onSelect(action),
                      ),
                    );
                  }

                  final productItem = context.state.registries.items.byId(
                    action.productId,
                  );
                  return Card(
                    margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    color: isSelected ? Style.selectedColorLight : null,
                    child: ListTile(
                      leading: ItemImage(item: productItem),
                      title: Text(action.name),
                      subtitle: Text(
                        'Lvl ${action.unlockLevel} • $durationText',
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

class _AreaChances extends StatelessWidget {
  const _AreaChances({required this.area});

  final FishingArea area;

  @override
  Widget build(BuildContext context) {
    final parts = <String>['Fish: ${percentToString(area.fishChance)}'];
    if (area.junkChance > 0) {
      parts.add('Junk: ${percentToString(area.junkChance)}');
    }
    if (area.specialChance > 0) {
      parts.add('Special: ${percentToString(area.specialChance)}');
    }

    return Text(
      parts.join(' • '),
      style: TextStyle(fontSize: 12, color: Style.fishingAreaSelectedColor),
    );
  }
}
