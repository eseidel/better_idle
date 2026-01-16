import 'dart:math';

import 'package:async_redux/async_redux.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:logic/logic.dart';

export 'package:async_redux/async_redux.dart';

class UpdateActivityProgressAction extends ReduxAction<GlobalState> {
  UpdateActivityProgressAction({required this.now});
  final DateTime now;

  /// Set by reduce() - ticks until next scheduled event.
  /// Used by GameLoop to schedule the next wake time.
  Tick? ticksUntilNextEvent;

  @override
  GlobalState reduce() {
    final ticks = ticksFromDuration(now.difference(state.updatedAt));
    final builder = StateUpdateBuilder(state);
    final random = Random();
    ticksUntilNextEvent = consumeTicks(builder, ticks, random: random);

    final changes = builder.changes;
    final newState = builder.build();
    if (changes.isEmpty) {
      return newState;
    }

    // If timeAway exists, accumulate changes into it for the dialog to display.
    // The dialog is showing these changes, so don't show toast.
    // If timeAway is null, show toast normally.
    final existingTimeAway = state.timeAway;
    if (existingTimeAway != null) {
      // timeAway should never be empty
      assert(
        !existingTimeAway.changes.isEmpty,
        'timeAway should never be empty',
      );
      // so if it exists, the dialog is showing and we should suppress toasts.
      final timeAway = existingTimeAway.mergeChanges(changes);
      // Don't show toast - dialog shows changes
      return newState.copyWith(timeAway: timeAway);
    } else {
      // No timeAway - show toast normally
      toastService.showToast(changes);

      // Show death dialog if player died during this tick
      if (changes.deathCount > 0) {
        toastService.showDeath(changes.lostOnDeath);
      }

      return newState;
    }
  }
}

class ToggleActionAction extends ReduxAction<GlobalState> {
  ToggleActionAction({required this.action});
  final Action action;
  @override
  GlobalState? reduce() {
    // If stunned, do nothing (UI should prevent this, but be safe)
    if (state.isStunned) {
      return null;
    }
    // If the action is already running, stop it
    if (state.activeAction?.id == action.id) {
      return state.clearAction();
    }
    // Otherwise, start this action (stops any other active action).
    final random = Random();
    return state.startAction(action, random: random);
  }
}

/// Sets the selected recipe index for an action with alternative costs.
class SetRecipeAction extends ReduxAction<GlobalState> {
  SetRecipeAction({required this.actionId, required this.recipeIndex});
  final ActionId actionId;
  final int recipeIndex;

  @override
  GlobalState reduce() {
    return state.setRecipeIndex(actionId, recipeIndex);
  }
}

/// Advances the game by a specified number of ticks and returns the changes.
/// Unlike UpdateActivityProgressAction, this does not show toasts.
class DebugAdvanceTicksAction extends ReduxAction<GlobalState> {
  DebugAdvanceTicksAction({required this.ticks});
  final Tick ticks;

  /// The time away that occurred during this advancement.
  late TimeAway timeAway;

  @override
  GlobalState reduce() {
    final random = Random();
    final (timeAway, newState) = consumeManyTicks(state, ticks, random: random);
    this.timeAway = timeAway;
    return newState;
  }
}

/// Calculates time away from pause and processes it,
/// merging with existing timeAway if present.
class ResumeFromPauseAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    final now = DateTime.timestamp();
    final duration = now.difference(state.updatedAt);
    final ticks = ticksFromDuration(duration);
    final random = Random();
    final (newTimeAway, newState) = consumeManyTicks(
      state,
      ticks,
      endTime: now,
      random: random,
    );
    final timeAway = newTimeAway.maybeMergeInto(state.timeAway);
    // Set timeAway on state if it has changes - empty timeAway should be null
    return newState.copyWith(
      timeAway: timeAway.changes.isEmpty ? null : timeAway,
    );
  }
}

/// Clears the welcome back dialog by removing timeAway from state.
class DismissWelcomeBackDialogAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return state.clearTimeAway();
  }
}

/// Sells a specified quantity of an item.
class SellItemAction extends ReduxAction<GlobalState> {
  SellItemAction({required this.item, required this.count});
  final Item item;
  final int count;

