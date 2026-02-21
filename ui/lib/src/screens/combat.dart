import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/attack_style_selector.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/currency_display.dart';
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
                    icon: const CachedImage(
                      assetPath: 'assets/media/skills/combat/combat.png',
                      size: 20,
                    ),
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
                    icon: const CachedImage(
                      assetPath: 'assets/media/skills/combat/dungeon.png',
                      size: 20,
                    ),
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
                    icon: const CachedImage(
                      assetPath: 'assets/media/skills/combat/strongholds.png',
                      size: 20,
                    ),
                    label: const Text('Stronghold'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const SlayerAreaSelectionDialog(),
                    ),
                    icon: const CachedImage(
                      assetPath: 'assets/media/skills/slayer/slayer.png',
                      size: 20,
                    ),
                    label: const Text('Slayer Area'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _SlayerTaskCard(),
            const SizedBox(height: 16),

            // Player stats card with food
            _PlayerStatsCard(
              playerHp: state.playerHp,
              maxPlayerHp: state.maxPlayerHp,
              equipment: state.equipment,
              animateAttack: state.isPlayerActive,
              attackTicksRemaining: combatState?.playerAttackTicksRemaining,
              totalAttackTicks: activeMonster != null
                  ? secondsToTicks(
                      computePlayerStats(
                        state,
                        // UI display only, no live combat state.
                        conditionContext: ConditionContext.empty,
                      ).attackSpeed,
                    )
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
              // Sequence (dungeon/stronghold) progress indicator
              if (state.activeActivity case CombatActivity(
                :final context,
              ) when context is SequenceCombatContext)
                _SequenceProgressCard(
                  name: switch (context.sequenceType) {
                    SequenceType.dungeon =>
                      state.registries.combat.dungeons
                          .byId(context.sequenceId)
                          .name,
                    SequenceType.stronghold =>
                      state.registries.combat.strongholds
                          .byId(context.sequenceId)
                          .name,
                  },
                  assetPath: switch (context.sequenceType) {
                    SequenceType.dungeon =>
                      'assets/media/skills/combat/dungeon.png',
                    SequenceType.stronghold =>
                      'assets/media/skills/combat/strongholds.png',
                  },
                  currentMonsterIndex: context.currentMonsterIndex,
                  totalMonsters: context.monsterIds.length,
                ),
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

    return _SequenceSelectionDialog(
      title: 'Select Dungeon',
      entries: [
        for (final dungeon in dungeons)
          _SequenceEntry(
            id: dungeon.id,
            name: dungeon.name,
            monsterIds: dungeon.monsterIds,
            media: dungeon.media,
            isActive: activeDungeonId == dungeon.id,
            completionCount: state.dungeonCompletions[dungeon.id] ?? 0,
            onEnter: () =>
                context.dispatch(StartDungeonAction(dungeon: dungeon)),
          ),
      ],
      isStunned: state.isStunned,
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

    return _SequenceSelectionDialog(
      title: 'Select Stronghold',
      entries: [
        for (final stronghold in strongholds)
          _SequenceEntry(
            id: stronghold.id,
            name: stronghold.name,
            monsterIds: stronghold.monsterIds,
            media: stronghold.media,
            isActive: activeStrongholdId == stronghold.id,
            completionCount: state.strongholdCompletions[stronghold.id] ?? 0,
            onEnter: () =>
                context.dispatch(StartStrongholdAction(stronghold: stronghold)),
          ),
      ],
      isStunned: state.isStunned,
    );
  }
}

@immutable
class _SequenceEntry {
  const _SequenceEntry({
    required this.id,
    required this.name,
    required this.monsterIds,
    required this.isActive,
    required this.completionCount,
    required this.onEnter,
    this.media,
  });

  final MelvorId id;
  final String name;
  final List<MelvorId> monsterIds;
  final String? media;
  final bool isActive;
  final int completionCount;
  final VoidCallback onEnter;
}

class _SequenceSelectionDialog extends StatelessWidget {
  const _SequenceSelectionDialog({
    required this.title,
    required this.entries,
    required this.isStunned,
  });

  final String title;
  final List<_SequenceEntry> entries;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries)
                _SequenceTile(entry: entry, isStunned: isStunned),
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

class _SequenceTile extends StatelessWidget {
  const _SequenceTile({required this.entry, required this.isStunned});

  final _SequenceEntry entry;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    final combat = context.state.registries.combat;
    final monsterCount = entry.monsterIds
        .map(combat.monsterById)
        .toList()
        .length;

    return Card(
      color: entry.isActive ? Style.activeColorLight : null,
      child: ListTile(
        leading: CachedImage(assetPath: entry.media, size: 40),
        title: Text(entry.name),
        subtitle: Text(
          '$monsterCount monsters • Completed: ${entry.completionCount}',
        ),
        trailing: entry.isActive
            ? const Icon(Icons.flash_on, color: Style.activeColor)
            : ElevatedButton(
                onPressed: isStunned
                    ? null
                    : () {
                        entry.onEnter();
                        Navigator.of(context).pop();
                      },
                child: const Text('Enter'),
              ),
      ),
    );
  }
}

