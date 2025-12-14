import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class FishingPage extends StatelessWidget {
  const FishingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.fishing;
    final actions = actionRegistry.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    return Scaffold(
      appBar: AppBar(title: const Text('Fishing')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
          Expanded(
            child:
                // Grid view of all activities, 2x wide
                GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  itemCount: actions.length,
                  itemBuilder: (context, index) {
                    final action = actions[index];
                    final progressTicks = context.state.activeProgress(action);
                    final actionState = context.state.actionState(action.name);
                    return FishingActionCell(
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

class FishingActionCell extends StatelessWidget {
  const FishingActionCell({
    required this.action,
    required this.actionState,
    required this.progressTicks,
    super.key,
  });

  final SkillAction action;
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

    // Format duration display
    String formatDuration(Duration d) {
      final seconds = d.inMilliseconds / 1000;
      // Round to at most 2 decimal places.
      final roundedSeconds = (seconds * 100).round() / 100;
      // Don't show the decimal point if it's a whole number.
      if (roundedSeconds % 1 == 0) {
        return '${roundedSeconds.toInt()}s';
      }
      return '${roundedSeconds}s';
    }

    final durationText = action.isFixedDuration
        ? '🕐 ${formatDuration(action.minDuration)}'
        : '🕐 ${formatDuration(action.minDuration)} - '
              '${formatDuration(action.maxDuration)}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text('Fishing'),
          Text(actionName, style: labelStyle),
          XpBadgesRow(action: action),
          Text(durationText),

          MasteryProgressCell(masteryXp: actionState.masteryXp),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: canStart || isRunning
                ? () {
                    context.dispatch(ToggleActionAction(action: action));
                  }
                : null,
            child: Text(isRunning ? 'Stop Fishing' : 'Start Fishing'),
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
                  Text('Fishing'),
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
