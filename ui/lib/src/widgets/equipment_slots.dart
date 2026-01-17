import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Displays the player's equipped gear in a simple list format.
class EquipmentSlotsList extends StatelessWidget {
  const EquipmentSlotsList({super.key});

  /// The slots to display (excludes summons/enhancements for now).
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
    final state = context.state;
    final slotDef = state.registries.equipmentSlots[slot];
    final slotName = slotDef?.emptyName ?? slot.jsonName;
    final isLocked = !state.isSlotUnlocked(slot);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 32,
        height: 32,
        child: isLocked
            ? Container(
                decoration: BoxDecoration(
                  color: Style.containerBackgroundEmpty,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Style.iconColorDefault),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Style.textColorSecondary,
                ),
              )
            : item != null
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
        isLocked ? '$slotName (Locked)' : (item?.name ?? slotName),
        style: TextStyle(
          color: isLocked || item == null ? Style.textColorSecondary : null,
          fontStyle: isLocked || item == null ? FontStyle.italic : null,
        ),
      ),
      subtitle: isLocked
          ? const Text('Complete "Into the Mist"')
          : (item != null ? null : Text(slotName)),
      trailing: item != null && !isLocked
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
    final state = context.state;
    final equipment = state.equipment;

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
    final slotDef = context.state.registries.equipmentSlots[slot];
    final slotName = slotDef?.emptyName ?? slot.jsonName;
    return Tooltip(
      message: item?.name ?? '$slotName (Empty)',
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
                  slotName.substring(0, 1),
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

/// A dialog that displays equipment slots in a visual grid layout
/// matching the Melvor Idle equipment screen.
class EquipmentGridDialog extends StatelessWidget {
  const EquipmentGridDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Equipment'),
      content: const EquipmentGrid(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A grid view of equipment slots positioned according to their gridPosition.
class EquipmentGrid extends StatelessWidget {
  const EquipmentGrid({super.key});

  static const double _cellSize = 56;
  static const double _cellSpacing = 4;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final slotRegistry = state.registries.equipmentSlots;
    final equipment = state.equipment;

    // Find grid dimensions from slot positions.
    var maxCol = 0;
    var maxRow = 0;
    for (final slotDef in slotRegistry.all) {
      final pos = slotDef.gridPosition;
      if (pos.col > maxCol) maxCol = pos.col;
      if (pos.row > maxRow) maxRow = pos.row;
    }

    // Build a map of grid positions to slot definitions.
    final positionMap = <(int, int), EquipmentSlotDef>{};
    for (final slotDef in slotRegistry.all) {
      final pos = slotDef.gridPosition;
      positionMap[(pos.col, pos.row)] = slotDef;
    }

    final gridWidth = (maxCol + 1) * (_cellSize + _cellSpacing) - _cellSpacing;
    final gridHeight = (maxRow + 1) * (_cellSize + _cellSpacing) - _cellSpacing;

    return SizedBox(
      width: gridWidth,
      height: gridHeight,
      child: Stack(
        children: [
          for (var row = 0; row <= maxRow; row++)
            for (var col = 0; col <= maxCol; col++)
              if (positionMap.containsKey((col, row)))
                Positioned(
                  left: col * (_cellSize + _cellSpacing),
                  top: row * (_cellSize + _cellSpacing),
                  child: _GridSlotCell(
                    slotDef: positionMap[(col, row)]!,
                    item: equipment.gearInSlot(positionMap[(col, row)]!.slot),
                    size: _cellSize,
                  ),
                ),
        ],
      ),
    );
  }
}

class _GridSlotCell extends StatelessWidget {
  const _GridSlotCell({
    required this.slotDef,
    required this.item,
    required this.size,
  });

  final EquipmentSlotDef slotDef;
  final Item? item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isLocked = !state.isSlotUnlocked(slotDef.slot);

    return Tooltip(
      message: isLocked
          ? '${slotDef.emptyName} (Locked)'
          : (item?.name ?? '${slotDef.emptyName} (Empty)'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: item != null
              ? Style.containerBackgroundFilled
              : Style.containerBackgroundEmpty,
          border: Border.all(
            color: isLocked
                ? Style.textColorSecondary
                : item != null
                ? Style.cellBorderColorSuccess
                : Style.iconColorDefault,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: isLocked
            ? const Icon(
                Icons.lock_outline,
                size: 20,
                color: Style.textColorSecondary,
              )
            : item != null
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: ItemImage(item: item!, size: size - 8),
              )
            : CachedImage(assetPath: slotDef.emptyMedia, size: size - 8),
      ),
    );
  }
}