class _SequenceProgressCard extends StatelessWidget {
  const _SequenceProgressCard({
    required this.name,
    required this.assetPath,
    required this.currentMonsterIndex,
    required this.totalMonsters,
  });

  final String name;
  final String assetPath;
  final int currentMonsterIndex;
  final int totalMonsters;

  @override
  Widget build(BuildContext context) {
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
                CachedImage(assetPath: assetPath, size: 20),
                const SizedBox(width: 8),
                Text(
                  name,
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
    this.onFight,
  });

  final CombatAction monster;
  final bool isActive;
  final bool isStunned;

  /// Custom fight callback. If null, dispatches [StartCombatAction].
  final VoidCallback? onFight;

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
                        : onFight ??
                              () {
                                context.dispatch(
                                  StartCombatAction(combatAction: monster),
                                );
                                Navigator.of(context).pop();
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
    // TODO(eseidel): Pass real ConditionContext from combat state.
    final playerStats = computePlayerStats(
      state,
      conditionContext: ConditionContext.empty, // UI display only.
    );
    final attackStyle = state.attackStyle;
    final combatType = attackStyle.combatType;

    // Get modifiers for crit and lifesteal
    final modifiers = state.createCombatModifierProvider(
      conditionContext: ConditionContext.empty, // UI display only.
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
    final playerStats = computePlayerStats(
      state,
      conditionContext: ConditionContext.empty, // UI display only.
    );

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

class _SlayerTaskCard extends StatelessWidget {
  const _SlayerTaskCard();

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    final task = state.slayerTask;
    final hasTask = task != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: always visible.
            Row(
              children: [
                const CachedImage(
                  assetPath: 'assets/media/skills/slayer/slayer.png',
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Slayer Task',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const SlayerTaskSelectionDialog(),
                  ),
                  child: const Text('New Task'),
                ),
              ],
            ),
            // Task details: only when a task is active.
            if (hasTask) ...[const Divider(), _SlayerTaskDetails(task: task)],
          ],
        ),
      ),
    );
  }
}

class _SlayerTaskDetails extends StatelessWidget {
  const _SlayerTaskDetails({required this.task});

  final SlayerTask task;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final combat = state.registries.combat;
    final category = state.registries.slayer.taskCategories.byId(
      task.categoryId,
    );
    final monster = combat.monsterById(task.monsterId);

