import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/input_items_row.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/skill_action_display.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class AltMagicPage extends StatelessWidget {
  const AltMagicPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.altMagic;
    final state = context.state;
    final actions = state.registries.altMagic.actions;
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((AltMagicAction a) => skillLevel >= a.unlockLevel)
        .toList();

    // Try to restore the last selected action from persisted state
    final savedActionId = state.selectedSkillAction(skill);
    SkillAction? savedAction;
    if (savedActionId != null) {
      savedAction = actions.cast<SkillAction?>().firstWhere(
        (a) => a?.id.localId == savedActionId,
        orElse: () => null,
      );
    }

    // Use saved action if available, otherwise default to first unlocked action
    final selectedAction =
        savedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    return GameScaffold(
      title: const Text('Alt. Magic'),
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
                  SkillActionDisplay(
                    action: selectedAction,
                    skill: skill,
                    skillLevel: skillLevel,
                    headerText: 'Cast',
                    buttonText: 'Cast',
                    onStart: () {
                      context.dispatch(
                        ToggleActionAction(action: selectedAction),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _SpellList(
                    actions: actions,
                    selectedAction: selectedAction,
                    skillLevel: skillLevel,
                    onSelect: (action) {
                      context.dispatch(
                        SetSelectedSkillAction(
                          skill: skill,
                          actionId: action.id.localId,
                        ),
                      );
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

class _SpellList extends StatelessWidget {
  const _SpellList({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<AltMagicAction> actions;
  final SkillAction selectedAction;
  final int skillLevel;
  final void Function(SkillAction) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Available Spells',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...actions.map((action) {
          final isSelected = action.id == selectedAction.id;
          final isUnlocked = skillLevel >= action.unlockLevel;

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
                    const SkillImage(skill: Skill.altMagic, size: 14),
                    Text(
                      ' Level ${action.unlockLevel}',
                      style: const TextStyle(color: Style.textColorSecondary),
                    ),
                  ],
                ),
              ),
            );
          }

          return Card(
            color: isSelected ? Style.selectedColorLight : null,
            child: ListTile(
              leading: CachedImage(assetPath: action.media, size: 40),
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
