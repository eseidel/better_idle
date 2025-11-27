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

class ActivityCell extends StatelessWidget {
  const ActivityCell({required this.activity, super.key});

  final ActivityView activity;

  @override
  Widget build(BuildContext context) {
    final activityName = activity.activity.name;
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
          ],
        ),
      ),
    );
  }
}
