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

  /// Calculates per-hour rate from total count and duration.
  double? _perHour(int count, Duration duration) {
    if (duration.inSeconds == 0) return null;
    return count * 3600.0 / duration.inSeconds;
  }

  /// Formats a per-hour rate string.
  String _perHourString(double rate) {
    return '${approximateCountString(rate.round())}/hr';
  }

  @override
  Widget build(BuildContext context) {
    final activeSkill = timeAway.activeSkill;
    final duration = timeAway.duration;
    final changes = timeAway.changes;
    final registries = timeAway.registries;

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

            // Level changes
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

            // XP gained
            if (changes.skillXpChanges.isNotEmpty) ...[
              ...changes.skillXpChanges.entries.map((entry) {
                final xpGained = entry.value;
                final skill = entry.key;
                final xpPerHour = timeAway.predictedXpPerHour[skill];
                final xpText = signedCountString(xpGained);
                final prediction = xpPerHour != null
                    ? ' (${approximateCountString(xpPerHour)} xp/hr)'
                    : '';

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

            // Monsters killed
            if (changes.monstersKilled.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.monstersKilled.entries.map((entry) {
                final monsterId = entry.key;
                final count = entry.value;
                final monster = registries.combat.monsterById(monsterId);
                final rate = _perHour(count, duration);
                final rateText = rate != null
                    ? ' (${_perHourString(rate)})'
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('Killed $count ${monster.name}$rateText'),
                );
              }),
            ],

            // Dungeon completions
            if (changes.dungeonsCompleted.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.dungeonsCompleted.entries.map((entry) {
                final dungeonId = entry.key;
                final count = entry.value;
                final dungeon = registries.dungeons.byId(dungeonId);
                final rate = _perHour(count, duration);
                final rateText = rate != null
                    ? ' (${_perHourString(rate)})'
                    : '';
                final times = count == 1 ? 'time' : 'times';
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    'Completed ${dungeon.name} $count $times$rateText',
                  ),
                );
              }),
            ],

            // Marks found (no per-hour)
            if (changes.marksFound.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.marksFound.entries.map((entry) {
                final familiarId = entry.key;
                final count = entry.value;
                // Get familiar name from item registry (marks are tracked by
                // familiarId which matches the tablet product ID)
                final item = registries.items.byId(familiarId);
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    'Found $count Mark of ${item.name}',
                    style: const TextStyle(color: Style.successColor),
                  ),
                );
              }),
            ],

            // Items gained (excluding food eaten, potions used, tablets used)
            if (changes.inventoryChanges.isNotEmpty) ...[
              ...changes.inventoryChanges.entries.map((entry) {
                final itemId = entry.key;
                final itemCount = entry.value;
                final item = registries.items.byId(itemId);
                final gainedPerHour = timeAway.itemsGainedPerHour[itemId];
                final consumedPerHour = timeAway.itemsConsumedPerHour[itemId];

                final String prediction;
                if (itemCount > 0 && gainedPerHour != null) {
                  prediction =
                      ' (${approximateCountString(gainedPerHour.round())} / hr)';
                } else if (itemCount < 0 && consumedPerHour != null) {
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

            // Currencies earned
            if (changes.currenciesGained.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.currenciesGained.entries.map((entry) {
                final currency = entry.key;
                final amount = entry.value;
                final rate = _perHour(amount, duration);
                final rateText = rate != null
                    ? ' (${_perHourString(rate)})'
                    : '';
                final abbrev = currency.abbreviation;
                final amountStr = approximateCountString(amount);
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    'Earned $amountStr $abbrev$rateText',
                    style: const TextStyle(color: Style.successColor),
                  ),
                );
              }),
            ],

            // Potions used
            if (changes.potionsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.potionsUsed.entries.map((entry) {
                final potionId = entry.key;
                final count = entry.value;
                final potion = registries.items.byId(potionId);
                final rate = _perHour(count, duration);
                final rateText = rate != null
                    ? ' (-${_perHourString(rate)})'
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('Used $count ${potion.name}$rateText'),
                );
              }),
            ],

            // Summoning tablets used (no per-hour)
            if (changes.tabletsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.tabletsUsed.entries.map((entry) {
                final tabletId = entry.key;
                final count = entry.value;
                final tablet = registries.items.byId(tabletId);
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('Used $count ${tablet.name} charges'),
                );
              }),
            ],

            // Food eaten
            if (changes.foodEaten.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.foodEaten.entries.map((entry) {
                final foodId = entry.key;
                final count = entry.value;
                final food = registries.items.byId(foodId);
                final rate = _perHour(count, duration);
                final rateText = rate != null
                    ? ' (${_perHourString(rate)})'
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text('Ate $count ${food.name}$rateText'),
                );
              }),
            ],

            // Dropped items
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
                final item = registries.items.byId(entry.key);
                return ItemChangeRow(item: item, count: -entry.value);
              }),
            ],

            // Deaths
            if (changes.deathCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                changes.deathCount == 1
                    ? 'You died!'
                    : 'You died ${changes.deathCount} times!',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Style.errorColor,
                ),
              ),
              if (changes.lostOnDeath.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 4),
                  child: Text('Luck was on your side. You lost nothing.'),
                )
              else
                ...changes.lostOnDeath.entries.map((entry) {
                  final item = registries.items.byId(entry.key);
                  return ItemChangeRow(item: item, count: -entry.value);
                }),
            ],

            // Empty state
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
