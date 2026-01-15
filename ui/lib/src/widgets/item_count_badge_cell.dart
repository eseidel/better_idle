import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A small square widget displaying an item icon with a count badge.
///
/// Shows an item icon centered on a background with a border. The count is
/// displayed in a pill-shaped badge overlapping the bottom border.
///
/// The border color indicates whether the player has enough of the item:
/// - Green border when [hasEnough] is true
/// - Red border when [hasEnough] is false
/// - Default grey border when [hasEnough] is null
class ItemCountBadgeCell extends StatelessWidget {
  const ItemCountBadgeCell({
    required this.item,
    required this.count,
    this.hasEnough,
    this.inradius = TextBadgeCell.defaultInradius,
    super.key,
  });

  final Item item;
  final int count;
  final bool? hasEnough;
  final double inradius;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (hasEnough) {
      true => Style.successColor,
      false => Style.errorColor,
      null => null,
    };

    // Icon size is roughly 60% of the inradius
    final iconSize = inradius * 0.6;

    return CountBadgeCell(
      inradius: inradius,
      backgroundColor: Style.xpBadgeBackgroundColor,
      borderColor: borderColor,
      count: count,
      child: Center(
        child: ItemImage(item: item, size: iconSize),
      ),
    );
  }
}

/// A row of [ItemCountBadgeCell] widgets for displaying item requirements.
///
/// Use [ItemCountBadgesRow.required] to show required items without inventory
/// comparison, or [ItemCountBadgesRow.inventory] to show inventory counts with
/// color-coded borders indicating whether the player has enough.
class ItemCountBadgesRow extends StatelessWidget {
  const ItemCountBadgesRow._({
    required this.items,
    required this.showInventory,
    this.onItemTap,
    super.key,
  });

  /// Creates a row showing required item counts (no inventory comparison).
  const ItemCountBadgesRow.required({
    required Map<MelvorId, int> items,
    void Function(Item item)? onItemTap,
    Key? key,
  }) : this._(
         items: items,
         showInventory: false,
         onItemTap: onItemTap,
         key: key,
       );

  /// Creates a row showing inventory counts with color-coded borders.
  const ItemCountBadgesRow.inventory({
    required Map<MelvorId, int> items,
    void Function(Item item)? onItemTap,
    Key? key,
  }) : this._(
         items: items,
         showInventory: true,
         onItemTap: onItemTap,
         key: key,
       );

  final Map<MelvorId, int> items;
  final bool showInventory;

  /// Optional callback when an item is tapped.
  final void Function(Item item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'None',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    final state = context.state;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.entries.map((entry) {
        final item = state.registries.items.byId(entry.key);
        final requiredCount = entry.value;

        Widget cell;
        if (showInventory) {
          final inventoryCount = state.inventory.countOfItem(item);
          final hasEnough = inventoryCount >= requiredCount;
          cell = ItemCountBadgeCell(
            item: item,
            count: inventoryCount,
            hasEnough: hasEnough,
          );
        } else {
          cell = ItemCountBadgeCell(item: item, count: requiredCount);
        }

        if (onItemTap != null) {
          return GestureDetector(onTap: () => onItemTap!(item), child: cell);
        }
        return cell;
      }).toList(),
    );
  }
}
