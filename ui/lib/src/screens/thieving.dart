import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class ThievingPage extends StatelessWidget {
  const ThievingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.thieving;
    final actions = actionRegistry.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);
    final playerHp = context.state.playerHp;
    final maxPlayerHp = context.state.maxPlayerHp;

    return Scaffold(
      appBar: AppBar(title: const Text('Thieving')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryXp),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HpBar(
                  currentHp: playerHp,
                  maxHp: maxPlayerHp,
                  color: Colors.green,
                ),
                const SizedBox(height: 4),
                Text('HP: $playerHp / $maxPlayerHp'),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
              ),
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final action = actions[index] as ThievingAction;
                final progressTicks = context.state.activeProgress(action);
                final actionState = context.state.actionState(action.name);
                return ThievingActionCell(
                  action: action,
                  actionState: actionState,
                  progressTicks: progressTicks,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ThievingActionCell extends StatelessWidget {
  const ThievingActionCell({
    required this.action,
    required this.actionState,
    required this.progressTicks,
    super.key,
  });

  final ThievingAction action;
  final ActionState actionState;
  final int? progressTicks;

  Widget _buildUnlocked(BuildContext context) {
    final actionName = action.name;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final actionState = context.state.actionState(actionName);
    final canStart = context.state.canStartAction(action);
    final isRunning = context.state.activeAction?.name == actionName;
    final isStunned = context.state.isStunned;
    final canToggle = (canStart || isRunning) && !isStunned;

    final perAction = xpPerAction(context.state, action);

    // Calculate stealth and success chance
    final thievingLevel = levelForXp(
      context.state.skillState(Skill.thieving).xp,
    );
    final masteryLevel = levelForXp(actionState.masteryXp);
    final stealth = calculateStealth(thievingLevel, masteryLevel);
    final successChance = ((100 + stealth) / (100 + action.perception)).clamp(
      0.0,
      1.0,
    );
    final successPercent = (successChance * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isStunned ? Colors.orange[100] : Colors.white,
        border: Border.all(color: isStunned ? Colors.orange : Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (isStunned) ...[
            Text(
              'Stunned',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
          ],
          const Text('Pickpocket'),
          Text(actionName, style: labelStyle),
          const SizedBox(height: 4),
          Text('Success: $successPercent%'),
          Text('Stealth: $stealth'),
          Text('XP per success: ${perAction.xp}'),
          Text('Max Gold: ${action.maxGold}'),
          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canToggle
                ? () {
                    context.dispatch(ToggleActionAction(action: action));
                  }
                : null,
            child: Text(isRunning ? 'Stop' : 'Pickpocket'),
          ),
          if (isRunning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Thieving...'),
                ],
              ),
            )
          else
            const SizedBox(height: 40, child: Text('Idle')),
        ],
      ),
    );
  }

  Widget _buildLocked(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [const Text('Locked'), Text('Level ${action.unlockLevel}')],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(action.skill);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= action.unlockLevel;
    if (isUnlocked) {
      return _buildUnlocked(context);
    } else {
      return _buildLocked(context);
    }
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
