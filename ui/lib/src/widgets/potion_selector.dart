import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Displays the selected potion for a skill with remaining charges.
///
/// Tapping opens a dialog to select a different potion or clear selection.
class PotionSelector extends StatelessWidget {
  const PotionSelector({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillId = skill.id;
    final selectedPotion = state.selectedPotionForSkill(skillId);
    final usesRemaining = state.potionUsesRemaining(skillId);

    // Find available potions in inventory for this skill
    final availablePotions = _getAvailablePotions(state);
    final hasAvailable = availablePotions.isNotEmpty;

    return InkWell(
      onTap: hasAvailable || selectedPotion != null
          ? () => _showPotionDialog(context, state, availablePotions)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Style.cellBorderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedPotion != null) ...[
              ItemImage(item: selectedPotion, size: 24),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedPotion.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '$usesRemaining uses left',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Style.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Icon(
                Icons.science_outlined,
                size: 24,
                color: hasAvailable
                    ? Style.textColorSecondary
                    : Style.textColorMuted,
              ),
              const SizedBox(width: 8),
              Text(
                hasAvailable ? 'Select Potion' : 'No Potions',
                style: TextStyle(
                  fontSize: 12,
                  color: hasAvailable
                      ? Style.textColorSecondary
                      : Style.textColorMuted,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: hasAvailable || selectedPotion != null
                  ? null
                  : Style.textColorMuted,
            ),
          ],
        ),
      ),
    );
  }

  /// Returns potions in inventory that apply to this skill.
  List<Item> _getAvailablePotions(GlobalState state) {
    final skillId = skill.id;
    final potions = <Item>[];

    for (final stack in state.inventory.items) {
      final item = stack.item;
      if (item.isPotion && item.potionAction == skillId) {
        potions.add(item);
      }
    }

    // Sort by tier (higher tier first)
    potions.sort((a, b) => (b.potionTier ?? 0).compareTo(a.potionTier ?? 0));
    return potions;
  }

  void _showPotionDialog(
    BuildContext context,
    GlobalState state,
    List<Item> availablePotions,
  ) {
    final skillId = skill.id;
    final selectedPotionId = state.selectedPotions[skillId];

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Select ${skill.name} Potion'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "None" option to clear selection
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('None'),
                  selected: selectedPotionId == null,
                  onTap: () {
                    context.dispatch(ClearPotionSelectionAction(skillId));
                    Navigator.pop(dialogContext);
                  },
                ),
                const Divider(),
                // Available potions
                ...availablePotions.map((potion) {
                  final count = state.inventory.countOfItem(potion);
                  final charges = potion.potionCharges ?? 1;
                  final isSelected = selectedPotionId == potion.id;

                  return ListTile(
                    leading: ItemImage(item: potion),
                    title: Text(potion.name),
                    subtitle: Text('$count in inventory ($charges charges ea)'),
                    selected: isSelected,
                    onTap: () {
                      context.dispatch(SelectPotionAction(skillId, potion.id));
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
                if (availablePotions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No potions available for this skill.\n'
                      'Brew some with Herblore!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Style.textColorSecondary),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
