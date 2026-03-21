import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

class CompactFoodSelector extends StatelessWidget {
  const CompactFoodSelector({
    required this.equipment,
    required this.canEat,
    super.key,
  });

  final Equipment equipment;
  final bool canEat;

  @override
  Widget build(BuildContext context) {
    final selectedSlot = equipment.selectedFoodSlot;
    final selectedFood = equipment.selectedFood;

    // Find previous/next slots with food for navigation
    int? findPrevSlot() {
      for (var i = selectedSlot - 1; i >= 0; i--) {
        if (equipment.foodSlots[i] != null) return i;
      }
      // Wrap around
      for (var i = foodSlotCount - 1; i > selectedSlot; i--) {
        if (equipment.foodSlots[i] != null) return i;
      }
      return null;
    }

    int? findNextSlot() {
      for (var i = selectedSlot + 1; i < foodSlotCount; i++) {
        if (equipment.foodSlots[i] != null) return i;
      }
      // Wrap around
      for (var i = 0; i < selectedSlot; i++) {
        if (equipment.foodSlots[i] != null) return i;
      }
      return null;
    }

    final prevSlot = findPrevSlot();
    final nextSlot = findNextSlot();
    final hasMultipleFood = prevSlot != null && prevSlot != selectedSlot;

    return Row(
      children: [
        // Left arrow
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: hasMultipleFood
              ? () =>
                    context.dispatch(SelectFoodSlotAction(slotIndex: prevSlot))
              : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        // Food display
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selectedFood != null
                  ? Style.containerBackgroundFilled
                  : Style.containerBackgroundEmpty,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Style.iconColorDefault),
            ),
            child: selectedFood != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ItemImage(item: selectedFood.item, size: 24),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          selectedFood.item.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'x${approximateCountString(selectedFood.count)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Style.textColorSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => context.dispatch(
                          UnequipFoodAction(slotIndex: selectedSlot),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Style.textColorSecondary,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Text(
                      'No food equipped',
                      style: TextStyle(
                        fontSize: 12,
                        color: Style.textColorSecondary,
                      ),
                    ),
                  ),
          ),
        ),
        // Right arrow
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: hasMultipleFood
              ? () =>
                    context.dispatch(SelectFoodSlotAction(slotIndex: nextSlot!))
              : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: 4),
        // Eat button
        SizedBox(
          height: 36,
          child: ElevatedButton(
            onPressed: canEat ? () => context.dispatch(EatFoodAction()) : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              selectedFood != null
                  ? 'Eat +${selectedFood.item.healsFor}'
                  : 'Eat',
            ),
          ),
        ),
      ],
    );
  }
}
