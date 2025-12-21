import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// Number of food slots available for equipment.
const int foodSlotCount = 3;

/// Represents the player's equipped items.
@immutable
class Equipment {
  const Equipment({required this.foodSlots, required this.selectedFoodSlot});

  const Equipment.empty()
    : foodSlots = const [null, null, null],
      selectedFoodSlot = 0;

  static Equipment? maybeFromJson(ItemRegistry items, dynamic json) {
    if (json == null) return null;
    return Equipment.fromJson(items, json as Map<String, dynamic>);
  }

  factory Equipment.fromJson(ItemRegistry items, Map<String, dynamic> json) {
    final foodSlotsJson = json['foodSlots'] as List<dynamic>?;
    final foodSlots = foodSlotsJson != null
        ? List<ItemStack?>.generate(foodSlotCount, (i) {
            if (i >= foodSlotsJson.length) return null;
            final slotJson = foodSlotsJson[i];
            if (slotJson == null) return null;
            final map = slotJson as Map<String, dynamic>;
            final id = MelvorId.fromJson(map['item'] as String);
            final item = items.byId(id);
            return ItemStack(item, count: map['count'] as int);
          })
        : const [null, null, null];

    return Equipment(
      foodSlots: foodSlots,
      selectedFoodSlot: json['selectedFoodSlot'] as int? ?? 0,
    );
  }

  /// The food items equipped in each slot. Null means empty slot.
  final List<ItemStack?> foodSlots;

  /// The currently selected food slot index (0-2).
  final int selectedFoodSlot;

  Map<String, dynamic> toJson() {
    return {
      'foodSlots': foodSlots
          .map(
            (stack) => stack != null
                ? {'item': stack.item.id.toJson(), 'count': stack.count}
                : null,
          )
          .toList(),
      'selectedFoodSlot': selectedFoodSlot,
    };
  }

  /// Gets the currently selected food stack, or null if the slot is empty.
  ItemStack? get selectedFood {
    if (selectedFoodSlot < 0 || selectedFoodSlot >= foodSlots.length) {
      return null;
    }
    return foodSlots[selectedFoodSlot];
  }

  /// Returns the index of an empty food slot, or -1 if all slots are full.
  int get firstEmptyFoodSlot {
    for (var i = 0; i < foodSlots.length; i++) {
      if (foodSlots[i] == null) return i;
    }
    return -1;
  }

  /// Returns the index of a slot containing the given item, or -1 if not found.
  int foodSlotWithItem(Item item) {
    for (var i = 0; i < foodSlots.length; i++) {
      if (foodSlots[i]?.item == item) return i;
    }
    return -1;
  }

  /// Returns true if the item can be equipped (either already equipped or has
  /// empty slot).
  bool canEquipFood(Item item) {
    if (!item.isConsumable) return false;
    return foodSlotWithItem(item) >= 0 || firstEmptyFoodSlot >= 0;
  }

  /// Adds food to equipment. If the item is already in a slot, adds to that
  /// stack. Otherwise uses the first empty slot.
  Equipment equipFood(ItemStack stack) {
    if (!stack.item.isConsumable) {
      throw ArgumentError(
        'Cannot equip non-consumable item: ${stack.item.name}',
      );
    }

    final existingSlot = foodSlotWithItem(stack.item);
    final newFoodSlots = List<ItemStack?>.from(foodSlots);

    if (existingSlot >= 0) {
      // Add to existing stack
      final existing = newFoodSlots[existingSlot]!;
      newFoodSlots[existingSlot] = existing.copyWith(
        count: existing.count + stack.count,
      );
    } else {
      // Find empty slot
      final emptySlot = firstEmptyFoodSlot;
      if (emptySlot < 0) {
        throw StateError('No empty food slot available');
      }
      newFoodSlots[emptySlot] = stack;
    }

    return copyWith(foodSlots: newFoodSlots);
  }

  /// Consumes one item from the selected food slot.
  /// Returns the updated equipment, or null if no food is selected.
  Equipment? consumeSelectedFood() {
    final food = selectedFood;
    if (food == null) return null;

    final newFoodSlots = List<ItemStack?>.from(foodSlots);
    if (food.count <= 1) {
      // Last item - clear the slot
      newFoodSlots[selectedFoodSlot] = null;
    } else {
      // Decrement count
      newFoodSlots[selectedFoodSlot] = food.copyWith(count: food.count - 1);
    }

    return copyWith(foodSlots: newFoodSlots);
  }

  /// Removes food from a specific slot, returning the item stack and updated
  /// equipment. Returns null if the slot is empty or index is invalid.
  (ItemStack, Equipment)? unequipFood(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= foodSlots.length) {
      return null;
    }
    final food = foodSlots[slotIndex];
    if (food == null) return null;

    final newFoodSlots = List<ItemStack?>.from(foodSlots);
    newFoodSlots[slotIndex] = null;

    return (food, copyWith(foodSlots: newFoodSlots));
  }

  Equipment copyWith({List<ItemStack?>? foodSlots, int? selectedFoodSlot}) {
    return Equipment(
      foodSlots: foodSlots ?? this.foodSlots,
      selectedFoodSlot: selectedFoodSlot ?? this.selectedFoodSlot,
    );
  }
}
