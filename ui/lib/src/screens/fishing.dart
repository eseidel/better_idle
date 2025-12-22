import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

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
    final registries = context.state.registries;

    // Get all fishing actions from registries.
    final fishingActions = registries.actions
        .forSkill(skill)
        .whereType<FishingAction>()
        .toList();

    // Get all fishing areas from registries.
    final fishingAreas = registries.fishingAreas.all;

    // Default to first action if none selected.
    final selectedAction = _selectedAction ?? fishingActions.first;

    // Group actions by area.
    final actionsByArea = <FishingArea, List<FishingAction>>{};
    for (final area in fishingAreas) {
      final actionsInArea = <FishingAction>[];
      for (final fishId in area.fishIDs) {
        final action = fishingActions.where((a) => a.id == fishId).firstOrNull;
        if (action != null) {
          actionsInArea.add(action);
        }
      }
      if (actionsInArea.isNotEmpty) {
        actionsByArea[area] = actionsInArea;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fishing')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
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

class _SelectedActionDisplay extends StatelessWidget {
  const _SelectedActionDisplay({required this.action, required this.onStart});

  final FishingAction action;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final isActive = state.activeAction?.id == action.id;
    final canStart = state.canStartAction(action);

    final durationText = action.isFixedDuration
        ? _formatDuration(action.minDuration)
        : '${_formatDuration(action.minDuration)} - '
              '${_formatDuration(action.maxDuration)}';

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
          // Header: Fishing + Action Name
          const Text(
            'Fishing',
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

          // Duration and Fish button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 4),
              Text(durationText),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canStart || isActive ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : 'Fish'),
          ),
        ],
      ),
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

  final Map<FishingArea, List<FishingAction>> actionsByArea;
  final FishingAction selectedAction;
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
                    color: Style.fishingAreaHeaderColor,
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
                      Text(
                        '${percentToString(area.fishChance)} fish',
                        style: TextStyle(
                          fontSize: 12,
                          color: Style.fishingAreaSelectedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions list (if not collapsed)
              if (!isCollapsed)
                ...actions.map((action) {
                  final isSelected = action.id == selectedAction.id;
                  final durationText = action.isFixedDuration
                      ? _formatDuration(action.minDuration)
                      : '${_formatDuration(action.minDuration)} - '
                            '${_formatDuration(action.maxDuration)}';
                  return Card(
                    margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    color: isSelected ? Style.selectedColorLight : null,
                    child: ListTile(
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
