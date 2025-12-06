import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.woodcutting;
    final actions = actionRegistry.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    return Scaffold(
      appBar: AppBar(title: const Text('Woodcutting')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryXp),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions.map((action) {
                      final progressTicks = context.state.activeProgress(
                        action,
                      );
                      final actionState = context.state.actionState(
                        action.name,
                      );
                      return SizedBox(
                        width: 300,
                        height: 150,
                        child: ActionCell(
                          action: action,
                          actionState: actionState,
                          progressTicks: progressTicks,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionCell extends StatelessWidget {
  const ActionCell({
    required this.action,
    required this.actionState,
    required this.progressTicks,
    super.key,
  });

  final Action action;
  final ActionState actionState;
  final int? progressTicks;

  Widget _buildUnlocked(BuildContext context) {
    final actionName = action.name;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final activeAction = context.state.activeAction;
    double progress;
    if (activeAction?.name == actionName && activeAction != null) {
      progress =
          (activeAction.totalTicks - activeAction.remainingTicks) /
          activeAction.totalTicks;
    } else {
      progress = 0.0;
    }
    final actionState = context.state.actionState(actionName);
    final canStart = context.state.canStartAction(action);
    final isRunning = context.state.activeAction?.name == actionName;
    final canToggle = canStart || isRunning;
    return GestureDetector(
      onTap: canToggle
          ? () {
              context.dispatch(ToggleActionAction(action: action));
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            const Text('Cut'),
            Text(actionName, style: labelStyle),
            Text(
              '${action.xp} Skill XP, ${action.minDuration.inSeconds} seconds',
            ),
            LinearProgressIndicator(value: progress),
            MasteryProgressCell(masteryXp: actionState.masteryXp),
          ],
        ),
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