    return Row(
      children: [
        CachedImage(assetPath: monster.media, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category?.name ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${task.killsRemaining} x ${monster.name}',
                style: const TextStyle(color: Style.textColorSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SlayerAreaSelectionDialog extends StatelessWidget {
  const SlayerAreaSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final areas = state.registries.slayer.areas.all;

    final activeActionId = state.currentActionId;
    CombatAction? activeMonster;
    if (activeActionId != null) {
      final action = state.registries.actionById(activeActionId);
      if (action is CombatAction) {
        activeMonster = action;
      }
    }

    return AlertDialog(
      title: const Text('Select Slayer Area'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final area in areas)
                _SlayerAreaTile(
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

class _SlayerAreaTile extends StatelessWidget {
  const _SlayerAreaTile({
    required this.area,
    required this.activeMonster,
    required this.isStunned,
  });

  final SlayerArea area;
  final CombatAction? activeMonster;
  final bool isStunned;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final combat = state.registries.combat;
    final monsters = area.monsterIds.map(combat.monsterById).toList();
    final unmet = state.unmetSlayerAreaRequirements(area);
    final meetsRequirements = unmet.isEmpty;

    final activeId = activeMonster?.id;
    final hasActiveMonster =
        activeId != null && area.monsterIds.contains(activeId.localId);

    return Card(
      color: hasActiveMonster ? Style.activeColorLight : null,
      child: ExpansionTile(
        leading: CachedImage(assetPath: area.media, size: 40),
        title: Text(area.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${monsters.length} monsters'),
            if (!meetsRequirements)
              Text(
                _requirementText(unmet, state),
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            if (area.areaEffectDescription != null)
              Text(
                area.areaEffectDescription!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Style.textColorSecondary,
                ),
              ),
          ],
        ),
        initiallyExpanded: hasActiveMonster,
        children: monsters
            .map(
              (monster) => _MonsterListTile(
                monster: monster,
                isActive: activeMonster?.id == monster.id,
                isStunned: isStunned || !meetsRequirements,
                onFight: meetsRequirements
                    ? () {
                        context.dispatch(
                          StartSlayerAreaCombatAction(
                            area: area,
                            monster: monster,
                          ),
                        );
                        Navigator.of(context).pop();
                      }
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }

  String _requirementText(
    List<SlayerAreaRequirement> unmet,
    GlobalState state,
  ) {
    final parts = <String>[];
    for (final req in unmet) {
      switch (req) {
        case SlayerLevelRequirement(:final level):
          parts.add('Slayer Lv. $level');
        case SlayerItemRequirement(:final itemId):
          final item = state.registries.items.byId(itemId);
          parts.add('Equip ${item.name}');
        case SlayerDungeonRequirement(:final dungeonId, :final count):
          final dungeon = state.registries.combat.dungeons.byId(dungeonId);
          parts.add('Complete ${dungeon.name} x$count');
        case SlayerShopPurchaseRequirement(:final purchaseId, :final count):
          parts.add('Shop purchase ${purchaseId.name} x$count');
      }
    }
    return 'Requires: ${parts.join(', ')}';
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

    // Check affordability per currency for color-coding.
    final canAffordMap = <Currency, bool>{};
    var canAfford = true;
    for (final cost in category.rollCost.costs) {
      final affordable = state.currency(cost.currency) >= cost.amount;
      canAffordMap[cost.currency] = affordable;
      if (!affordable) canAfford = false;
    }

    final canStart = isUnlocked && canAfford && !isStunned;

    // Combat level range from monster selection.
    final levelRange = switch (category.monsterSelection) {
      CombatLevelSelection(:final minLevel, :final maxLevel) =>
        '$minLevel - $maxLevel',
    };

    return Card(
      child: InkWell(
        onTap: canStart
            ? () {
                context.dispatch(StartSlayerTaskAction(category: category));
                Navigator.of(context).pop();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? null : Style.textColorSecondary,
                  ),
                ),
              ),
              const CachedImage(
                assetPath: 'assets/media/skills/combat/combat.png',
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(levelRange),
              const SizedBox(width: 12),
              CurrencyListDisplay.fromCosts(
                category.rollCost,
                canAfford: canAffordMap,
                emptyText: 'Free',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
