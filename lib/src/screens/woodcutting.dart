import 'package:flutter/material.dart';

import '../activities.dart';
import '../router.dart';
import '../state.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final category = Category.woodcutting;
    final activities = allActivities
        .where((activity) => activity.category == category)
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => router.pop(context)),
        title: const Text('Woodcutting'),
      ),
      body: Column(
        children: [
          const Text('Woodcutting'),
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
                    final state =
                        context.state.activities[activities[index].name] ?? 0;
                    return ActivityCell(
                      activity: ActivityView(
                        activity: activities[index],
                        state: state,
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
