import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/cost_row.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/mastery_unlocks_dialog.dart';
import 'package:ui/src/widgets/skill_milestones_dialog.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class AgilityPage extends StatelessWidget {
  const AgilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.agility;
    final state = context.state;
    final skillState = state.skillState(skill);
    final registries = state.registries;
    final agilityState = state.agility;

    // Get course configuration
    final course = registries.agility.courseForRealm(
      const MelvorId('melvorD:Melvor'),
    );
    final slotCount = course?.obstacleSlots.length ?? 10;

    // Calculate course totals from built obstacles
    var totalDuration = Duration.zero;
    var totalXp = 0;
    var totalGp = 0;
    final builtObstacles = <int, AgilityObstacle>{};

    for (var slot = 0; slot < slotCount; slot++) {
      final obstacleId = agilityState.obstacleInSlot(slot);
      if (obstacleId != null) {
        final obstacle = registries.agility.byId(obstacleId.localId);
        if (obstacle != null) {
          builtObstacles[slot] = obstacle;
          totalDuration += obstacle.minDuration;
          totalXp += obstacle.xp;
          for (final reward in obstacle.currencyRewards) {
            if (reward.currency == Currency.gp) {
              totalGp += reward.amount;
            }
          }
        }
      }
    }

    final hasBuiltObstacles = builtObstacles.isNotEmpty;

    return GameScaffold(
      title: const Text('Agility'),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MasteryUnlocksButton(skill: skill),
              SkillMilestonesButton(skill: skill),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Course Summary Header
                  _CourseSummaryHeader(
                    totalDuration: totalDuration,
                    totalXp: totalXp,
                    totalGp: totalGp,
                    hasBuiltObstacles: hasBuiltObstacles,
                    builtObstacles: builtObstacles.values.toList(),
                  ),
                  const SizedBox(height: 16),

                  // Course progress bar (when running)
                  _CourseProgressBar(builtObstacles: builtObstacles),
                  const SizedBox(height: 16),

                  // Slot cards
                  const Text(
                    'Course Obstacles',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(slotCount, (slot) {
                    final slotLevel =
                        course != null && slot < course.obstacleSlots.length
                        ? course.obstacleSlots[slot]
                        : 1;
                    return _ObstacleSlotCard(
                      slot: slot,
                      slotLevel: slotLevel,
                      obstacle: builtObstacles[slot],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Course summary header showing totals and action buttons.
class _CourseSummaryHeader extends StatelessWidget {
  const _CourseSummaryHeader({
    required this.totalDuration,
    required this.totalXp,
    required this.totalGp,
    required this.hasBuiltObstacles,
    required this.builtObstacles,
  });

  final Duration totalDuration;
  final int totalXp;
  final int totalGp;
  final bool hasBuiltObstacles;
  final List<AgilityObstacle> builtObstacles;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = totalDuration.inMilliseconds / 1000;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.containerBackgroundLight,
        border: Border.all(color: Style.iconColorDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Agility course breakdown (inclusive of modifiers):',
            style: TextStyle(fontSize: 14, color: Style.textColorSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBadge(
                icon: Icons.timer_outlined,
                value: '${totalSeconds.toStringAsFixed(2)}s',
                label: 'Time',
              ),
              _StatBadge(
                icon: Icons.trending_up,
                value: '$totalXp',
                label: 'Skill XP',
                color: Style.xpBadgeBackgroundColor,
              ),
              _StatBadge(
                icon: Icons.monetization_on_outlined,
                value: '$totalGp',
                label: 'GP',
                color: Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: builtObstacles.isEmpty
                    ? null
                    : () => _showGlobalModifiersDialog(context),
                icon: const Icon(Icons.list_alt, size: 18),
                label: const Text('View Global Modifiers'),
              ),
              ElevatedButton.icon(
                onPressed: hasBuiltObstacles
                    ? () {
                        // TODO(eseidel): Implement course start/stop.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Course running not yet implemented'),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start Course'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showGlobalModifiersDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _GlobalModifiersDialog(builtObstacles: builtObstacles),
    );
  }
}

/// Small stat badge for course summary.
class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color ?? Style.textColorSecondary),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Style.textColorSecondary),
        ),
      ],
    );
  }
}

/// Course progress bar with alternating colors for each obstacle.
class _CourseProgressBar extends StatelessWidget {
  const _CourseProgressBar({required this.builtObstacles});

  final Map<int, AgilityObstacle> builtObstacles;

