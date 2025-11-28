import 'package:flutter/material.dart' hide Action;

import '../data/actions.dart';
import '../logic/redux_actions.dart';
import '../state.dart';
import '../widgets/context_extensions.dart';
import '../widgets/mastery_pool.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/skill_progress.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final skill = Skill.woodcutting;
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
            child:
                // Grid view of all activities, 2x wide
                GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  itemBuilder: (context, index) {
                    if (index >= actions.length) {
                      return Container();
                    }
                    final action = actions[index];
                    final progressTicks = context.state.activeProgress(action);
                    final actionState = context.state.actionState(action.name);
                    return ActionCell(
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

  @override
  Widget build(BuildContext context) {
    final actionName = action.name;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final progress = (progressTicks ?? 0) / action.maxValue;
    final actionState = context.state.actionState(actionName);

    return GestureDetector(
      onTap: () {
        context.dispatch(StartActionAction(action: action));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text('Cut'),
            Text(actionName, style: labelStyle),
            Text('${action.xp} Skill XP, ${action.duration.inSeconds} seconds'),
            LinearProgressIndicator(value: progress),
            MasteryProgressCell(masteryXp: actionState.masteryXp),
          ],
        ),
      ),
    );
  }
}
