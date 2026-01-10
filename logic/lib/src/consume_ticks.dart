import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/farming_background.dart';
import 'package:logic/src/passive_cooking.dart';
import 'package:meta/meta.dart';

/// Ticks required to regenerate 1 HP (10 seconds = 100 ticks).
final int ticksPer1Hp = ticksFromDuration(const Duration(seconds: 10));

// playerTotalMasteryForSkill is presumably a sum of all mastery xp
// for all actions in this skill?
int playerTotalMasteryForSkill(GlobalState state, Skill skill) {
  var total = 0;
  for (final entry in state.actionStates.entries) {
    final actionId = entry.key;
    final actionState = entry.value;
    if (actionId.skillId != skill.id) {
      continue;
    }
    total += actionState.masteryXp;
  }
  return total;
}

/// Returns the amount of mastery XP gained per action.
int masteryXpPerAction(GlobalState state, SkillAction action) {
  return calculateMasteryXpPerAction(
    actions: state.registries.actions,
    action: action,
    unlockedActions: state.unlockedActionsCount(action.skill),
    playerTotalMasteryForSkill: playerTotalMasteryForSkill(state, action.skill),
    itemMasteryLevel: state.actionState(action.id).masteryLevel,
    bonus: 0,
  );
}

/// Why [consumeTicksUntil] stopped processing.
enum ConsumeTicksStopReason {
  /// The stop condition was satisfied.
  conditionSatisfied,

  /// The maximum tick limit was reached before the condition was satisfied.
  maxTicksReached,

  /// The foreground action stopped (death, inventory full, inputs depleted).
  actionStopped,

  /// No progress could be made (no action, no background tasks, full health).
  noProgressPossible,
}

/// Result of applying ticks to mining state.
typedef MiningTickResult = ({MiningState state, Tick ticksConsumed});

/// Applies respawn countdown to a depleted mining node.
/// Returns the updated state and how many ticks were consumed by respawning.
/// If the node is not depleted, returns 0 ticks consumed.
MiningTickResult _applyRespawnTicks(
  MiningState miningState,
  Tick ticksAvailable,
) {
  final respawnTicks = miningState.respawnTicksRemaining;
  if (respawnTicks == null || respawnTicks <= 0) {
    // Not depleted, no ticks consumed
    return (state: miningState, ticksConsumed: 0);
  }

  if (ticksAvailable >= respawnTicks) {
    // Node fully respawns - return to full health
    return (state: const MiningState.empty(), ticksConsumed: respawnTicks);
  } else {
    // Partial respawn progress
    final newState = miningState.copyWith(
      respawnTicksRemaining: respawnTicks - ticksAvailable,
    );
    return (state: newState, ticksConsumed: ticksAvailable);
  }
}

/// Applies HP regeneration to a mining node.
/// Returns the updated state and how many ticks were consumed by regeneration.
MiningTickResult _applyRegenTicks(
  MiningState miningState,
  Tick ticksAvailable,
) {
  var hpLost = miningState.totalHpLost;
  if (hpLost == 0) {
    return (state: miningState, ticksConsumed: 0);
  }

  var ticksUntilNextHeal = miningState.hpRegenTicksRemaining;
  var ticksRemaining = ticksAvailable;

  // Apply heals while we have HP to regen and enough ticks
  while (hpLost > 0 && ticksRemaining >= ticksUntilNextHeal) {
    ticksRemaining -= ticksUntilNextHeal;
    hpLost -= 1;
    ticksUntilNextHeal = ticksPer1Hp;
  }

  // Apply partial progress toward next heal if we still have HP to regen
  if (hpLost > 0) {
    ticksUntilNextHeal -= ticksRemaining;
    ticksRemaining = 0;
  } else {
    ticksUntilNextHeal = 0;
  }

  return (
    state: miningState.copyWith(
      totalHpLost: hpLost,
      hpRegenTicksRemaining: ticksUntilNextHeal,
    ),
    ticksConsumed: ticksAvailable - ticksRemaining,
  );
}

/// Applies HP regeneration and respawn countdowns to a mining node.
/// Returns updated MiningState with HP regenerated and/or respawn progressed.
MiningState applyMiningTicks(MiningState miningState, Tick ticksElapsed) {
  if (miningState.isDepleted) {
    final respawnResult = _applyRespawnTicks(miningState, ticksElapsed);
    return respawnResult.state;
  } else {
    final regenResult = _applyRegenTicks(miningState, ticksElapsed);
    return regenResult.state;
  }
}

// ============================================================================
// Player HP Regeneration
// ============================================================================

/// Result of applying HP regen ticks to player health.
typedef PlayerHpRegenResult = ({HealthState state, Tick ticksConsumed});

/// Applies HP regeneration ticks to player health.
/// Heals 1% of max HP every 10 seconds while injured.
PlayerHpRegenResult _applyPlayerHpRegenTicks(
  HealthState health,
  int maxPlayerHp,
  Tick ticksAvailable,
) {
  if (health.isFullHealth) {
    return (state: health, ticksConsumed: 0);
  }

  var lostHp = health.lostHp;
  var ticksUntilNextHeal = health.hpRegenTicksRemaining;

  // If regen timer not started, start it
  if (ticksUntilNextHeal == 0 && lostHp > 0) {
    ticksUntilNextHeal = hpRegenTickInterval;
  }

  var ticksRemaining = ticksAvailable;

  // Calculate heal amount (1% of max HP, minimum 1)
  final healPerTick = max(1, (maxPlayerHp * 0.01).round());

  // Apply heals while we have HP to regen and enough ticks
  while (lostHp > 0 && ticksRemaining >= ticksUntilNextHeal) {
    ticksRemaining -= ticksUntilNextHeal;
    lostHp = max(0, lostHp - healPerTick);
    ticksUntilNextHeal = hpRegenTickInterval;
  }

  // Apply partial progress toward next heal if we still have HP to regen
  if (lostHp > 0) {
    ticksUntilNextHeal -= ticksRemaining;
    ticksRemaining = 0;
  } else {
    ticksUntilNextHeal = 0;
  }

  return (
    state: HealthState(
      lostHp: lostHp,
      hpRegenTicksRemaining: ticksUntilNextHeal,
    ),
    ticksConsumed: ticksAvailable - ticksRemaining,
  );
}

// ============================================================================
// Background Action System
// ============================================================================

/// Result of applying ticks to a background action.
typedef BackgroundTickResult = ({
  MiningState newState,
  Tick ticksConsumed,
  bool completed,
});

/// Represents a background process that consumes ticks independently.
/// Background actions run in parallel with the foreground action.
abstract class BackgroundTickConsumer {
  /// The action ID this background consumer is associated with.
  ActionId get actionId;

  /// Whether this background action has work to do.
  bool get isActive;

  /// Apply ticks and return the result.
  BackgroundTickResult applyTicks(Tick ticks);
}

