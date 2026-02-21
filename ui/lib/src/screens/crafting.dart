import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/categorized_action_list.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/production_action_display.dart';
import 'package:ui/src/widgets/skill_fab.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';

class CraftingPage extends StatefulWidget {
  const CraftingPage({super.key});

  @override
  State<CraftingPage> createState() => _CraftingPageState();
}

class _CraftingPageState extends State<CraftingPage> {
  CraftingAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.crafting;
    final registries = context.state.registries;
    final actions = registries.crafting.actions;
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Group actions by category
    final actionsByCategory = <CraftingCategory, List<CraftingAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? registries.crafting.categoryById(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((CraftingAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return GameScaffold(
      title: const Text('Crafting'),
      actions: const [SkillOverflowMenu(skill: skill)],
      floatingActionButton: const SkillFab(skill: skill),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ProductionActionDisplay(
                    action: selectedAction!,
                    productId: selectedAction.productId,
                    skill: Skill.crafting,
                    headerText: 'Create',
                    buttonText: 'Create',
                    showRecycleBadge: true,
                    skillLevel: skillLevel,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  CategorizedActionList<CraftingCategory, CraftingAction>(
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
