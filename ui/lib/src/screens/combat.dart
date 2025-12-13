import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class CombatPage extends StatelessWidget {
  const CombatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final plant = combatActionByName('Plant');

    // Check if we're in combat with this monster
    final isInCombat = state.activeAction?.name == plant.name;
    // Get combat state from action states if in combat
    final combatState = isInCombat
        ? state.actionState(plant.name).combat
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Combat')),
      drawer: const AppNavigationDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Player stats card with food
            _PlayerStatsCard(
              playerHp: state.playerHp,
              maxPlayerHp: state.maxPlayerHp,
              equipment: state.equipment,
            ),
            const SizedBox(height: 16),

            // Monster card
            _MonsterCard(
              action: plant,
              combatState: combatState,
              isInCombat: isInCombat,
            ),
            const SizedBox(height: 16),

            // Fight button
            if (!isInCombat)
              ElevatedButton(
                onPressed: () {
                  context.dispatch(StartCombatAction(combatAction: plant));
                },
                child: const Text('Fight Plant'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  context.dispatch(StopCombatAction());
                },
                child: const Text('Run Away'),
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
  });

  final int playerHp;
  final int maxPlayerHp;
  final Equipment equipment;

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
              color: Colors.green,
            ),
            Text('HP: $playerHp / $maxPlayerHp'),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
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
              color: stack != null ? Colors.green[100] : Colors.grey[200],
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey,
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
                      style: TextStyle(fontSize: 10, color: Colors.grey),
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
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _HpBar(
              currentHp: currentHp,
              maxHp: action.maxHp,
              color: Colors.red,
            ),
            Text('HP: $currentHp / ${action.maxHp}'),
            const SizedBox(height: 8),
            Text('Attack Speed: ${action.stats.attackSpeed}s'),
            Text('Max Hit: ${action.stats.maxHit}'),
            Text('GP Drop: ${action.minGpDrop}-${action.maxGpDrop}'),
            if (isRespawning)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Respawning...',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              )
            else if (isInCombat)
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
        color: Colors.grey[300],
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