  @override
  GlobalState reduce() {
    return state.sellItem(ItemStack(item, count: count));
  }
}

/// Sells multiple item stacks at once.
class SellMultipleItemsAction extends ReduxAction<GlobalState> {
  SellMultipleItemsAction({required this.stacks});
  final List<ItemStack> stacks;

  @override
  GlobalState reduce() {
    var newState = state;
    for (final stack in stacks) {
      newState = newState.sellItem(stack);
    }
    return newState;
  }
}

/// Purchases a shop item (skill upgrade or other purchase).
class PurchaseShopItemAction extends ReduxAction<GlobalState> {
  PurchaseShopItemAction({required this.purchaseId});
  final MelvorId purchaseId;

  @override
  GlobalState reduce() {
    final shopRegistry = state.registries.shop;
    final purchase = shopRegistry.byId(purchaseId);

    if (purchase == null) {
      throw Exception('Unknown shop purchase: $purchaseId');
    }

    // Check buy limit
    final currentCount = state.shop.purchaseCount(purchaseId);
    if (!purchase.isUnlimited && currentCount >= purchase.buyLimit) {
      throw Exception('Already purchased maximum of ${purchase.name}');
    }

    // Check unlock requirements
    for (final req in purchase.unlockRequirements) {
      if (req is ShopPurchaseRequirement) {
        if (state.shop.purchaseCount(req.purchaseId) < req.count) {
          throw Exception('Must own prerequisite purchase first');
        }
      } else if (req is DungeonCompletionRequirement) {
        if (state.dungeonCompletionCount(req.dungeonId) < req.count) {
          throw Exception(
            'Must complete dungeon ${req.dungeonId.name} '
            '${req.count} time(s)',
          );
        }
      }
    }

    // Check purchase requirements (skill levels and dungeon completions)
    for (final req in purchase.purchaseRequirements) {
      if (req is SkillLevelRequirement) {
        final skillLevel = state.skillState(req.skill).skillLevel;
        if (skillLevel < req.level) {
          throw Exception('Requires ${req.skill.name} level ${req.level}');
        }
      } else if (req is DungeonCompletionRequirement) {
        if (state.dungeonCompletionCount(req.dungeonId) < req.count) {
          throw Exception(
            'Must complete dungeon ${req.dungeonId.name} '
            '${req.count} time(s)',
          );
        }
      }
    }

    // Check inventory space for granted items before processing
    final grantedItems = purchase.contains.items;
    if (grantedItems.isNotEmpty) {
      final capacity = state.inventoryCapacity;
      for (final grantedItem in grantedItems) {
        final item = state.registries.items.byId(grantedItem.itemId);
        if (!state.inventory.canAdd(item, capacity: capacity)) {
          throw Exception('Not enough bank space for ${item.name}');
        }
      }
    }

    // Calculate and apply currency costs
    var newState = state;
    final currencyCosts = purchase.cost.currencyCosts(
      bankSlotsPurchased: state.shop.bankSlotsPurchased,
    );
    for (final (currency, amount) in currencyCosts) {
      final balance = newState.currency(currency);
      if (balance < amount) {
        throw Exception(
          'Not enough ${currency.abbreviation}. Need $amount, have $balance',
        );
      }
      newState = newState.addCurrency(currency, -amount);
    }

    // Check and apply item costs
    final itemCosts = purchase.cost.items;
    var newInventory = newState.inventory;
    for (final itemCost in itemCosts) {
      final item = state.registries.items.byId(itemCost.itemId);
      final count = newInventory.countOfItem(item);
      if (count < itemCost.quantity) {
        throw Exception(
          'Not enough ${item.name}. Need ${itemCost.quantity}, have $count',
        );
      }
      newInventory = newInventory.removing(
        ItemStack(item, count: itemCost.quantity),
      );
    }

    // Add items granted by the purchase
    for (final grantedItem in purchase.contains.items) {
      final item = state.registries.items.byId(grantedItem.itemId);
      newInventory = newInventory.adding(
        ItemStack(item, count: grantedItem.quantity),
      );
    }

    // Handle itemCharges purchases
    var newItemCharges = newState.itemCharges;
    final itemCharges = purchase.contains.itemCharges;
    if (itemCharges != null) {
      // Get the item to receive charges
      final chargeItem = state.registries.items.byId(itemCharges.itemId);

      // If player doesn't have the item, add it to inventory first
      if (newInventory.countOfItem(chargeItem) == 0) {
        newInventory = newInventory.adding(ItemStack(chargeItem, count: 1));
      }

      // Add charges to the item
      newItemCharges = Map<MelvorId, int>.from(newItemCharges);
      newItemCharges[itemCharges.itemId] =
          (newItemCharges[itemCharges.itemId] ?? 0) + itemCharges.quantity;
    }

    // Apply purchase
    return newState.copyWith(
      inventory: newInventory,
      itemCharges: newItemCharges,
      shop: newState.shop.withPurchase(purchaseId),
    );
  }
}

