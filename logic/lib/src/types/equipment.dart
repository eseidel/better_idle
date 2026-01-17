import 'dart:math';

import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// Number of food slots available for equipment.
const int foodSlotCount = 3;

/// Result of applying the death penalty.
/// Contains the updated equipment and what was lost (if anything).
@immutable
class DeathPenaltyResult {
  const DeathPenaltyResult({
    required this.equipment,
    required this.slotRolled,
    this.itemLost,
  });

  /// The updated equipment after the death penalty.
  final Equipment equipment;

  /// The slot that was randomly selected.
  final EquipmentSlot slotRolled;

  /// The item stack that was lost, or null if the slot was empty.
  final ItemStack? itemLost;

  /// True if the player was lucky and lost nothing.
  bool get wasLucky => itemLost == null;
}

/// Represents the player's equipped items.
@immutable
class Equipment {
  const Equipment({
    required this.foodSlots,
    required this.selectedFoodSlot,
    this.gearSlots = const {},
    this.summonCounts = const {},
  });

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

    // Parse gear slots
    final gearSlotsJson = json['gearSlots'] as Map<String, dynamic>?;
    final gearSlots = <EquipmentSlot, Item>{};
    if (gearSlotsJson != null) {
      for (final entry in gearSlotsJson.entries) {
        final slot = EquipmentSlot.fromJson(entry.key);
        final itemId = MelvorId.fromJson(entry.value as String);
        gearSlots[slot] = items.byId(itemId);
      }
    }

    // Parse summon counts (charges for summoning tablets)
    final summonCountsJson = json['summonCounts'] as Map<String, dynamic>?;
    final summonCounts = <EquipmentSlot, int>{};
    if (summonCountsJson != null) {
      for (final entry in summonCountsJson.entries) {
        final slot = EquipmentSlot.fromJson(entry.key);
        summonCounts[slot] = entry.value as int;
      }
    }

