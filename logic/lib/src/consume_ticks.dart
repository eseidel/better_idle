import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/combat.dart';
import 'package:logic/src/data/items.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/health.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/stunned.dart';
import 'package:logic/src/types/time_away.dart';

/// Ticks required to regenerate 1 HP (10 seconds = 100 ticks).
final int ticksPer1Hp = ticksFromDuration(const Duration(seconds: 10));

/// Calculates the amount of mastery XP gained per action from raw values.
/// Derived from https://wiki.melvoridle.com/w/Mastery.
int calculateMasteryXpPerAction({
  required int unlockedActions,
  required int playerTotalMasteryForSkill,
  required int totalMasteryForSkill,
  required int itemMasteryLevel,
  required int totalItemsInSkill,
  required double actionSeconds, // In seconds
  required double bonus, // e.g. 0.1 for +10%
}) {
  // We don't currently have a way to get the "total mastery for skill" value,
  // so we're not using the mastery portion of the formula.
  // final masteryPortion =
  //     unlockedActions * (playerTotalMasteryForSkill / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  // final baseValue = masteryPortion + itemPortion;
  final baseValue = itemPortion;
  return max(1, baseValue * actionSeconds * 0.5 * (1 + bonus)).toInt();
}

// playerTotalMasteryForSkill is presumably a sum of all mastery xp
// for all actions in this skill?
int playerTotalMasteryForSkill(GlobalState state, Skill skill) {
  int total = 0;
  // This is terribly inefficient, but good enough for now.
  for (final entry in state.actionStates.entries) {
    final actionName = entry.key;
    final actionState = entry.value;
    final action = actionRegistry.byName(actionName);
    if (action is SkillAction && action.skill == skill) {
      total += actionState.masteryXp;
    }
  }
  return total;
}

/// Returns the amount of mastery XP gained per action.
// TODO(eseidel): Take a duration instead of using maxDuration?
int masteryXpPerAction(GlobalState state, SkillAction action) {
  final actionState = state.actionState(action.name);
  final actionMasteryLevel = actionState.masteryLevel;
  final actions = actionRegistry.forSkill(action.skill);
  final itemsInSkill = actions.length;
  return calculateMasteryXpPerAction(
    unlockedActions: state.unlockedActionsCount(action.skill),
    actionSeconds: action.maxDuration.inSeconds.toDouble(),
    playerTotalMasteryForSkill: playerTotalMasteryForSkill(state, action.skill),
    totalMasteryForSkill: itemsInSkill * maxMasteryXp,
    itemMasteryLevel: actionMasteryLevel,
    totalItemsInSkill: itemsInSkill,
    bonus: 0,
  );
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
  /// The action name this background consumer is associated with.
  String get actionName;

  /// Whether this background action has work to do.
  bool get isActive;

  /// Apply ticks and return the result.
  BackgroundTickResult applyTicks(Tick ticks);
}

/// Background action for mining node HP regeneration and respawn.
class MiningBackgroundAction implements BackgroundTickConsumer {
  MiningBackgroundAction(this.actionName, this.miningState);

