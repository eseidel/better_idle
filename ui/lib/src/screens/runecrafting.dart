import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/categorized_action_list.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/production_action_display.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
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
    final actions = registries.runecrafting.actions;
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Group actions by category
    final actionsByCategory =
        <RunecraftingCategory, List<RunecraftingAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? registries.runecrafting.categoryById(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((RunecraftingAction a) => skillLevel >= a.unlockLevel)
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
                  ProductionActionDisplay(
                    action: selectedAction!,
                    productId: selectedAction.productId,
                    skill: Skill.runecrafting,
                    headerText: 'Create',
                    buttonText: 'Create',
                    showRecycleBadge: false,
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
