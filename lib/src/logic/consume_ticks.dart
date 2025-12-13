import 'dart:math';

import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/combat.dart';
import 'package:better_idle/src/data/items.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/types/inventory.dart';
import 'package:better_idle/src/types/time_away.dart';

export 'package:async_redux/async_redux.dart';

export '../types/time_away.dart';

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

/// Returns the amount of mastery XP gained per action.
// TODO(eseidel): Take a duration instead of using maxDuration?
int masteryXpPerAction(GlobalState state, SkillAction action) {
  final skillState = state.skillState(action.skill);
  final actionState = state.actionState(action.name);
  final actionMasteryLevel = levelForXp(actionState.masteryXp);
  final itemsInSkill = actionRegistry.forSkill(action.skill).length;
  return calculateMasteryXpPerAction(
    unlockedActions: state.unlockedActionsCount(action.skill),
    actionSeconds: action.maxDuration.inSeconds.toDouble(),
    playerTotalMasteryForSkill: skillState.xp,
    totalMasteryForSkill: skillState.masteryXp,
    itemMasteryLevel: actionMasteryLevel,
    totalItemsInSkill: itemsInSkill,
    bonus: 0,
  );
}

/// Gets the current HP of a mining node.
int getCurrentHp(MiningAction action, MiningState miningState, int masteryXp) {
  final masteryLevel = levelForXp(masteryXp);
  final maxHp = action.maxHpForMasteryLevel(masteryLevel);
  return max(0, maxHp - miningState.totalHpLost);
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
List<BackgroundTickConsumer> _getBackgroundActions(GlobalState state) {
  final backgrounds = <BackgroundTickConsumer>[];

  for (final entry in state.actionStates.entries) {
    final actionName = entry.key;
    final actionState = entry.value;

    // Check if this is a mining action with background work
    final action = actionRegistry.byName(actionName);
    if (action is MiningAction) {
      final mining = actionState.mining ?? const MiningState.empty();
      final bgAction = MiningBackgroundAction(actionName, mining);
      if (bgAction.isActive) {
        backgrounds.add(bgAction);
      }
    }
  }

  return backgrounds;
}

/// Applies ticks to all background actions and updates the builder.
void _applyBackgroundTicks(
  StateUpdateBuilder builder,
  List<BackgroundTickConsumer> backgrounds,
  Tick ticks,
) {
  for (final bg in backgrounds) {
    final result = bg.applyTicks(ticks);
    builder.updateMiningState(bg.actionName, result.newState);
  }
}

class StateUpdateBuilder {
  StateUpdateBuilder(this._state);

  GlobalState _state;
  Changes _changes = const Changes.empty();

  GlobalState get state => _state;

  void setActionProgress(Action action, {required int remainingTicks}) {
    _state = _state.updateActiveAction(
      action.name,
      remainingTicks: remainingTicks,
    );
  }

  void restartCurrentAction(Action action, {Random? random}) {
    // This shouldn't be able to start a *new* action, only restart the current.
    _state = _state.startAction(action, random: random ?? Random());
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
    final oldXp = _state.skillState(skill).xp;
    final oldLevel = levelForXp(oldXp);

    _state = _state.addSkillXp(skill, amount);
    _changes = _changes.addingSkillXp(skill, amount);

    final newXp = _state.skillState(skill).xp;
    final newLevel = levelForXp(newXp);

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

  void clearAction() {
    _state = _state.clearAction();
  }

  void addGp(int amount) {
    _state = _state.copyWith(gp: _state.gp + amount);
    _changes = _changes.addingGp(amount);
  }

  void setPlayerHp(int hp) {
    _state = _state.copyWith(playerHp: hp);
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

class _Progress {
  const _Progress(this.action, this.remainingTicks, this.totalTicks);
  final SkillAction action;
  final int remainingTicks;
  final int totalTicks;

  // Computed getter for convenience
  int get progressTicks => totalTicks - remainingTicks;
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

/// Completes a skill action, consuming inputs, adding outputs, and awarding XP.
/// Returns true if the action can repeat (no items were dropped).
bool completeAction(
  StateUpdateBuilder builder,
  SkillAction action, {
  Random? random,
}) {
  final rng = random ?? Random();
  var canRepeatAction = true;

  // Consume required items
  for (final requirement in action.inputs.entries) {
    final item = itemRegistry.byName(requirement.key);
    builder.removeInventory(ItemStack(item, count: requirement.value));
  }

  // Process all drops (action-level, skill-level, and global)
  // This handles both simple Drops and DropTables via polymorphism.
  for (final drop in dropsRegistry.allDropsForAction(action)) {
    final itemStack = drop.roll(rng);
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
    final currentHp = getCurrentHp(
      action,
      newMiningState,
      actionState.masteryXp,
    );

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

/// Waits for a mining node to respawn, consuming ticks.
/// Returns the number of ticks consumed (0 if not depleted).
/// Updates mining state in the builder.
Tick _waitForRespawn(
  StateUpdateBuilder builder,
  MiningAction action,
  Tick ticksAvailable,
) {
  final miningState =
      builder.state.actionState(action.name).mining ??
      const MiningState.empty();

  if (!miningState.isDepleted) {
    return 0;
  }

  final respawnResult = _applyRespawnTicks(miningState, ticksAvailable);
  builder.updateMiningState(action.name, respawnResult.state);
  return respawnResult.ticksConsumed;
}

/// Consumes a specified number of ticks and updates the state.
/// Only handles SkillActions - CombatActions are handled by consumeCombatTicks.
void consumeTicks(StateUpdateBuilder builder, Tick ticks, {Random? random}) {
  final state = builder.state;
  final startingAction = state.activeAction;
  if (startingAction == null) {
    return;
  }
  final action = actionRegistry.byName(startingAction.name);
  if (action is! SkillAction) {
    throw StateError('Non-SkillAction in consumeTicks');
  }

  var ticksRemaining = ticks;
  final rng = random ?? Random();

  // Apply HP regeneration for mining (runs in background, independent of loop)
  if (action is MiningAction) {
    final actionState = state.actionState(action.name);
    final miningState = actionState.mining ?? const MiningState.empty();
    if (!miningState.isDepleted && miningState.totalHpLost > 0) {
      final regenResult = _applyRegenTicks(miningState, ticks);
      builder.updateMiningState(action.name, regenResult.state);
    }
  }

  while (ticksRemaining > 0) {
    final currentAction = builder.state.activeAction;
    if (currentAction == null || currentAction.name != startingAction.name) {
      break;
    }

    // For mining, handle respawn waiting at the start of each iteration
    if (action is MiningAction) {
      final ticksConsumed = _waitForRespawn(builder, action, ticksRemaining);
      ticksRemaining -= ticksConsumed;

      if (ticksRemaining <= 0) {
        break; // All ticks consumed waiting for respawn
      }

      // If node just respawned, restart the action
      if (ticksConsumed > 0) {
        builder.restartCurrentAction(action, random: rng);
        continue;
      }
    }

    // Process action progress
    final before = _Progress(
      action,
      currentAction.remainingTicks,
      currentAction.totalTicks,
    );
    final ticksToApply = min(ticksRemaining, before.remainingTicks);
    final newRemainingTicks = before.remainingTicks - ticksToApply;
    ticksRemaining -= ticksToApply;
    builder.setActionProgress(action, remainingTicks: newRemainingTicks);

    if (newRemainingTicks <= 0) {
      final canRepeat = completeAction(builder, action, random: rng);

      if (builder.state.activeAction?.name != startingAction.name) {
        throw Exception('Active action changed during consumption?');
      }

      // For mining, depletion sets canRepeat=false - loop handles respawn
      if (action is MiningAction && !canRepeat) {
        final miningState =
            builder.state.actionState(action.name).mining ??
            const MiningState.empty();
        if (miningState.isDepleted) {
          continue; // Next iteration handles respawn via _waitForRespawn
        }
      }

      // Restart action if possible, otherwise clear and exit
      if (canRepeat && builder.state.canStartAction(action)) {
        builder.restartCurrentAction(action, random: rng);
      } else {
        builder.clearAction();
        break;
      }
    }
  }
}

/// Processes combat ticks for an active Combat action.
/// The combat state (including which monster) is stored in ActionState.
void consumeCombatTicks(
  StateUpdateBuilder builder,
  Tick ticks, {
  Random? random,
}) {
  const actionName = 'Combat';
  final actionState = builder.state.actionState(actionName);
  final combatState = actionState.combat;

  // Combat state must exist - it's initialized when combat starts
  if (combatState == null) {
    return;
  }

  final action = combatState.combatAction;

  final rng = random ?? Random();
  var remainingTicks = ticks;
  var currentCombat = combatState;
  var playerHp = builder.state.playerHp;

  while (remainingTicks > 0) {
    // Handle monster respawn
    final respawnTicks = currentCombat.respawnTicksRemaining;
    if (respawnTicks != null) {
      if (remainingTicks >= respawnTicks) {
        // Monster respawns
        remainingTicks -= respawnTicks;
        final pStats = playerStats(builder.state);
        currentCombat = CombatActionState.start(action, pStats);
        builder.updateCombatState(actionName, currentCombat);
        continue;
      } else {
        // Still waiting for respawn
        currentCombat = currentCombat.copyWith(
          respawnTicksRemaining: respawnTicks - remainingTicks,
        );
        builder.updateCombatState(actionName, currentCombat);
        return;
      }
    }

    // Find next event (player attack or monster attack)
    final playerTicks = currentCombat.playerAttackTicksRemaining;
    final monsterTicks = currentCombat.monsterAttackTicksRemaining;
    final nextEventTicks = playerTicks < monsterTicks
        ? playerTicks
        : monsterTicks;

    if (remainingTicks < nextEventTicks) {
      // Not enough ticks for any attack, just update timers
      currentCombat = currentCombat.copyWith(
        playerAttackTicksRemaining: playerTicks - remainingTicks,
        monsterAttackTicksRemaining: monsterTicks - remainingTicks,
      );
      builder.updateCombatState(actionName, currentCombat);
      return;
    }

    // Advance to next event
    remainingTicks -= nextEventTicks;
    final newPlayerTicks = playerTicks - nextEventTicks;
    final newMonsterTicks = monsterTicks - nextEventTicks;

    // Process player attack if ready
    var monsterHp = currentCombat.monsterHp;
    var resetPlayerTicks = newPlayerTicks;
    if (newPlayerTicks <= 0) {
      final pStats = playerStats(builder.state);
      final damage = pStats.rollDamage(rng);
      monsterHp -= damage;
      // Reset player attack timer
      resetPlayerTicks = ticksFromDuration(
        Duration(milliseconds: (pStats.attackSpeed * 1000).round()),
      );
    }

    // Check if monster died
    if (monsterHp <= 0) {
      // Monster dies - grant GP drop and start respawn
      final gpDrop = action.rollGpDrop(rng);
      builder.addGp(gpDrop);
      currentCombat = currentCombat.copyWith(
        monsterHp: 0,
        playerAttackTicksRemaining: resetPlayerTicks,
        monsterAttackTicksRemaining: newMonsterTicks,
        respawnTicksRemaining: ticksFromDuration(monsterRespawnDuration),
      );
      builder.updateCombatState(actionName, currentCombat);
      continue;
    }

    // Process monster attack if ready
    var resetMonsterTicks = newMonsterTicks;
    if (newMonsterTicks <= 0) {
      final mStats = action.stats;
      final damage = mStats.rollDamage(rng);
      final pStats = playerStats(builder.state);
      final reducedDamage = (damage * (1 - pStats.damageReduction)).round();
      playerHp -= reducedDamage;
      builder.setPlayerHp(playerHp);
      // Reset monster attack timer
      resetMonsterTicks = ticksFromDuration(
        Duration(milliseconds: (mStats.attackSpeed * 1000).round()),
      );
    }

    // Check if player died
    if (playerHp <= 0) {
      // Player dies - end combat, reset HP
      builder
        ..setPlayerHp(maxPlayerHp)
        ..clearAction();
      return;
    }

    // Update combat state
    currentCombat = currentCombat.copyWith(
      monsterHp: monsterHp,
      playerAttackTicksRemaining: resetPlayerTicks,
      monsterAttackTicksRemaining: resetMonsterTicks,
    );
    builder.updateCombatState(actionName, currentCombat);
  }
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
}

/// Processes one iteration of a SkillAction foreground.
/// Returns how many ticks were consumed and whether to continue.
(ForegroundResult, Tick) _processSkillForeground(
  StateUpdateBuilder builder,
  SkillAction action,
  Tick ticksAvailable,
  Random rng,
) {
  final currentAction = builder.state.activeAction;
  if (currentAction == null) {
    return (ForegroundResult.stopped, 0);
  }

  // For mining, handle respawn waiting (blocking foreground behavior)
  if (action is MiningAction) {
    final miningState = builder.state.actionState(action.name).mining ??
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
    // Action completed
    final canRepeat = completeAction(builder, action, random: rng);

    // For mining, check if node just depleted
    if (action is MiningAction && !canRepeat) {
      final miningState = builder.state.actionState(action.name).mining ??
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
      builder.clearAction();
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
  var playerHp = builder.state.playerHp;

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
    playerHp = playerHp - reducedDamage;
    builder.setPlayerHp(playerHp);
    resetMonsterTicks = ticksFromDuration(
      Duration(milliseconds: (mStats.attackSpeed * 1000).round()),
    );
  }

  // Check if player died
  if (playerHp <= 0) {
    builder
      ..setPlayerHp(maxPlayerHp)
      ..clearAction();
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
///
/// This is the new unified entry point that replaces the old scattered logic.
void consumeAllTicks(
  StateUpdateBuilder builder,
  Tick ticks, {
  Random? random,
}) {
  final rng = random ?? Random();
  var ticksRemaining = ticks;

  while (ticksRemaining > 0) {
    // 1. Compute current background actions (may change each iteration)
    final backgroundActions = _getBackgroundActions(builder.state);

    // 2. Determine how many ticks to process this iteration
    Tick ticksThisIteration;

    final activeAction = builder.state.activeAction;
    if (activeAction != null) {
      // Process foreground action until next "event"
      final action = actionRegistry.byName(activeAction.name);
      final (foregroundResult, ticksUsed) = _processForegroundAction(
        builder,
        action,
        ticksRemaining,
        rng,
      );
      ticksThisIteration = ticksUsed;

      // Handle foreground result
      if (foregroundResult == ForegroundResult.stopped) {
        // Apply remaining ticks to background before exiting
        _applyBackgroundTicks(builder, backgroundActions, ticksRemaining);
        break;
      }
    } else {
      // No foreground action - consume all ticks for background actions
      ticksThisIteration = ticksRemaining;
    }

    // 3. Apply same ticks to ALL background actions
    _applyBackgroundTicks(builder, backgroundActions, ticksThisIteration);

    ticksRemaining -= ticksThisIteration;

    // If no foreground action and no background actions, we're done
    if (activeAction == null && backgroundActions.isEmpty) {
      break;
    }

    // Safety: if no ticks were consumed, break to avoid infinite loop
    if (ticksThisIteration == 0) {
      break;
    }
  }
}

/// Applies ticks to all game systems: active action and background resource
/// recovery (respawn/heal) for all mining nodes.
///
/// This is the core tick-processing logic used by UpdateActivityProgressAction.
void consumeTicksForAllSystems(
  StateUpdateBuilder builder,
  Tick ticks, {
  Random? random,
}) {
  consumeAllTicks(builder, ticks, random: random);
}

/// Consumes a specified number of ticks and returns the changes.
(TimeAway, GlobalState) consumeManyTicks(
  GlobalState state,
  Tick ticks, {
  DateTime? endTime,
}) {
  final activeAction = state.activeAction;
  if (activeAction == null) {
    // No activity active, return empty changes
    return (TimeAway.empty(), state);
  }
  final builder = StateUpdateBuilder(state);
  consumeTicksForAllSystems(builder, ticks);
  final startTime = state.updatedAt;
  final calculatedEndTime =
      endTime ??
      startTime.add(
        Duration(milliseconds: ticks * tickDuration.inMilliseconds),
      );
  // For TimeAway, we only need the action for predictions.
  // Combat actions return empty predictions anyway, so null is fine.
  final action = activeAction.name == 'Combat'
      ? null
      : actionRegistry.byName(activeAction.name);
  final timeAway = TimeAway(
    startTime: startTime,
    endTime: calculatedEndTime,
    activeSkill: state.activeSkill,
    activeAction: action,
    changes: builder.changes,
  );
  return (timeAway, builder.build());
}
