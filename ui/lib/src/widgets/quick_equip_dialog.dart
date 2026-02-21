import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Shows a dialog for quickly equipping items relevant to a skill.
void showQuickEquipDialog(BuildContext context, Skill skill) {
  showDialog<void>(
    context: context,
    builder: (_) => QuickEquipDialog(skill: skill),
  );
}

/// A dialog that displays equippable items grouped by slot, with
/// skill-relevant items shown first.
class QuickEquipDialog extends StatelessWidget {
  const QuickEquipDialog({required this.skill, super.key});

  final Skill skill;

  /// Slots to display, in the same order as EquipmentSlotsList.
  static const List<EquipmentSlot> _displaySlots = [
    EquipmentSlot.weapon,
    EquipmentSlot.shield,
    EquipmentSlot.helmet,
    EquipmentSlot.platebody,
    EquipmentSlot.platelegs,
    EquipmentSlot.boots,
    EquipmentSlot.gloves,
    EquipmentSlot.cape,
    EquipmentSlot.amulet,
    EquipmentSlot.ring,
    EquipmentSlot.quiver,
    EquipmentSlot.passive,
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final equipment = state.equipment;
    final skillId = skill.id;

    // Gather equippable items from inventory, grouped by slot.
    final itemsBySlot = <EquipmentSlot, List<Item>>{};
    for (final stack in state.inventory.items) {
      final item = stack.item;
      if (!item.isEquippable || item.isSummonTablet) continue;
      // Group under the first valid display slot.
      for (final slot in _displaySlots) {
        if (item.canEquipInSlot(slot)) {
          itemsBySlot.putIfAbsent(slot, () => []).add(item);
          break;
        }
      }
    }

    // Sort items within each slot: skill-relevant first, then
    // alphabetically.
    for (final items in itemsBySlot.values) {
      items.sort((a, b) {
        final aRelevant = a.hasModifiersForSkill(skillId);
        final bRelevant = b.hasModifiersForSkill(skillId);
        if (aRelevant != bRelevant) return aRelevant ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    }

    // Only show slots that have items in inventory or are equipped.
    final slotsToShow = _displaySlots.where((slot) {
      return itemsBySlot.containsKey(slot) ||
          equipment.gearInSlot(slot) != null;
    }).toList();

    return AlertDialog(
      title: Text('Quick Equip — ${skill.name}'),
      content: SizedBox(
        width: 350,
        child: slotsToShow.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No equippable items in your bank.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Style.textColorSecondary),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: slotsToShow.length,
                itemBuilder: (context, index) {
                  final slot = slotsToShow[index];
                  return _SlotSection(
                    slot: slot,
                    skill: skill,
                    equippedItem: equipment.gearInSlot(slot),
                    bankItems: itemsBySlot[slot] ?? const [],
                  );
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

/// A section in the quick equip dialog for a single slot.
class _SlotSection extends StatelessWidget {
  const _SlotSection({
    required this.slot,
    required this.skill,
    required this.equippedItem,
    required this.bankItems,
  });

  final EquipmentSlot slot;
  final Skill skill;
  final Item? equippedItem;
  final List<Item> bankItems;

  @override
  Widget build(BuildContext context) {
    final slotDef = context.state.registries.equipmentSlots[slot];
    final slotName = slotDef?.emptyName ?? slot.jsonName;
    final hasRelevantItems = bankItems.any(
      (item) => item.hasModifiersForSkill(skill.id),
    );

    return ExpansionTile(
      initiallyExpanded: hasRelevantItems,
      leading: equippedItem != null
          ? SizedBox(
              width: 24,
              height: 24,
              child: ItemImage(item: equippedItem!, size: 24),
            )
          : const Icon(
              Icons.circle_outlined,
              size: 24,
              color: Style.textColorSecondary,
            ),
      title: Text(slotName),
      subtitle: equippedItem != null
          ? Text(equippedItem!.name, style: const TextStyle(fontSize: 12))
          : const Text(
              'Empty',
              style: TextStyle(fontSize: 12, color: Style.textColorSecondary),
            ),
      children: [
        if (bankItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No items in bank for this slot',
              style: TextStyle(
                fontSize: 12,
                color: Style.textColorSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final item in bankItems)
            _EquippableItemTile(
              item: item,
              slot: slot,
              skill: skill,
              isEquipped: equippedItem?.id == item.id,
            ),
      ],
    );
  }
}

/// A tile for a single equippable item.
class _EquippableItemTile extends StatelessWidget {
  const _EquippableItemTile({
    required this.item,
    required this.slot,
    required this.skill,
    required this.isEquipped,
  });

  final Item item;
  final EquipmentSlot slot;
  final Skill skill;
  final bool isEquipped;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final unmetReqs = state.unmetEquipRequirements(item);
    final isRelevant = item.hasModifiersForSkill(skill.id);

    return ListTile(
      dense: true,
      leading: ItemImage(item: item, size: 24),
      title: Text(
        item.name,
        style: TextStyle(fontWeight: isRelevant ? FontWeight.bold : null),
      ),
      subtitle: unmetReqs.isNotEmpty
          ? Text(
              'Requirements not met',
              style: TextStyle(
                fontSize: 12,
                color: Style.unmetRequirementColor,
              ),
            )
          : null,
      selected: isEquipped,
      trailing: isEquipped ? const Icon(Icons.check, size: 20) : null,
      enabled: unmetReqs.isEmpty && !isEquipped,
      onTap: unmetReqs.isEmpty && !isEquipped
          ? () {
              context.dispatch(EquipGearAction(item: item, slot: slot));
            }
          : null,
    );
  }
}
