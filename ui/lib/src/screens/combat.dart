import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/attack_style_selector.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/hp_bar.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/monster_drops_dialog.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skills.dart';
import 'package:ui/src/widgets/style.dart';

class CombatPage extends StatelessWidget {
  const CombatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    // Get the currently active combat action (if any)
    final activeActionId = state.currentActionId;
    CombatAction? activeMonster;
    CombatActionState? combatState;
    if (activeActionId != null) {
      final action = state.registries.actionById(activeActionId);
      if (action is CombatAction) {
        activeMonster = action;
        combatState = state.actionState(activeMonster.id).combat;
      }
    }

    return GameScaffold(
      title: const Text('Combat'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Select Combat Area, Dungeon, and Slayer Task buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const CombatAreaSelectionDialog(),
                    ),
                    icon: const Icon(Icons.map),
                    label: const Text('Combat Area'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const DungeonSelectionDialog(),
                    ),
                    icon: const Icon(Icons.castle),
                    label: const Text('Dungeon'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const StrongholdSelectionDialog(),
                    ),
                    icon: const Icon(Icons.shield),
                    label: const Text('Stronghold'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SlayerTaskSelectionDialog(),
                    ),
                    icon: const Icon(Icons.assignment),
                    label: const Text('Slayer Task'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Player stats card with food
            _PlayerStatsCard(
              playerHp: state.playerHp,
              maxPlayerHp: state.maxPlayerHp,
              equipment: state.equipment,
              animateAttack: state.isPlayerActive,
              attackTicksRemaining: combatState?.playerAttackTicksRemaining,
              totalAttackTicks: activeMonster != null
                  ? secondsToTicks(computePlayerStats(state).attackSpeed)
                  : null,
            ),
            const SizedBox(height: 16),

            // Attack style selector
            const AttackStyleSelector(),
            const SizedBox(height: 16),

            // Player combat stats card
            _PlayerCombatStatsCard(activeMonster: activeMonster),
            const SizedBox(height: 16),

            // Active combat section
            if (activeMonster != null) ...[
              // Dungeon progress indicator
              if (combatState?.isInDungeon ?? false)
                _DungeonProgressCard(
                  dungeonId: combatState!.dungeonId!,
                  currentMonsterIndex: combatState.dungeonMonsterIndex ?? 0,
                ),
              // Stronghold progress indicator
              if (state.activeActivity case CombatActivity(:final context)
                  when context is SequenceCombatContext &&
                      context.sequenceType == SequenceType.stronghold)
                _StrongholdProgressCard(
                  strongholdId: context.sequenceId,
                  currentMonsterIndex: context.currentMonsterIndex,
                ),
              // Slayer task progress indicator
              if (state.activeActivity case CombatActivity(
                :final context,
              ) when context is SlayerTaskContext)
                _SlayerTaskProgressCard(taskContext: context),
              _MonsterCard(
                action: activeMonster,
                combatState: combatState,
                isInCombat: true,
              ),
              const SizedBox(height: 8),
              if (state.isStunned)
                const ElevatedButton(onPressed: null, child: Text('Stunned'))
              else
                ElevatedButton(
                  onPressed: () => context.dispatch(StopCombatAction()),
                  child: const Text('Run Away'),
                ),
              const SizedBox(height: 16),
            ],

            // Loot container (shown when there's loot)
            if (state.hasLoot) ...[
              _LootContainerCard(loot: state.loot),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _LootContainerCard extends StatelessWidget {
  const _LootContainerCard({required this.loot});

  final LootState loot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Loot (${loot.stackCount}/$maxLootStacks)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => context.dispatch(CollectAllLootAction()),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Loot All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Display loot items in a wrap
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stack in loot.stacks) _LootItemTile(stack: stack),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LootItemTile extends StatelessWidget {
  const _LootItemTile({required this.stack});

  final ItemStack stack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 70,
      decoration: BoxDecoration(
        color: Style.containerBackgroundFilled,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Style.iconColorDefault),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ItemImage(item: stack.item),
          const SizedBox(height: 2),
          Text(
            '${stack.count}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class CombatAreaSelectionDialog extends StatelessWidget {
  const CombatAreaSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final areas = state.registries.combatAreas.all;

    // Get the currently active combat action (if any)
    final activeActionId = state.currentActionId;
    CombatAction? activeMonster;
    if (activeActionId != null) {
      final action = state.registries.actionById(activeActionId);
      if (action is CombatAction) {
        activeMonster = action;
      }
    }

    return AlertDialog(
      title: const Text('Select Combat Area'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final area in areas)
                _CombatAreaTile(
                  area: area,
                  activeMonster: activeMonster,
                  isStunned: state.isStunned,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class DungeonSelectionDialog extends StatelessWidget {
  const DungeonSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final dungeons = state.registries.dungeons.all;

    // Check if currently in a dungeon
    final activeActionId = state.currentActionId;
    MelvorId? activeDungeonId;
    if (activeActionId != null) {
      final actionState = state.actionState(activeActionId);
      activeDungeonId = actionState.combat?.dungeonId;
    }

    return AlertDialog(
      title: const Text('Select Dungeon'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final dungeon in dungeons)
                _DungeonTile(
                  dungeon: dungeon,
                  isActive: activeDungeonId == dungeon.id,
                  isStunned: state.isStunned,
                  completionCount: state.dungeonCompletions[dungeon.id] ?? 0,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DungeonTile extends StatelessWidget {
  const _DungeonTile({
    required this.dungeon,
    required this.isActive,
    required this.isStunned,
    required this.completionCount,
  });

  final Dungeon dungeon;
  final bool isActive;
  final bool isStunned;
  final int completionCount;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final combat = state.registries.combat;
    final monsters = dungeon.monsterIds.map(combat.monsterById).toList();

    return Card(
      color: isActive ? Style.activeColorLight : null,
      child: ListTile(
        leading: dungeon.media != null
            ? CachedImage(assetPath: dungeon.media, size: 40)
            : const Icon(Icons.castle),
        title: Text(dungeon.name),
        subtitle: Text(
          '${monsters.length} monsters • Completed: $completionCount',
        ),
        trailing: isActive
            ? const Icon(Icons.flash_on, color: Style.activeColor)
            : ElevatedButton(
                onPressed: isStunned
                    ? null
                    : () {
                        context.dispatch(StartDungeonAction(dungeon: dungeon));
                        Navigator.of(context).pop();
                      },
                child: const Text('Enter'),
              ),
      ),
    );
  }
}

class _DungeonProgressCard extends StatelessWidget {
  const _DungeonProgressCard({
    required this.dungeonId,
    required this.currentMonsterIndex,
  });

  final MelvorId dungeonId;
  final int currentMonsterIndex;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final dungeon = state.registries.dungeons.byId(dungeonId);

    final totalMonsters = dungeon.monsterIds.length;
    final progress = (currentMonsterIndex + 1) / totalMonsters;

    return Card(
      color: Style.activeColorLight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.castle, size: 20),
                const SizedBox(width: 8),
                Text(
                  dungeon.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Style.activeColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Monster ${currentMonsterIndex + 1} of $totalMonsters',
              style: const TextStyle(
                color: Style.textColorSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StrongholdSelectionDialog extends StatelessWidget {
  const StrongholdSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final strongholds = state.registries.strongholds.all;

    MelvorId? activeStrongholdId;
    if (state.activeActivity case CombatActivity(:final context)
        when context is SequenceCombatContext &&
            context.sequenceType == SequenceType.stronghold) {
      activeStrongholdId = context.sequenceId;
    }

    return AlertDialog(
      title: const Text('Select Stronghold'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stronghold in strongholds)
                _StrongholdTile(
                  stronghold: stronghold,
                  isActive: activeStrongholdId == stronghold.id,
                  isStunned: state.isStunned,
                  completionCount:
                      state.strongholdCompletions[stronghold.id] ?? 0,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _StrongholdTile extends StatelessWidget {
  const _StrongholdTile({
    required this.stronghold,
    required this.isActive,
    required this.isStunned,
    required this.completionCount,
  });

  final Stronghold stronghold;
  final bool isActive;
  final bool isStunned;
  final int completionCount;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final combat = state.registries.combat;
    final monsters = stronghold.monsterIds.map(combat.monsterById).toList();

    return Card(
      color: isActive ? Style.activeColorLight : null,
      child: ListTile(
        leading: stronghold.media != null
            ? CachedImage(assetPath: stronghold.media, size: 40)
            : const Icon(Icons.shield),
        title: Text(stronghold.name),
        subtitle: Text(
          '${monsters.length} monsters'
          ' • Completed: $completionCount',
        ),
        trailing: isActive
            ? const Icon(Icons.flash_on, color: Style.activeColor)
            : ElevatedButton(
                onPressed: isStunned
                    ? null
                    : () {
                        context.dispatch(
                          StartStrongholdAction(stronghold: stronghold),
                        );
                        Navigator.of(context).pop();
                      },
                child: const Text('Enter'),
              ),
      ),
    );
  }
}

class _StrongholdProgressCard extends StatelessWidget {
  const _StrongholdProgressCard({
    required this.strongholdId,
    required this.currentMonsterIndex,
  });

  final MelvorId strongholdId;
  final int currentMonsterIndex;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final stronghold = state.registries.strongholds.byId(strongholdId);

    final totalMonsters = stronghold.monsterIds.length;
    final progress = (currentMonsterIndex + 1) / totalMonsters;

    return Card(
      color: Style.activeColorLight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield, size: 20),
                const SizedBox(width: 8),
                Text(
                  stronghold.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Style.activeColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Monster ${currentMonsterIndex + 1}'
              ' of $totalMonsters',
              style: const TextStyle(
                color: Style.textColorSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CombatAreaTile extends StatelessWidget {
  const _CombatAreaTile({
    required this.area,
    required this.activeMonster,
    required this.isStunned,
  });

  final CombatArea area;
  final CombatAction? activeMonster;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    // Resolve monster IDs to actual CombatAction objects
    final combat = state.registries.combat;
    final monsters = area.monsterIds.map(combat.monsterById).toList();

    // Check if any monster in this area is being fought
    final activeId = activeMonster?.id;
    final hasActiveMonster =
        activeId != null && area.monsterIds.contains(activeId.localId);

    return Card(
      color: hasActiveMonster ? Style.activeColorLight : null,
      child: ExpansionTile(
        leading: area.media != null
            ? CachedImage(assetPath: area.media, size: 40)
            : null,
        title: Text(area.name),
        subtitle: Text('${monsters.length} monsters'),
        initiallyExpanded: hasActiveMonster,
        children: monsters
            .map(
              (monster) => _MonsterListTile(
                monster: monster,
                isActive: activeMonster?.id == monster.id,
                isStunned: isStunned,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MonsterListTile extends StatelessWidget {
  const _MonsterListTile({
    required this.monster,
    required this.isActive,
    required this.isStunned,
  });

  final CombatAction monster;
  final bool isActive;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive ? Style.activeColorLight : null,
      child: ListTile(
        leading: monster.media != null
            ? CachedImage(assetPath: monster.media, size: 40)
            : null,
        title: Row(
          children: [
            CachedImage(assetPath: monster.attackType.assetPath, size: 16),
            const SizedBox(width: 4),
            Text(monster.name),
          ],
        ),
        subtitle: Row(
          children: [
            Text('Lvl ${monster.combatLevel} • '),
            const SkillImage(skill: Skill.hitpoints, size: 14),
            Text(' ${monster.maxHp}'),
          ],
        ),
        trailing: isActive
            ? const Icon(Icons.flash_on, color: Style.activeColor)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => MonsterDropsDialog(monster: monster),
                    ),
                    child: const Text('Drops'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isStunned
                        ? null
                        : () {
                            context.dispatch(
                              StartCombatAction(combatAction: monster),
                            );
                            Navigator.of(context).pop(); // Close dialog
                          },
                    child: const Text('Fight'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PlayerStatsCard extends StatelessWidget {
  const _PlayerStatsCard({
    required this.playerHp,
    required this.maxPlayerHp,
    required this.equipment,
    required this.animateAttack,
    this.attackTicksRemaining,
    this.totalAttackTicks,
  });

  final int playerHp;
  final int maxPlayerHp;
  final Equipment equipment;
  final int? attackTicksRemaining;
  final int? totalAttackTicks;
  final bool animateAttack;

  @override
  Widget build(BuildContext context) {
    final selectedFood = equipment.selectedFood;
    final canEat = selectedFood != null && playerHp < maxPlayerHp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Player',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            HpBar(
              currentHp: playerHp,
              maxHp: maxPlayerHp,
              color: Style.playerHpBarColor,
            ),
            Text('HP: $playerHp / $maxPlayerHp'),
            const SizedBox(height: 8),
            AttackBar(
              ticksRemaining: attackTicksRemaining,
              totalTicks: totalAttackTicks,
              animate: animateAttack,
            ),
            const SizedBox(height: 12),
            // Compact food selector
            _CompactFoodSelector(equipment: equipment, canEat: canEat),
          ],
        ),
      ),
    );
  }
}

class _CompactFoodSelector extends StatelessWidget {
  const _CompactFoodSelector({required this.equipment, required this.canEat});

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

class _PlayerCombatStatsCard extends StatelessWidget {
  const _PlayerCombatStatsCard({this.activeMonster});

  final CombatAction? activeMonster;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final playerStats = computePlayerStats(state);
    final attackStyle = state.attackStyle;
    final combatType = attackStyle.combatType;

    // Get modifiers for crit and lifesteal
    final modifiers = state.createCombatModifierProvider(
      conditionContext: ConditionContext.empty,
    );

    // Calculate crit chance based on combat type
    final critChance = switch (combatType) {
      CombatType.melee => modifiers.meleeCritChance,
      CombatType.ranged => modifiers.rangedCritChance,
      CombatType.magic => modifiers.magicCritChance,
    };

    // Calculate lifesteal based on combat type
    final lifesteal =
        modifiers.lifesteal +
        switch (combatType) {
          CombatType.melee => modifiers.meleeLifesteal,
          CombatType.ranged => modifiers.rangedLifesteal,
          CombatType.magic => modifiers.magicLifesteal,
        };

    // Calculate hit chance if there's an active monster
    double? hitChance;
    if (activeMonster != null) {
      final monsterStats = MonsterCombatStats.fromAction(activeMonster!);
      // Player attacks against the monster's evasion for player's combat type
      final monsterEvasion = switch (combatType) {
        CombatType.melee => monsterStats.meleeEvasion,
        CombatType.ranged => monsterStats.rangedEvasion,
        CombatType.magic => monsterStats.magicEvasion,
      };
      hitChance = CombatCalculator.calculateHitChance(
        playerStats.accuracy,
        monsterEvasion,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Combat Stats',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _StatRow(
              icon: CachedImage(assetPath: combatType.assetPath, size: 16),
              label: 'Damage Type',
              value:
                  combatType.name[0].toUpperCase() +
                  combatType.name.substring(1),
            ),
            _StatRow(label: 'Minimum Hit', value: '${playerStats.minHit}'),
            _StatRow(label: 'Maximum Hit', value: '${playerStats.maxHit}'),
            _StatRow(
              label: 'Chance to Hit',
              value: hitChance != null
                  ? '${(hitChance * 100).toStringAsFixed(1)}%'
                  : '-',
            ),
            _StatRow(
              label: 'Accuracy Rating',
              value: '${playerStats.accuracy}',
            ),
            _StatRow(label: 'Crit Chance', value: '$critChance%'),
            const _StatRow(label: 'Crit Multiplier', value: '150%'),
            _StatRow(label: 'Lifesteal', value: '$lifesteal%'),
            _StatRow(
              label: 'Damage Reduction',
              value:
                  '${(playerStats.damageReduction * 100).toStringAsFixed(1)}%',
            ),
            const Divider(),
            _StatRow(
              icon: const CachedImage(
                assetPath: 'assets/media/skills/combat/attack.png',
                size: 16,
              ),
              label: 'Melee Evasion',
              value: '${playerStats.meleeEvasion}',
            ),
            _StatRow(
              icon: const CachedImage(
                assetPath: 'assets/media/skills/ranged/ranged.png',
                size: 16,
              ),
              label: 'Ranged Evasion',
              value: '${playerStats.rangedEvasion}',
            ),
            _StatRow(
              icon: const CachedImage(
                assetPath: 'assets/media/skills/magic/magic.png',
                size: 16,
              ),
              label: 'Magic Evasion',
              value: '${playerStats.magicEvasion}',
            ),
            _StatRow(
              icon: const SkillImage(skill: Skill.prayer, size: 16),
              label: 'Prayer Points',
              value: '${state.prayerPoints}',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.icon});

  final Widget? icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Style.textColorSecondary),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _MonsterCard extends StatelessWidget {
  const _MonsterCard({
    required this.action,
    required this.combatState,
    required this.isInCombat,
  });

  final CombatAction action;
  final CombatActionState? combatState;
  final bool isInCombat;

  static String _formatPercent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final isSpawning = combatState?.isSpawning ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isSpawning ? _buildSpawning() : _buildActive(context),
      ),
    );
  }

  Widget _buildSpawning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              action.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              'Lvl ${action.combatLevel}',
              style: TextStyle(color: Style.levelTextColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text(
                  'Monster spawning...',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Style.textColorSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActive(BuildContext context) {
    final state = context.state;
    final currentHp = combatState?.monsterHp ?? action.maxHp;
    final monsterStats = MonsterCombatStats.fromAction(action);
    final playerStats = computePlayerStats(state);

    // Calculate monster's hit chance against player
    final monsterHitChance = CombatCalculator.monsterHitChance(
      monsterStats,
      playerStats,
      action.attackType,
    );

    final attackType = action.attackType;
    final attackTypeName =
        attackType.name[0].toUpperCase() + attackType.name.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: action.media != null
              ? CachedImage(assetPath: action.media, size: 80)
              : const Icon(Icons.bug_report, size: 80),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              action.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              'Lvl ${action.combatLevel}',
              style: TextStyle(color: Style.levelTextColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        HpBar(
          currentHp: currentHp,
          maxHp: action.maxHp,
          color: Style.monsterHpBarColor,
        ),
        Text('HP: $currentHp / ${action.maxHp}'),
        const SizedBox(height: 8),
        AttackBar(
          ticksRemaining: combatState?.monsterAttackTicksRemaining,
          totalTicks: isInCombat
              ? ticksFromDuration(
                  Duration(
                    milliseconds: (action.stats.attackSpeed * 1000).round(),
                  ),
                )
              : null,
          animate: state.isMonsterActive,
        ),
        const SizedBox(height: 12),
        // Offensive Stats
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Style.iconColorDefault),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Offensive Stats',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _StatRow(
                icon: CachedImage(assetPath: attackType.assetPath, size: 16),
                label: 'Damage Type',
                value: attackTypeName,
              ),
              _StatRow(label: 'Minimum Hit', value: '${action.stats.minHit}'),
              _StatRow(label: 'Maximum Hit', value: '${action.stats.maxHit}'),
              _StatRow(
                label: 'Chance to Hit',
                value: '${(monsterHitChance * 100).toStringAsFixed(1)}%',
              ),
              _StatRow(
                label: 'Accuracy Rating',
                value: '${monsterStats.accuracy}',
              ),
              _StatRow(
                label: 'Attack Speed',
                value: '${action.stats.attackSpeed}s',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Defensive Stats
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Style.iconColorDefault),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Defensive Stats',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _StatRow(
                icon: const CachedImage(
                  assetPath: 'assets/media/skills/combat/attack.png',
                  size: 16,
                ),
                label: 'Melee Evasion',
                value: '${monsterStats.meleeEvasion}',
              ),
              _StatRow(
                icon: const CachedImage(
                  assetPath: 'assets/media/skills/ranged/ranged.png',
                  size: 16,
                ),
                label: 'Ranged Evasion',
                value: '${monsterStats.rangedEvasion}',
              ),
              _StatRow(
                icon: const CachedImage(
                  assetPath: 'assets/media/skills/magic/magic.png',
                  size: 16,
                ),
                label: 'Magic Evasion',
                value: '${monsterStats.magicEvasion}',
              ),
              _StatRow(
                icon: const Icon(Icons.shield, size: 16),
                label: 'Damage Reduction',
                value: _formatPercent(monsterStats.damageReduction),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'GP Drop: ${action.minGpDrop}-${action.maxGpDrop}',
          style: const TextStyle(color: Style.textColorSecondary),
        ),
        if (isInCombat)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Fighting...'),
              ],
            ),
          ),
      ],
    );
  }
}

class _SlayerTaskProgressCard extends StatelessWidget {
  const _SlayerTaskProgressCard({required this.taskContext});

  final SlayerTaskContext taskContext;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final category = state.registries.slayer.taskCategories.byId(
      taskContext.categoryId,
    );

    final progress = taskContext.killsCompleted / taskContext.killsRequired;

    return Card(
      color: Style.activeColorLight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Slayer Task: ${category?.name ?? 'Unknown'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Style.activeColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Kills: ${taskContext.killsCompleted} / '
              '${taskContext.killsRequired}',
              style: const TextStyle(
                color: Style.textColorSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SlayerTaskSelectionDialog extends StatelessWidget {
  const SlayerTaskSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final categories = state.registries.slayer.taskCategories.all;
    final slayerLevel = state.skillState(Skill.slayer).skillLevel;

    return AlertDialog(
      title: const Text('Select Slayer Task'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final category in categories)
                _SlayerTaskCategoryTile(
                  category: category,
                  slayerLevel: slayerLevel,
                  isStunned: state.isStunned,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SlayerTaskCategoryTile extends StatelessWidget {
  const _SlayerTaskCategoryTile({
    required this.category,
    required this.slayerLevel,
    required this.isStunned,
  });

  final SlayerTaskCategory category;
  final int slayerLevel;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isUnlocked = slayerLevel >= category.level;

    // Check if player can afford the task
    var canAfford = true;
    for (final cost in category.rollCost.costs) {
      if (state.currency(cost.currency) < cost.amount) {
        canAfford = false;
        break;
      }
    }

    final canStart = isUnlocked && canAfford && !isStunned;

    // Build cost string
    final costParts = <String>[];
    for (final cost in category.rollCost.costs) {
      costParts.add('${cost.amount} ${cost.currency.abbreviation}');
    }
    final costString = costParts.isEmpty ? 'Free' : costParts.join(', ');

    return Card(
      child: ListTile(
        leading: const Icon(Icons.assignment),
        title: Text(category.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Level ${category.level} • ~${category.baseTaskLength} kills'),
            Text(
              'Cost: $costString',
              style: TextStyle(color: canAfford ? null : Colors.red),
            ),
          ],
        ),
        trailing: canStart
            ? ElevatedButton(
                onPressed: () {
                  context.dispatch(StartSlayerTaskAction(category: category));
                  Navigator.of(context).pop();
                },
                child: const Text('Start'),
              )
            : Text(
                !isUnlocked ? 'Lvl ${category.level}' : 'Not enough',
                style: const TextStyle(color: Style.textColorSecondary),
              ),
      ),
    );
  }
}
