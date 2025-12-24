import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/categorized_action_list.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/double_chance_badge_cell.dart';
import 'package:better_idle/src/widgets/item_count_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class RunecraftingPage extends StatefulWidget {
  const RunecraftingPage({super.key});

  @override
  State<RunecraftingPage> createState() => _RunecraftingPageState();
}

class _RunecraftingPageState extends State<RunecraftingPage> {
  RunecraftingAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.runecrafting;
    final registries = context.state.registries;
    final actions = registries.actions
        .forSkill(skill)
        .whereType<RunecraftingAction>()
        .toList();
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;
    final categories = registries.runecraftingCategories;

    // Group actions by category
    final actionsByCategory =
        <RunecraftingCategory, List<RunecraftingAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? categories.byId(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Runecrafting')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
          const MasteryUnlocksButton(skill: skill),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _SelectedActionDisplay(
                    action: selectedAction!,
                    skillLevel: skillLevel,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  CategorizedActionList<
                    RunecraftingCategory,
                    RunecraftingAction
                  >(
                    actionsByCategory: actionsByCategory,
                    selectedAction: selectedAction,
                    collapsedCategories: _collapsedCategories,
                    skill: skill,
                    skillLevel: skillLevel,
                    title: 'Available Recipes',
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
                      });
                    },
                    onToggleCategory: (category) {
                      setState(() {
                        if (_collapsedCategories.contains(category.id)) {
                          _collapsedCategories.remove(category.id);
                        } else {
                          _collapsedCategories.add(category.id);
                        }
                      });
                    },
                    categoryId: (c) => c.id,
                    categoryName: (c) => c.name,
                    categoryMedia: (c) => c.media,
                    actionProductId: (a) => a.productId,
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
  const _SelectedActionDisplay({
    required this.action,
    required this.skillLevel,
    required this.onStart,
  });

  final RunecraftingAction action;
  final int skillLevel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
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
              const SkillImage(skill: Skill.runecrafting, size: 16),
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
    final isActive = state.activeAction?.id == action.id;
    final canStart = state.canStartAction(action);

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
          // Header: Create + Action Name
          const Text(
            'Create',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
          ),
          Text(
            action.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Double chance (placeholder)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [DoubleChanceBadgeCell(chance: '0%')],
          ),
          const SizedBox(height: 12),

          // Mastery progress
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 12),

          // Requires section
          const Text(
            'Requires:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.required(items: action.inputs),
          const SizedBox(height: 8),

          // You Have section
          const Text(
            'You Have:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.inventory(items: action.inputs),
          const SizedBox(height: 8),

          // Produces section
          const Text(
            'Produces:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ItemCountBadgesRow.required(items: action.outputs),
          const SizedBox(height: 8),

          // Grants section
          const Text('Grants:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          XpBadgesRow(action: action),
          const SizedBox(height: 16),

          // Duration and Create button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 4),
              Text('${action.minDuration.inSeconds}s'),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canStart || isActive ? onStart : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive ? Style.activeColor : null,
            ),
            child: Text(isActive ? 'Stop' : 'Create'),
          ),
        ],
      ),
    );
  }
}
