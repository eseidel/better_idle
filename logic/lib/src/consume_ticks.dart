import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/farming_background.dart';
import 'package:logic/src/passive_cooking.dart';
import 'package:meta/meta.dart';

/// Returns the sum of all mastery levels for all actions in a skill.
/// Used in the mastery XP formula which operates on levels (1-99), not XP.
/// All actions default to level 1 even if untrained.
int playerTotalMasteryLevelForSkill(GlobalState state, Skill skill) {
  var total = 0;
  for (final action in state.registries.actionsForSkill(skill)) {
    // state.actionState returns ActionState.empty() for untrained actions,
    // which has masteryXp=0, giving masteryLevel=1 (levelForXp(0) == 1).
    total += state.actionState(action.id).masteryLevel;
  }
  return total;
}

/// Returns the amount of mastery XP gained per action.
int masteryXpPerAction(GlobalState state, SkillAction action) {
  return calculateMasteryXpPerAction(
    registries: state.registries,
    action: action,
    unlockedActions: state.unlockedActionsCount(action.skill),
    playerTotalMasteryLevel: playerTotalMasteryLevelForSkill(
      state,
      action.skill,
    ),
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

  for (final entry in state.miningState.rockStates.entries) {
    final localId = entry.key;
    final mining = entry.value;
    final actionId = ActionId(Skill.mining.id, localId);

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

  return backgrounds;
}

/// Applies ticks to all background actions and updates the builder.
/// Re-reads the current state from the builder to avoid stale data issues
/// when foreground and background both modify the same action's state.
void _applyBackgroundTicks(
  StateUpdateBuilder builder,
  List<BackgroundTickConsumer> backgrounds,
  Tick ticks,
  Random random, {
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
    final currentMining = builder.state.miningState.rockState(
      bg.actionId.localId,
    );

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

  // Apply township background processing (seasons and town updates)
  _applyTownshipTicks(builder, ticks, random);

  // Apply bonfire countdown only when firemaking is active
  // (bonfire pauses when firemaking stops, resumes when it starts again)
  if (builder.state.bonfire.isActive && activeActionId != null) {
    final action = builder.registries.actionById(activeActionId);
    if (action is FiremakingAction) {
      final bonfire = builder.state.bonfire;
      final newBonfire = bonfire.consumeTicks(ticks);
      builder.setBonfire(newBonfire);

      // Auto-restart bonfire if it burned out and we have logs
      if (newBonfire.isEmpty) {
        final bonfireAction = builder.registries.firemaking.byId(
          bonfire.actionId!.localId,
        )!;
        builder.restartBonfire(bonfireAction);
      }
    }
  }
}

/// Applies ticks to Township: season countdown and hourly town updates.
void _applyTownshipTicks(
  StateUpdateBuilder builder,
  Tick ticks,
  Random random,
) {
  var township = builder.state.township;
  final registry = builder.registries.township;

  var remainingTicks = ticks;

  // Process season timer
  while (remainingTicks > 0 &&
      township.seasonTicksRemaining <= remainingTicks) {
    remainingTicks -= township.seasonTicksRemaining;
    township = township.advanceSeason();
  }
  if (remainingTicks > 0) {
    township = township.copyWith(
      seasonTicksRemaining: township.seasonTicksRemaining - remainingTicks,
    );
  }

  // Reset for update timer processing
  remainingTicks = ticks;

  // Process town update timer
  final townshipLevel = builder.state.skillState(Skill.town).skillLevel;
  while (remainingTicks > 0 && township.ticksUntilUpdate <= remainingTicks) {
    remainingTicks -= township.ticksUntilUpdate;

    // Process the town update
    final result = processTownUpdate(
      township,
      registry,
      random,
      townshipLevel: townshipLevel,
    );
    township = result.state.copyWith(ticksUntilUpdate: ticksPerHour);

    // Add GP and XP from the update
    if (result.gpProduced > 0) {
      builder.addCurrency(Currency.gp, result.gpProduced);
    }
    if (result.xpGained > 0) {
      builder.addSkillXp(Skill.town, result.xpGained.round());
    }
  }
  if (remainingTicks > 0) {
    township = township.copyWith(
      ticksUntilUpdate: township.ticksUntilUpdate - remainingTicks,
    );
  }

  builder.setTownship(township);
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
  // Passive cooking only runs when active activity is CookingActivity
  final activity = builder.state.activeActivity;
  if (activity is! CookingActivity) return;

  final registries = builder.state.registries;

  // Process each non-active cooking area from CookingActivity.areaProgress
  for (final entry in activity.areaProgress.entries) {
    final area = entry.key;
    final progress = entry.value;

    // Skip the active cooking area (handled by foreground)
    if (area == activity.activeArea) continue;

    final action = registries.actionById(progress.recipeId);
    if (action is! CookingAction) continue;

    // Check if we have inputs to cook
    if (!builder.state.canStartAction(action)) continue;

    final recipeDuration = ticksFromDuration(action.maxDuration);

    // Passive cooking is 5x slower: effective ticks = ticks / 5
    final effectiveTicks = ticks ~/ passiveCookingMultiplier;
    if (effectiveTicks <= 0) continue;

    final remaining = progress.ticksRemaining;

    if (effectiveTicks >= remaining) {
      // Cook completed - produce output (no XP/mastery/bonuses)
      completeCookingAction(builder, action, random, isPassive: true);

      // Reset progress for next cook
      final newProgress = CookingAreaProgress(
        recipeId: progress.recipeId,
        ticksRemaining: recipeDuration,
        totalTicks: recipeDuration,
      );
      builder.updateCookingActivityProgress(area, newProgress);
    } else {
      // Still cooking - decrement countdown
      final newProgress = progress.copyWith(
        ticksRemaining: remaining - effectiveTicks,
      );
      builder.updateCookingActivityProgress(area, newProgress);
    }
  }
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
  ModifierAccessors modifiers,
) {
  // Apply skillXP modifier (percentage points, e.g., -10 = 10% reduction)
  var xpModifier = modifiers.skillXP(skillId: action.skill.id);

  // Apply bonfire XP bonus for firemaking actions
  if (action.skill == Skill.firemaking && state.bonfire.isActive) {
    xpModifier += state.bonfire.xpBonus;
  }

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
/// For Drop items, applies randomProductChance modifier bonus based on
/// the item's ID and skill (e.g., bird nest potion boosts bird nest drops).
/// Returns false if any item was dropped due to full inventory.
bool rollAndCollectDrops(
  StateUpdateBuilder builder,
  SkillAction action,
  ModifierAccessors modifiers,
  Random random,
  RecipeSelection selection,
) {
  final registries = builder.registries;
  var allItemsAdded = true;

  final doublingChance = action.doublingChance(modifiers);

  for (final drop in registries.drops.allDropsForAction(action, selection)) {
    ItemStack? itemStack;

    if (drop is Drop) {
      // For simple drops, apply randomProductChance modifier
      // The modifier is scoped by itemId and skillId in Melvor data
      final modifierBonus = modifiers.randomProductChance(
        itemId: drop.itemId,
        skillId: action.skill.id,
      );
      final effectiveRate = (drop.rate + modifierBonus / 100.0).clamp(0.0, 1.0);

      // Only roll if rate < 1.0 to preserve random sequence for other drops
      if (effectiveRate >= 1.0 || random.nextDouble() < effectiveRate) {
        itemStack = drop.toItemStack(registries.items);
      }
    } else if (drop is ThievingUniqueDrop) {
      // Compute actual player stealth for accurate NPC unique drop rate.
      final thievingAction = action as ThievingAction;
      final thievingLevel = builder.state.skillState(Skill.thieving).skillLevel;
      final actionMasteryLevel = builder.currentMasteryLevel(thievingAction);
      final stealthBonus = modifiers.thievingStealth(
        actionId: thievingAction.id.localId,
      );
      final stealth = calculateStealth(
        thievingLevel,
        actionMasteryLevel,
        thievingStealthBonus: stealthBonus,
      );
      itemStack = drop.rollWithContext(
        registries.items,
        random,
        stealth: stealth,
      );
    } else if (drop is RareDrop) {
      // Use rollWithContext for RareDrops to check requiredItemId
      final skillLevel = builder.state.skillState(action.skill).skillLevel;
      final totalMastery = playerTotalMasteryLevelForSkill(
        builder.state,
        action.skill,
      );
      final hasRequiredItem =
          drop.requiredItemId == null ||
          builder.state.inventory.hasEverAcquired(drop.requiredItemId!);

      itemStack = drop.rollWithContext(
        registries.items,
        random,
        skillLevel: skillLevel,
        totalMastery: totalMastery,
        hasRequiredItem: hasRequiredItem,
      );
    } else {
      // For other Droppable types (DropTable, DropChance), use base roll
      itemStack = drop.roll(registries.items, random);
    }

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

  // Roll mastery token drop (separate from other drops, not affected by
  // doubling chance). Mastery tokens drop from non-combat skills only.
  final masteryTokenDrop = registries.drops.masteryTokenForSkill(action.skill);
  if (masteryTokenDrop != null) {
    final unlockedActions = builder.state.unlockedActionsCount(action.skill);
    final tokenStack = masteryTokenDrop.rollWithContext(
      registries.items,
      random,
      unlockedActions: unlockedActions,
    );
    if (tokenStack != null) {
      final success = builder.addInventory(tokenStack);
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
  final modifierProvider = builder.state.createActionModifierProvider(
    action,
    conditionContext: ConditionContext.empty, // Skill action, no combat.
    consumesOnType: null,
  );
  final thievingStealth = modifierProvider.thievingStealth(
    actionId: action.id.localId,
  );
  final success = action.rollSuccess(
    random,
    thievingLevel,
    actionMasteryLevel,
    thievingStealth,
  );

  if (success) {
    // Grant XP on success
    final perAction = xpPerAction(builder.state, action, modifierProvider);
    builder
      ..addSkillXp(action.skill, perAction.xp)
      ..addActionMasteryXp(action.id, perAction.masteryXp)
      ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);

    // Grant gold with currencyGain modifier
    final baseGold = action.rollGold(random);
    final currencyGainMod = modifierProvider.currencyGain(
      skillId: action.skill.id,
      actionId: action.id.localId,
    );
    final adjustedGold = (baseGold * (1.0 + currencyGainMod / 100.0))
        .round()
        .clamp(1, baseGold * 10);
    builder.addCurrency(Currency.gp, adjustedGold);

    // Roll drops with doubling applied
    final actionState = builder.state.actionState(action.id);
    final selection = actionState.recipeSelection(action);
    rollAndCollectDrops(builder, action, modifierProvider, random, selection);

    return true;
  } else {
    // Thieving failed - deal damage
    final damage = action.rollDamage(random);
    builder.damagePlayer(damage);

    // Try auto-eat after taking damage
    final modifiers = builder.state.createGlobalModifierProvider(
      conditionContext: ConditionContext.empty, // Auto-eat threshold only.
    );
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
  final modifiers = builder.state.createActionModifierProvider(
    action,
    conditionContext: ConditionContext.empty, // Skill action, no combat.
    consumesOnType: null,
  );

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
    final perfectChance =
        modifiers.perfectCookChance(
          actionId: action.id.localId,
          categoryId: action.categoryId,
        ) /
        100.0;
    final isPerfect = random.nextDouble() < perfectChance;
    outputId = isPerfect ? action.perfectCookId! : action.productId;
  } else {
    outputId = action.productId;
  }

  final outputItem = registries.items.byId(outputId);
  var quantity = action.baseQuantity;

  // Apply doubling for active cooking only
  if (!isPassive) {
    final doublingChance = action.doublingChance(modifiers);
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
  final familiars = registries.summoning.familiarsForSkill(action.skill);
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
  final modifierProvider = builder.state.createActionModifierProvider(
    action,
    conditionContext: ConditionContext.empty, // Skill action, no combat.
    consumesOnType: null,
  );
  final canRepeatAction = rollAndCollectDrops(
    builder,
    action,
    modifierProvider,
    random,
    selection,
  );

  final perAction = xpPerAction(builder.state, action, modifierProvider);

  builder
    ..addSkillXp(action.skill, perAction.xp)
    ..addActionMasteryXp(action.id, perAction.masteryXp)
    ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp)
    ..consumeSummonChargesForSkill(action)
    ..consumePotionCharge(action, random);

  // Roll for summoning mark discovery
  _rollMarkDiscovery(builder, action, random);

  // Mark tablet as crafted when completing a summoning action
  // This unblocks further mark discovery for that familiar
  if (action is SummoningAction) {
    builder.markTabletCrafted(action.productId);
  }

  // Apply mining swing damage/depletion. Depletion does not short-circuit
  // here; _processMiningForeground handles the respawn wait.
  if (action is MiningAction) {
    _completeMiningSwing(builder, action);
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

/// Handles skill action completion, dispatching to skill-specific handlers
/// via switch expression on action type.
ForegroundResult _completeSkillAction(
  StateUpdateBuilder builder,
  SkillAction action,
  Random random,
) => switch (action) {
  ThievingAction() => _completeThievingForeground(builder, action, random),
  CookingAction() => _completeCookingForeground(builder, action, random),
  _ => _completeGenericSkillAction(builder, action, random),
};

/// Handles thieving completion with unique stun/death mechanics.
ForegroundResult _completeThievingForeground(
  StateUpdateBuilder builder,
  ThievingAction action,
  Random random,
) {
  final playerAlive = completeThievingAction(builder, action, random);
  if (!playerAlive) {
    builder.stopAction(ActionStopReason.playerDied);
    return ForegroundResult.stopped;
  }
  if (builder.state.isStunned) {
    // Failed - leave at remainingTicks=0, return justStunned so
    // background skips stun countdown (ticks were for action completion)
    return ForegroundResult.justStunned;
  }
  return _restartOrStop(builder, action, true, random);
}

/// Handles cooking completion with success/fail mechanics.
ForegroundResult _completeCookingForeground(
  StateUpdateBuilder builder,
  CookingAction action,
  Random random,
) {
  completeCookingAction(builder, action, random, isPassive: false);
  return _restartOrStop(builder, action, true, random);
}

/// Handles generic skill completion (woodcutting, fishing, etc.).
ForegroundResult _completeGenericSkillAction(
  StateUpdateBuilder builder,
  SkillAction action,
  Random random,
) {
  final canRepeat = completeAction(builder, action, random: random);
  return _restartOrStop(builder, action, canRepeat, random);
}

/// Restarts the action if it can repeat, otherwise stops with the
/// appropriate reason.
ForegroundResult _restartOrStop(
  StateUpdateBuilder builder,
  SkillAction action,
  bool canRepeat,
  Random random,
) {
  if (canRepeat && builder.state.canStartAction(action)) {
    builder.restartCurrentAction(action, random: random);
    return ForegroundResult.continued;
  }

  final stopReason = !canRepeat
      ? ActionStopReason.inventoryFull
      : ActionStopReason.outOfInputs;
  builder.stopAction(stopReason);
  return ForegroundResult.stopped;
}

/// Processes one iteration of a SkillAction foreground.
/// Returns how many ticks were consumed and whether to continue.
(ForegroundResult, Tick) _processSkillForeground(
  StateUpdateBuilder builder,
  SkillAction action,
  Tick ticksAvailable,
  Random random,
) {
  var currentActivity = builder.state.activeActivity;
  if (currentActivity == null) {
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
  if (currentActivity.remainingTicks == 0) {
    builder.restartCurrentAction(action, random: random);
    currentActivity = builder.state.activeActivity;
  }
  if (currentActivity == null) {
    throw StateError('Active activity is null');
  }

  // Process action progress
  final ticksToApply = min(ticksAvailable, currentActivity.remainingTicks);
  final newRemainingTicks = currentActivity.remainingTicks - ticksToApply;
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
    // Action completed - dispatch to skill-specific completion handler
    final result = _completeSkillAction(builder, action, random);
    return (result, ticksToApply);
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
  final activeActionId = builder.state.currentActionId;
  if (activeActionId == null) {
    return (ForegroundResult.stopped, 0);
  }

  final combatState = builder.state.actionState(activeActionId).combat;
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
      // Monster spawns - preserve dungeon info if in a dungeon
      final context = builder.state.buildCombatConditionContext(
        enemyAction: action,
        enemyCurrentHp: action.maxHp,
      );
      final pStats = computePlayerStats(
        builder.state,
        conditionContext: context,
      );
      final playerAttackTicks = secondsToTicks(pStats.attackSpeed);
      final monsterAttackTicks = secondsToTicks(action.stats.attackSpeed);

      currentCombat = CombatActionState(
        monsterId: action.id,
        monsterHp: action.maxHp,
        playerAttackTicksRemaining: playerAttackTicks,
        monsterAttackTicksRemaining: monsterAttackTicks,
        dungeonId: currentCombat.dungeonId,
        dungeonMonsterIndex: currentCombat.dungeonMonsterIndex,
      );
      builder.updateCombatState(activeActionId, currentCombat);
      return (ForegroundResult.continued, spawnTicks);
    } else {
      // Still waiting for spawn
      currentCombat = currentCombat.copyWith(
        spawnTicksRemaining: spawnTicks - remainingTicks,
      );
      builder.updateCombatState(activeActionId, currentCombat);
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
    builder.updateCombatState(activeActionId, currentCombat);
    return (ForegroundResult.continued, remainingTicks);
  }

  // Advance to next event
  final ticksConsumed = nextEventTicks;
  final newPlayerTicks = playerTicks - nextEventTicks;
  final newMonsterTicks = monsterTicks - nextEventTicks;
  builder.addActionTicks(activeActionId, ticksConsumed);

  // Process player attack if ready
  var monsterHp = currentCombat.monsterHp;
  var resetPlayerTicks = newPlayerTicks;
  if (newPlayerTicks <= 0) {
    final combatContext = builder.state.buildCombatConditionContext(
      enemyAction: action,
      enemyCurrentHp: monsterHp,
    );
    final pStats = computePlayerStats(
      builder.state,
      conditionContext: combatContext,
    );
    final mStats = MonsterCombatStats.fromAction(action);

    // Consume summoning tablet charges (1 per attack, for relevant familiars)
    builder.consumeSummonChargesForCombat(
      action,
      attackSpeedSeconds: pStats.attackSpeed,
    );

    // Consume consumable if equipped with PlayerAttack trigger
    final playerCombatType = builder.state.attackStyle.combatType;
    builder.consumeConsumable(
      ConsumesOnType.playerAttack,
      attackType: playerCombatType,
    );

    // Get combat triangle modifiers based on player vs monster combat types
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

    // Drop bones if the monster has them (bones stack in loot)
    final bones = action.bones;
    if (bones != null) {
      final item = builder.registries.items.byId(bones.itemId);
      builder.addToLoot(ItemStack(item, count: bones.quantity), isBones: true);
    }

    // Roll loot table if present (regular loot does NOT stack)
    final lootTable = action.lootTable;
    if (lootTable != null) {
      final loot = lootTable.roll(builder.registries.items, random);
      if (loot != null) {
        builder.addToLoot(loot, isBones: false);
      }
    }

    // Track monster kill for task progress
    builder.trackMonsterKill(action.id.localId);

    // Handle dungeon/stronghold sequence progression
    final seqContext = switch (builder.state.activeActivity) {
      CombatActivity(:final context) when context is SequenceCombatContext =>
        context,
      _ => null,
    };
    if (seqContext != null) {
      // If last monster was killed, increment completion count
      if (seqContext.isLastMonster) {
        builder.incrementSequenceCompletion(
          seqContext.sequenceType,
          seqContext.sequenceId,
        );
      }

      // Advance to the next monster (wraps to 0 after last)
      final nextContext = seqContext.advanceToNextMonster();
      final nextMonsterId = nextContext.currentMonsterId;
      final nextMonster = builder.registries.combat.monsterById(nextMonsterId);
      final fullMonsterAttackTicks = ticksFromDuration(
        Duration(milliseconds: (nextMonster.stats.attackSpeed * 1000).round()),
      );
      // Calculate spawn ticks with modifiers (e.g., Monster Hunter Scroll)
      final respawnCtx = builder.state.buildCombatConditionContext(
        enemyAction: nextMonster,
        enemyCurrentHp: nextMonster.maxHp,
      );
      final modifiers = builder.state.createCombatModifierProvider(
        conditionContext: respawnCtx,
      );
      final spawnTicks = calculateMonsterSpawnTicks(
        modifiers.flatMonsterRespawnInterval,
      );
      currentCombat = CombatActionState(
        monsterId: nextMonster.id,
        monsterHp: 0,
        playerAttackTicksRemaining: resetPlayerTicks,
        monsterAttackTicksRemaining: fullMonsterAttackTicks,
        spawnTicksRemaining: spawnTicks,
        dungeonId: nextContext.sequenceId,
        dungeonMonsterIndex: nextContext.currentMonsterIndex,
      );
      // Update to the next monster's action and its combat state
      builder
        ..switchToAction(nextMonster, remainingTicks: resetPlayerTicks)
        ..updateCombatState(nextMonster.id, currentCombat);
      return (ForegroundResult.continued, ticksConsumed);
    }

    // Handle slayer task progression
    final slayerContext = switch (builder.state.activeActivity) {
      CombatActivity(:final context) when context is SlayerTaskContext =>
        context,
      _ => null,
    };
    if (slayerContext != null) {
      // Record the kill
      final updatedContext = slayerContext.recordKill();

      if (updatedContext.isComplete) {
        // Task completed! Grant rewards
        final category = builder.registries.slayer.taskCategories.byId(
          updatedContext.categoryId,
        );
        if (category != null) {
          // Grant slayer XP based on monster HP (simplified formula)
          // Melvor grants XP per kill, we give bonus XP on completion
          final slayerXp = action.maxHp * updatedContext.killsRequired ~/ 5;
          builder.addSkillXp(Skill.slayer, slayerXp);

          // Grant slayer coins based on HP and reward percent
          for (final reward in category.currencyRewards) {
            // Slayer coins = percent% of total HP killed
            final totalHp = action.maxHp * updatedContext.killsRequired;
            final coins = (totalHp * reward.percent) ~/ 100;
            builder.addCurrency(reward.currency, coins);
          }

          // Increment task completion count
          builder.incrementSlayerTaskCompletion(category.id);
        }

        // Stop combat - task is done, player needs to select new task
        builder.stopAction(ActionStopReason.slayerTaskComplete);
        return (ForegroundResult.stopped, ticksConsumed);
      } else {
        // Continue with the same monster for the slayer task
        final fullMonsterAttackTicks = ticksFromDuration(
          Duration(milliseconds: (action.stats.attackSpeed * 1000).round()),
        );
        final slayerRespawnCtx = builder.state.buildCombatConditionContext(
          enemyAction: action,
          enemyCurrentHp: action.maxHp,
        );
        final modifiers = builder.state.createCombatModifierProvider(
          conditionContext: slayerRespawnCtx,
        );
        final respawnTicks = calculateMonsterSpawnTicks(
          modifiers.flatMonsterRespawnInterval,
        );

        // Update the combat activity with the new context
        final newActivity = builder.combatActivity.copyWith(
          context: updatedContext,
        );
        builder.updateActivity(newActivity);

        currentCombat = currentCombat.copyWith(
          monsterHp: 0,
          playerAttackTicksRemaining: resetPlayerTicks,
          monsterAttackTicksRemaining: fullMonsterAttackTicks,
          spawnTicksRemaining: respawnTicks,
        );
        builder.updateCombatState(activeActionId, currentCombat);
        return (ForegroundResult.continued, ticksConsumed);
      }
    }

    // Regular combat - respawn the same monster
    final fullMonsterAttackTicks = ticksFromDuration(
      Duration(milliseconds: (action.stats.attackSpeed * 1000).round()),
    );
    // Calculate spawn ticks with modifiers (e.g., Monster Hunter Scroll)
    final regularRespawnCtx = builder.state.buildCombatConditionContext(
      enemyAction: action,
      enemyCurrentHp: action.maxHp,
    );
    final modifiers = builder.state.createCombatModifierProvider(
      conditionContext: regularRespawnCtx,
    );
    final respawnTicks = calculateMonsterSpawnTicks(
      modifiers.flatMonsterRespawnInterval,
    );
    currentCombat = currentCombat.copyWith(
      monsterHp: 0,
      playerAttackTicksRemaining: resetPlayerTicks,
      monsterAttackTicksRemaining: fullMonsterAttackTicks,
      spawnTicksRemaining: respawnTicks,
    );
    builder.updateCombatState(activeActionId, currentCombat);
    return (ForegroundResult.continued, ticksConsumed);
  }

  // Process monster attack if ready
  var resetMonsterTicks = newMonsterTicks;
  if (newMonsterTicks <= 0) {
    final mStats = MonsterCombatStats.fromAction(action);
    final combatCtx = builder.state.buildCombatConditionContext(
      enemyAction: action,
      enemyCurrentHp: monsterHp,
    );
    final pStats = computePlayerStats(
      builder.state,
      conditionContext: combatCtx,
    );

    // Consume consumable if equipped with EnemyAttack trigger
    // Monster attack type is the same as its combat type
    builder.consumeConsumable(
      ConsumesOnType.enemyAttack,
      attackType: action.attackType.combatType,
    );

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
    final modifiers = builder.state.createGlobalModifierProvider(
      conditionContext: ConditionContext.empty, // Auto-eat threshold only.
    );
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
  builder.updateCombatState(activeActionId, currentCombat);
  return (ForegroundResult.continued, ticksConsumed);
}

/// Processes one iteration of an AgilityActivity foreground.
/// Returns how many ticks were consumed and whether to continue.
(ForegroundResult, Tick) _processAgilityForeground(
  StateUpdateBuilder builder,
  AgilityObstacle obstacle,
  AgilityActivity activity,
  Tick ticksAvailable,
  Random random,
) {
  // Process obstacle progress
  final ticksToApply = min(ticksAvailable, activity.remainingTicks);
  final newRemainingTicks = activity.remainingTicks - ticksToApply;

  // Update progress
  final updatedActivity = activity.withProgress(
    progressTicks: activity.progressTicks + ticksToApply,
  );
  builder
    ..updateActivity(updatedActivity)
    ..addActionTicks(obstacle.id, ticksToApply);

  if (newRemainingTicks <= 0) {
    // Obstacle completed - award XP, mastery, and currency
    final modifiers = builder.state.createActionModifierProvider(
      obstacle,
      conditionContext: ConditionContext.empty, // Skill action, no combat.
      consumesOnType: null,
    );
    final perAction = xpPerAction(builder.state, obstacle, modifiers);

    builder
      ..addSkillXp(Skill.agility, perAction.xp)
      ..addActionMasteryXp(obstacle.id, perAction.masteryXp)
      ..addSkillMasteryXp(Skill.agility, perAction.masteryPoolXp);

    // Award currency rewards (e.g., GP from obstacle)
    for (final reward in obstacle.currencyRewards) {
      final currencyGainMod = modifiers.currencyGain(
        skillId: Skill.agility.id,
        actionId: obstacle.id.localId,
      );
      final adjustedAmount = (reward.amount * (1.0 + currencyGainMod / 100.0))
          .round();
      builder.addCurrency(reward.currency, adjustedAmount);
    }

    // Roll for summoning mark discovery
    _rollMarkDiscovery(builder, obstacle, random);

    // Advance to next obstacle
    final nextIndex =
        (activity.currentObstacleIndex + 1) % activity.obstacleCount;
    final nextObstacleId = activity.obstacleIds[nextIndex];
    final nextObstacle = builder.registries.agility.byId(
      nextObstacleId.localId,
    );
    if (nextObstacle == null) {
      // Obstacle no longer exists (was destroyed) - stop course
      builder.stopAction(ActionStopReason.outOfInputs);
      return (ForegroundResult.stopped, ticksToApply);
    }

    // Roll duration for next obstacle with modifiers
    final nextTotalTicks = builder.state.rollDurationWithModifiers(
      nextObstacle,
      random,
      builder.registries.shop,
    );

    // Advance activity to next obstacle (index is tracked in AgilityActivity)
    final newActivity = activity.advanceToNextObstacle(
      newTotalTicks: nextTotalTicks,
    );
    builder.advanceAgilityObstacle(newActivity);

    return (ForegroundResult.continued, ticksToApply);
  }

  // Obstacle still in progress
  return (ForegroundResult.continued, ticksToApply);
}

/// Processes one iteration of a MiningAction foreground.
/// Handles mining-specific respawn waiting and node depletion, delegating
/// to the generic skill path for normal swing progress.
(ForegroundResult, Tick) _processMiningForeground(
  StateUpdateBuilder builder,
  MiningAction action,
  Tick ticksAvailable,
  Random random,
) {
  final currentActivity = builder.state.activeActivity;
  if (currentActivity == null) {
    return (ForegroundResult.stopped, 0);
  }

  // If the node is depleted, wait for respawn before doing anything else.
  final miningState = builder.state.miningState.rockState(action.id.localId);
  if (miningState.isDepleted) {
    final respawnResult = _applyRespawnTicks(miningState, ticksAvailable);
    builder.updateMiningState(action.id, respawnResult.state);

    if (respawnResult.state.isDepleted) {
      // Still depleted, consumed all available ticks waiting.
      return (ForegroundResult.continued, ticksAvailable);
    }
    // Respawn complete, restart action and continue.
    builder.restartCurrentAction(action, random: random);
    return (ForegroundResult.continued, respawnResult.ticksConsumed);
  }

  // Delegate normal swing progress to the generic skill processor.
  // If the node depletes, the action restarts normally and the next
  // iteration handles respawn waiting at the top of this function.
  return _processSkillForeground(builder, action, ticksAvailable, random);
}

/// Applies mining swing damage. If the node's HP reaches zero, depletes
/// it and sets the respawn timer. [_processMiningForeground] handles the
/// respawn wait on the next iteration.
void _completeMiningSwing(StateUpdateBuilder builder, MiningAction action) {
  final actionState = builder.state.actionState(action.id);
  final miningState = builder.state.miningState.rockState(action.id.localId);

  final newTotalHpLost = miningState.totalHpLost + 1;
  final newMiningState = miningState.copyWith(totalHpLost: newTotalHpLost);
  final currentHp = newMiningState.currentHp(action, actionState.masteryXp);

  if (currentHp <= 0) {
    builder.depleteResourceNode(action.id, action, newTotalHpLost);
    return;
  }
  builder.damageResourceNode(action.id, newTotalHpLost);
}

/// Dispatches foreground processing based on activity type.
///
/// Uses pattern matching on [ActiveActivity] sealed class for type-safe
/// dispatch. The [action] parameter is still needed for accessing action
/// properties during processing.
(ForegroundResult, Tick) _processForegroundAction(
  StateUpdateBuilder builder,
  Action action,
  Tick ticksAvailable,
  Random random,
) {
  final activity = builder.state.activeActivity;

  // Pattern match on the sealed ActiveActivity class
  return switch (activity) {
    SkillActivity() when action is MiningAction => _processMiningForeground(
      builder,
      action,
      ticksAvailable,
      random,
    ),
    SkillActivity() when action is SkillAction => _processSkillForeground(
      builder,
      action,
      ticksAvailable,
      random,
    ),
    // CookingActivity uses the same processing as SkillActivity
    // (CookingAction extends SkillAction)
    CookingActivity() when action is CookingAction => _processSkillForeground(
      builder,
      action,
      ticksAvailable,
      random,
    ),
    CombatActivity() when action is CombatAction => _processCombatForeground(
      builder,
      action,
      ticksAvailable,
      random,
    ),
    AgilityActivity() when action is AgilityObstacle =>
      _processAgilityForeground(
        builder,
        action,
        activity,
        ticksAvailable,
        random,
      ),
    // Fallback for mismatched state (shouldn't happen in normal operation)
    _ => throw StateError(
      'Activity/action type mismatch: '
      'activity=${activity.runtimeType}, action=${action.runtimeType}',
    ),
  };
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

    final activeActionId = builder.state.currentActionId;

    // 1. Compute current background actions (may change each iteration)
    // Pass active action name so we can exclude respawn handling for it
    // (foreground handles respawn synchronously for the active action)
    final backgroundActions = _getBackgroundActions(
      builder.state,
      activeActionId: activeActionId,
    );

    // 2. Determine how many ticks to process this iteration
    Tick ticksThisIteration;

    var skipStunCountdown = false;

    if (activeActionId != null) {
      // Process foreground action until next "event"
      final action = registries.actionById(activeActionId);
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
        _applyBackgroundTicks(
          builder,
          backgroundActions,
          ticksRemaining,
          random,
        );
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
      random,
      activeActionId: activeActionId,
      skipStunCountdown: skipStunCountdown,
    );

    ticksRemaining -= ticksThisIteration;
    builder.addElapsedTicks(ticksThisIteration);

    // If no foreground action, no mining background actions, and player is
    // fully healed, we're done
    final hasPlayerHpRegen = !builder.state.health.isFullHealth;
    if (activeActionId == null &&
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
/// Returns ticks until the next scheduled event (for scheduling next wake).
Tick? consumeTicks(
  StateUpdateBuilder builder,
  Tick ticks, {
  required Random random,
}) {
  _consumeTicksCore(builder, ticks, random: random);
  return builder.calculateTicksUntilNextEvent();
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
  final activeActionId = state.currentActionId;
  // For TimeAway, we only need the action for predictions.
  // Combat actions return empty predictions anyway, so null is fine.
  final action = activeActionId != null
      ? registries.actionById(activeActionId)
      : null;
  // Convert stoppedAtTick to Duration if action stopped
  final stoppedAfter = builder.stoppedAtTick != null
      ? durationFromTicks(builder.stoppedAtTick!)
      : null;
  // Compute doubling chance and recipe selection for predictions
  var doublingChance = 0.0;
  RecipeSelection recipeSelection = const NoSelectedRecipe();
  if (action is SkillAction) {
    final modifierProvider = state.createActionModifierProvider(
      action,
      conditionContext: ConditionContext.empty, // Skill action, no combat.
      consumesOnType: null,
    );
    doublingChance = action.doublingChance(modifierProvider);
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
    pendingLoot: builder.state.loot,
  );
  return (timeAway, builder.build());
}
