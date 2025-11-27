import 'dart:math';

import 'package:flutter/material.dart';

import '../activities.dart';
import '../state.dart';
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
                    final isCurrent =
                        context.state.activeActionName == action.name;
                    final progressTicks = isCurrent
                        ? (context.state.activeActionView?.progressTicks ?? 0)
                        : 0;
                    return ActionCell(
                      action: ActiveActionView(
                        action: action,
                        progressTicks: progressTicks,
                      ),
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
  const ActionCell({required this.action, super.key});

  final ActiveActionView action;

  @override
  Widget build(BuildContext context) {
    final actionName = action.action.name;
    final skillXp = action.action.xp;
    final masteryXp = masteryXpForAction(context.state, action.action);
    final masteryPoolXp = max(1, 0.25 * masteryXp).toInt();

    return GestureDetector(
      onTap: () {
        context.dispatch(StartActionAction(action: action.action));
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
            Text(actionName),
            LinearProgressIndicator(value: action.progress),
            Text('XP: $skillXp'),
            Text('Mastery XP: $masteryXp'),
            Text('Mastery Pool XP: $masteryPoolXp'),
          ],
        ),
      ),
    );
  }
}