/// Starts combat with a monster using the action system.
class StartCombatAction extends ReduxAction<GlobalState> {
  StartCombatAction({required this.combatAction});
  final CombatAction combatAction;

  @override
  GlobalState? reduce() {
    // If stunned, do nothing (UI should prevent this, but be safe)
    if (state.isStunned) {
      return null;
    }
    // If already in combat with this monster, do nothing
    if (state.activeAction?.id == combatAction.id) {
      return null;
    }
    // Start the combat action (this stops any other active action)
    final random = Random();
    return state.startAction(combatAction, random: random);
  }
}

/// Stops combat by clearing the active action.
class StopCombatAction extends ReduxAction<GlobalState> {
  @override
  GlobalState? reduce() {
    // If stunned, do nothing (UI should prevent this, but be safe)
    if (state.isStunned) {
      return null;
    }
    return state.clearAction();
  }
}

/// Equips food from inventory to an equipment slot.
class EquipFoodAction extends ReduxAction<GlobalState> {
  EquipFoodAction({required this.item, required this.count});
  final Item item;
  final int count;

  @override
  GlobalState reduce() {
    return state.equipFood(ItemStack(item, count: count));
  }
}

/// Eats the currently selected food to heal.
class EatFoodAction extends ReduxAction<GlobalState> {
  @override
  GlobalState? reduce() {
    return state.eatSelectedFood();
  }
}

/// Selects a food equipment slot.
class SelectFoodSlotAction extends ReduxAction<GlobalState> {
  SelectFoodSlotAction({required this.slotIndex});
  final int slotIndex;

  @override
  GlobalState reduce() {
    return state.selectFoodSlot(slotIndex);
  }
}

/// Opens openable items and receives the drops.
class OpenItemAction extends ReduxAction<GlobalState> {
  OpenItemAction({
    required this.item,
    required this.count,
    required this.onResult,
  });
  final Item item;
  final int count;
  final void Function(OpenResult) onResult;

  @override
  GlobalState? reduce() {
    final random = Random();
    final (newState, result) = state.openItems(
      item,
      count: count,
      random: random,
    );

    // Call the result callback
    onResult(result);

    // Always return newState - even partial opens should be applied
    return newState;
  }
}

/// Sorts the inventory by bank sort order.
class SortInventoryAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return state.copyWith(
      inventory: state.inventory.sorted(state.registries.compareBankItems),
    );
  }
}

/// Equips gear from inventory to an equipment slot.
class EquipGearAction extends ReduxAction<GlobalState> {
  EquipGearAction({required this.item, required this.slot});
  final Item item;
  final EquipmentSlot slot;

  @override
  GlobalState reduce() {
    return state.equipGear(item, slot);
  }
}

/// Unequips gear from an equipment slot back to inventory.
class UnequipGearAction extends ReduxAction<GlobalState> {
  UnequipGearAction({required this.slot});
  final EquipmentSlot slot;

  @override
  GlobalState? reduce() {
    return state.unequipGear(slot);
  }
}

// Debug actions

