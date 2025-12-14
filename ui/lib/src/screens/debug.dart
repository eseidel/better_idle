import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/welcome_back_dialog.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      drawer: const AppNavigationDrawer(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _showWelcomeBackDialog(context),
              child: const Text('Show Welcome Back Dialog (Example)'),
            ),
          ],
        ),
      ),
    );
  }

  TimeAway _createExampleTimeAway() {
    // Create an example TimeAway with all types of changes
    final now = DateTime.now();
    // Use Oak Tree action to demonstrate predictions
    final oakTreeAction = actionRegistry.byName('Oak Tree');
    return TimeAway(
      startTime: now.subtract(const Duration(hours: 2, minutes: 30)),
      endTime: now,
      activeSkill: Skill.woodcutting,
      activeAction: oakTreeAction,
      changes: const Changes(
        // Skill level gains
        skillLevelChanges: LevelChanges(
          changes: {
            Skill.woodcutting: LevelChange(startLevel: 19, endLevel: 21),
            Skill.firemaking: LevelChange(startLevel: 5, endLevel: 6),
          },
        ),
        // Skill XP gains
        skillXpChanges: Counts<Skill>(
          counts: {Skill.woodcutting: 450, Skill.firemaking: 125},
        ),
        // Inventory changes (positive and negative)
        inventoryChanges: Counts<String>(
          counts: {
            'Normal Logs': 150, // Gained
            'Oak Logs': 75, // Gained
            'Coal Ore': 12, // Gained (from drops)
            'Bird Nest': 3, // Gained (from drops)
            'Ash': -45, // Consumed
          },
        ),
        // Dropped items (inventory was full)
        droppedItems: Counts<String>(
          counts: {'Willow Logs': 5, 'Teak Logs': 2},
        ),
      ),
      masteryLevels: {'Normal Tree': 2, 'Oak Tree': 1},
    );
  }

  Future<void> _showWelcomeBackDialog(BuildContext context) async {
    final timeAway = _createExampleTimeAway();

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => WelcomeBackDialog(timeAway: timeAway),
      );
    }
  }
}
