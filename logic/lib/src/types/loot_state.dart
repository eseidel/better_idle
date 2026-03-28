import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

/// Maximum number of stacks in the loot container.
const int maxLootStacks = 100;

/// State for combat loot container.
///
/// Items dropped from combat go here first before being collected to inventory.
/// Most items do NOT stack - each drop creates a new entry.
/// Exception: Bones stack with existing bones of the same type.
@immutable
class LootState {
  const LootState({this.stacks = const []});

  const LootState.empty() : stacks = const [];

  factory LootState.fromJson(ItemRegistry items, Map<String, dynamic> json) {
    final stacksJson = json['stacks'] as List<dynamic>? ?? [];
    final stacks = stacksJson.map((s) {
      final map = s as Map<String, dynamic>;
      final itemId = MelvorId.fromJson(map['itemId'] as String);
      final count = map['count'] as int;
      return ItemStack(items.byId(itemId), count: count);
    }).toList();
    return LootState(stacks: stacks);
  }

  /// Deserializes a [LootState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static LootState? maybeFromJson(ItemRegistry items, dynamic json) {
    if (json == null) return null;
    return LootState.fromJson(items, json as Map<String, dynamic>);
  }

  /// The list of item stacks in the loot container.
  /// Items are ordered by drop time (oldest first).
  final List<ItemStack> stacks;

  bool get isEmpty => stacks.isEmpty;
  bool get isNotEmpty => stacks.isNotEmpty;
  bool get isFull => stacks.length >= maxLootStacks;
  int get stackCount => stacks.length;

  /// Adds an item to loot. Bones always stack; other items stack only when
  /// [allowStacking] is true (from the allowLootContainerStacking modifier).
  /// Returns (newState, lostItems) where lostItems are items that couldn't fit.
  (LootState, List<ItemStack>) addItem(
    ItemStack stack, {
    required bool isBones,
    bool allowStacking = false,
  }) {
    final newStacks = List<ItemStack>.from(stacks);
    final lostItems = <ItemStack>[];

    if (isBones || allowStacking) {
      // Stack with existing items of same type
      final existingIndex = newStacks.indexWhere(
        (s) => s.item.id == stack.item.id,
      );
      if (existingIndex >= 0) {
        final existing = newStacks[existingIndex];
        newStacks[existingIndex] = existing.copyWith(
          count: existing.count + stack.count,
        );
        return (LootState(stacks: newStacks), lostItems);
      }
    }

    // Non-stacking or new item type - add as new stack
    if (newStacks.length >= maxLootStacks) {
      // FIFO: remove oldest (first) item
      lostItems.add(newStacks.removeAt(0));
    }
    newStacks.add(stack);
    return (LootState(stacks: newStacks), lostItems);
  }

  /// Returns all stacks for collection.
  List<ItemStack> get allStacks => List.from(stacks);

  Map<String, dynamic> toJson() {
    if (isEmpty) {
      return {};
    }
    return {
      'stacks': stacks
          .map((s) => {'itemId': s.item.id.toJson(), 'count': s.count})
          .toList(),
    };
  }
}