/// Background action for mining node HP regeneration and respawn.
@immutable
class MiningBackgroundAction implements BackgroundTickConsumer {
  const MiningBackgroundAction(this.actionId, this.miningState);

  @override
  final ActionId actionId;

  final MiningState miningState;

  @override
  bool get isActive => miningState.isDepleted || miningState.totalHpLost > 0;

  @override
  BackgroundTickResult applyTicks(Tick ticks) {
    if (miningState.isDepleted) {
      final result = _applyRespawnTicks(miningState, ticks);
      return (
        newState: result.state,
        ticksConsumed: result.ticksConsumed,
        completed: !result.state.isDepleted,
      );
    } else if (miningState.totalHpLost > 0) {
      final result = _applyRegenTicks(miningState, ticks);
      return (
        newState: result.state,
        ticksConsumed: result.ticksConsumed,
        completed: result.state.totalHpLost == 0,
      );
    }
    return (newState: miningState, ticksConsumed: 0, completed: false);
  }
}

/// Collects all active background actions from the current state.
/// For the active mining action, only includes healing (not respawn, since
/// foreground handles respawn synchronously).
List<BackgroundTickConsumer> _getBackgroundActions(
  GlobalState state, {
  ActionId? activeActionId,
}) {
  final backgrounds = <BackgroundTickConsumer>[];
  final actions = state.registries.actions;

  for (final entry in state.actionStates.entries) {
    final actionId = entry.key;
    final actionState = entry.value;

    // Check if this is a mining action with background work
    final action = actions.byId(actionId);
    if (action is MiningAction) {
      final mining = actionState.mining ?? const MiningState.empty();

      // For the active action, only include if it needs healing (not respawn)
      // because foreground handles respawn synchronously
      if (actionId == activeActionId) {
        if (!mining.isDepleted && mining.totalHpLost > 0) {
          backgrounds.add(MiningBackgroundAction(actionId, mining));
        }
      } else {
        // Non-active actions: include all background work (healing + respawn)
        final bgAction = MiningBackgroundAction(actionId, mining);
        if (bgAction.isActive) {
          backgrounds.add(bgAction);
        }
      }
    }
  }

  return backgrounds;
}

/// Applies ticks to all background actions and updates the builder.
/// Re-reads the current state from the builder to avoid stale data issues
/// when foreground and background both modify the same action's state.
void _applyBackgroundTicks(
  StateUpdateBuilder builder,
  List<BackgroundTickConsumer> backgrounds,
  Tick ticks, {
  ActionId? activeActionId,
  bool skipStunCountdown = false,
}) {
  // Apply stunned countdown (unless stun was just applied this iteration)
  if (builder.state.isStunned && !skipStunCountdown) {
    final newStunned = builder.state.stunned.applyTicks(ticks);
    builder.setStunned(newStunned);
  }

  // Apply player HP regeneration
  final health = builder.state.health;
  if (!health.isFullHealth) {
    final result = _applyPlayerHpRegenTicks(
      health,
      builder.state.maxPlayerHp,
      ticks,
    );
    builder.setHealth(result.state);
  }

  // Apply mining node background actions
  for (final bg in backgrounds) {
    // Re-read the current mining state from builder to get any updates
    // that the foreground action may have made
    final currentActionState = builder.state.actionState(bg.actionId);
    final currentMining =
        currentActionState.mining ?? const MiningState.empty();

    // For the active action, only apply healing (not respawn)
    // because foreground handles respawn synchronously
    if (bg.actionId == activeActionId) {
      if (currentMining.isDepleted || currentMining.totalHpLost == 0) {
        continue;
      }
    }

    // Only apply if the action still needs background processing
    final updatedBg = MiningBackgroundAction(bg.actionId, currentMining);
    if (!updatedBg.isActive) {
      continue;
    }

    final result = updatedBg.applyTicks(ticks);
    builder.updateMiningState(bg.actionId, result.newState);
  }

  // Apply farming plot background actions
  for (final entry in builder.state.plotStates.entries) {
    final plotId = entry.key;
    final plotState = entry.value;

    final farmingBg = FarmingPlotGrowth(plotId, plotState.cropId!, plotState);
    if (!farmingBg.isActive) {
      continue;
    }

    final result = farmingBg.applyTicks(ticks);
    builder.updatePlotState(plotId, result.newState);
  }
}

/// Applies ticks to passive cooking areas (non-active cooking areas with
/// recipes assigned). Passive cooking runs at 5x the normal rate and does
/// not grant XP, mastery, or bonuses.
///
/// IMPORTANT: Passive cooking ONLY runs when the player is actively cooking
/// in one of the three cooking areas. If the player switches to any other
/// skill, passive cooking stops completely.
void _applyPassiveCookingTicks(
  StateUpdateBuilder builder,
  Tick ticks,
  ActionId? activeActionId,
  Random random,
) {
  // Passive cooking only runs when the active action is a CookingAction
  if (activeActionId == null) return;

  final actions = builder.state.registries.actions;
  final activeAction = actions.byId(activeActionId);

  // If not cooking, passive cooking doesn't run
  if (activeAction is! CookingAction) return;

  final cookingState = builder.state.cooking;
  final activeCookingArea = CookingArea.fromCategoryId(activeAction.categoryId);

  // Process each non-active cooking area
  for (final (area, areaState) in cookingState.allAreas) {
    // Skip the active cooking area (handled by foreground)
    if (area == activeCookingArea) continue;

    // Skip areas without a recipe or not actively cooking
    if (!areaState.isActive || areaState.recipeId == null) continue;

    final recipeId = areaState.recipeId!;
    final action = actions.byId(recipeId);
    if (action is! CookingAction) continue;

    // Check if we have inputs to cook
    if (!builder.state.canStartAction(action)) continue;

    final recipeDuration = ticksFromDuration(action.maxDuration);
    final passiveProcessor = PassiveCookingTickProcessor(
      area: area,
      areaState: areaState,
      recipeDuration: recipeDuration,
    );

    if (!passiveProcessor.isActive) continue;

    final result = passiveProcessor.applyTicks(ticks);

    if (result.completed) {
      // Cook completed - produce output (no XP/mastery/bonuses)
      completeCookingAction(builder, action, random, isPassive: true);
    }

    // Update the cooking area state
    builder.updateCookingAreaState(area, result.newState);
  }
}

class StateUpdateBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = const Changes.empty();
  ActionStopReason _stopReason = ActionStopReason.stillRunning;
  Tick _ticksElapsed = 0;
  Tick? _stoppedAtTick;
  DeathPenaltyResult? _lastDeathPenalty;

  Registries get registries => _state.registries;

  GlobalState get state => _state;
  ActionStopReason get stopReason => _stopReason;
  Tick? get stoppedAtTick => _stoppedAtTick;
  Tick get ticksElapsed => _ticksElapsed;
  DeathPenaltyResult? get lastDeathPenalty => _lastDeathPenalty;

  void addElapsedTicks(Tick ticks) {
    _ticksElapsed += ticks;
  }

  void stopAction(ActionStopReason reason) {
    _stopReason = reason;
    _stoppedAtTick = _ticksElapsed;
    _state = _state.clearAction();
  }

  void setActionProgress(Action action, {required int remainingTicks}) {
    _state = _state.updateActiveAction(
      action.id,
      remainingTicks: remainingTicks,
    );
  }

  int currentMasteryLevel(Action action) {
    return levelForXp(_state.actionState(action.id).masteryXp);
  }

  void restartCurrentAction(Action action, {required Random random}) {
    // This shouldn't be able to start a *new* action, only restart the current.
    _state = _state.startAction(action, random: random);
  }

  /// Adds inventory if there's space. Returns true if successful.
  /// If inventory is full and the item is new, the item is dropped and
  /// tracked in dropped items.
  bool addInventory(ItemStack stack) {
    // Check if inventory is full and this is a new item type
    final isNewItemType = _state.inventory.countOfItem(stack.item) == 0;
    if (_state.isInventoryFull && isNewItemType) {
      // Can't add new item type when inventory is full - drop it
      _changes = _changes.dropping(stack);
      return false;
    }

    // Add the item to inventory (either new slot available or stacking)
    _state = _state.copyWith(inventory: _state.inventory.adding(stack));
    _changes = _changes.adding(stack);
    return true;
  }

  void removeInventory(ItemStack stack) {
    _state = _state.copyWith(inventory: _state.inventory.removing(stack));
    _changes = _changes.removing(stack);
  }

  void addSkillXp(Skill skill, int amount) {
    final oldLevel = _state.skillState(skill).skillLevel;

    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingSkillXp(skill, amount);

    final newLevel = _state.skillState(skill).skillLevel;

    // Track level changes
    if (newLevel > oldLevel) {
      _changes = _changes.addingSkillLevel(skill, oldLevel, newLevel);
    }
  }

  void addSkillMasteryXp(Skill skill, int amount) {
    _state = _state.addSkillMasteryXp(skill, amount);
    // Skill Mastery XP is not tracked in the changes object.
  }

  void addActionMasteryXp(ActionId actionId, int amount) {
    _state = _state.addActionMasteryXp(actionId, amount);
    // Action Mastery XP is not tracked in the changes object.
    // Probably getting to 99 is?
  }

  void addActionTicks(ActionId actionId, Tick ticks) {
    final oldState = _state.actionState(actionId);
    final newState = oldState.copyWith(
      cumulativeTicks: oldState.cumulativeTicks + ticks,
    );
    updateActionState(actionId, newState);
  }

  void updateActionState(ActionId actionId, ActionState newState) {
    final newActionStates = Map<ActionId, ActionState>.from(
      _state.actionStates,
    );
    newActionStates[actionId] = newState;
    _state = _state.copyWith(actionStates: newActionStates);
  }

  void updatePlotState(MelvorId plotId, PlotState newState) {
    final newPlotStates = Map<MelvorId, PlotState>.from(_state.plotStates);
    newPlotStates[plotId] = newState;
    _state = _state.copyWith(plotStates: newPlotStates);
  }

  void updateCookingAreaState(CookingArea area, CookingAreaState newState) {
    final cooking = _state.cooking.withAreaState(area, newState);
    _state = _state.copyWith(cooking: cooking);
  }

  void addCurrency(Currency currency, int amount) {
    _state = _state.addCurrency(currency, amount);
    _changes = _changes.addingCurrency(currency, amount);
  }

  void setHealth(HealthState health) {
    _state = _state.copyWith(health: health);
  }

  void setStunned(StunnedState stunned) {
    _state = _state.copyWith(stunned: stunned);
  }

  void damagePlayer(int damage) {
    _state = _state.copyWith(health: _state.health.takeDamage(damage));
  }

  void resetPlayerHealth() {
    _state = _state.copyWith(health: const HealthState.full());
  }

  /// Applies the death penalty: randomly selects an equipment slot and
  /// removes any item in it. Tracks the lost item and death in changes.
  /// Returns the result indicating what was lost (if anything).
  DeathPenaltyResult applyDeathPenalty(Random random) {
    final result = _state.equipment.applyDeathPenalty(random);
    _state = _state.copyWith(equipment: result.equipment);
    _lastDeathPenalty = result;

    // Record the death occurrence
    _changes = _changes.recordingDeath();

    // Track the lost item in changes
    final lost = result.itemLost;
    if (lost != null) {
      _changes = _changes.losingOnDeath(lost);
    }

    return result;
  }

  /// Updates the combat state for an action.
  void updateCombatState(ActionId actionId, CombatActionState newCombat) {
    final actionState = _state.actionState(actionId);
    updateActionState(actionId, actionState.copyWith(combat: newCombat));
  }

  /// Depletes a mining node and starts its respawn timer.
  void depleteResourceNode(
    ActionId actionId,
    MiningAction action,
    int totalHpLost,
  ) {
    final actionState = _state.actionState(actionId);
    final newMining = MiningState(
      totalHpLost: totalHpLost,
      respawnTicksRemaining: action.respawnTicks,
    );
    updateActionState(actionId, actionState.copyWith(mining: newMining));
  }

  /// Damages a mining node and starts HP regeneration if needed.
  void damageResourceNode(ActionId actionId, int totalHpLost) {
    final actionState = _state.actionState(actionId);
    final currentMining = actionState.mining ?? const MiningState.empty();
    final newMining = currentMining.copyWith(
      totalHpLost: totalHpLost,
      hpRegenTicksRemaining: currentMining.hpRegenTicksRemaining == 0
          ? ticksPer1Hp
          : currentMining.hpRegenTicksRemaining,
    );
    updateActionState(actionId, actionState.copyWith(mining: newMining));
  }

  /// Updates the mining state for an action.
  void updateMiningState(ActionId actionId, MiningState newMining) {
    final actionState = _state.actionState(actionId);
    updateActionState(actionId, actionState.copyWith(mining: newMining));
  }

  /// Attempts auto-eat if player has the modifier and HP is below threshold.
  ///
  /// Auto-eat triggers when:
  /// 1. Player has autoEatThreshold modifier > 0 (from shop purchase)
  /// 2. Current HP is below (maxHP * threshold / 100)
  ///
  /// When triggered, consumes food from selected slot until:
  /// - HP reaches (maxHP * hpLimit / 100), or
  /// - No more food available in selected slot
  ///
  /// Returns number of food items consumed.
  int tryAutoEat(ResolvedModifiers modifiers) {
    final threshold = modifiers.autoEatThreshold;
    if (threshold <= 0) return 0;

    final maxHp = _state.maxPlayerHp;
    final currentHp = _state.playerHp;
    final thresholdHp = (maxHp * threshold / 100).ceil();

    // Check if we're below threshold
    if (currentHp >= thresholdHp) return 0;

    // Calculate target HP
    final hpLimit = modifiers.autoEatHPLimit;
    final targetHp = (maxHp * hpLimit / 100).ceil();

    // Calculate efficiency
    final efficiency = modifiers.autoEatEfficiency;

    var foodConsumed = 0;
    var hp = currentHp;

    // Eat until we reach target HP or run out of food
    while (hp < targetHp) {
      final food = _state.equipment.selectedFood;
      if (food == null) break;

      final healAmount = food.item.healsFor;
      if (healAmount == null || healAmount <= 0) break;

      // Apply efficiency to heal amount
      final effectiveHeal = (healAmount * efficiency / 100).ceil();

      // Consume the food
      final newEquipment = _state.equipment.consumeSelectedFood();
      if (newEquipment == null) break;

      // Track the consumption in changes
      _changes = _changes.removing(ItemStack(food.item, count: 1));

      // Apply the heal
      _state = _state.copyWith(
        equipment: newEquipment,
        health: _state.health.heal(effectiveHeal),
      );

      hp = _state.playerHp;
      foodConsumed++;
    }

    return foodConsumed;
  }

  /// Adds a summoning mark for a familiar.
  void addSummoningMark(MelvorId familiarId) {
    _state = _state.copyWith(
      summoning: _state.summoning.withMarks(familiarId, 1),
    );
    // Marks are not tracked in changes for now.
  }

  /// Records that a tablet was crafted for a familiar.
  /// This unblocks further mark discovery for that familiar.
  void markTabletCrafted(MelvorId familiarId) {
    _state = _state.copyWith(
      summoning: _state.summoning.withTabletCrafted(familiarId),
    );
  }

  /// Consumes charges from equipped summoning tablets relevant to [action].
  ///
  /// Only consumes charges if the equipped familiar is relevant to the skill
  /// being performed (i.e., the skill is in the familiar's markSkillIds).
  ///
  /// For non-combat skills: 1 charge per action.
  /// For combat: 1 charge per attack (2 during synergies - not implemented).
  ///
  // TODO(eseidel): Add charge preservation modifier support.
  // TODO(eseidel): Increase to 2 charges for combat when synergy is active.
  void consumeSummonCharges(Action action) {
    var equipment = _state.equipment;

    // Check each summon slot
    for (final slot in [EquipmentSlot.summon1, EquipmentSlot.summon2]) {
      final tablet = equipment.gearInSlot(slot);
      if (tablet == null) continue;

      // Check if this familiar is relevant to the current action
      final isRelevant = _isFamiliarRelevantToAction(tablet.id, action);
      if (!isRelevant) continue;

      equipment = equipment.consumeSummonCharges(slot, 1);
    }

    _state = _state.copyWith(equipment: equipment);
  }

  /// Returns true if the familiar is relevant to the given action.
  bool _isFamiliarRelevantToAction(MelvorId tabletId, Action action) {
    if (action is SkillAction) {
      return registries.actions.isFamiliarRelevantToSkill(
        tabletId,
        action.skill,
      );
    }

    if (action is CombatAction) {
      // Use the player's current combat type to determine relevance
      final combatTypeSkills = _state.attackStyle.combatType.skills;
      return registries.actions.isFamiliarRelevantToCombat(
        tabletId,
        combatTypeSkills,
      );
    }

    return false;
  }

  GlobalState build() => _state;

  Changes get changes => _changes;
}

