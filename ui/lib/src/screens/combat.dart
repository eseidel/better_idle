import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/equipment_slots.dart';
import 'package:better_idle/src/widgets/hp_bar.dart';
import 'package:better_idle/src/widgets/monster_drops_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
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
    final activeAction = state.activeAction;
    CombatAction? activeMonster;
    CombatActionState? combatState;
    if (activeAction != null) {
      final action = state.registries.actions.byId(activeAction.id);
      if (action is CombatAction) {
        activeMonster = action;
        combatState = state.actionState(activeMonster.id).combat;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Combat')),
      drawer: const AppNavigationDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Select Combat Area button
            ElevatedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const CombatAreaSelectionDialog(),
              ),
              icon: const Icon(Icons.map),
              label: const Text('Select Combat Area'),
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

            // Active combat section
            if (activeMonster != null) ...[
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
              const SizedBox(height: 24),
            ],
          ],
        ),
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
    final activeAction = state.activeAction;
    CombatAction? activeMonster;
    if (activeAction != null) {
      final action = state.registries.actions.byId(activeAction.id);
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
    final actions = state.registries.actions;
    final monsters = area.monsterIds.map(actions.combatWithId).toList();

    // Check if any monster in this area is being fought
    final activeId = activeMonster?.id;
    final hasActiveMonster =
        activeId != null && area.monsterIds.contains(activeId.localId);

    return Card(
      color: hasActiveMonster ? Style.activeColorLight : null,
      child: ExpansionTile(
        leading: area.media != null
            ? CachedImage(assetPath: area.media!, size: 40)
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
            ? CachedImage(assetPath: monster.media!, size: 40)
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
            const Text(
              'Equipment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
