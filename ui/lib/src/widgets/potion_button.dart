import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Asset path for the empty potion icon.
const _emptyPotionAsset = 'assets/media/skills/herblore/potion_empty.png';

/// A button that displays the currently active potion (if any) and opens
/// a dialog to select potions for the current skill.
class PotionButton extends StatelessWidget {
  const PotionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final activeSkill = state.activeSkill();

    // Find the selected potion for the active skill.
    Item? activePotion;
    int chargesRemaining = 0;
    if (activeSkill != null) {
      final potionId = state.selectedPotions[activeSkill.id];
      if (potionId != null) {
        activePotion = state.registries.items.byId(potionId);
        chargesRemaining = state.currentPotionChargesRemaining(activeSkill.id);
      }
    }

    // Check if there are any potions available for the active skill.
    final hasAvailable =
        activeSkill != null &&
        state.inventory.items.any(
          (stack) =>
              stack.item.isPotion && stack.item.potionAction == activeSkill.id,
        );

    final isEnabled = activePotion != null || hasAvailable;

    return IconButton(
      icon: activePotion != null
          ? Badge(
              label: Text('$chargesRemaining'),
              child: SizedBox(
                width: 24,
                height: 24,
                child: ItemImage(item: activePotion, size: 24),
              ),
            )
          : Opacity(
              opacity: isEnabled ? 1.0 : 0.4,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CachedImage(assetPath: _emptyPotionAsset, size: 24),
              ),
            ),
      tooltip: 'Potions',
      onPressed: isEnabled
          ? () => showDialog<void>(
              context: context,
              builder: (_) => PotionSelectionDialog(skill: activeSkill!),
            )
          : null,
    );
  }
}

/// A dialog that displays potion selection options for the active skill.
class PotionSelectionDialog extends StatelessWidget {
  const PotionSelectionDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillId = skill.id;
    final selectedPotionId = state.selectedPotions[skillId];

    // Gather potions in inventory for this skill.
    final potions = <Item>[];
    for (final stack in state.inventory.items) {
      final item = stack.item;
      if (item.isPotion && item.potionAction == skillId) {
        potions.add(item);
      }
    }

    // Sort by tier (higher first).
    potions.sort((a, b) => (b.potionTier ?? 0).compareTo(a.potionTier ?? 0));

    return AlertDialog(
      title: Text('${skill.name} Potions'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "None" option to clear selection.
            ListTile(
              dense: true,
              leading: const Icon(Icons.block, size: 20),
              title: const Text('None'),
              selected: selectedPotionId == null,
              onTap: () {
                context.dispatch(ClearPotionSelectionAction(skillId));
                Navigator.of(context).pop();
              },
            ),
            const Divider(),
            // Available potions.
            for (final potion in potions)
              _PotionTile(
                potion: potion,
                skillId: skillId,
                isSelected: selectedPotionId == potion.id,
              ),
            if (potions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No potions in inventory',
                  style: TextStyle(
                    fontSize: 12,
                    color: Style.textColorSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A tile displaying a single potion option.
class _PotionTile extends StatelessWidget {
  const _PotionTile({
    required this.potion,
    required this.skillId,
    required this.isSelected,
  });

  final Item potion;
  final MelvorId skillId;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final count = state.inventory.countOfItem(potion);
    final charges = potion.potionCharges ?? 1;

    return ListTile(
      dense: true,
      leading: ItemImage(item: potion, size: 24),
      title: Text(potion.name),
      subtitle: Text('$count in inventory ($charges charges ea)'),
      selected: isSelected,
      trailing: isSelected ? const Icon(Icons.check, size: 20) : null,
      onTap: () {
        context.dispatch(SelectPotionAction(skillId, potion.id));
        Navigator.of(context).pop();
      },
    );
  }
}
