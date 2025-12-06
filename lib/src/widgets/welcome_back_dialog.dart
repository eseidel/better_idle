import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';

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
          if (activeSkill != null) ...[
            Icon(activeSkill.icon),
            const SizedBox(width: 8),
          ],
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (changes.skillLevelChanges.isNotEmpty) ...[
              ...changes.skillLevelChanges.entries.map(
                (entry) {
                  final skill = entry.key;
                  final levelChange = entry.value;
                  final levelsGained = levelChange.levelsGained;
                  final range =
                      '${levelChange.startLevel}->${levelChange.endLevel}';
                  final levelText = levelsGained > 1
                      ? 'gained $levelsGained levels $range'
                      : 'level up $range';
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(
                      '${skill.name} $levelText!',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  );
                },
              ),
            ],
            if (changes.skillXpChanges.isNotEmpty) ...[
              ...changes.skillXpChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    '${signedCountString(entry.value)} ${entry.key.name} xp',
                  ),
                ),
              ),
            ],
            if (changes.inventoryChanges.isNotEmpty) ...[
              ...changes.inventoryChanges.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('${signedCountString(entry.value)} ${entry.key}'),
                ),
              ),
            ],
            if (changes.droppedItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Dropped items (inventory full):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              ...changes.droppedItems.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    '${entry.value} ${entry.key}',
                    style: const TextStyle(color: Colors.orange),
                  ),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