  @override
  Widget build(BuildContext context) {
    if (builtObstacles.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate total duration and obstacle proportions
    var totalMs = 0;
    for (final obstacle in builtObstacles.values) {
      totalMs += obstacle.minDuration.inMilliseconds;
    }

    if (totalMs == 0) return const SizedBox.shrink();

    // Build alternating colored segments
    final segments = <Widget>[];
    final colors = [Style.progressForegroundColorSuccess, Colors.teal];
    var colorIndex = 0;

    for (final entry in builtObstacles.entries) {
      final obstacle = entry.value;
      final proportion = obstacle.minDuration.inMilliseconds / totalMs;
      segments.add(
        Expanded(
          flex: (proportion * 1000).round(),
          child: Container(
            height: 24,
            color: colors[colorIndex % colors.length],
          ),
        ),
      );
      colorIndex++;
    }

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: Style.progressBackgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: segments),
    );
  }
}

/// Card showing a single obstacle slot in the course.
class _ObstacleSlotCard extends StatelessWidget {
  const _ObstacleSlotCard({
    required this.slot,
    required this.slotLevel,
    required this.obstacle,
  });

  final int slot;
  final int slotLevel;
  final AgilityObstacle? obstacle;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillState = state.skillState(Skill.agility);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= slotLevel;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isUnlocked ? null : Style.thievingNpcUnlockedColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: obstacle != null
            ? _FilledSlotContent(
                slot: slot,
                obstacle: obstacle!,
                isUnlocked: isUnlocked,
              )
            : _EmptySlotContent(
                slot: slot,
                slotLevel: slotLevel,
                isUnlocked: isUnlocked,
              ),
      ),
    );
  }
}

/// Content for a slot with a built obstacle.
class _FilledSlotContent extends StatelessWidget {
  const _FilledSlotContent({
    required this.slot,
    required this.obstacle,
    required this.isUnlocked,
  });

  final int slot;
  final AgilityObstacle obstacle;
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(obstacle.id);
    final durationSec = obstacle.minDuration.inMilliseconds / 1000;
    final rewardsStr = obstacle.currencyRewards
        .map((r) => '${r.amount} ${r.currency.abbreviation}')
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slot ${slot + 1}: ${obstacle.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${durationSec.toStringAsFixed(2)}s',
                    style: const TextStyle(color: Style.textColorSecondary),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.timer_outlined,
              size: 20,
              color: Style.textColorSecondary,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Grants section
        const Text(
          'Grants per obstacle completion:',
          style: TextStyle(fontSize: 12, color: Style.textColorSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.trending_up, size: 14),
            const SizedBox(width: 4),
            Text('${obstacle.xp} Skill XP'),
            if (rewardsStr.isNotEmpty) ...[
              const SizedBox(width: 16),
              const Icon(Icons.monetization_on_outlined, size: 14),
              const SizedBox(width: 4),
              Text(rewardsStr),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Global passives section
        if (obstacle.modifiers.modifiers.isNotEmpty) ...[
          const Text(
            'Global Active Passives:',
            style: TextStyle(fontSize: 12, color: Style.textColorSecondary),
          ),
          const SizedBox(height: 4),
          ...obstacle.modifiers.modifiers.map((mod) {
            final value = mod.entries.firstOrNull?.value ?? 0;
            final sign = value >= 0 ? '+' : '';
            return Text(
              '$sign$value ${_formatModifierName(mod.name)}',
              style: TextStyle(
                color: value >= 0 ? Style.successColor : Style.errorColor,
              ),
            );
          }),
          const SizedBox(height: 8),
        ],

        // Mastery progress
        MasteryProgressCell(masteryXp: actionState.masteryXp),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isUnlocked
                  ? () => _showObstacleSelectionDialog(context, slot)
                  : null,
              child: const Text('Change Obstacle'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: isUnlocked
                  ? () => _destroyObstacle(context, slot)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Style.errorColor),
              child: const Text('Destroy'),
            ),
          ],
        ),
      ],
    );
  }

  void _showObstacleSelectionDialog(BuildContext context, int slot) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ObstacleSelectionDialog(slot: slot),
    );
  }

  void _destroyObstacle(BuildContext context, int slot) {
    context.dispatch(DestroyAgilityObstacleAction(slot: slot));
  }
}

/// Content for an empty slot.
class _EmptySlotContent extends StatelessWidget {
  const _EmptySlotContent({
    required this.slot,
    required this.slotLevel,
    required this.isUnlocked,
  });

  final int slot;
  final int slotLevel;
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Slot ${slot + 1}: Empty',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isUnlocked ? null : Style.textColorSecondary,
                ),
              ),
              if (!isUnlocked)
                Text(
                  'Requires Level $slotLevel',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
            ],
          ),
        ),
        if (isUnlocked)
          ElevatedButton(
            onPressed: () => _showObstacleSelectionDialog(context, slot),
            child: const Text('Build Obstacle'),
          )
        else
          const Icon(Icons.lock, color: Style.textColorSecondary),
      ],
    );
  }

  void _showObstacleSelectionDialog(BuildContext context, int slot) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ObstacleSelectionDialog(slot: slot),
    );
  }
}