/// Fills inventory with random items (one of each type not already present).
class DebugFillInventoryAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    var inventory = state.inventory;
    final capacity = state.inventoryCapacity;

    // Get items not already in inventory
    final existingItems = inventory.items.map((s) => s.item).toSet();
    final availableItems = state.registries.items.all
        .where((item) => !existingItems.contains(item))
        .toList();

    // Add items until inventory is full
    for (final item in availableItems) {
      if (inventory.items.length >= capacity) break;
      inventory = inventory.adding(ItemStack(item, count: 1));
    }

    return state.copyWith(inventory: inventory);
  }
}

/// Adds a specific item to inventory for debugging.
/// Returns null if inventory is full (cannot add new item type).
class DebugAddItemAction extends ReduxAction<GlobalState> {
  DebugAddItemAction({required this.item, this.count = 1});
  final Item item;
  final int count;

  @override
  GlobalState? reduce() {
    if (!state.inventory.canAdd(item, capacity: state.inventoryCapacity)) {
      return null;
    }
    final stack = ItemStack(item, count: count);
    final newInventory = state.inventory.adding(stack);
    return state.copyWith(inventory: newInventory);
  }
}

/// Resets the game state to a fresh empty state.
class DebugResetStateAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return GlobalState.empty(state.registries);
  }
}

class DebugAddCurrencyAction extends ReduxAction<GlobalState> {
  DebugAddCurrencyAction(this.currency, this.amount);
  final Currency currency;
  final int amount;

  @override
  GlobalState reduce() {
    return state.addCurrency(currency, amount);
  }
}

// ============================================================================
// Farming Actions
// ============================================================================

/// Plants a crop in a farming plot.
class PlantCropAction extends ReduxAction<GlobalState> {
  PlantCropAction({required this.plotId, required this.crop});
  final MelvorId plotId;
  final FarmingCrop crop;

  @override
  GlobalState reduce() {
    return state.plantCrop(plotId, crop);
  }
}

/// Applies compost to a growing crop.
class ApplyCompostAction extends ReduxAction<GlobalState> {
  ApplyCompostAction({required this.plotId, required this.compost});
  final MelvorId plotId;
  final Item compost;

  @override
  GlobalState reduce() {
    return state.applyCompost(plotId, compost);
  }
}

/// Harvests a ready crop from a plot.
class HarvestCropAction extends ReduxAction<GlobalState> {
  HarvestCropAction({required this.plotId});
  final MelvorId plotId;

  @override
  GlobalState reduce() {
    final random = Random();
    return state.harvestCrop(plotId, random);
  }
}

/// Unlocks a farming plot.
class UnlockPlotAction extends ReduxAction<GlobalState> {
  UnlockPlotAction({required this.plotId});
  final MelvorId plotId;

  @override
  GlobalState? reduce() {
    final plot = state.registries.farmingPlots.byId(plotId);
    if (plot == null) {
      return null;
    }

    // Check level requirement
    final farmingLevel = state.skillState(Skill.farming).skillLevel;
    if (farmingLevel < plot.level) {
      return null;
    }

    // Check currency costs
    for (final cost in plot.currencyCosts.costs) {
      if (state.currency(cost.currency) < cost.amount) {
        return null;
      }
    }

    // Deduct costs and unlock plot
    var newState = state;
    for (final cost in plot.currencyCosts.costs) {
      newState = newState.addCurrency(cost.currency, -cost.amount);
    }

    final newUnlockedPlots = Set<MelvorId>.from(newState.unlockedPlots)
      ..add(plotId);

    return newState.copyWith(unlockedPlots: newUnlockedPlots);
  }
}

/// Clears a farming plot, destroying any growing crop and compost.
class ClearPlotAction extends ReduxAction<GlobalState> {
  ClearPlotAction({required this.plotId});
  final MelvorId plotId;

  @override
  GlobalState reduce() {
    return state.clearPlot(plotId);
  }
}

/// Sets the player's attack style for combat XP distribution.
class SetAttackStyleAction extends ReduxAction<GlobalState> {
  SetAttackStyleAction({required this.attackStyle});
  final AttackStyle attackStyle;

  @override
  GlobalState reduce() {
    return state.setAttackStyle(attackStyle);
  }
}

// ============================================================================
// Cooking Actions
// ============================================================================

/// Assigns a recipe to a cooking area.
class AssignCookingRecipeAction extends ReduxAction<GlobalState> {
  AssignCookingRecipeAction({required this.area, required this.recipe});
  final CookingArea area;
  final CookingAction recipe;

