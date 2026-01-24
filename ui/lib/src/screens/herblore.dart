import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/categorized_action_list.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/mastery_unlocks_dialog.dart';
import 'package:ui/src/widgets/production_action_display.dart';
import 'package:ui/src/widgets/skill_milestones_dialog.dart';
import 'package:ui/src/widgets/skill_progress.dart';

class HerblorePage extends StatefulWidget {
  const HerblorePage({super.key});

  @override
  State<HerblorePage> createState() => _HerblorePageState();
}

class _HerblorePageState extends State<HerblorePage> {
  HerbloreAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    const skill = Skill.herblore;
    final registries = context.state.registries;
    final actions = registries.herblore.actions;
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Group actions by category
    final actionsByCategory = <HerbloreCategory, List<HerbloreAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? registries.herblore.categoryById(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((HerbloreAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return GameScaffold(
      title: const Text('Herblore'),
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ProductionActionDisplay(
                    action: selectedAction!,
                    productId: selectedAction.productId,
                    skill: Skill.herblore,
                    headerText: 'Brew',
                    buttonText: 'Brew',
                    showRecycleBadge: false,
                    skillLevel: skillLevel,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  CategorizedActionList<HerbloreCategory, HerbloreAction>(
                    actionsByCategory: actionsByCategory,
                    selectedAction: selectedAction,
                    collapsedCategories: _collapsedCategories,
                    skill: skill,
                    skillLevel: skillLevel,
                    title: 'Available Potions',
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
