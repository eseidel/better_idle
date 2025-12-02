import 'package:flutter/material.dart';

import '../logic/consume_ticks.dart';
import '../logic/redux_actions.dart';
import 'duration.dart';

/// A dialog shown when returning to the app after being away.
/// Displays the changes (inventory and XP) that occurred while away.
class WelcomeBackDialog extends StatelessWidget {
  const WelcomeBackDialog({required this.timeAway, super.key});

  final TimeAway timeAway;

  @override
  Widget build(BuildContext context) {
    final activeSkill = timeAway.activeSkill;
    final duration = timeAway.duration;
    final changes = timeAway.changes;
    return AlertDialog(
      title: Column(
        children: [
          if (activeSkill != null)
            // This will eventually be an icon instead.
            Text(
              activeSkill.name,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          const Text('Welcome Back!'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You were away for ${approximateDuration(duration)}.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (changes.skillXpChanges.isNotEmpty) ...[
              ...changes.skillXpChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('+${entry.value} ${entry.key.name} xp'),
                ),
              ),
            ],
            if (changes.inventoryChanges.isNotEmpty) ...[
              ...changes.inventoryChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('+${entry.value} ${entry.key}'),
                ),
              ),
            ],
            // This dialog shouldn't be shown if there are no changes.
            if (changes.isEmpty) ...[const Text('Nothing new happened.')],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Dispatch action to clear timeAway
            context.dispatchSync(DismissWelcomeBackDialogAction());
            // Pop the dialog
            Navigator.of(context).pop();
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