class XpPerAction {
  const XpPerAction({required this.xp, required this.masteryXp});
  final int xp;
  final int masteryXp;
  int get masteryPoolXp => max(1, (0.25 * masteryXp).toInt());
}

XpPerAction xpPerAction(
  GlobalState state,
  SkillAction action,
  ResolvedModifiers modifiers,
) {
  // Apply skillXP modifier (percentage points, e.g., -10 = 10% reduction)
  final xpModifier = modifiers.skillXP;
  final baseXp = action.xp;
  final adjustedXp = (baseXp * (1.0 + xpModifier / 100.0)).round().clamp(
    1,
    baseXp * 10,
  );

  return XpPerAction(
    xp: adjustedXp,
    masteryXp: masteryXpPerAction(state, action),
  );
}

/// Rolls all drops for an action and adds them to inventory.
/// Applies skillItemDoublingChance from modifiers to double items.
/// Returns false if any item was dropped due to full inventory.
bool rollAndCollectDrops(
  StateUpdateBuilder builder,
  SkillAction action,
  ResolvedModifiers modifiers,
  Random random,
  RecipeSelection selection,
) {
  final registries = builder.registries;
  var allItemsAdded = true;

  // Get doubling chance from modifiers (percentage -> 0.0-1.0)
  final doublingChance = (modifiers.skillItemDoublingChance / 100.0).clamp(
    0.0,
    1.0,
  );

  for (final drop in registries.drops.allDropsForAction(action, selection)) {
    var itemStack = drop.roll(registries.items, random);
    if (itemStack != null) {
      // Apply doubling chance
      if (doublingChance > 0 && random.nextDouble() < doublingChance) {
        itemStack = ItemStack(itemStack.item, count: itemStack.count * 2);
      }
      final success = builder.addInventory(itemStack);
      if (!success) {
        allItemsAdded = false;
      }
    }
  }
  return allItemsAdded;
}

/// Completes a thieving action with success/fail mechanics.
/// On success: grants XP, 1-maxGold GP, and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
/// Returns true if the player is still alive (action can continue).
bool completeThievingAction(
  StateUpdateBuilder builder,
  ThievingAction action,
  Random random,
) {
  final thievingLevel = builder.state.skillState(Skill.thieving).skillLevel;
  final actionMasteryLevel = builder.currentMasteryLevel(action);
  final modifiers = builder.state.resolveSkillModifiers(action);
  final success = action.rollSuccess(
    random,
    thievingLevel,
    actionMasteryLevel,
    modifiers,
  );

  if (success) {
    // Grant XP on success
    final perAction = xpPerAction(builder.state, action, modifiers);
    builder
      ..addSkillXp(action.skill, perAction.xp)
      ..addActionMasteryXp(action.id, perAction.masteryXp)
      ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);

    // Grant gold with currencyGain modifier
    final baseGold = action.rollGold(random);
    final currencyGainMod = modifiers.currencyGain;
    final adjustedGold = (baseGold * (1.0 + currencyGainMod / 100.0))
        .round()
        .clamp(1, baseGold * 10);
    builder.addCurrency(Currency.gp, adjustedGold);

    // Roll drops with doubling applied
    final actionState = builder.state.actionState(action.id);
    final selection = actionState.recipeSelection(action);
    rollAndCollectDrops(builder, action, modifiers, random, selection);

    return true;
  } else {
    // Thieving failed - deal damage
    final damage = action.rollDamage(random);
    builder.damagePlayer(damage);

    // Try auto-eat after taking damage
    final modifiers = builder.state.resolveGlobalModifiers();
    builder.tryAutoEat(modifiers);

    // Check if player died (after auto-eat attempt)
    if (builder.state.playerHp <= 0) {
      builder
        ..applyDeathPenalty(random)
        ..resetPlayerHealth();
      return false;
    }

    // Stun the player
    builder.setStunned(builder.state.stunned.stun());

    return true;
  }
}

