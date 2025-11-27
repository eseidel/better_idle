import 'dart:math';

import 'package:flutter/material.dart';

import '../activities.dart';
import '../state.dart';
import '../widgets/navigation_drawer.dart';
import '../widgets/skill_progress.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final skill = Skill.woodcutting;
    final activities = allActivities
        .where((activity) => activity.skill == skill)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Woodcutting')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: context.state.skillXp(skill)),
          Expanded(
            child:
                // Grid view of all activities, 2x wide
                GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                  ),
                  itemBuilder: (context, index) {
                    if (index >= activities.length) {
                      return Container();
                    }
                    final activity = activities[index];
                    final isCurrent =
                        context.state.currentActivityName == activity.name;
                    final state = isCurrent
                        ? (context.state.activeActivity?.progress ?? 0)
                        : 0;
                    return ActivityCell(
                      activity: ActivityView(activity: activity, state: state),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

int calculateMasteryXp({
  required int unlockedActions,
  required int playerTotalMasteryForSkill,
  required int totalMasteryForSkill,
  required int itemMasteryLevel,
  required int totalItemsInSkill,
  required double actionTime, // In seconds, or ticks as appropriate
  required double bonus, // e.g. 0.1 for +10%
}) {
  final masteryPortion =
      unlockedActions * (playerTotalMasteryForSkill / totalMasteryForSkill);
  final itemPortion = itemMasteryLevel * (totalItemsInSkill / 10);
  final baseValue = masteryPortion + itemPortion;
  return max(1, baseValue * actionTime * 0.5 * (1 + bonus)).toInt();
}

class ActivityCell extends StatelessWidget {
  const ActivityCell({required this.activity, super.key});

  final ActivityView activity;

  @override
  Widget build(BuildContext context) {
    final activityName = activity.activity.name;
    final skillXp = activity.activity.xp;
    final masteryXp = calculateMasteryXp(
      unlockedActions: 1,
      playerTotalMasteryForSkill: 100,
      totalMasteryForSkill: 1000,
      itemMasteryLevel: 1,
      totalItemsInSkill: 100,
      actionTime: 1,
      bonus: 0.1,
    );
    final masteryPoolXp = max(1, 0.25 * masteryXp).toInt();

    return GestureDetector(
      onTap: () {
        context.dispatch(StartActivityAction(activityName: activityName));
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
            Text(activityName),
            LinearProgressIndicator(value: activity.progress),
            Text('XP: $skillXp'),
            Text('Mastery XP: $masteryXp'),
            Text('Mastery Pool XP: $masteryPoolXp'),
          ],
        ),
      ),
    );
  }
}
