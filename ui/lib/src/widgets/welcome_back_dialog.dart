import 'package:better_idle/src/widgets/skills.dart';
import 'package:better_idle/src/widgets/strings.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

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
              ...changes.skillLevelChanges.entries.map((entry) {
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
              }),
            ],
            if (changes.skillXpChanges.isNotEmpty) ...[
              ...changes.skillXpChanges.entries.map((entry) {
                final xpGained = entry.value;
                final skill = entry.key;
                final xpPerHour = timeAway.predictedXpPerHour[skill];
                final xpText = signedCountString(xpGained);
                final prediction = xpPerHour != null
                    ? ' (${approximateCountString(xpPerHour)} xp/hr)'
                    : '';

                // Color XP gains green (XP is typically always positive)
                final xpColor = xpGained > 0 ? Colors.green : Colors.red;

                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: xpText,
                          style: TextStyle(color: xpColor),
                        ),
                        TextSpan(text: ' ${skill.name} xp$prediction'),
                      ],
                    ),
                  ),
                );
              }),
            ],
            if (changes.inventoryChanges.isNotEmpty) ...[
              ...changes.inventoryChanges.entries.map((entry) {
                final itemName = entry.key;
                final itemCount = entry.value;
                // Check both gained and consumed predictions
                final gainedPerHour = timeAway.itemsGainedPerHour[itemName];
                final consumedPerHour = timeAway.itemsConsumedPerHour[itemName];
                final countText = signedCountString(itemCount);

                // Determine which prediction to show based on item count change
                final String prediction;
                if (itemCount > 0 && gainedPerHour != null) {
                  // Positive change - show gain prediction
                  prediction =
                      ' (${approximateCountString(gainedPerHour.round())} / hr)';
                } else if (itemCount < 0 && consumedPerHour != null) {
                  // Negative change - show consumption prediction
                  prediction =
                      ' (${approximateCountString(consumedPerHour.round())} / hr)';
                } else {
                  prediction = '';
                }

                // Determine color based on gain/loss
                final countColor = itemCount > 0 ? Colors.green : Colors.red;

                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: countText,
                          style: TextStyle(color: countColor),
                        ),
                        TextSpan(text: ' $itemName$prediction'),
                      ],
                    ),
                  ),
                );
              }),
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
