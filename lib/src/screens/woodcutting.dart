import 'package:flutter/material.dart';

import '../activities.dart';
import '../router.dart';
import '../state.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentActivity = context.state.currentActivity;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => router.pop(context)),
        title: const Text('Woodcutting'),
      ),
      body: Column(
        children: [
          const Text('Woodcutting'),
          LinearProgressIndicator(value: currentActivity?.progress ?? 0.0),
          ElevatedButton(
            child: Text(currentActivity == null ? 'Start' : 'Stop'),
            onPressed: () {
              if (currentActivity == null) {
                context.dispatch(StartActivityAction(activity: woodcutting));
              } else {
                context.dispatch(StopActivityAction());
              }
            },
          ),
        ],
      ),
    );
  }
}
