import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/item_change_row.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog shown when returning to the app after being away.
///
/// Always driven by [ValueListenable] notifiers so the dialog can transition
/// in-place between loading (progress bar) and results states. When [result]
/// is non-null, results are shown; otherwise a progress bar is displayed.
class WelcomeBackDialog extends StatelessWidget {
  const WelcomeBackDialog({
    required this.awayDuration,
    required this.progress,
    required this.result,
    super.key,
  });

  final ValueListenable<Duration> awayDuration;
  final ValueListenable<double> progress;
  final ValueListenable<TimeAway?> result;

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
    return ValueListenableBuilder<TimeAway?>(
      valueListenable: result,
      builder: (context, resolvedTimeAway, _) {
        if (resolvedTimeAway != null) {
          return _buildResults(context, resolvedTimeAway);
        }
        // Still loading - show progress bar
        return ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, progressValue, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: awayDuration,
              builder: (context, durationValue, _) {
                return AlertDialog(
                  title: const Column(children: [Text('Welcome Back!')]),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'You were away for '
                        '${approximateDuration(durationValue)}.',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      const Text('Processing...'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progressValue),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildResults(BuildContext context, TimeAway timeAway) {
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

            // 1. XP gained (including per hour estimates)
            if (changes.skillXpChanges.isNotEmpty) ...[
              ...changes.skillXpChanges.entries.map((entry) {
                final xpGained = entry.value;
                final skill = entry.key;
                final xpPerHour = timeAway.predictedXpPerHour[skill];
                final xpText = signedCountString(xpGained);
                final prediction = xpPerHour != null
                    ? ' (${approximateCountString(xpPerHour)}/hr)'
                    : '';

                final xpColor = xpGained > 0
                    ? Style.successColor
                    : Style.errorColor;

                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(xpText, style: TextStyle(color: xpColor)),
                      const SizedBox(width: 4),
                      SkillImage(skill: skill, size: 16),
                      const SizedBox(width: 4),
                      Flexible(child: Text('xp$prediction')),
                    ],
                  ),
                );
              }),
            ],

            // Level changes (shown after XP for emphasis)
            if (changes.skillLevelChanges.isNotEmpty) ...[
              ...changes.skillLevelChanges.entries.map((entry) {
                final skill = entry.key;
                final levelChange = entry.value;
                final levelsGained = levelChange.levelsGained;
                final range =
                    '${levelChange.startLevel}->${levelChange.endLevel}';
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SkillImage(skill: skill, size: 16),
                      const SizedBox(width: 4),
                      if (levelsGained > 1) ...[
                        const Text('gained '),
                        Text(
                          '$levelsGained',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Style.successColor,
                          ),
                        ),
                        Text(' levels $range!'),
                      ] else ...[
                        const Text('level up '),
                        Text(
                          range,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Style.successColor,
                          ),
                        ),
                        const Text('!'),
                      ],
                    ],
                  ),
                );
              }),
            ],

            // 2. # of NPCs killed (with per hour estimates), by type
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Killed '),
                      Text(
                        '$count',
                        style: const TextStyle(color: Style.successColor),
                      ),
                      const SizedBox(width: 4),
                      if (monster.media != null)
                        CachedImage(assetPath: monster.media, size: 16),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${monster.name}$rateText')),
                    ],
                  ),
                );
              }),
            ],

            // 3. Dungeon completions (with per hour estimates)
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

            // 4. Marks found (no per-hour estimate)
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

            // 5. Items gained, by type (with per hour estimate)
            if (changes.inventoryChanges.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.inventoryChanges.entries.map((entry) {
                final itemId = entry.key;
                final itemCount = entry.value;
                final item = registries.items.byId(itemId);
                final gainedPerHour = timeAway.itemsGainedPerHour[itemId];
                final consumedPerHour = timeAway.itemsConsumedPerHour[itemId];

                final String prediction;
                if (itemCount > 0 && gainedPerHour != null) {
                  prediction =
                      ' (${approximateCountString(gainedPerHour.round())}/hr)';
                } else if (itemCount < 0 && consumedPerHour != null) {
                  prediction =
                      ' (${approximateCountString(consumedPerHour.round())}/hr)';
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

            // 6. Currencies earned (by type)
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
                final amountStr = signedCountString(amount);
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        amountStr,
                        style: const TextStyle(color: Style.successColor),
                      ),
                      const SizedBox(width: 4),
                      CachedImage(assetPath: currency.assetPath, size: 16),
                      const SizedBox(width: 4),
                      Flexible(child: Text('$abbrev$rateText')),
                    ],
                  ),
                );
              }),
            ],

            // 7. Potions used (-Y per hour)
            if (changes.potionsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.potionsUsed.entries.map((entry) {
                final potionId = entry.key;
                final count = entry.value;
                final potion = registries.items.byId(potionId);
                final rate = _perHour(count, duration);
                final rateText = rate != null
                    ? ' (${_perHourString(rate)})'
                    : '';
                return ItemChangeRow(
                  item: potion,
                  count: -count,
                  suffix: rateText,
                );
              }),
            ],

            // 8. Summoning tablets used, by type (no per hour)
            if (changes.tabletsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...changes.tabletsUsed.entries.map((entry) {
                final tabletId = entry.key;
                final count = entry.value;
                final tablet = registries.items.byId(tabletId);
                return ItemChangeRow(item: tablet, count: -count);
              }),
            ],

            // 9. Food eaten, by type (per hour estimate)
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
                return ItemChangeRow(
                  item: food,
                  count: -count,
                  suffix: rateText,
                );
              }),
            ],

            // 10. Pending loot to collect (aggregated by item type)
            if (timeAway.pendingLoot.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Aggregate stacks by item type
              ...() {
                final totals = <MelvorId, (Item, int)>{};
                for (final stack in timeAway.pendingLoot.stacks) {
                  final existing = totals[stack.item.id];
                  if (existing != null) {
                    totals[stack.item.id] = (
                      stack.item,
                      existing.$2 + stack.count,
                    );
                  } else {
                    totals[stack.item.id] = (stack.item, stack.count);
                  }
                }
                return totals.values.map((entry) {
                  final (item, count) = entry;
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('You have '),
                        Text(
                          '$count',
                          style: const TextStyle(color: Style.successColor),
                        ),
                        const SizedBox(width: 4),
                        ItemImage(item: item, size: 16),
                        const SizedBox(width: 4),
                        Flexible(child: Text('${item.name} to loot')),
                      ],
                    ),
                  );
                });
              }(),
            ],

            // 11. Items lost from loot overflow
            if (changes.lostFromLoot.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...changes.lostFromLoot.entries.map((entry) {
                final item = registries.items.byId(entry.key);
                final count = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('You looted '),
                      Text(
                        '$count',
                        style: const TextStyle(color: Style.warningColor),
                      ),
                      const SizedBox(width: 4),
                      ItemImage(item: item, size: 16),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text('but your loot box was full :('),
                      ),
                    ],
                  ),
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
