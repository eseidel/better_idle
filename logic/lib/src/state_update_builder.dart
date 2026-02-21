import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/passive_cooking.dart';

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

  /// Returns the active activity as a [CombatActivity].
  /// Throws [StateError] if the active activity is not a [CombatActivity].
  CombatActivity get combatActivity {
    final activity = _state.activeActivity;
    if (activity is! CombatActivity) {
      throw StateError(
        'Expected CombatActivity but got ${activity.runtimeType}',
      );
    }
    return activity;
  }

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
    _state = _state.updateActiveActivity(
      action.id,
      remainingTicks: remainingTicks,
    );
  }

  /// Switches to a new combat action during dungeon progression.
  /// Unlike setActionProgress, this allows changing to a different action ID.
  ///
  /// This preserves the dungeon context from the current activity while
  /// switching to the new monster.
  /// Switches to a new monster during dungeon/stronghold progression.
  ///
  /// Preserves the sequence context while updating progress ticks.
  /// Only called during dungeon progression where the activity is always
  /// a [CombatActivity] with [SequenceCombatContext].
  void switchToAction(Action action, {required int remainingTicks}) {
    final totalTicks = remainingTicks;
    final currentActivity = _state.activeActivity;

    assert(
      currentActivity is CombatActivity &&
          currentActivity.context is SequenceCombatContext,
      'switchToAction should only be called during dungeon/stronghold combat',
    );

    final combatActivity = currentActivity! as CombatActivity;
    _state = _state.copyWith(
      activeActivity: combatActivity.copyWith(
        progressTicks: totalTicks - remainingTicks,
        totalTicks: totalTicks,
      ),
    );
  }

  int currentMasteryLevel(Action action) {
    return _state.actionState(action.id).masteryLevel;
  }

  void restartCurrentAction(Action action, {required Random random}) {
    final activity = _state.activeActivity;
    if (activity != null && action is SkillAction) {
      // Use the activity's restarted method to preserve internal state
      // (e.g., CookingActivity preserves passive area progress)
      final newTotalTicks = _state.rollDurationWithModifiers(
        action,
        random,
        registries.shop,
      );
      _state = _state.copyWith(
        activeActivity: activity.restarted(newTotalTicks: newTotalTicks),
      );
      return;
    }

    // For combat or when there's no activity, restart via startAction.
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

  /// Adds an item to the loot container.
  /// Items lost due to overflow are tracked in Changes.
  void addToLoot(ItemStack stack, {required bool isBones}) {
    final (newLoot, lostItems) = _state.loot.addItem(stack, isBones: isBones);
    _state = _state.copyWith(loot: newLoot);

    // Track any lost items due to overflow
    for (final lost in lostItems) {
      _changes = _changes.losingFromLoot(lost);
    }
  }

  /// Collects all loot to inventory.
  /// Items that don't fit stay in loot (don't disturb stacks).
  void collectAllLoot() {
    final stacks = _state.loot.allStacks;
    final remainingStacks = <ItemStack>[];

    for (final stack in stacks) {
      final canAdd = _state.inventory.canAdd(
        stack.item,
        capacity: _state.inventoryCapacity,
      );

      if (canAdd) {
        // Add to inventory
        _state = _state.copyWith(inventory: _state.inventory.adding(stack));
        _changes = _changes.adding(stack);
      } else {
        // Can't fit - keep in loot
        remainingStacks.add(stack);
      }
    }

    // Update loot with remaining items
    _state = _state.copyWith(loot: LootState(stacks: remainingStacks));
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

    // Track task progress for skillXP goals
    _updateTaskProgressForSkillXP(skill, amount);
  }

  /// Updates task progress for all uncompleted tasks with skillXP goals.
  void _updateTaskProgressForSkillXP(Skill skill, int amount) {
    final township = _state.township;
    final completedTasks = township.completedMainTasks;

    for (final task in township.registry.tasks) {
      // Skip completed tasks
      if (completedTasks.contains(task.id)) continue;

      // Check if this task has a goal for this skill's XP
      for (final goal in task.goals) {
        if (goal.type == TaskGoalType.skillXP && goal.id == skill.id) {
          _state = _state.copyWith(
            township: township.updateTaskProgress(
              task.id,
              TaskGoalType.skillXP,
              skill.id,
              amount,
            ),
          );
          // Re-get township for next iteration
          break;
        }
      }
    }
  }

  /// Tracks a monster kill for task progress and welcome back dialog.
  void trackMonsterKill(MelvorId monsterId) {
    // Track for welcome back dialog
    _changes = _changes.recordingMonsterKill(monsterId);

    // Track for township task progress
    final township = _state.township;
    final completedTasks = township.completedMainTasks;

    for (final task in township.registry.tasks) {
      // Skip completed tasks
      if (completedTasks.contains(task.id)) continue;

      // Check if this task has a goal for this monster
      for (final goal in task.goals) {
        if (goal.type == TaskGoalType.monsters && goal.id == monsterId) {
          _state = _state.copyWith(
            township: township.updateTaskProgress(
              task.id,
              TaskGoalType.monsters,
              monsterId,
              1,
            ),
          );
          break;
        }
      }
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

  /// Updates progress for a specific cooking area in the active
  /// [CookingActivity].
  void updateCookingActivityProgress(
    CookingArea area,
    CookingAreaProgress newProgress,
  ) {
    final activity = _state.activeActivity;
    if (activity is! CookingActivity) return;
    final newActivity = activity.withAreaProgress(area, newProgress);
    _state = _state.copyWith(activeActivity: newActivity);
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

  void setTownship(TownshipState township) {
    _state = _state.copyWith(township: township);
  }

  void setBonfire(BonfireState bonfire) {
    _state = _state.copyWith(bonfire: bonfire);
  }

  /// Restarts the current bonfire by consuming logs and resetting the timer.
  /// Returns true if restart was successful, false if not enough logs.
  bool restartBonfire(FiremakingAction bonfireAction) {
    final logItem = registries.items.byId(bonfireAction.logId);
    final logCount = _state.inventory.countOfItem(logItem);
    if (logCount < GlobalState.bonfireLogCost) return false;

    // Consume logs and reset bonfire timer
    final bonfireTicks = ticksFromDuration(bonfireAction.bonfireInterval);
    _state = _state.copyWith(
      inventory: _state.inventory.removing(
        ItemStack(logItem, count: GlobalState.bonfireLogCost),
      ),
      bonfire: BonfireState(
        actionId: bonfireAction.id,
        ticksRemaining: bonfireTicks,
        totalTicks: bonfireTicks,
        xpBonus: bonfireAction.bonfireXPBonus,
      ),
    );
    return true;
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
  ///
  /// This updates both the legacy `actionStates[...].combat` and the new
  /// `activeActivity` (when it's a `CombatActivity`) to keep them in sync.
  void updateCombatState(ActionId actionId, CombatActionState newCombat) {
    // Update legacy actionStates
    final actionState = _state.actionState(actionId);
    updateActionState(actionId, actionState.copyWith(combat: newCombat));

    // Also update activeActivity if it's a CombatActivity
    final activity = _state.activeActivity;
    if (activity is CombatActivity) {
      final newProgress = CombatProgressState(
        monsterHp: newCombat.monsterHp,
        playerAttackTicksRemaining: newCombat.playerAttackTicksRemaining,
        monsterAttackTicksRemaining: newCombat.monsterAttackTicksRemaining,
        spawnTicksRemaining: newCombat.spawnTicksRemaining,
      );

      // Update context if dungeon monster index changed
      var newContext = activity.context;
      if (newCombat.dungeonId != null) {
        // In a dungeon - update the context with new monster index
        final currentContext = activity.context;
        if (currentContext is SequenceCombatContext) {
          newContext = currentContext.copyWith(
            currentMonsterIndex: newCombat.dungeonMonsterIndex ?? 0,
          );
        }
      } else if (actionId.localId != activity.context.currentMonsterId) {
        throw StateError(
          'Monster ID changed unexpectedly during combat: '
          'expected ${activity.context.currentMonsterId}, '
          'got ${actionId.localId}',
        );
      }

      _state = _state.copyWith(
        activeActivity: activity.copyWith(
          context: newContext,
          progress: newProgress,
        ),
      );
    }
  }

  /// Depletes a mining node and starts its respawn timer.
  void depleteResourceNode(
    ActionId actionId,
    MiningAction action,
    int totalHpLost,
  ) {
    final newMining = MiningState(
      totalHpLost: totalHpLost,
      respawnTicksRemaining: action.respawnTicks,
    );
    updateMiningState(actionId, newMining);
  }

  /// Damages a mining node and starts HP regeneration if needed.
  void damageResourceNode(ActionId actionId, int totalHpLost) {
    final currentMining = _state.miningState.rockState(actionId.localId);
    final newMining = currentMining.copyWith(
      totalHpLost: totalHpLost,
      hpRegenTicksRemaining: currentMining.hpRegenTicksRemaining == 0
          ? ticksPer1Hp
          : currentMining.hpRegenTicksRemaining,
    );
    updateMiningState(actionId, newMining);
  }

  /// Updates the mining state for an action.
  void updateMiningState(ActionId actionId, MiningState newMining) {
    _state = _state.copyWith(
      miningState: _state.miningState.withRockState(
        actionId.localId,
        newMining,
      ),
    );
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
  int tryAutoEat(ModifierAccessors modifiers) {
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

    final canAutoSwap = modifiers.autoSwapFoodUnlocked > 0;

    var foodConsumed = 0;
    var hp = currentHp;

    // Eat until we reach target HP or run out of food
    while (hp < targetHp) {
      var food = _state.equipment.selectedFood;

      // If current slot is empty, try auto-swap to next non-empty slot.
      if (food == null && canAutoSwap) {
        final nextSlot = _state.equipment.nextNonEmptyFoodSlot;
        if (nextSlot != null) {
          _state = _state.copyWith(
            equipment: _state.equipment.copyWith(selectedFoodSlot: nextSlot),
          );
          food = _state.equipment.selectedFood;
        }
      }

      if (food == null) break;

      final healAmount = food.item.healsFor;
      if (healAmount == null || healAmount <= 0) break;

      // Apply efficiency to heal amount
      final effectiveHeal = (healAmount * efficiency / 100).ceil();

      // Consume the food
      final newEquipment = _state.equipment.consumeSelectedFood();
      if (newEquipment == null) break;

      // Track the consumption in changes (both inventory change and food eaten)
      _changes = _changes
          .removing(ItemStack(food.item, count: 1))
          .recordingFoodEaten(food.item.id, 1);

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
    // Track for welcome back dialog
    _changes = _changes.recordingMarkFound(familiarId);
  }

  /// Increments the completion count for a dungeon or stronghold.
  void incrementSequenceCompletion(SequenceType type, MelvorId sequenceId) {
    switch (type) {
      case SequenceType.dungeon:
        final current = _state.dungeonCompletions[sequenceId] ?? 0;
        final updated = Map<MelvorId, int>.from(_state.dungeonCompletions)
          ..[sequenceId] = current + 1;
        _state = _state.copyWith(dungeonCompletions: updated);
        _changes = _changes.recordingDungeonCompletion(sequenceId);
      case SequenceType.stronghold:
        final current = _state.strongholdCompletions[sequenceId] ?? 0;
        final updated = Map<MelvorId, int>.from(_state.strongholdCompletions)
          ..[sequenceId] = current + 1;
        _state = _state.copyWith(strongholdCompletions: updated);
        _changes = _changes.recordingStrongholdCompletion(sequenceId);
    }
  }

  /// Updates the active slayer task (e.g., recording a kill).
  void updateSlayerTask(SlayerTask task) {
    _state = _state.copyWith(slayerTask: task);
  }

  /// Clears the active slayer task (when completed).
  void clearSlayerTask() {
    _state = _state.clearSlayerTask();
  }

  /// Increments the completion count for a slayer task category.
  void incrementSlayerTaskCompletion(MelvorId categoryId) {
    final currentCount = _state.slayerTaskCompletions[categoryId] ?? 0;
    final newCompletions = Map<MelvorId, int>.from(_state.slayerTaskCompletions)
      ..[categoryId] = currentCount + 1;
    _state = _state.copyWith(slayerTaskCompletions: newCompletions);
  }

  /// Updates the active agility activity to the next obstacle.
  void advanceAgilityObstacle(AgilityActivity newActivity) {
    _state = _state.copyWith(activeActivity: newActivity);
  }

  /// Updates the active activity (e.g., for updating slayer task context).
  void updateActivity(ActiveActivity newActivity) {
    _state = _state.copyWith(activeActivity: newActivity);
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
  /// Grants Summoning XP when tablets are consumed using the formula:
  /// XP = (Action Time × Tablet Level × 10) / (Tablet Level + 10)
  /// where Tablet Level is the summoning level required to create the tablet.
  ///
  // TODO(eseidel): Add charge preservation modifier support.
  void consumeSummonChargesForSkill(SkillAction action) {
    final actionTimeSeconds = action.meanDuration.inMilliseconds / 1000.0;
    _consumeSummonChargesInternal(action, actionTimeSeconds);
  }

  /// Consumes charges from equipped summoning tablets relevant to combat.
  ///
  /// [attackSpeedSeconds] is the player's attack speed, used for XP calc.
  ///
  // TODO(eseidel): Familiars may attack on their own 3s timer, not player's.
  void consumeSummonChargesForCombat(
    CombatAction action, {
    required double attackSpeedSeconds,
  }) {
    _consumeSummonChargesInternal(action, attackSpeedSeconds);
  }

  void _consumeSummonChargesInternal(Action action, double actionTimeSeconds) {
    var equipment = _state.equipment;

    // Check if an active synergy applies to this action type.
    final synergy = _state.getActiveSynergy();
    final consumesOnType = _consumesOnTypeForAction(action);
    final synergyApplies =
        synergy != null &&
        consumesOnType != null &&
        synergy.appliesTo(consumesOnType);

    for (final slot in [EquipmentSlot.summon1, EquipmentSlot.summon2]) {
      final tablet = equipment.gearInSlot(slot);
      if (tablet == null) continue;

      // Charges consumed per tablet:
      //  - 1 if the familiar is individually relevant to the action
      //  - 1 if the synergy applies to this action type
      // These stack: a relevant familiar with an active synergy consumes 2.
      var charges = 0;
      if (_isFamiliarRelevantToAction(tablet.id, action)) charges += 1;
      if (synergyApplies) charges += 1;
      if (charges == 0) continue;

      _changes = _changes.recordingTabletUsed(tablet.id, charges);

      // Grant Summoning XP for using the tablet.
      // XP is earned per charge consumed.
      // Formula: (Action Time × Tablet Level × 10) / (Tablet Level + 10)
      final summoningAction = registries.summoning.actionForTablet(tablet.id);
      if (summoningAction != null) {
        final tabletLevel = summoningAction.unlockLevel;
        final xpPerCharge =
            (actionTimeSeconds * tabletLevel * 10) / (tabletLevel + 10);
        addSkillXp(Skill.summoning, (xpPerCharge * charges).round());
      }

      equipment = equipment.consumeSummonCharges(slot, charges);
    }

    _state = _state.copyWith(equipment: equipment);
  }

  /// Maps an action to its corresponding [ConsumesOnType].
  ConsumesOnType? _consumesOnTypeForAction(Action action) {
    if (action is SkillAction) {
      return switch (action.skill) {
        Skill.woodcutting => ConsumesOnType.woodcuttingAction,
        Skill.fishing => ConsumesOnType.fishingAction,
        Skill.firemaking => ConsumesOnType.firemakingAction,
        Skill.cooking => ConsumesOnType.cookingAction,
        Skill.mining => ConsumesOnType.miningAction,
        Skill.smithing => ConsumesOnType.smithingAction,
        Skill.thieving => ConsumesOnType.thievingAction,
        Skill.fletching => ConsumesOnType.fletchingAction,
        Skill.crafting => ConsumesOnType.craftingAction,
        Skill.herblore => ConsumesOnType.herbloreAction,
        Skill.runecrafting => ConsumesOnType.runecraftingAction,
        Skill.agility => ConsumesOnType.agilityAction,
        Skill.summoning => ConsumesOnType.summoningAction,
        Skill.astrology => ConsumesOnType.astrologyAction,
        Skill.farming => ConsumesOnType.farmingPlantAction,
        _ => null,
      };
    }
    if (action is CombatAction) {
      return ConsumesOnType.playerSummonAttack;
    }
    return null;
  }

  /// Returns true if the familiar is relevant to the given action.
  bool _isFamiliarRelevantToAction(MelvorId tabletId, Action action) {
    if (action is SkillAction) {
      return registries.summoning.isFamiliarRelevantToSkill(
        tabletId,
        action.skill,
      );
    }

    if (action is CombatAction) {
      // Use the player's current combat type to determine relevance
      final combatTypeSkills = _state.attackStyle.combatType.skills;
      return registries.summoning.isFamiliarRelevantToCombat(
        tabletId,
        combatTypeSkills,
      );
    }

    return false;
  }

  /// Consumes one item from the consumable slot if it has a matching
  /// [ConsumesOnType].
  ///
  /// Consumables are equipped in the [EquipmentSlot.consumable] slot and
  /// are consumed when their trigger event occurs (e.g., PlayerAttack).
  ///
  /// [attackType] is only used for PlayerAttack/EnemyAttack to filter by
  /// melee/ranged/magic.
  void consumeConsumable(ConsumesOnType triggerType, {CombatType? attackType}) {
    final consumable = _state.equipment.gearInSlot(EquipmentSlot.consumable);
    if (consumable == null) return;

    // Check if this consumable should be consumed on this trigger
    final shouldConsume = consumable.consumesOn.any((c) {
      if (c.type != triggerType) return false;

      // For PlayerAttack/EnemyAttack, check attack type filter
      if (triggerType == ConsumesOnType.playerAttack ||
          triggerType == ConsumesOnType.enemyAttack) {
        if (c.attackTypes != null && attackType != null) {
          return c.attackTypes!.contains(attackType);
        }
        // No filter or no attack type specified - consume for all attacks
        return c.attackTypes == null;
      }

      return true;
    });

    if (!shouldConsume) return;

    // Consume one from the stack
    final equipment = _state.equipment.consumeStackSlotCharges(
      EquipmentSlot.consumable,
      1,
    );
    _state = _state.copyWith(equipment: equipment);
  }

  /// Consumes one charge from the selected potion for the skill.
  ///
  /// When charges reach the potion's max charges, consumes one potion from
  /// inventory and resets charges. Clears selection when inventory is depleted.
  void consumePotionCharge(SkillAction action, Random random) {
    final skill = action.skill;
    final skillId = skill.id;
    final potionId = _state.selectedPotions[skillId];
    if (potionId == null) return;

    final potion = registries.items.byId(potionId);
    final maxCharges = potion.potionCharges ?? 1;

    // Check charge preservation chance
    final modifiers = _state.createActionModifierProvider(
      action,
      conditionContext: ConditionContext.empty, // Skill action, no combat.
      consumesOnType: null,
    );
    final preserveChance = modifiers.potionChargePreservationChance;
    if (preserveChance > 0 && random.nextDouble() * 100 < preserveChance) {
      return; // Charge preserved, don't consume
    }

    // Increment charges used for this skill
    final usedCharges = _state.potionChargesUsedForSkill(skillId) + 1;

    if (usedCharges >= maxCharges) {
      // This potion is fully used - consume one from inventory
      final potionStack = ItemStack(potion, count: 1);
      final newInventory = _state.inventory.removing(potionStack);
      final newChargesUsed = Map<MelvorId, int>.from(_state.potionChargesUsed)
        ..remove(skillId);

      // Track potion usage for welcome back dialog
      _changes = _changes.recordingPotionUsed(potionId);

      // Check if we still have potions in inventory
      final remainingCount = newInventory.countOfItem(potion);
      if (remainingCount <= 0) {
        // No more potions - clear selection
        final newSelectedPotions = Map<MelvorId, MelvorId>.from(
          _state.selectedPotions,
        )..remove(skillId);
        _state = _state.copyWith(
          inventory: newInventory,
          selectedPotions: newSelectedPotions,
          potionChargesUsed: newChargesUsed,
        );
      } else {
        _state = _state.copyWith(
          inventory: newInventory,
          potionChargesUsed: newChargesUsed,
        );
      }
    } else {
      // Just update charges used
      final newChargesUsed = Map<MelvorId, int>.from(_state.potionChargesUsed)
        ..[skillId] = usedCharges;
      _state = _state.copyWith(potionChargesUsed: newChargesUsed);
    }
  }

  GlobalState build() => _state;

  Changes get changes => _changes;

  /// Calculates ticks until the next scheduled event from all active timers.
  /// Returns null if no events are scheduled.
  ///
  /// This is used by GameLoop to schedule the next wake time, avoiding
  /// unnecessary polling when nothing will happen for a while.
  Tick? calculateTicksUntilNextEvent() {
    Tick? minTicks;

    void updateMin(Tick? ticks) {
      if (ticks == null || ticks <= 0) return;
      if (minTicks == null || ticks < minTicks!) {
        minTicks = ticks;
      }
    }

    // 1. Foreground action completion
    final activeActivity = _state.activeActivity;
    final activeActionId = _state.currentActionId;
    if (activeActivity != null) {
      updateMin(activeActivity.remainingTicks);

      // Combat timers (if in combat)
      final combatState = _state.actionState(activeActionId!).combat;
      if (combatState != null) {
        updateMin(combatState.spawnTicksRemaining);
        if (!combatState.isSpawning) {
          updateMin(combatState.playerAttackTicksRemaining);
          updateMin(combatState.monsterAttackTicksRemaining);
        }
      }
    }

    // 2. Stun countdown
    if (_state.isStunned) {
      updateMin(_state.stunned.ticksRemaining);
    }

    // 3. Player HP regen
    if (!_state.health.isFullHealth) {
      updateMin(_state.health.hpRegenTicksRemaining);
    }

    // 4. Mining node timers (all nodes, not just active)
    for (final mining in _state.miningState.rockStates.values) {
      // Respawn timer
      updateMin(mining.respawnTicksRemaining);

      // HP regen timer (only if damaged)
      if (mining.totalHpLost > 0) {
        updateMin(mining.hpRegenTicksRemaining);
      }
    }

    // 5. Farming plot timers
    for (final plotState in _state.plotStates.values) {
      if (plotState.isGrowing) {
        updateMin(plotState.growthTicksRemaining);
      }
    }

    // 6. Township timers (active once a deity is chosen)
    if (_state.township.worshipId != null) {
      updateMin(_state.township.seasonTicksRemaining);
      updateMin(_state.township.ticksUntilUpdate);
    }

    // 7. Passive cooking timers (only when actively cooking)
    final activity = _state.activeActivity;
    if (activity is CookingActivity) {
      for (final entry in activity.areaProgress.entries) {
        final area = entry.key;
        final progress = entry.value;

        // Skip active area (handled by foreground)
        if (area == activity.activeArea) continue;

        // Check for passive cooking progress
        if (progress.ticksRemaining > 0) {
          // Passive cooking runs at 5x slower rate
          updateMin(progress.ticksRemaining * passiveCookingMultiplier);
        }
      }
    }

    return minTicks;
  }
}
