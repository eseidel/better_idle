import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_action_display.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class CookingPage extends StatefulWidget {
  const CookingPage({super.key});

  @override
  State<CookingPage> createState() => _CookingPageState();
}

class _CookingPageState extends State<CookingPage> {
  SkillAction? _selectedAction;

  @override
  Widget build(BuildContext context) {
    const skill = Skill.cooking;
    final state = context.state;
    final actions = state.registries.actions.forSkill(skill).toList();
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    // Get healing value from output item
    final outputId = selectedAction.outputs.keys.firstOrNull;
    final outputItem = outputId != null
        ? state.registries.items.byId(outputId)
        : null;
    final healsFor = outputItem?.healsFor;

    return Scaffold(
      appBar: AppBar(title: const Text('Cooking')),
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
                  SkillActionDisplay(
                    action: selectedAction,
                    skill: skill,
                    skillLevel: skillLevel,
                    headerText: 'Cook',
                    buttonText: 'Cook',
                    additionalContent: healsFor != null
                        ? Row(
                            children: [
                              const Icon(
                                Icons.favorite,
                                size: 16,
                                color: Style.healColor,
                              ),
                              const SizedBox(width: 4),
                              Text('Heals $healsFor HP'),
                            ],
                          )
                        : null,
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _ActionList(
                    actions: actions,
                    selectedAction: selectedAction,
                    skillLevel: skillLevel,
                    onSelect: (action) {
                      setState(() {
                        _selectedAction = action;
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

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<SkillAction> actions;
  final SkillAction selectedAction;
  final int skillLevel;
  final void Function(SkillAction) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Available Recipes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actions.map((action) {
          final isSelected = action.name == selectedAction.name;
          final isUnlocked = skillLevel >= action.unlockLevel;
          final cookingAction = action as CookingAction;

          if (!isUnlocked) {
            return Card(
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
                    const SkillImage(skill: Skill.cooking, size: 14),
                    Text(
                      ' Level ${action.unlockLevel}',
                      style: const TextStyle(color: Style.textColorSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          final productItem = context.state.registries.items.byId(
            cookingAction.productId,
          );
          return Card(
            color: isSelected ? Style.selectedColorLight : null,
            child: ListTile(
              leading: ItemImage(item: productItem),
              title: Text(action.name),
              subtitle: InputItemsRow(items: action.inputs),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Style.selectedColor)
                  : null,
              onTap: () => onSelect(action),
            ),
          );
        }),
      ],
    );
  }
}