  @override
  GlobalState reduce() {
    // Create area state with recipe assigned (no progress until cooking starts)
    final areaState = CookingAreaState(recipeId: recipe.id);
    return state.copyWith(
      cooking: state.cooking.withAreaState(area, areaState),
    );
  }
}

/// Starts cooking in a specific area (makes it the active cooking action).
class StartCookingAction extends ReduxAction<GlobalState> {
  StartCookingAction({required this.area});
  final CookingArea area;

  @override
  GlobalState? reduce() {
    // If stunned, do nothing
    if (state.isStunned) {
      return null;
    }

    // Get the recipe assigned to this area
    final areaState = state.cooking.areaState(area);
    if (areaState.recipeId == null) {
      return null; // No recipe assigned
    }

    // Find the cooking action
    final recipe = state.registries.actions
        .forSkill(Skill.cooking)
        .whereType<CookingAction>()
        .firstWhere(
          (a) => a.id == areaState.recipeId,
          orElse: () => throw Exception('Recipe not found'),
        );

    // Start the cooking action (this will set up progress in the area)
    final random = Random();
    return state.startAction(recipe, random: random);
  }
}

// ============================================================================
// Township Actions
// ============================================================================

/// Selects a deity for Township worship.
class SelectTownshipDeityAction extends ReduxAction<GlobalState> {
  SelectTownshipDeityAction({required this.deityId});
  final MelvorId deityId;

  @override
  GlobalState reduce() {
    return state.selectWorship(deityId);
  }
}

/// Builds a Township building in a biome.
class BuildTownshipBuildingAction extends ReduxAction<GlobalState> {
  BuildTownshipBuildingAction({
    required this.biomeId,
    required this.buildingId,
  });
  final MelvorId biomeId;
  final MelvorId buildingId;

  @override
  GlobalState reduce() {
    return state.buildTownshipBuilding(biomeId, buildingId);
  }
}

/// Repairs a Township building in a biome.
class RepairTownshipBuildingAction extends ReduxAction<GlobalState> {
  RepairTownshipBuildingAction({
    required this.biomeId,
    required this.buildingId,
  });
  final MelvorId biomeId;
  final MelvorId buildingId;

  @override
  GlobalState reduce() {
    return state.repairTownshipBuilding(biomeId, buildingId);
  }
}

/// Repairs all Township buildings across all biomes.
class RepairAllTownshipBuildingsAction extends ReduxAction<GlobalState> {
  @override
  GlobalState reduce() {
    return state.repairAllTownshipBuildings();
  }
}

/// Claims a completed Township task and shows rewards in a toast.
class ClaimTownshipTaskAction extends ReduxAction<GlobalState> {
  ClaimTownshipTaskAction(this.taskId);
  final MelvorId taskId;

  @override
  GlobalState reduce() {
    final task = state.registries.township.taskById(taskId);
    final newState = state.claimTaskReward(taskId);

    // Show toast with rewards
    final changes = task.rewardsToChanges(state.registries.items);
    if (!changes.isEmpty) {
      toastService.showToast(changes);
    }

    return newState;
  }
}

class HealTownshipAction extends ReduxAction<GlobalState> {
  HealTownshipAction({required this.resource, required this.amount});

  final HealingResource resource;
  final int amount;

  @override
  GlobalState reduce() {
    return state.copyWith(township: state.township.healWith(resource, amount));
  }
}

// ============================================================================
// Potion Actions
// ============================================================================

/// Selects a potion to use for a specific skill.
class SelectPotionAction extends ReduxAction<GlobalState> {
  SelectPotionAction(this.skillId, this.potionId);
  final MelvorId skillId;
  final MelvorId potionId;

  @override
  GlobalState reduce() {
    return state.selectPotion(skillId, potionId);
  }
}

/// Clears the selected potion for a specific skill.
class ClearPotionSelectionAction extends ReduxAction<GlobalState> {
  ClearPotionSelectionAction(this.skillId);
  final MelvorId skillId;

  @override
  GlobalState reduce() {
    return state.clearSelectedPotion(skillId);
  }
}
