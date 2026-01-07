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

class FletchingPage extends StatefulWidget {
  const FletchingPage({super.key});

  @override
  State<FletchingPage> createState() => _FletchingPageState();
}

class _FletchingPageState extends State<FletchingPage> {
  FletchingAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.fletching;
    final registries = context.state.registries;
    final actions = registries.actions
        .forSkill(skill)
        .whereType<FletchingAction>()
        .toList();
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;
    final categories = registries.fletchingCategories;

    // Group actions by category
    final actionsByCategory = <FletchingCategory, List<FletchingAction>>{};
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
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    return Scaffold(
      appBar: AppBar(title: const Text('Fletching')),
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
                    action: selectedAction,
                    productId: selectedAction.productId,
                    skill: Skill.fletching,
                    headerText: 'Fletch',
                    buttonText: 'Fletch',
                    showRecycleBadge: true,
                    skillLevel: skillLevel,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  CategorizedActionList<FletchingCategory, FletchingAction>(
                    actionsByCategory: actionsByCategory,
                    selectedAction: selectedAction,
                    collapsedCategories: _collapsedCategories,
                    skill: skill,
                    skillLevel: skillLevel,
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
