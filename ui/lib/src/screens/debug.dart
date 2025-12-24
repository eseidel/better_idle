import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_catalog_grid.dart';
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
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _showWelcomeBackDialog(context),
                child: const Text('Show Welcome Back Dialog'),
              ),
              ElevatedButton(
                onPressed: () {
                  context.dispatch(DebugAddEggChestsAction());
                },
                child: const Text('Add 50 Egg Chests'),
              ),
              ElevatedButton(
                onPressed: () {
                  context.dispatch(DebugFillInventoryAction());
                },
                child: const Text('Fill Inventory'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tap an item to add it to inventory:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(child: ItemCatalogGrid()),
        ],
      ),
    );
  }

  TimeAway _createExampleTimeAway(Registries registries) {
    // Create an example TimeAway with all types of changes
    final now = DateTime.now();
    // Use Oak Tree action to demonstrate predictions
    final oakTreeId = ActionId(Skill.woodcutting.id, 'Oak Tree');
    final oakTreeAction = registries.actions.byId(oakTreeId);
    return TimeAway(
      registries: registries,
      startTime: now.subtract(const Duration(hours: 2, minutes: 30)),
      endTime: now,
      activeSkill: Skill.woodcutting,
      activeAction: oakTreeAction,
      changes: Changes(
        // Skill level gains
        skillLevelChanges: const LevelChanges(
          changes: {
            Skill.woodcutting: LevelChange(startLevel: 19, endLevel: 21),
            Skill.firemaking: LevelChange(startLevel: 5, endLevel: 6),
          },
        ),
        // Skill XP gains
        skillXpChanges: const Counts<Skill>(
          counts: {Skill.woodcutting: 450, Skill.firemaking: 125},
        ),
        // Inventory changes (positive and negative)
        inventoryChanges: Counts<MelvorId>(
          counts: {
            MelvorId.fromName('Normal Logs'): 150, // Gained
            MelvorId.fromName('Oak Logs'): 75, // Gained
            MelvorId.fromName('Coal Ore'): 12, // Gained (from drops)
            MelvorId.fromName('Bird Nest'): 3, // Gained (from drops)
            MelvorId.fromName('Ash'): -45, // Consumed
          },
        ),
        // Dropped items (inventory was full)
        droppedItems: Counts<MelvorId>(
          counts: {
            MelvorId.fromName('Willow Logs'): 5,
            MelvorId.fromName('Teak Logs'): 2,
          },
        ),
      ),
      masteryLevels: {
        ActionId(Skill.woodcutting.id, 'Normal Tree'): 2,
        ActionId(Skill.woodcutting.id, 'Oak Tree'): 1,
      },
    );
  }

  Future<void> _showWelcomeBackDialog(BuildContext context) async {
    final timeAway = _createExampleTimeAway(context.state.registries);

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => WelcomeBackDialog(timeAway: timeAway),
      );
    }
  }
}