    return Equipment(
      foodSlots: foodSlots,
      selectedFoodSlot: json['selectedFoodSlot'] as int? ?? 0,
      gearSlots: gearSlots,
      summonCounts: summonCounts,
    );
  }

  const Equipment.empty()
    : foodSlots = const [null, null, null],
      selectedFoodSlot = 0,
      gearSlots = const {},
      summonCounts = const {};

  static Equipment? maybeFromJson(ItemRegistry items, dynamic json) {
    if (json == null) return null;
    return Equipment.fromJson(items, json as Map<String, dynamic>);
  }

  /// The food items equipped in each slot. Null means empty slot.
  final List<ItemStack?> foodSlots;

  /// The currently selected food slot index (0-2).
  final int selectedFoodSlot;

  /// The gear items equipped in each slot. Keys are slot types, values are
  /// the equipped items. Empty slots are not present in the map.
  final Map<EquipmentSlot, Item> gearSlots;

  /// The counts for summoning tablet slots (charges remaining).
  /// Only populated for summon1/summon2 slots. Other slots always have count 1.
  final Map<EquipmentSlot, int> summonCounts;

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
      'gearSlots': gearSlots.map(
        (slot, item) => MapEntry(slot.toJson(), item.id.toJson()),
      ),
      if (summonCounts.isNotEmpty)
        'summonCounts': summonCounts.map(
          (slot, count) => MapEntry(slot.toJson(), count),
        ),
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

  /// Returns the item currently equipped in the given slot, or null if empty.
  Item? gearInSlot(EquipmentSlot slot) => gearSlots[slot];

  /// Returns true if the item can be equipped in the given slot.
  /// An item can be equipped if the slot is empty or will be swapped.
  bool canEquipGear(Item item, EquipmentSlot slot) {
    return item.canEquipInSlot(slot);
  }

  /// Equips an item in the given slot, returning the updated equipment
  /// and any item that was previously in that slot (or null if empty).
  /// Throws if the item cannot be equipped in that slot.
  (Equipment, Item?) equipGear(Item item, EquipmentSlot slot) {
    if (!item.canEquipInSlot(slot)) {
      throw ArgumentError(
        'Cannot equip ${item.name} in $slot slot. '
        'Valid slots: ${item.validSlots.map((s) => s.jsonName).join(', ')}',
      );
    }

    final previousItem = gearSlots[slot];
    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots);
    newGearSlots[slot] = item;

    return (copyWith(gearSlots: newGearSlots), previousItem);
  }

  /// Removes an item from the given slot, returning the item and updated
  /// equipment. Returns null if the slot is empty.
  (Item, Equipment)? unequipGear(EquipmentSlot slot) {
    final item = gearSlots[slot];
    if (item == null) return null;

    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots)..remove(slot);

    return (item, copyWith(gearSlots: newGearSlots));
  }

  /// Applies the death penalty by randomly selecting an equipment slot
  /// and removing any item in that slot.
  ///
  /// Per Melvor Idle rules:
  /// - A random equipment slot is selected (not food slots)
  /// - If the slot has an item, it is lost forever
  /// - If the slot is empty, nothing is lost ("Luck was on your side")
  /// - For ammo (quiver) or summons, the entire stack is lost
  DeathPenaltyResult applyDeathPenalty(Random random) {
    // Roll a random equipment slot (excluding food slots)
    const allSlots = EquipmentSlot.values;
    final slotIndex = random.nextInt(allSlots.length);
    final slot = allSlots[slotIndex];

    // Check if there's an item in this slot
    final item = gearSlots[slot];
    if (item == null) {
      // Lucky! Nothing equipped in this slot
      return DeathPenaltyResult(equipment: this, slotRolled: slot);
    }

    // Remove the item from equipment (it's lost forever)
    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots)..remove(slot);

    // For stack slots (summon or quiver), include the full stack count
    final count = slot.isStackSlot ? (summonCounts[slot] ?? 1) : 1;
    final newSummonCounts = slot.isStackSlot
        ? (Map<EquipmentSlot, int>.from(summonCounts)..remove(slot))
        : summonCounts;

    return DeathPenaltyResult(
      equipment: copyWith(
        gearSlots: newGearSlots,
        summonCounts: newSummonCounts,
      ),
      slotRolled: slot,
      itemLost: ItemStack(item, count: count),
    );
  }

  /// Returns the count for a summon slot, or 0 if not equipped.
  int summonCountInSlot(EquipmentSlot slot) => summonCounts[slot] ?? 0;

  /// Returns the stack count for a slot that tracks stacks (summon or quiver).
  /// Returns 0 if nothing is equipped in the slot.
  int stackCountInSlot(EquipmentSlot slot) => summonCounts[slot] ?? 0;

  /// Equips a stacked item (ammo or summoning tablet) in the given slot.
  /// Returns the updated equipment and any previously equipped item stack.
  /// Throws ArgumentError if the slot doesn't support stacking.
  (Equipment, ItemStack?) equipStackedItem(
    Item item,
    EquipmentSlot slot,
    int count,
  ) {
    if (!slot.isStackSlot) {
      throw ArgumentError('$slot does not support stacked items');
    }
    if (!item.canEquipInSlot(slot)) {
      throw ArgumentError(
        'Cannot equip ${item.name} in $slot slot. '
        'Valid slots: ${item.validSlots.map((s) => s.jsonName).join(', ')}',
      );
    }

    final previousItem = gearSlots[slot];
    final previousCount = summonCounts[slot] ?? 0;
    ItemStack? previousStack;
    if (previousItem != null && previousCount > 0) {
      previousStack = ItemStack(previousItem, count: previousCount);
    }

    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots);
    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts);
    newGearSlots[slot] = item;
    newSummonCounts[slot] = count;

    return (
      copyWith(gearSlots: newGearSlots, summonCounts: newSummonCounts),
      previousStack,
    );
  }

  /// Adds to an existing stacked item in the given slot.
  /// The item must match what's already equipped.
  /// Returns the updated equipment.
  /// Throws ArgumentError if the slot doesn't support stacking or item doesn't
  /// match.
  Equipment addToStackedItem(Item item, EquipmentSlot slot, int count) {
    if (!slot.isStackSlot) {
      throw ArgumentError('$slot does not support stacked items');
    }
    final currentItem = gearSlots[slot];
    if (currentItem == null) {
      throw ArgumentError('No item equipped in $slot slot');
    }
    if (currentItem != item) {
      throw ArgumentError(
        'Cannot add ${item.name} to $slot slot: '
        '${currentItem.name} is already equipped',
      );
    }

    final currentCount = summonCounts[slot] ?? 0;
    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts);
    newSummonCounts[slot] = currentCount + count;

    return copyWith(summonCounts: newSummonCounts);
  }

  /// Unequips a stacked item from the given slot.
  /// Returns the item stack and updated equipment, or null if slot is empty.
  /// Throws ArgumentError if the slot doesn't support stacking.
  (ItemStack, Equipment)? unequipStackedItem(EquipmentSlot slot) {
    if (!slot.isStackSlot) {
      throw ArgumentError('$slot does not support stacked items');
    }

    final item = gearSlots[slot];
    if (item == null) return null;

    final count = summonCounts[slot] ?? 1;
    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots)..remove(slot);
    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts)
      ..remove(slot);

    return (
      ItemStack(item, count: count),
      copyWith(gearSlots: newGearSlots, summonCounts: newSummonCounts),
    );
  }

  /// Equips a summoning tablet in the given slot with the specified count.
  /// Returns the updated equipment and any previously equipped tablet stack.
  (Equipment, ItemStack?) equipSummonTablet(
    Item item,
    EquipmentSlot slot,
    int count,
  ) {
    if (!slot.isSummonSlot) {
      throw ArgumentError('$slot is not a summon slot');
    }
    if (!item.isSummonTablet) {
      throw ArgumentError('${item.name} is not a summoning tablet');
    }
    if (!item.canEquipInSlot(slot)) {
      throw ArgumentError(
        'Cannot equip ${item.name} in $slot slot. '
        'Valid slots: ${item.validSlots.map((s) => s.jsonName).join(', ')}',
      );
    }

    final previousItem = gearSlots[slot];
    final previousCount = summonCounts[slot] ?? 0;
    ItemStack? previousStack;
    if (previousItem != null && previousCount > 0) {
      previousStack = ItemStack(previousItem, count: previousCount);
    }

    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots);
    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts);
    newGearSlots[slot] = item;
    newSummonCounts[slot] = count;

    return (
      copyWith(gearSlots: newGearSlots, summonCounts: newSummonCounts),
      previousStack,
    );
  }

  /// Unequips a summoning tablet from the given slot.
  /// Returns the tablet stack and updated equipment, or null if slot is empty.
  (ItemStack, Equipment)? unequipSummonTablet(EquipmentSlot slot) {
    if (!slot.isSummonSlot) {
      throw ArgumentError('$slot is not a summon slot');
    }

    final item = gearSlots[slot];
    if (item == null) return null;

    final count = summonCounts[slot] ?? 1;
    final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots)..remove(slot);
    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts)
      ..remove(slot);

    return (
      ItemStack(item, count: count),
      copyWith(gearSlots: newGearSlots, summonCounts: newSummonCounts),
    );
  }

  /// Consumes charges from a summon slot. Returns updated equipment.
  /// If charges reach 0, the tablet is unequipped.
  Equipment consumeSummonCharges(EquipmentSlot slot, int amount) {
    if (!slot.isSummonSlot) {
      throw ArgumentError('$slot is not a summon slot');
    }

    final currentCount = summonCounts[slot] ?? 0;
    if (currentCount <= 0) return this;

    final newCount = currentCount - amount;
    if (newCount <= 0) {
      // Charges depleted - unequip the tablet
      final newGearSlots = Map<EquipmentSlot, Item>.from(gearSlots)
        ..remove(slot);
      final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts)
        ..remove(slot);
      return copyWith(gearSlots: newGearSlots, summonCounts: newSummonCounts);
    }

    final newSummonCounts = Map<EquipmentSlot, int>.from(summonCounts);
    newSummonCounts[slot] = newCount;
    return copyWith(summonCounts: newSummonCounts);
  }

  Equipment copyWith({
    List<ItemStack?>? foodSlots,
    int? selectedFoodSlot,
    Map<EquipmentSlot, Item>? gearSlots,
    Map<EquipmentSlot, int>? summonCounts,
  }) {
    return Equipment(
      foodSlots: foodSlots ?? this.foodSlots,
      selectedFoodSlot: selectedFoodSlot ?? this.selectedFoodSlot,
      gearSlots: gearSlots ?? this.gearSlots,
      summonCounts: summonCounts ?? this.summonCounts,
    );
  }
}
