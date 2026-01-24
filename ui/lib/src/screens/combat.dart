import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/attack_style_selector.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/equipment_slots.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/hp_bar.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/monster_drops_dialog.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

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
            // Select Combat Area and Dungeon buttons
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
            const SizedBox(height: 16),
            // Food slots section
            const Text(
              'Food',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _FoodSlotsRow(equipment: equipment),
            const SizedBox(height: 8),
            // Eat button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canEat
                    ? () => context.dispatch(EatFoodAction())
                    : null,
                icon: const Icon(Icons.restaurant),
                label: Text(
                  selectedFood != null
                      ? 'Eat ${selectedFood.item.name} '
                            '(+${selectedFood.item.healsFor} HP)'
                      : 'No food selected',
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Equipment slots section
            Row(
              children: [
                const Text(
                  'Equipment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const EquipmentGridDialog(),
                  ),
                  icon: const Icon(Icons.grid_view, size: 16),
                  label: const Text('View Grid'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const EquipmentSlotsCompact(),
          ],
        ),
      ),
    );
  }
}

class _FoodSlotsRow extends StatelessWidget {
  const _FoodSlotsRow({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(foodSlotCount, (index) {
        final stack = equipment.foodSlots[index];
        final isSelected = equipment.selectedFoodSlot == index;

        return GestureDetector(
          onTap: () => context.dispatch(SelectFoodSlotAction(slotIndex: index)),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: stack != null
                  ? Style.containerBackgroundFilled
                  : Style.containerBackgroundEmpty,
              border: Border.all(
                color: isSelected
                    ? Style.selectedColor
                    : Style.iconColorDefault,
                width: isSelected ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: stack != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stack.item.name,
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        approximateCountString(stack.count),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Text(
                      'Empty',
                      style: TextStyle(
                        fontSize: 10,
                        color: Style.textColorSecondary,
                      ),
                    ),
                  ),
          ),
        );
      }),
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

  @override
  Widget build(BuildContext context) {
    final currentHp = combatState?.monsterHp ?? action.maxHp;
    final isSpawning = combatState?.isSpawning ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Lvl ${action.combatLevel}',
                  style: TextStyle(color: Style.levelTextColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isSpawning)
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
              )
            else ...[
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
                          milliseconds: (action.stats.attackSpeed * 1000)
                              .round(),
                        ),
                      )
                    : null,
                animate: context.state.isMonsterActive,
              ),
              const SizedBox(height: 8),
              Text('Attack Speed: ${action.stats.attackSpeed}s'),
              Text('Max Hit: ${action.stats.maxHit}'),
              Text('GP Drop: ${action.minGpDrop}-${action.maxGpDrop}'),
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
          ],
        ),
      ),
    );
  }
}
