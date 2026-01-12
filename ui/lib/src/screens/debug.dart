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
                  context.dispatch(DebugFillInventoryAction());
                },
                child: const Text('Fill Inventory'),
              ),
              ElevatedButton(
                onPressed: () => _fastForward30Minutes(context),
                child: const Text('Fast Forward 30m'),
              ),
              ElevatedButton(
                onPressed: () {
                  context.dispatch(DebugAddCurrencyAction(Currency.gp, 1000));
                },
                child: const Text('Add 1000 GP'),
              ),
              ElevatedButton(
                onPressed: () {
                  context.dispatch(
                    DebugAddCurrencyAction(Currency.slayerCoins, 1000),
                  );
                },
                child: const Text('Add 1000 SC'),
              ),
              ElevatedButton(
                onPressed: () => _confirmResetState(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reset State'),
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
    final oakTreeId = ActionId.test(Skill.woodcutting, 'Oak Tree');
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
        ActionId.test(Skill.woodcutting, 'Normal Tree'): 2,
        ActionId.test(Skill.woodcutting, 'Oak Tree'): 1,
      },
    );
  }

  Future<void> _fastForward30Minutes(BuildContext context) async {
    const thirtyMinutesInTicks = 30 * 60 * 10; // 30 min * 60 sec * 10 ticks/sec
    final action = AdvanceTicksAction(ticks: thirtyMinutesInTicks);
    context.dispatch(action);

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => WelcomeBackDialog(timeAway: action.timeAway),
      );
    }
  }

  Future<void> _confirmResetState(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset State?'),
        content: const Text(
          'This will erase all progress and start fresh. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      context.dispatch(DebugResetStateAction());
    }
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
