import 'package:better_idle/src/widgets/item_change_row.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
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
            SkillImage(skill: activeSkill, size: 48),
            const SizedBox(height: 8),
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
                      color: Style.successColor,
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
                final xpColor = xpGained > 0
                    ? Style.successColor
                    : Style.errorColor;

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
                final itemId = entry.key;
                final itemCount = entry.value;
                final item = timeAway.registries.items.byId(itemId);
                // Check both gained and consumed predictions
                final gainedPerHour = timeAway.itemsGainedPerHour[itemId];
                final consumedPerHour = timeAway.itemsConsumedPerHour[itemId];

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

                return ItemChangeRow(
                  item: item,
                  count: itemCount,
                  suffix: prediction,
                );
              }),
            ],
            if (changes.droppedItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Dropped items (inventory full):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Style.warningColor,
                ),
              ),
              ...changes.droppedItems.entries.map((entry) {
                final item = timeAway.registries.items.byId(entry.key);
                // Show dropped items as negative (they were lost)
                return ItemChangeRow(item: item, count: -entry.value);
              }),
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