/// Completes a cooking action with success/fail mechanics.
///
/// Cooking has unique mechanics compared to other skills:
/// - Base 70% success rate, +0.6% per mastery level (capped at level 50)
/// - On failure: consumes inputs, awards only 1 XP, no output produced
/// - On success: normal XP/mastery, roll for perfect cook output
/// - Passive cooking (from non-active areas) skips XP, mastery, and bonuses
void completeCookingAction(
  StateUpdateBuilder builder,
  CookingAction action,
  Random random, {
  required bool isPassive,
}) {
  final registries = builder.registries;
  final actionState = builder.state.actionState(action.id);
  final selection = actionState.recipeSelection(action);
  final masteryLevel = builder.currentMasteryLevel(action);
  final modifiers = builder.state.resolveSkillModifiers(action);

  // Calculate success chance: 70% base + 0.6% per mastery level (capped at 50)
  // Total possible from mastery: 70% + 30% = 100% at level 50
  final masteryBonus = masteryLevel.clamp(0, 50) * 0.6;
  final baseSuccessChance = 70.0 + masteryBonus;
  // cookingSuccessCap modifier can increase the cap above 100%
  final successCap = 100.0 + modifiers.cookingSuccessCap;
  final successChance = baseSuccessChance.clamp(0.0, successCap) / 100.0;

  final success = random.nextDouble() < successChance;

  // Always consume inputs (preservation doesn't apply to cooking failures)
  final inputs = action.inputsForRecipe(selection);
  for (final requirement in inputs.entries) {
    final item = registries.items.byId(requirement.key);
    builder.removeInventory(ItemStack(item, count: requirement.value));
  }

  if (!success) {
    // Failed cook: award only 1 XP, no mastery, no output
    // Note: Burnt items are NOT received in Melvor Idle
    builder.addSkillXp(Skill.cooking, 1);
    return;
  }

  // Success path
  // Passive cooking gets NO XP, mastery, preservation, doubling, or perfect
  if (!isPassive) {
    final perAction = xpPerAction(builder.state, action, modifiers);
    builder
      ..addSkillXp(action.skill, perAction.xp)
      ..addActionMasteryXp(action.id, perAction.masteryXp)
      ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);
  }

  // Determine output item (perfect cook or normal)
  MelvorId outputId;
  if (!isPassive && action.perfectCookId != null) {
    // Roll for perfect cook using perfectCookChance modifier
    final perfectChance = modifiers.perfectCookChance / 100.0;
    final isPerfect = random.nextDouble() < perfectChance;
    outputId = isPerfect ? action.perfectCookId! : action.productId;
  } else {
    outputId = action.productId;
  }

  final outputItem = registries.items.byId(outputId);
  var quantity = action.baseQuantity;

  // Apply doubling for active cooking only
  if (!isPassive) {
    final doublingChance = (modifiers.skillItemDoublingChance / 100.0).clamp(
      0.0,
      1.0,
    );
    if (doublingChance > 0 && random.nextDouble() < doublingChance) {
      quantity *= 2;
    }
  }

  builder.addInventory(ItemStack(outputItem, count: quantity));
}

/// Rolls for summoning mark discovery after completing a skill action.
///
/// Mark discovery follows this formula:
/// Chance = (actionTimeSeconds / ((tier + 1)² × 200)) × equipmentModifier
///
/// Mark discovery is blocked if:
/// - The skill doesn't have any associated familiars
/// - The player doesn't have the required summoning level for the familiar
/// - The player has found one mark but hasn't crafted a tablet yet
void _rollMarkDiscovery(
  StateUpdateBuilder builder,
  SkillAction action,
  Random random,
) {
  final state = builder.state;
  final registries = builder.registries;

  // Get familiars that can be discovered in this skill
  final familiars = registries.actions.summoningFamiliarsForSkill(action.skill);
  if (familiars.isEmpty) return;

  // Get player's summoning level
  final summoningLevel = state.skillState(Skill.summoning).skillLevel;

  // Calculate action time in seconds (use average of min/max duration)
  final avgDurationMs =
      (action.minDuration.inMilliseconds + action.maxDuration.inMilliseconds) /
      2;
  final actionTimeSeconds = avgDurationMs / 1000.0;

  // TODO(eseidel): Calculate equipment modifier based on equipped familiars
  // 2.5× for non-combat skills with familiar equipped, 2× for combat
  const equipmentModifier = 1.0;

  for (final familiar in familiars) {
    // Check if player has required summoning level
    if (summoningLevel < familiar.unlockLevel) continue;

    // Check if mark discovery is blocked for this familiar
    if (state.summoning.isMarkDiscoveryBlocked(familiar.productId)) continue;

    // Calculate discovery chance
    final chance = markDiscoveryChance(
      actionTimeSeconds: actionTimeSeconds,
      tier: familiar.tier,
      equipmentModifier: equipmentModifier,
    );

    // Roll for discovery
    if (random.nextDouble() < chance) {
      builder.addSummoningMark(familiar.productId);
    }
  }
}

/// Completes a skill action, consuming inputs, adding outputs, and awarding XP.
/// Returns true if the action can repeat (no items were dropped).
bool completeAction(
  StateUpdateBuilder builder,
  SkillAction action, {
  required Random random,
}) {
  final registries = builder.registries;
  final actionState = builder.state.actionState(action.id);
  final selection = actionState.recipeSelection(action);

  // Consume required items (using selected recipe if applicable)
  final inputs = action.inputsForRecipe(selection);
  for (final requirement in inputs.entries) {
    final item = registries.items.byId(requirement.key);
    builder.removeInventory(ItemStack(item, count: requirement.value));
  }

  // Roll drops with doubling applied (using recipe for output multiplier)
  final modifiers = builder.state.resolveSkillModifiers(action);
  var canRepeatAction = rollAndCollectDrops(
    builder,
    action,
    modifiers,
    random,
    selection,
  );

  final perAction = xpPerAction(builder.state, action, modifiers);

  builder
    ..addSkillXp(action.skill, perAction.xp)
    ..addActionMasteryXp(action.id, perAction.masteryXp)
    ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp)
    ..consumeSummonCharges(action);

  // Roll for summoning mark discovery
  _rollMarkDiscovery(builder, action, random);

  // Mark tablet as crafted when completing a summoning action
  // This unblocks further mark discovery for that familiar
  if (action is SummoningAction) {
    builder.markTabletCrafted(action.productId);
  }

  // Handle resource depletion for mining
  if (action is MiningAction) {
    final actionState = builder.state.actionState(action.id);
    final miningState = actionState.mining ?? const MiningState.empty();

    // Increment damage
    final newTotalHpLost = miningState.totalHpLost + 1;
    final newMiningState = miningState.copyWith(totalHpLost: newTotalHpLost);
    final currentHp = newMiningState.currentHp(action, actionState.masteryXp);

    // Check if depleted
    if (currentHp <= 0) {
      // Node is depleted - set respawn timer
      builder.depleteResourceNode(action.id, action, newTotalHpLost);
      canRepeatAction = false; // Can't continue mining
    } else {
      // Still has HP, just update damage and start regen countdown if needed
      builder.damageResourceNode(action.id, newTotalHpLost);
    }
  }

  return canRepeatAction;
}