  @override
  final String actionName;
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
  String? activeActionName,
}) {
  final backgrounds = <BackgroundTickConsumer>[];

  for (final entry in state.actionStates.entries) {
    final actionName = entry.key;
    final actionState = entry.value;

    // Check if this is a mining action with background work
    final action = actionRegistry.byName(actionName);
    if (action is MiningAction) {
      final mining = actionState.mining ?? const MiningState.empty();

      // For the active action, only include if it needs healing (not respawn)
      // because foreground handles respawn synchronously
      if (actionName == activeActionName) {
        if (!mining.isDepleted && mining.totalHpLost > 0) {
          backgrounds.add(MiningBackgroundAction(actionName, mining));
        }
      } else {
        // Non-active actions: include all background work (healing + respawn)
        final bgAction = MiningBackgroundAction(actionName, mining);
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
  String? activeActionName,
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
    final currentActionState = builder.state.actionState(bg.actionName);
    final currentMining =
        currentActionState.mining ?? const MiningState.empty();

    // For the active action, only apply healing (not respawn)
    // because foreground handles respawn synchronously
    if (bg.actionName == activeActionName) {
      if (currentMining.isDepleted || currentMining.totalHpLost == 0) {
        continue;
      }
    }

    // Only apply if the action still needs background processing
    final updatedBg = MiningBackgroundAction(bg.actionName, currentMining);
    if (!updatedBg.isActive) {
      continue;
    }

    final result = updatedBg.applyTicks(ticks);
    builder.updateMiningState(bg.actionName, result.newState);
  }
}

class StateUpdateBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = const Changes.empty();
  ActionStopReason _stopReason = ActionStopReason.stillRunning;
  Tick _ticksElapsed = 0;
  Tick? _stoppedAtTick;

  GlobalState get state => _state;
  ActionStopReason get stopReason => _stopReason;
  Tick? get stoppedAtTick => _stoppedAtTick;

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
      action.name,
      remainingTicks: remainingTicks,
    );
  }

  int currentMasteryLevel(Action action) {
    return levelForXp(_state.actionState(action.name).masteryXp);
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

  void addActionMasteryXp(String actionName, int amount) {
    _state = _state.addActionMasteryXp(actionName, amount);
    // Action Mastery XP is not tracked in the changes object.
    // Probably getting to 99 is?
  }

  void updateActionState(String actionName, ActionState newState) {
    final newActionStates = Map<String, ActionState>.from(_state.actionStates);
    newActionStates[actionName] = newState;
    _state = _state.copyWith(actionStates: newActionStates);
  }

  void addGp(int amount) {
    _state = _state.copyWith(gp: _state.gp + amount);
    _changes = _changes.addingGp(amount);
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

  /// Updates the combat state for an action.
  void updateCombatState(String actionName, CombatActionState newCombat) {
    final actionState = _state.actionState(actionName);
    updateActionState(actionName, actionState.copyWith(combat: newCombat));
  }

  /// Depletes a mining node and starts its respawn timer.
  void depleteResourceNode(
    String actionName,
    MiningAction action,
    int totalHpLost,
  ) {
    final actionState = _state.actionState(actionName);
    final newMining = MiningState(
      totalHpLost: totalHpLost,
      respawnTicksRemaining: action.respawnTicks,
    );
    updateActionState(actionName, actionState.copyWith(mining: newMining));
  }

  /// Damages a mining node and starts HP regeneration if needed.
  void damageResourceNode(String actionName, int totalHpLost) {
    final actionState = _state.actionState(actionName);
    final currentMining = actionState.mining ?? const MiningState.empty();
    final newMining = currentMining.copyWith(
      totalHpLost: totalHpLost,
      hpRegenTicksRemaining: currentMining.hpRegenTicksRemaining == 0
          ? ticksPer1Hp
          : currentMining.hpRegenTicksRemaining,
    );
    updateActionState(actionName, actionState.copyWith(mining: newMining));
  }

  /// Updates the mining state for an action.
  void updateMiningState(String actionName, MiningState newMining) {
    final actionState = _state.actionState(actionName);
    updateActionState(actionName, actionState.copyWith(mining: newMining));
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

XpPerAction xpPerAction(GlobalState state, SkillAction action) {
  return XpPerAction(
    xp: action.xp,
    masteryXp: masteryXpPerAction(state, action),
  );
}

/// Completes a thieving action with success/fail mechanics.
/// On success: grants XP, 1-maxGold GP, and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
/// Returns true if the player is still alive (action can continue).
bool completeThievingAction(
  StateUpdateBuilder builder,
  ThievingAction action,
  Random rng,
) {
  final thievingLevel = builder.state.skillState(Skill.thieving).skillLevel;
  final actionMasteryLevel = builder.currentMasteryLevel(action);
  final success = action.rollSuccess(rng, thievingLevel, actionMasteryLevel);

  if (success) {
    // Grant XP on success
    final perAction = xpPerAction(builder.state, action);
    builder
      ..addSkillXp(action.skill, perAction.xp)
      ..addActionMasteryXp(action.name, perAction.masteryXp)
      ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);

    // Grant gold
    final gold = action.rollGold(rng);
    builder.addGp(gold);

    // Process drops
    final masteryLevel = builder.currentMasteryLevel(action);
    for (final drop in dropsRegistry.allDropsForAction(
      action,
      masteryLevel: masteryLevel,
    )) {
      final itemStack = drop.roll(rng);
      if (itemStack != null) {
        builder.addInventory(itemStack);
      }
    }

    return true;
  } else {
    // Thieving failed - deal damage
    final damage = action.rollDamage(rng);
    builder.damagePlayer(damage);

    // Check if player died
    if (builder.state.playerHp <= 0) {
      builder.resetPlayerHealth();
      return false;
    }

    // Stun the player
    builder.setStunned(builder.state.stunned.stun());

    return true;
  }
}

/// Completes a skill action, consuming inputs, adding outputs, and awarding XP.
/// Returns true if the action can repeat (no items were dropped).
bool completeAction(
  StateUpdateBuilder builder,
  SkillAction action, {
  required Random random,
}) {
  var canRepeatAction = true;

  // Consume required items
  for (final requirement in action.inputs.entries) {
    final item = itemRegistry.byName(requirement.key);
    builder.removeInventory(ItemStack(item, count: requirement.value));
  }

  final masteryLevel = builder.currentMasteryLevel(action);
  // Process all drops (action-level, skill-level, and global)
  // This handles both simple Drops and DropTables via polymorphism.
  for (final drop in dropsRegistry.allDropsForAction(
    action,
    masteryLevel: masteryLevel,
  )) {
    final itemStack = drop.roll(random);
    if (itemStack != null) {
      final success = builder.addInventory(itemStack);
      if (!success) {
        // Item was dropped, can't repeat action
        canRepeatAction = false;
      }
    }
  }
  final perAction = xpPerAction(builder.state, action);

  builder
    ..addSkillXp(action.skill, perAction.xp)
    ..addActionMasteryXp(action.name, perAction.masteryXp)
    ..addSkillMasteryXp(action.skill, perAction.masteryPoolXp);

  // Handle resource depletion for mining
  if (action is MiningAction) {
    final actionState = builder.state.actionState(action.name);
    final miningState = actionState.mining ?? const MiningState.empty();

    // Increment damage
    final newTotalHpLost = miningState.totalHpLost + 1;
    final newMiningState = miningState.copyWith(totalHpLost: newTotalHpLost);
    final currentHp = newMiningState.currentHp(action, actionState.masteryXp);

    // Check if depleted
    if (currentHp <= 0) {
      // Node is depleted - set respawn timer
      builder.depleteResourceNode(action.name, action, newTotalHpLost);
      canRepeatAction = false; // Can't continue mining
    } else {
      // Still has HP, just update damage and start regen countdown if needed
      builder.damageResourceNode(action.name, newTotalHpLost);
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
  Random rng,
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
    builder.restartCurrentAction(action, random: rng);
    currentAction = builder.state.activeAction!;
  }

  // For mining, handle respawn waiting (blocking foreground behavior)
  if (action is MiningAction) {
    final miningState =
        builder.state.actionState(action.name).mining ??
        const MiningState.empty();

    if (miningState.isDepleted) {
      // Wait for respawn - this is foreground blocking behavior
      final respawnResult = _applyRespawnTicks(miningState, ticksAvailable);
      builder.updateMiningState(action.name, respawnResult.state);

      if (respawnResult.state.isDepleted) {
        // Still depleted, consumed all available ticks waiting
        return (ForegroundResult.continued, ticksAvailable);
      } else {
        // Respawn complete, restart action and continue
        builder.restartCurrentAction(action, random: rng);
        return (ForegroundResult.continued, respawnResult.ticksConsumed);
      }
    }
  }

  // Process action progress
  final ticksToApply = min(ticksAvailable, currentAction.remainingTicks);
  final newRemainingTicks = currentAction.remainingTicks - ticksToApply;
  builder.setActionProgress(action, remainingTicks: newRemainingTicks);

  if (newRemainingTicks <= 0) {
    // Action completed - handle differently based on action type
    if (action is ThievingAction) {
      final playerAlive = completeThievingAction(builder, action, rng);
      if (playerAlive) {
        if (builder.state.isStunned) {
          // Failed - leave at remainingTicks=0, return justStunned so
          // background skips stun countdown (ticks were for action completion)
          return (ForegroundResult.justStunned, ticksToApply);
        } else {
          // Success - restart action normally
          builder.restartCurrentAction(action, random: rng);
          return (ForegroundResult.continued, ticksToApply);
        }
      } else {
        // Player died - stop action
        builder.stopAction(ActionStopReason.playerDied);
        return (ForegroundResult.stopped, ticksToApply);
      }
    }

    final canRepeat = completeAction(builder, action, random: rng);

    // For mining, check if node just depleted
    if (action is MiningAction && !canRepeat) {
      final miningState =
          builder.state.actionState(action.name).mining ??
          const MiningState.empty();
      if (miningState.isDepleted) {
        // Node depleted - next iteration will handle respawn
        return (ForegroundResult.continued, ticksToApply);
      }
    }

    // Restart action if possible, otherwise stop
    if (canRepeat && builder.state.canStartAction(action)) {
      builder.restartCurrentAction(action, random: rng);
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
  Random rng,
) {
  final activeAction = builder.state.activeAction;
  if (activeAction == null) {
    return (ForegroundResult.stopped, 0);
  }

  final combatState = builder.state.actionState(activeAction.name).combat;
  if (combatState == null) {
    return (ForegroundResult.stopped, 0);
  }

  final remainingTicks = ticksAvailable;
  var currentCombat = combatState;
  var health = builder.state.health;

  // Handle monster respawn
  final respawnTicks = currentCombat.respawnTicksRemaining;
  if (respawnTicks != null) {
    if (remainingTicks >= respawnTicks) {
      // Monster respawns
      final pStats = playerStats(builder.state);
      currentCombat = CombatActionState.start(action, pStats);
      builder.updateCombatState(activeAction.name, currentCombat);
      return (ForegroundResult.continued, respawnTicks);
    } else {
      // Still waiting for respawn
      currentCombat = currentCombat.copyWith(
        respawnTicksRemaining: respawnTicks - remainingTicks,
      );
      builder.updateCombatState(activeAction.name, currentCombat);
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
    builder.updateCombatState(activeAction.name, currentCombat);
    return (ForegroundResult.continued, remainingTicks);
  }

  // Advance to next event
  final ticksConsumed = nextEventTicks;
  final newPlayerTicks = playerTicks - nextEventTicks;
  final newMonsterTicks = monsterTicks - nextEventTicks;

  // Process player attack if ready
  var monsterHp = currentCombat.monsterHp;
  var resetPlayerTicks = newPlayerTicks;
  if (newPlayerTicks <= 0) {
    final pStats = playerStats(builder.state);
    final damage = pStats.rollDamage(rng);
    monsterHp -= damage;
    resetPlayerTicks = ticksFromDuration(
      Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
    );
  }

  // Check if monster died
  if (monsterHp <= 0) {
    final gpDrop = action.rollGpDrop(rng);
    builder.addGp(gpDrop);
    currentCombat = currentCombat.copyWith(
      monsterHp: 0,
      playerAttackTicksRemaining: resetPlayerTicks,
      monsterAttackTicksRemaining: newMonsterTicks,
      respawnTicksRemaining: ticksFromDuration(monsterRespawnDuration),
    );
    builder.updateCombatState(activeAction.name, currentCombat);
    return (ForegroundResult.continued, ticksConsumed);
  }

  // Process monster attack if ready
  var resetMonsterTicks = newMonsterTicks;
  if (newMonsterTicks <= 0) {
    final mStats = action.stats;
    final damage = mStats.rollDamage(rng);
    final pStats = playerStats(builder.state);
    final reducedDamage = (damage * (1 - pStats.damageReduction)).round();
    health = health.takeDamage(reducedDamage);
    builder.setHealth(health);
    resetMonsterTicks = ticksFromDuration(
      Duration(milliseconds: (mStats.attackSpeed * 1000).round()),
    );
  }

  // Check if player died (lostHp >= maxHp means playerHp <= 0)
  if (builder.state.playerHp <= 0) {
    builder
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
  builder.updateCombatState(activeAction.name, currentCombat);
  return (ForegroundResult.continued, ticksConsumed);
}

/// Dispatches foreground processing based on action type.
(ForegroundResult, Tick) _processForegroundAction(
  StateUpdateBuilder builder,
  Action action,
  Tick ticksAvailable,
  Random rng,
) {
  if (action is CombatAction) {
    return _processCombatForeground(builder, action, ticksAvailable, rng);
  } else if (action is SkillAction) {
    return _processSkillForeground(builder, action, ticksAvailable, rng);
  } else {
    throw StateError('Unknown action type: ${action.runtimeType}');
  }
}

/// Main tick processing - handles foreground action (if any) and all
/// background actions in parallel.
void consumeTicks(
  StateUpdateBuilder builder,
  Tick ticks, {
  required Random random,
}) {
  var ticksRemaining = ticks;

  while (ticksRemaining > 0) {
    final activeAction = builder.state.activeAction;

    // 1. Compute current background actions (may change each iteration)
    // Pass active action name so we can exclude respawn handling for it
    // (foreground handles respawn synchronously for the active action)
    final backgroundActions = _getBackgroundActions(
      builder.state,
      activeActionName: activeAction?.name,
    );

    // 2. Determine how many ticks to process this iteration
    Tick ticksThisIteration;

    var skipStunCountdown = false;

    if (activeAction != null) {
      // Process foreground action until next "event"
      final action = actionRegistry.byName(activeAction.name);
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
        break;
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
      activeActionName: activeAction?.name,
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
      break;
    }

    // Safety: if no ticks were consumed, break to avoid infinite loop
    if (ticksThisIteration == 0) {
      break;
    }
  }
}

/// Consumes a specified number of ticks and returns the changes.
(TimeAway, GlobalState) consumeManyTicks(
  GlobalState state,
  Tick ticks, {
  DateTime? endTime,
  required Random random,
}) {
  final activeAction = state.activeAction;
  if (activeAction == null) {
    // No activity active, return empty changes
    return (TimeAway.empty(), state);
  }
  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, ticks, random: random);
  final startTime = state.updatedAt;
  final calculatedEndTime =
      endTime ??
      startTime.add(
        Duration(milliseconds: ticks * tickDuration.inMilliseconds),
      );
  // For TimeAway, we only need the action for predictions.
  // Combat actions return empty predictions anyway, so null is fine.
  final action = actionRegistry.byName(activeAction.name);
  // Convert stoppedAtTick to Duration if action stopped
  final stoppedAfter = builder.stoppedAtTick != null
      ? durationFromTicks(builder.stoppedAtTick!)
      : null;
  final timeAway = TimeAway(
    startTime: startTime,
    endTime: calculatedEndTime,
    activeSkill: state.activeSkill,
    // Only pass SkillActions - CombatActions don't support predictions
    activeAction: action is SkillAction ? action : null,
    changes: builder.changes,
    masteryLevels: builder.state.actionStates.map(
      (key, value) => MapEntry(key, value.masteryLevel),
    ),
    stopReason: builder.stopReason,
    stoppedAfter: stoppedAfter,
  );
  return (timeAway, builder.build());
}
