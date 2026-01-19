import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class AgilityPage extends StatefulWidget {
  const AgilityPage({super.key});

  @override
  State<AgilityPage> createState() => _AgilityPageState();
}

class _AgilityPageState extends State<AgilityPage> {
  AgilityObstacle? _selectedObstacle;
  final Set<int> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.agility;
    final skillState = context.state.skillState(skill);
    final registries = context.state.registries;

    // Get all agility obstacles from the registry, sorted by category then name
    final obstacles =
        registries.agility.obstacles.toList()
          ..sort((AgilityObstacle a, AgilityObstacle b) {
            final catCompare = a.category.compareTo(b.category);
            if (catCompare != 0) return catCompare;
            return a.name.compareTo(b.name);
          });

    // Group obstacles by category
    final obstaclesByCategory = <int, List<AgilityObstacle>>{};
    for (final obstacle in obstacles) {
      obstaclesByCategory
          .putIfAbsent(obstacle.category, () => [])
          .add(obstacle);
    }

    // Default to first obstacle if none selected
    final selectedObstacle = _selectedObstacle ?? obstacles.firstOrNull;

    // Get course info for level requirements
    final course = registries.agility.courseForRealm(
      const MelvorId('melvorD:Melvor'),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Agility')),
      drawer: const AppNavigationDrawer(),
      body: Column(
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (selectedObstacle != null)
                    _SelectedObstacleDisplay(
                      obstacle: selectedObstacle,
                      onStart: () {
                        context.dispatch(
                          ToggleActionAction(action: selectedObstacle),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  _ObstacleList(
                    obstaclesByCategory: obstaclesByCategory,
                    selectedObstacle: selectedObstacle,
                    collapsedCategories: _collapsedCategories,
                    course: course,
                    onSelect: (obstacle) {
                      setState(() {
                        _selectedObstacle = obstacle;
                      });
                    },
                    onToggleCategory: (category) {
                      setState(() {
                        if (_collapsedCategories.contains(category)) {
                          _collapsedCategories.remove(category);
                        } else {
                          _collapsedCategories.add(category);
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

class _SelectedObstacleDisplay extends StatelessWidget {
  const _SelectedObstacleDisplay({
    required this.obstacle,
    required this.onStart,
  });

  final AgilityObstacle obstacle;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(obstacle.id);
    final isActive = state.isActionActive(obstacle);
    final canStart = state.canStartAction(obstacle);
    final canToggle = canStart || isActive;

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
          // Header
          Text(
            'Slot ${obstacle.category + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Style.textColorSecondary,
            ),
          ),
          Text(
            obstacle.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          XpBadgesRow(action: obstacle),
          const SizedBox(height: 16),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text(
                    'Interval',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  Text(
                    '${obstacle.minDuration.inMilliseconds / 1000}s',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'Rewards',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  if (obstacle.currencyRewards.isEmpty)
                    const Text(
                      '-',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    )
                  else
                    ...obstacle.currencyRewards.map(
                      (reward) => Text(
                        '${reward.amount} ${reward.currency.abbreviation}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              Column(
                children: [
                  const Text(
                    'XP',
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  Text(
                    '${obstacle.xp}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          _AgilityProgressBar(obstacle: obstacle),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: canToggle ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : 'Train'),
          ),
        ],
      ),
    );
  }
}

class _AgilityProgressBar extends StatelessWidget {
  const _AgilityProgressBar({required this.obstacle});

  final AgilityObstacle obstacle;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isActive = state.isActionActive(obstacle);

    double progress;
    Color barColor;
    String label;

    if (isActive) {
      final progressTicks = state.activeProgress(obstacle);
      final totalTicks = ticksFromDuration(obstacle.minDuration);
      progress = progressTicks / totalTicks;
      barColor = Style.progressForegroundColorSuccess;
      label = 'Training...';
    } else {
      progress = 0.0;
      barColor = Style.iconColorDefault;
      label = 'Idle';
    }

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: Style.progressBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: progress > 0.5
                    ? Style.textColorPrimary
                    : Style.progressTextDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ObstacleList extends StatelessWidget {
  const _ObstacleList({
    required this.obstaclesByCategory,
    required this.selectedObstacle,
    required this.collapsedCategories,
    required this.course,
    required this.onSelect,
    required this.onToggleCategory,
  });

  final Map<int, List<AgilityObstacle>> obstaclesByCategory;
  final AgilityObstacle? selectedObstacle;
  final Set<int> collapsedCategories;
  final AgilityCourse? course;
  final void Function(AgilityObstacle) onSelect;
  final void Function(int) onToggleCategory;

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(Skill.agility);
    final skillLevel = levelForXp(skillState.xp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Obstacles',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...obstaclesByCategory.entries.map((entry) {
          final category = entry.key;
          final obstacles = entry.value;
          final isCollapsed = collapsedCategories.contains(category);

          // Get level requirement for this slot from course
          final slotLevel =
              course != null && category < course!.obstacleSlots.length
              ? course!.obstacleSlots[category]
              : 1;
          final slotUnlocked = skillLevel >= slotLevel;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category header with collapse toggle
              InkWell(
                onTap: () => onToggleCategory(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: slotUnlocked
                        ? Style.categoryHeaderColor
                        : Style.thievingNpcUnlockedColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                        size: 24,
                        color: slotUnlocked ? null : Style.textColorSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Slot ${category + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: slotUnlocked ? null : Style.textColorSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        slotUnlocked
                            ? '${obstacles.length} obstacles'
                            : 'Requires Lvl $slotLevel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Style.textColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Obstacles list (if not collapsed)
              if (!isCollapsed)
                ...obstacles.map((obstacle) {
                  final isSelected = obstacle.id == selectedObstacle?.id;
                  final rewardsStr = obstacle.currencyRewards
                      .map((r) => '${r.amount} ${r.currency.abbreviation}')
                      .join(', ');
                  return Card(
                    margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                    color: isSelected
                        ? Style.selectedColorLight
                        : slotUnlocked
                        ? null
                        : Style.thievingNpcUnlockedColor,
                    child: ListTile(
                      title: Text(
                        obstacle.name,
                        style: TextStyle(
                          color: slotUnlocked ? null : Style.textColorSecondary,
                        ),
                      ),
                      subtitle: Text(
                        rewardsStr.isNotEmpty
                            ? '${obstacle.xp} XP • $rewardsStr'
                            : '${obstacle.xp} XP',
                        style: TextStyle(
                          color: slotUnlocked ? null : Style.textColorSecondary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Style.selectedColor,
                            )
                          : slotUnlocked
                          ? null
                          : const Icon(
                              Icons.lock,
                              color: Style.textColorSecondary,
                            ),
                      onTap: slotUnlocked ? () => onSelect(obstacle) : null,
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