// ============================================================================
// Main Tick Processing - New Architecture
// ============================================================================

/// Result of processing a foreground action for one iteration.
enum ForegroundResult {
  /// Action is still in progress, more ticks can be applied.
  continued,

  /// Action ended (no inputs, inventory full, player died, etc.).
  stopped,

  /// Action completed but player got stunned. Ticks were spent completing
  /// the action, not waiting for stun - skip stun countdown this iteration.
  justStunned,
}

/// Processes one iteration of a SkillAction foreground.
/// Returns how many ticks were consumed and whether to continue.
(ForegroundResult, Tick) _processSkillForeground(
  StateUpdateBuilder builder,
  SkillAction action,
  Tick ticksAvailable,
  Random random,
) {
  var currentAction = builder.state.activeAction;
  if (currentAction == null) {
    return (ForegroundResult.stopped, 0);
  }

  // If stunned, wait for stun to clear before processing any foreground action.
  // Return ticks to consume (up to stun remaining) but don't modify stun -
  // background handles the countdown.
  if (builder.state.isStunned) {
    final ticksToWait = min(
      ticksAvailable,
      builder.state.stunned.ticksRemaining,
    );
    return (ForegroundResult.continued, ticksToWait);
  }

  // If action completed (remainingTicks=0), stun just cleared - restart it.
  // This happens when an action (e.g., thieving) completed but was stunned,
  // leaving it at remainingTicks=0 until stun cleared.
  if (currentAction.remainingTicks == 0) {
    builder.restartCurrentAction(action, random: random);
    currentAction = builder.state.activeAction;
  }
  if (currentAction == null) {
    throw StateError('Active action is null');
  }

  // For mining, handle respawn waiting (blocking foreground behavior)
  if (action is MiningAction) {
    final miningState =
        builder.state.actionState(action.id).mining ??
        const MiningState.empty();

    if (miningState.isDepleted) {
      // Wait for respawn - this is foreground blocking behavior
      final respawnResult = _applyRespawnTicks(miningState, ticksAvailable);
      builder.updateMiningState(action.id, respawnResult.state);

      if (respawnResult.state.isDepleted) {
        // Still depleted, consumed all available ticks waiting
        return (ForegroundResult.continued, ticksAvailable);
      } else {
        // Respawn complete, restart action and continue
        builder.restartCurrentAction(action, random: random);
        return (ForegroundResult.continued, respawnResult.ticksConsumed);
      }
    }
  }

  // Process action progress
  final ticksToApply = min(ticksAvailable, currentAction.remainingTicks);
  final newRemainingTicks = currentAction.remainingTicks - ticksToApply;
  builder
    ..setActionProgress(action, remainingTicks: newRemainingTicks)
    ..addActionTicks(action.id, ticksToApply);

  // For cooking, process passive cooking areas continuously (not just at
  // completion). This ensures passive cooking completes at the right time
  // even if the passive duration doesn't align with active completion events.
  if (action is CookingAction) {
    _applyPassiveCookingTicks(builder, ticksToApply, action.id, random);
  }

  if (newRemainingTicks <= 0) {
    // Action completed - handle differently based on action type
    if (action is ThievingAction) {
      final playerAlive = completeThievingAction(builder, action, random);
      if (playerAlive) {
        if (builder.state.isStunned) {
          // Failed - leave at remainingTicks=0, return justStunned so
          // background skips stun countdown (ticks were for action completion)
          return (ForegroundResult.justStunned, ticksToApply);
        } else {
          // Success - restart action normally
          builder.restartCurrentAction(action, random: random);
          return (ForegroundResult.continued, ticksToApply);
        }
      } else {
        // Player died - stop action
        builder.stopAction(ActionStopReason.playerDied);
        return (ForegroundResult.stopped, ticksToApply);
      }
    }

    // Handle cooking with success/fail mechanics
    if (action is CookingAction) {
      completeCookingAction(builder, action, random, isPassive: false);
      // Passive cooking is processed above (before completion check) so it
      // runs continuously, not just at active completion events.
      if (builder.state.canStartAction(action)) {
        builder.restartCurrentAction(action, random: random);
        return (ForegroundResult.continued, ticksToApply);
      } else {
        builder.stopAction(ActionStopReason.outOfInputs);
        return (ForegroundResult.stopped, ticksToApply);
      }
    }

    final canRepeat = completeAction(builder, action, random: random);

    // For mining, check if node just depleted
    if (action is MiningAction && !canRepeat) {
      final miningState =
          builder.state.actionState(action.id).mining ??
          const MiningState.empty();
      if (miningState.isDepleted) {
        // Node depleted - next iteration will handle respawn
        return (ForegroundResult.continued, ticksToApply);
      }
    }

    // Restart action if possible, otherwise stop
    if (canRepeat && builder.state.canStartAction(action)) {
      builder.restartCurrentAction(action, random: random);
      return (ForegroundResult.continued, ticksToApply);
    } else {
      // Determine stop reason: inventory full (can't repeat) or out of inputs
      final stopReason = !canRepeat
          ? ActionStopReason.inventoryFull
          : ActionStopReason.outOfInputs;
      builder.stopAction(stopReason);
      return (ForegroundResult.stopped, ticksToApply);
    }
  }

  // Action still in progress
  return (ForegroundResult.continued, ticksToApply);
}

