import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class CombatPage extends StatelessWidget {
  const CombatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final areas = state.registries.combatAreas.all;

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
            // Player stats card with food
            _PlayerStatsCard(
              playerHp: state.playerHp,
              maxPlayerHp: state.maxPlayerHp,
              equipment: state.equipment,
              attackTicksRemaining: combatState?.playerAttackTicksRemaining,
              totalAttackTicks: activeMonster != null
                  ? ticksFromDuration(
                      Duration(
                        milliseconds: (playerStats(state).attackSpeed * 1000)
                            .round(),
                      ),
                    )
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

            // Combat Areas
            const Text(
              'Combat Areas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final area in areas)
              _CombatAreaTile(
                area: area,
                activeMonster: activeMonster,
                isStunned: state.isStunned,
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
    final actions = state.registries.actions;
    final monsters = area.monsterIds.map(actions.combatActionById).toList();

    // Check if any monster in this area is being fought
    final activeId = activeMonster?.id;
    final hasActiveMonster =
        activeId != null && area.monsterIds.contains(activeId);

    return Card(
      color: hasActiveMonster ? Style.activeColorLight : null,
      child: ExpansionTile(
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
        title: Text(monster.name),
        subtitle: Text(
          'Lvl ${monster.combatLevel} • HP: ${monster.maxHp} • '
          'Max Hit: ${monster.stats.maxHit}',
        ),
        trailing: isActive
            ? const Icon(Icons.flash_on, color: Style.activeColor)
            : ElevatedButton(
                onPressed: isStunned
                    ? null
                    : () => context.dispatch(
                        StartCombatAction(combatAction: monster),
                      ),
                child: const Text('Fight'),
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
    this.attackTicksRemaining,
    this.totalAttackTicks,
  });

  final int playerHp;
  final int maxPlayerHp;
  final Equipment equipment;
  final int? attackTicksRemaining;
  final int? totalAttackTicks;

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
            _HpBar(
              currentHp: playerHp,
              maxHp: maxPlayerHp,
              color: Style.playerHpBarColor,
            ),
            Text('HP: $playerHp / $maxPlayerHp'),
            const SizedBox(height: 8),
            _AttackBar(
              ticksRemaining: attackTicksRemaining,
              totalTicks: totalAttackTicks,
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
    final isRespawning = combatState?.isRespawning ?? false;

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
            if (isRespawning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text(
                        'Loading next monster...',
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
              _HpBar(
                currentHp: currentHp,
                maxHp: action.maxHp,
                color: Style.monsterHpBarColor,
              ),
              Text('HP: $currentHp / ${action.maxHp}'),
              const SizedBox(height: 8),
              _AttackBar(
                ticksRemaining: combatState?.monsterAttackTicksRemaining,
                totalTicks: isInCombat
                    ? ticksFromDuration(
                        Duration(
                          milliseconds: (action.stats.attackSpeed * 1000)
                              .round(),
                        ),
                      )
                    : null,
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

class _HpBar extends StatelessWidget {
  const _HpBar({
    required this.currentHp,
    required this.maxHp,
    required this.color,
  });

  final int currentHp;
  final int maxHp;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = maxHp > 0 ? (currentHp / maxHp).clamp(0.0, 1.0) : 0.0;

    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: Style.progressBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _AttackBar extends StatelessWidget {
  const _AttackBar({required this.ticksRemaining, required this.totalTicks});

  final int? ticksRemaining;
  final int? totalTicks;

  @override
  Widget build(BuildContext context) {
    final total = totalTicks;
    final remaining = ticksRemaining;
    // Progress goes from 0 to 1 as the attack charges up.
    final progress = (total != null && total > 0 && remaining != null)
        ? (1.0 - remaining / total).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: Style.progressBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: Style.attackBarColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
