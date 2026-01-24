import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Asset path for the empty potion icon.
const _emptyPotionAsset = 'assets/media/skills/herblore/potion_empty.png';

/// Looks up an item by ID, returning null if not found (instead of throwing).
Item? _findItemById(ItemRegistry registry, MelvorId id) {
  final idJson = id.toJson();
  return registry.all.where((item) => item.id.toJson() == idJson).firstOrNull;
}

/// A button that displays the currently active potion (if any) and opens
/// a dialog to select potions for different skills.
class PotionButton extends StatelessWidget {
  const PotionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    // Find the first selected potion to display on the button.
    Item? activePotion;
    for (final entry in state.selectedPotions.entries) {
      final potion = _findItemById(state.registries.items, entry.value);
      if (potion != null) {
        activePotion = potion;
        break;
      }
    }

    return IconButton(
      icon: activePotion != null
          ? SizedBox(
              width: 24,
              height: 24,
              child: ItemImage(item: activePotion, size: 24),
            )
          : const SizedBox(
              width: 24,
              height: 24,
              child: CachedImage(assetPath: _emptyPotionAsset, size: 24),
            ),
      tooltip: 'Potions',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const PotionSelectionDialog(),
      ),
    );
  }
}

/// A dialog that displays potion selection options for all skills.
class PotionSelectionDialog extends StatelessWidget {
  const PotionSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    // Gather all potions in inventory grouped by skill.
    final potionsBySkill = <Skill, List<Item>>{};
    for (final stack in state.inventory.items) {
      final item = stack.item;
      if (item.isPotion && item.potionAction != null) {
        final skill = Skill.values.firstWhere(
          (s) => s.id == item.potionAction,
          orElse: () => Skill.woodcutting, // Fallback, shouldn't happen.
        );
        potionsBySkill.putIfAbsent(skill, () => []).add(item);
      }
    }

    // Sort potions within each skill by tier (higher first).
    for (final potions in potionsBySkill.values) {
      potions.sort((a, b) => (b.potionTier ?? 0).compareTo(a.potionTier ?? 0));
    }

    // Also include skills that have a potion selected but none in inventory.
    for (final skillId in state.selectedPotions.keys) {
      final skill = Skill.values.firstWhere(
        (s) => s.id == skillId,
        orElse: () => Skill.woodcutting,
      );
      potionsBySkill.putIfAbsent(skill, () => []);
    }

    // Sort skills alphabetically.
    final skills = potionsBySkill.keys.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return AlertDialog(
      title: const Text('Potions'),
      content: SizedBox(
        width: 350,
        child: skills.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No potions available.\nBrew some with Herblore!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Style.textColorSecondary),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: skills.length,
                itemBuilder: (context, index) {
                  final skill = skills[index];
                  final potions = potionsBySkill[skill] ?? [];
                  return _SkillPotionSection(skill: skill, potions: potions);
                },
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

/// A section in the potion dialog for a single skill.
class _SkillPotionSection extends StatelessWidget {
  const _SkillPotionSection({required this.skill, required this.potions});

  final Skill skill;
  final List<Item> potions;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final selectedPotionId = state.selectedPotions[skill.id];
    final selectedPotion = selectedPotionId != null
        ? _findItemById(state.registries.items, selectedPotionId)
        : null;
    final usesRemaining = state.potionUsesRemaining(skill.id);

    return ExpansionTile(
      leading: SkillImage(skill: skill, size: 24),
      title: Text(skill.name),
      subtitle: selectedPotion != null
          ? Row(
              children: [
                ItemImage(item: selectedPotion, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$usesRemaining uses',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            )
          : const Text(
              'No potion selected',
              style: TextStyle(fontSize: 12, color: Style.textColorSecondary),
            ),
      children: [
        // "None" option to clear selection.
        ListTile(
          dense: true,
          leading: const Icon(Icons.block, size: 20),
          title: const Text('None'),
          selected: selectedPotionId == null,
          onTap: () {
            context.dispatch(ClearPotionSelectionAction(skill.id));
          },
        ),
        // Available potions.
        for (final potion in potions) ...[
          _PotionTile(
            potion: potion,
            skillId: skill.id,
            isSelected: selectedPotionId == potion.id,
          ),
        ],
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
      },
    );
  }
}