/// Processes one iteration of a CombatAction foreground.
/// Returns how many ticks were consumed and whether to continue.
(ForegroundResult, Tick) _processCombatForeground(
  StateUpdateBuilder builder,
  CombatAction action,
  Tick ticksAvailable,
  Random random,
) {
  final activeAction = builder.state.activeAction;
  if (activeAction == null) {
    return (ForegroundResult.stopped, 0);
  }

  final combatState = builder.state.actionState(activeAction.id).combat;
  if (combatState == null) {
    return (ForegroundResult.stopped, 0);
  }

  final remainingTicks = ticksAvailable;
  var currentCombat = combatState;
  var health = builder.state.health;

  // Handle monster spawn
  final spawnTicks = currentCombat.spawnTicksRemaining;
  if (spawnTicks != null) {
    if (remainingTicks >= spawnTicks) {
      // Monster spawns
      final pStats = computePlayerStats(builder.state);
      final playerAttackTicks = secondsToTicks(pStats.attackSpeed);
      final monsterAttackTicks = secondsToTicks(action.stats.attackSpeed);

      currentCombat = CombatActionState(
        monsterId: action.id,
        monsterHp: action.maxHp,
        playerAttackTicksRemaining: playerAttackTicks,
        monsterAttackTicksRemaining: monsterAttackTicks,
      );
      builder.updateCombatState(activeAction.id, currentCombat);
      return (ForegroundResult.continued, spawnTicks);
    } else {
      // Still waiting for spawn
      currentCombat = currentCombat.copyWith(
        spawnTicksRemaining: spawnTicks - remainingTicks,
      );
      builder.updateCombatState(activeAction.id, currentCombat);
      return (ForegroundResult.continued, remainingTicks);
    }
  }

  // Find next event (player attack or monster attack)
  final playerTicks = currentCombat.playerAttackTicksRemaining;
  final monsterTicks = currentCombat.monsterAttackTicksRemaining;
  final nextEventTicks = min(playerTicks, monsterTicks);

  if (remainingTicks < nextEventTicks) {
    // Not enough ticks for any attack, just update timers
    currentCombat = currentCombat.copyWith(
      playerAttackTicksRemaining: playerTicks - remainingTicks,
      monsterAttackTicksRemaining: monsterTicks - remainingTicks,
    );
    builder.updateCombatState(activeAction.id, currentCombat);
    return (ForegroundResult.continued, remainingTicks);
  }

  // Advance to next event
  final ticksConsumed = nextEventTicks;
  final newPlayerTicks = playerTicks - nextEventTicks;
  final newMonsterTicks = monsterTicks - nextEventTicks;
  builder.addActionTicks(activeAction.id, ticksConsumed);

  // Process player attack if ready
  var monsterHp = currentCombat.monsterHp;
  var resetPlayerTicks = newPlayerTicks;
  if (newPlayerTicks <= 0) {
    // Consume summoning tablet charges (1 per attack, for relevant familiars)
    builder.consumeSummonCharges(action);

    final pStats = computePlayerStats(builder.state);
    final mStats = MonsterCombatStats.fromAction(action);

    // Get combat triangle modifiers based on player vs monster combat types
    final playerCombatType = builder.state.attackStyle.combatType;
    final triangleModifiers = CombatTriangle.getModifiers(
      playerCombatType,
      action.attackType,
    );

    // Calculate hit chance and roll to see if attack hits
    // Player attacks monster using the player's combat type for evasion lookup
    final monsterDefenceType = playerCombatType == CombatType.melee
        ? AttackType.melee
        : playerCombatType == CombatType.ranged
        ? AttackType.ranged
        : AttackType.magic;
    final hitChance = CombatCalculator.playerHitChance(
      pStats,
      mStats,
      monsterDefenceType,
    );

    if (CombatCalculator.rollHit(random, hitChance)) {
      final baseDamage = pStats.rollDamage(random);
      // Apply combat triangle damage modifier
      final damage = CombatTriangle.applyDamageModifier(
        baseDamage,
        triangleModifiers,
      );
      monsterHp -= damage;

      // Grant combat XP based on damage dealt and attack style
      final xpGrant = CombatXpGrant.fromDamage(
        damage,
        builder.state.attackStyle,
      );
      for (final entry in xpGrant.xpGrants.entries) {
        builder.addSkillXp(entry.key, entry.value);
      }
    }
    // Miss: no damage dealt, no XP granted

    resetPlayerTicks = ticksFromDuration(
      Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
    );
  }

  // Check if monster died
  if (monsterHp <= 0) {
    final gpDrop = action.rollGpDrop(random);
    builder.addCurrency(Currency.gp, gpDrop);

    // Drop bones if the monster has them
    final bones = action.bones;
    if (bones != null) {
      final item = builder.registries.items.byId(bones.itemId);
      builder.addInventory(ItemStack(item, count: bones.quantity));
    }

    // Roll loot table if present
    final lootTable = action.lootTable;
    if (lootTable != null) {
      final loot = lootTable.roll(builder.registries.items, random);
      if (loot != null) {
        builder.addInventory(loot);
      }
    }

    // Reset monster attack timer to full duration for when it spawns
    final fullMonsterAttackTicks = ticksFromDuration(
      Duration(milliseconds: (action.stats.attackSpeed * 1000).round()),
    );
    currentCombat = currentCombat.copyWith(
      monsterHp: 0,
      playerAttackTicksRemaining: resetPlayerTicks,
      monsterAttackTicksRemaining: fullMonsterAttackTicks,
      spawnTicksRemaining: ticksFromDuration(monsterSpawnDuration),
    );
    builder.updateCombatState(activeAction.id, currentCombat);
    return (ForegroundResult.continued, ticksConsumed);
  }

  // Process monster attack if ready
  var resetMonsterTicks = newMonsterTicks;
  if (newMonsterTicks <= 0) {
    final mStats = MonsterCombatStats.fromAction(action);
    final pStats = computePlayerStats(builder.state);

    // Get combat triangle modifiers for damage reduction calculation
    final playerCombatType = builder.state.attackStyle.combatType;
    final triangleModifiers = CombatTriangle.getModifiers(
      playerCombatType,
      action.attackType,
    );

    // Calculate hit chance and roll to see if monster hits
    final hitChance = CombatCalculator.monsterHitChance(
      mStats,
      pStats,
      action.attackType,
    );

    if (CombatCalculator.rollHit(random, hitChance)) {
      final damage = mStats.rollDamage(random);
      // Apply combat triangle to damage reduction
      final reducedDamage = CombatTriangle.applyDamageReduction(
        damage,
        pStats.damageReduction,
        triangleModifiers,
      );
      health = health.takeDamage(reducedDamage);
      builder.setHealth(health);
    }
    // Miss: no damage taken

    resetMonsterTicks = ticksFromDuration(
      Duration(milliseconds: (mStats.attackSpeed * 1000).round()),
    );

    // Try auto-eat after attack (whether hit or miss, player may need healing)
    final modifiers = builder.state.resolveGlobalModifiers();
    builder.tryAutoEat(modifiers);
  }

  // Check if player died (lostHp >= maxHp means playerHp <= 0)
  // This happens AFTER auto-eat, so player can survive if food available
  if (builder.state.playerHp <= 0) {
    builder
      ..applyDeathPenalty(random)
      ..resetPlayerHealth()
      ..stopAction(ActionStopReason.playerDied);
    return (ForegroundResult.stopped, ticksConsumed);
  }

  // Update combat state
  currentCombat = currentCombat.copyWith(
    monsterHp: monsterHp,
    playerAttackTicksRemaining: resetPlayerTicks,
    monsterAttackTicksRemaining: resetMonsterTicks,
  );
  builder.updateCombatState(activeAction.id, currentCombat);
  return (ForegroundResult.continued, ticksConsumed);
}

/// Dispatches foreground processing based on action type.
(ForegroundResult, Tick) _processForegroundAction(
  StateUpdateBuilder builder,
  Action action,
  Tick ticksAvailable,
  Random random,
) {
  if (action is CombatAction) {
    return _processCombatForeground(builder, action, ticksAvailable, random);
  } else if (action is SkillAction) {
    return _processSkillForeground(builder, action, ticksAvailable, random);
  } else {
    throw StateError('Unknown action type: ${action.runtimeType}');
  }
}

