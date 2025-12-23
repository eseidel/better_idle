import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Displays the player's equipped gear in a simple list format.
class EquipmentSlotsList extends StatelessWidget {
  const EquipmentSlotsList({super.key});

  /// The main equipment slots to display (excludes summons/enhancements for now).
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
    final equipment = context.state.equipment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Equipment',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final slot in _displaySlots)
          _EquipmentSlotTile(slot: slot, item: equipment.gearInSlot(slot)),
      ],
    );
  }
}

class _EquipmentSlotTile extends StatelessWidget {
  const _EquipmentSlotTile({required this.slot, required this.item});

  final EquipmentSlot slot;
  final Item? item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 32,
        height: 32,
        child: item != null
            ? ItemImage(item: item!)
            : Container(
                decoration: BoxDecoration(
                  color: Style.containerBackgroundEmpty,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Style.iconColorDefault),
                ),
              ),
      ),
      title: Text(
        item?.name ?? slot.displayName,
        style: TextStyle(
          color: item != null ? null : Style.textColorSecondary,
          fontStyle: item != null ? null : FontStyle.italic,
        ),
      ),
      subtitle: item != null ? null : Text(slot.displayName),
      trailing: item != null
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 20,
              tooltip: 'Unequip',
              onPressed: () {
                context.dispatch(UnequipGearAction(slot: slot));
              },
            )
          : null,
    );
  }
}

/// A compact grid view of equipment slots for use in the combat UI.
class EquipmentSlotsCompact extends StatelessWidget {
  const EquipmentSlotsCompact({super.key});

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
  ];

  @override
  Widget build(BuildContext context) {
    final equipment = context.state.equipment;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final slot in _displaySlots)
          _CompactSlotCell(slot: slot, item: equipment.gearInSlot(slot)),
      ],
    );
  }
}

class _CompactSlotCell extends StatelessWidget {
  const _CompactSlotCell({required this.slot, required this.item});

  final EquipmentSlot slot;
  final Item? item;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item?.name ?? '${slot.displayName} (Empty)',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: item != null
              ? Style.containerBackgroundFilled
              : Style.containerBackgroundEmpty,
          border: Border.all(
            color: item != null
                ? Style.cellBorderColorSuccess
                : Style.iconColorDefault,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: item != null
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: ItemImage(item: item!),
              )
            : Center(
                child: Text(
                  slot.displayName.substring(0, 1),
                  style: const TextStyle(
                    color: Style.textColorSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
      ),
    );
  }
}
