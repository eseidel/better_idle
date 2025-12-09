import 'package:better_idle/src/data/combat.dart';
import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:flutter/material.dart';

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
            // Player stats card
            _PlayerStatsCard(playerHp: state.playerHp),
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
  const _PlayerStatsCard({required this.playerHp});

  final int playerHp;

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
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