/// Condition function that determines when to stop consuming ticks.
/// Called after each action iteration with the current state.
/// Returns true to stop, false to continue.
typedef StopCondition = bool Function(GlobalState state);

/// Core tick processing loop - handles foreground action (if any) and all
/// background actions in parallel.
///
/// Processes ticks until one of:
/// - [maxTicks] is reached
/// - [stopCondition] returns true (if provided)
/// - The foreground action stops (death, inventory full, etc.)
/// - No progress can be made
///
/// Returns why processing stopped.
ConsumeTicksStopReason _consumeTicksCore(
  StateUpdateBuilder builder,
  Tick maxTicks, {
  required Random random,
  StopCondition? stopCondition,
}) {
  var ticksRemaining = maxTicks;
  final registries = builder.registries;

  while (ticksRemaining > 0) {
    // Check stop condition at the start of each iteration
    if (stopCondition != null && stopCondition(builder.state)) {
      return ConsumeTicksStopReason.conditionSatisfied;
    }

    final activeAction = builder.state.activeAction;

    // 1. Compute current background actions (may change each iteration)
    // Pass active action name so we can exclude respawn handling for it
    // (foreground handles respawn synchronously for the active action)
    final backgroundActions = _getBackgroundActions(
      builder.state,
      activeActionId: activeAction?.id,
    );

    // 2. Determine how many ticks to process this iteration
    Tick ticksThisIteration;

    var skipStunCountdown = false;

    if (activeAction != null) {
      // Process foreground action until next "event"
      final action = registries.actions.byId(activeAction.id);
      final (foregroundResult, ticksUsed) = _processForegroundAction(
        builder,
        action,
        ticksRemaining,
        random,
      );

      // Handle foreground result
      if (foregroundResult == ForegroundResult.stopped) {
        // Apply remaining ticks to background before exiting
        // Note: activeAction is now null after stopped, so pass null
        _applyBackgroundTicks(builder, backgroundActions, ticksRemaining);
        return ConsumeTicksStopReason.actionStopped;
      }
      if (foregroundResult == ForegroundResult.justStunned) {
        // Stun was just applied - ticks were for action completion, not stun
        skipStunCountdown = true;
      }
      ticksThisIteration = ticksUsed;
    } else {
      // No foreground action - consume all ticks for background actions
      ticksThisIteration = ticksRemaining;
    }

    // 3. Apply same ticks to ALL background actions
    _applyBackgroundTicks(
      builder,
      backgroundActions,
      ticksThisIteration,
      activeActionId: activeAction?.id,
      skipStunCountdown: skipStunCountdown,
    );

    ticksRemaining -= ticksThisIteration;
    builder.addElapsedTicks(ticksThisIteration);

    // If no foreground action, no mining background actions, and player is
    // fully healed, we're done
    final hasPlayerHpRegen = !builder.state.health.isFullHealth;
    if (activeAction == null &&
        backgroundActions.isEmpty &&
        !hasPlayerHpRegen) {
      return ConsumeTicksStopReason.noProgressPossible;
    }

    // Safety: if no ticks were consumed, break to avoid infinite loop
    if (ticksThisIteration == 0) {
      return ConsumeTicksStopReason.noProgressPossible;
    }
  }

  // Exhausted all ticks without condition being satisfied
  return ConsumeTicksStopReason.maxTicksReached;
}

/// Main tick processing - handles foreground action (if any) and all
/// background actions in parallel.
///
/// Consumes exactly [ticks] ticks (or stops early if the action stops).
void consumeTicks(
  StateUpdateBuilder builder,
  Tick ticks, {
  required Random random,
}) {
  _consumeTicksCore(builder, ticks, random: random);
}

/// Consumes ticks until a condition is met.
///
/// Unlike [consumeTicks] which processes a fixed number of ticks, this function
/// runs until [stopCondition] returns true. It checks the condition after each
/// action iteration (typically after each action completes).
///
/// [maxTicks] provides a safety limit to prevent infinite loops.
///
/// Returns why processing stopped, which callers can use to detect when
/// maxTicks was hit without the condition being satisfied.
///
/// Example:
/// ```dart
/// final reason = consumeTicksUntil(
///   builder,
///   random: random,
///   stopCondition: (state) => state.skillState(Skill.woodcutting).xp >= 100,
/// );
/// if (reason == ConsumeTicksStopReason.maxTicksReached) {
///   // Handle stuck state
/// }
/// ```
ConsumeTicksStopReason consumeTicksUntil(
  StateUpdateBuilder builder, {
  required Random random,
  required StopCondition stopCondition,
  Tick maxTicks = 360000, // 10 hours of game time
}) {
  return _consumeTicksCore(
    builder,
    maxTicks,
    random: random,
    stopCondition: stopCondition,
  );
}

/// Consumes a specified number of ticks and returns the changes.
(TimeAway, GlobalState) consumeManyTicks(
  GlobalState state,
  Tick ticks, {
  required Random random,
  DateTime? endTime,
}) {
  final registries = state.registries;
  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, ticks, random: random);

  final startTime = state.updatedAt;
  final calculatedEndTime =
      endTime ??
      startTime.add(
        Duration(milliseconds: ticks * tickDuration.inMilliseconds),
      );

  // Build TimeAway with action details if there was an active action
  final activeAction = state.activeAction;
  // For TimeAway, we only need the action for predictions.
  // Combat actions return empty predictions anyway, so null is fine.
  final action = activeAction != null
      ? registries.actions.byId(activeAction.id)
      : null;
  // Convert stoppedAtTick to Duration if action stopped
  final stoppedAfter = builder.stoppedAtTick != null
      ? durationFromTicks(builder.stoppedAtTick!)
      : null;
  // Compute doubling chance and recipe selection for predictions
  var doublingChance = 0.0;
  RecipeSelection recipeSelection = const NoSelectedRecipe();
  if (action is SkillAction) {
    final modifiers = state.resolveSkillModifiers(action);
    doublingChance = (modifiers.skillItemDoublingChance / 100.0).clamp(
      0.0,
      1.0,
    );
    final actionState = state.actionState(action.id);
    recipeSelection = actionState.recipeSelection(action);
  }
  final timeAway = TimeAway(
    registries: registries,
    startTime: startTime,
    endTime: calculatedEndTime,
    activeSkill: state.activeSkill(),
    // Only pass SkillActions - CombatActions don't support predictions
    activeAction: action is SkillAction ? action : null,
    recipeSelection: recipeSelection,
    changes: builder.changes,
    masteryLevels: builder.state.actionStates.map(
      (key, value) => MapEntry(key, value.masteryLevel),
    ),
    stopReason: builder.stopReason,
    stoppedAfter: stoppedAfter,
    doublingChance: doublingChance,
  );
  return (timeAway, builder.build());
}
