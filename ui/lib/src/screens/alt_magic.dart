import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/input_items_row.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/skill_action_display.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class AltMagicPage extends StatefulWidget {
  const AltMagicPage({super.key});

  @override
  State<AltMagicPage> createState() => _AltMagicPageState();
}

class _AltMagicPageState extends State<AltMagicPage> {
  SkillAction? _selectedAction;

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
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    return GameScaffold(
      title: const Text('Alt. Magic'),
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
