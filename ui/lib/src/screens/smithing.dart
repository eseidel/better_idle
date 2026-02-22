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

class SmithingPage extends StatefulWidget {
  const SmithingPage({super.key});

  @override
  State<SmithingPage> createState() => _SmithingPageState();
}

class _SmithingPageState extends State<SmithingPage> {
  SmithingAction? _selectedAction;
  final Set<MelvorId> _collapsedCategories = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const skill = Skill.smithing;
    final registries = context.state.registries;
    final actions = registries.smithing.actions;
    final skillState = context.state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Group actions by category
    final actionsByCategory = <SmithingCategory, List<SmithingAction>>{};
    for (final action in actions) {
      final category = action.categoryId != null
          ? registries.smithing.categoryById(action.categoryId!)
          : null;
      if (category != null) {
        actionsByCategory.putIfAbsent(category, () => []).add(action);
      }
    }

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((SmithingAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return GameScaffold(
      title: const Text('Smithing'),
      actions: const [SkillOverflowMenu(skill: skill)],
      floatingActionButton: const SkillFab(skill: skill),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ProductionActionDisplay(
                    action: selectedAction!,
                    productId: selectedAction.productId,
                    skill: Skill.smithing,
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
                  CategorizedActionList<SmithingCategory, SmithingAction>(
                    actionsByCategory: actionsByCategory,
                    selectedAction: selectedAction,
                    collapsedCategories: _collapsedCategories,
                    skill: skill,
                    skillLevel: skillLevel,
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
                      });
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
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
