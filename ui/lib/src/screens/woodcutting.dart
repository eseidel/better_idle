import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/production_action_display.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.woodcutting;
    final state = context.state;
    final registries = state.registries;
    final actions = registries.woodcutting.actions;
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((WoodcuttingTree a) => skillLevel >= a.unlockLevel)
        .toList();

    // Try to restore the last selected action from persisted state
    final savedActionId = state.selectedSkillAction(skill);
    WoodcuttingTree? savedAction;
    if (savedActionId != null) {
      savedAction = actions.cast<WoodcuttingTree?>().firstWhere(
        (a) => a?.id.localId == savedActionId,
        orElse: () => null,
      );
    }

    // Use saved action if available, otherwise default to first unlocked action
    final selectedAction =
        savedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : null);

    return GameScaffold(
      title: const Text('Woodcutting'),
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
                  if (selectedAction != null)
                    ProductionActionDisplay(
                      action: selectedAction,
                      productId: selectedAction.productId,
                      skill: Skill.woodcutting,
                      headerText: 'Cut',
                      buttonText: 'Cut',
                      showRecycleBadge: false,
                      skillLevel: skillLevel,
                      onStart: () {
                        context.dispatch(
                          ToggleActionAction(action: selectedAction),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  _TreeSelectionButton(
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

/// Button that shows the selected tree and opens a popup for tree selection.
class _TreeSelectionButton extends StatelessWidget {
  const _TreeSelectionButton({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<WoodcuttingTree> actions;
  final WoodcuttingTree? selectedAction;
  final int skillLevel;
  final void Function(WoodcuttingTree) onSelect;

  @override
  Widget build(BuildContext context) {
    final productItem = selectedAction != null
        ? context.state.registries.items.byId(selectedAction!.productId)
        : null;

    return InkWell(
      onTap: () => _showTreeSelectionDialog(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Style.containerBackgroundLight,
          border: Border.all(color: Style.iconColorDefault),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (productItem != null) ...[
              ItemImage(item: productItem),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                selectedAction?.name ?? 'Select a tree',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _showTreeSelectionDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _TreeSelectionDialog(
        actions: actions,
        selectedAction: selectedAction,
        skillLevel: skillLevel,
        onSelect: (action) {
          onSelect(action);
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }
}

/// Dialog showing all trees for selection.
class _TreeSelectionDialog extends StatelessWidget {
  const _TreeSelectionDialog({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<WoodcuttingTree> actions;
  final WoodcuttingTree? selectedAction;
  final int skillLevel;
  final void Function(WoodcuttingTree) onSelect;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Tree'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            final isSelected = action.id == selectedAction?.id;
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
                      const SkillImage(skill: Skill.woodcutting, size: 14),
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
              action.productId,
            );

            return Card(
              color: isSelected ? Style.selectedColorLight : null,
              child: ListTile(
                leading: CachedImage(assetPath: action.media, size: 40),
                title: Text(action.name),
                subtitle: Row(
                  children: [
                    ItemImage(item: productItem, size: 16),
                    const SizedBox(width: 4),
                    Text(productItem.name),
                  ],
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Style.selectedColor)
                    : null,
                onTap: () => onSelect(action),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