/// Dialog for selecting an obstacle to build in a slot.
class _ObstacleSelectionDialog extends StatelessWidget {
  const _ObstacleSelectionDialog({required this.slot});

  final int slot;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final registries = state.registries;
    final agilityState = state.agility;
    final slotState = agilityState.slotState(slot);

    // Get obstacles for this slot category
    final obstacles =
        registries.agility.obstacles.where((o) => o.category == slot).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return AlertDialog(
      title: Text('Select Obstacle for Slot ${slot + 1}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (slotState.purchaseCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Cost discount: '
                    '${(slotState.costDiscount * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Style.successColor),
                  ),
                ),
              ...obstacles.map(
                (obstacle) => _ObstacleSelectionTile(
                  obstacle: obstacle,
                  slot: slot,
                  discount: slotState.costDiscount,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Tile for a single obstacle in the selection dialog.
class _ObstacleSelectionTile extends StatelessWidget {
  const _ObstacleSelectionTile({
    required this.obstacle,
    required this.slot,
    required this.discount,
  });

  final AgilityObstacle obstacle;
  final int slot;
  final double discount;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final durationSec = obstacle.minDuration.inMilliseconds / 1000;
    final rewardsStr = obstacle.currencyRewards
        .map((r) => '${r.amount} ${r.currency.abbreviation}')
        .join(', ');

    // Calculate discounted costs
    final gpCost = obstacle.currencyCosts.gpCost;
    final discountedGp = gpCost > 0 ? (gpCost * (1 - discount)).round() : 0;
    final canAffordGp =
        discountedGp == 0 || state.currencies[Currency.gp]! >= discountedGp;

    // Check item costs
    var canAffordItems = true;
    for (final entry in obstacle.inputs.entries) {
      final discountedQty = (entry.value * (1 - discount)).ceil();
      if (state.inventory.countById(entry.key) < discountedQty) {
        canAffordItems = false;
        break;
      }
    }
    final canAfford = canAffordGp && canAffordItems;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(obstacle.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${durationSec.toStringAsFixed(2)}s • ${obstacle.xp} XP'),
            if (rewardsStr.isNotEmpty) Text(rewardsStr),
            if (discountedGp > 0)
              CostRow(currencyCosts: [(Currency.gp, discountedGp)]),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: canAfford
              ? () {
                  context.dispatch(
                    BuildAgilityObstacleAction(
                      slot: slot,
                      obstacleId: obstacle.id,
                    ),
                  );
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Build'),
        ),
      ),
    );
  }
}

/// Dialog showing combined global modifiers from all built obstacles.
class _GlobalModifiersDialog extends StatelessWidget {
  const _GlobalModifiersDialog({required this.builtObstacles});

  final List<AgilityObstacle> builtObstacles;

  @override
  Widget build(BuildContext context) {
    // Combine all modifiers from built obstacles
    final positiveModifiers = <String, num>{};
    final negativeModifiers = <String, num>{};

    for (final obstacle in builtObstacles) {
      for (final mod in obstacle.modifiers.modifiers) {
        for (final entry in mod.entries) {
          final key = mod.name;
          if (entry.value >= 0) {
            positiveModifiers[key] =
                (positiveModifiers[key] ?? 0) + entry.value;
          } else {
            negativeModifiers[key] =
                (negativeModifiers[key] ?? 0) + entry.value;
          }
        }
      }
    }

    return AlertDialog(
      title: const Text('Active Course Modifiers'),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (positiveModifiers.isNotEmpty) ...[
                const Text(
                  'Positive:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Style.successColor,
                  ),
                ),
                ...positiveModifiers.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '+ ${e.value} ${_formatModifierName(e.key)}',
                      style: const TextStyle(color: Style.successColor),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (negativeModifiers.isNotEmpty) ...[
                const Text(
                  'Negative:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Style.errorColor,
                  ),
                ),
                ...negativeModifiers.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '${e.value} ${_formatModifierName(e.key)}',
                      style: const TextStyle(color: Style.errorColor),
                    ),
                  ),
                ),
              ],
              if (positiveModifiers.isEmpty && negativeModifiers.isEmpty)
                const Text(
                  'No modifiers active.',
                  style: TextStyle(color: Style.textColorSecondary),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Formats a modifier name for display (e.g., "skillXP" -> "Skill XP").
String _formatModifierName(String name) {
  // Simple camelCase to Title Case conversion
  final result = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    if (i > 0 && char == char.toUpperCase() && char != char.toLowerCase()) {
      result.write(' ');
    }
    result.write(i == 0 ? char.toUpperCase() : char);
  }
  return result.toString();
}
