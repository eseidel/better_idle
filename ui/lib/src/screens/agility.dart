import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
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

    // Determine which slots to show: built slots + next empty slot
    final slotsToShow = <int>[];
    int? nextEmptySlot;
    for (var slot = 0; slot < slotCount; slot++) {
      if (builtObstacles.containsKey(slot)) {
        slotsToShow.add(slot);
      } else if (nextEmptySlot == null) {
        // First empty slot - show it as the "next" slot
        nextEmptySlot = slot;
        slotsToShow.add(slot);
      }
    }

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
                  ...slotsToShow.map((slot) {
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
                assetPath: Skill.agility.assetPath,
                value: '$totalXp',
                label: 'Skill XP',
              ),
              _StatBadge(
                assetPath: Currency.gp.assetPath,
                value: '$totalGp',
                label: 'GP',
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
              _CourseActionButton(hasBuiltObstacles: hasBuiltObstacles),
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

/// Button to start/stop the agility course.
class _CourseActionButton extends StatelessWidget {
  const _CourseActionButton({required this.hasBuiltObstacles});

  final bool hasBuiltObstacles;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isRunning = state.activeActivity is AgilityActivity;

    if (isRunning) {
      return ElevatedButton.icon(
        onPressed: () {
          context.dispatch(StopAgilityCourseAction());
        },
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
        icon: const Icon(Icons.stop, size: 18),
        label: const Text('Stop Course'),
      );
    }

    return ElevatedButton.icon(
      onPressed: hasBuiltObstacles
          ? () {
              context.dispatch(StartAgilityCourseAction());
            }
          : null,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: const Text('Start Course'),
    );
  }
}

/// Small stat badge for course summary.
class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.value,
    required this.label,
    this.icon,
    this.assetPath,
  });

  final IconData? icon;
  final String? assetPath;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (assetPath != null)
              CachedImage(assetPath: assetPath, size: 16)
            else if (icon != null)
              Icon(icon, size: 16, color: Style.textColorSecondary),
            const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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

/// Animated course progress bar with alternating colors for each obstacle.
class _CourseProgressBar extends StatefulWidget {
  const _CourseProgressBar({required this.builtObstacles});

  final Map<int, AgilityObstacle> builtObstacles;

  @override
  State<_CourseProgressBar> createState() => _CourseProgressBarState();
}

class _CourseProgressBarState extends State<_CourseProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.builtObstacles.isEmpty) {
      return const SizedBox.shrink();
    }

    final state = context.state;
    final activity = state.activeActivity;
    final isRunning = activity is AgilityActivity;

    // Calculate total duration
    var totalMs = 0;
    for (final obstacle in widget.builtObstacles.values) {
      totalMs += obstacle.minDuration.inMilliseconds;
    }

    if (totalMs == 0) return const SizedBox.shrink();

    // Build background segments with alternating colors
    final backgroundSegments = <Widget>[];
    final colors = [Style.progressForegroundColorSuccess, Colors.teal];
    final dimmedColors = [
      Style.progressForegroundColorSuccess.withValues(alpha: 0.3),
      Colors.teal.withValues(alpha: 0.3),
    ];
    var colorIndex = 0;

    for (final obstacle in widget.builtObstacles.values) {
      final proportion = obstacle.minDuration.inMilliseconds / totalMs;
      backgroundSegments.add(
        Expanded(
          flex: (proportion * 1000).round(),
          child: Container(
            height: 24,
            color: dimmedColors[colorIndex % dimmedColors.length],
          ),
        ),
      );
      colorIndex++;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: 24,
          decoration: BoxDecoration(
            color: Style.progressBackgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Background with alternating dimmed colors
              Row(children: backgroundSegments),
              // Foreground progress overlay
              if (isRunning)
                _AnimatedCourseProgress(
                  builtObstacles: widget.builtObstacles,
                  activity: activity,
                  colors: colors,
                  totalMs: totalMs,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Animated foreground progress that fills across obstacle segments.
class _AnimatedCourseProgress extends StatelessWidget {
  const _AnimatedCourseProgress({
    required this.builtObstacles,
    required this.activity,
    required this.colors,
    required this.totalMs,
  });

  final Map<int, AgilityObstacle> builtObstacles;
  final AgilityActivity activity;
  final List<Color> colors;
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.timestamp();
    final state = context.state;

    // Estimate current progress within the current obstacle
    final elapsed = now.difference(state.updatedAt);
    final estimatedTicksPassed = elapsed.inMilliseconds / 100; // 100ms per tick
    final estimatedProgress =
        ((activity.progressTicks + estimatedTicksPassed) / activity.totalTicks)
            .clamp(0.0, 1.0);

    // Build filled segments
    final segments = <Widget>[];
    var colorIndex = 0;

    for (final entry in builtObstacles.entries) {
      final slotIndex = entry.key;
      final obstacle = entry.value;
      final proportion = obstacle.minDuration.inMilliseconds / totalMs;

      double fillProgress;
      if (slotIndex < activity.currentObstacleIndex) {
        // Completed obstacle - fully filled
        fillProgress = 1.0;
      } else if (slotIndex == activity.currentObstacleIndex) {
        // Current obstacle - use estimated progress
        fillProgress = estimatedProgress;
      } else {
        // Future obstacle - empty
        fillProgress = 0.0;
      }

      segments.add(
        Expanded(
          flex: (proportion * 1000).round(),
          child: _ObstacleSegmentFill(
            color: colors[colorIndex % colors.length],
            fillProgress: fillProgress,
          ),
        ),
      );
      colorIndex++;
    }

    return Row(children: segments);
  }
}

/// Filled portion of a single obstacle segment.
class _ObstacleSegmentFill extends StatelessWidget {
  const _ObstacleSegmentFill({required this.color, required this.fillProgress});

  final Color color;
  final double fillProgress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth = constraints.maxWidth * fillProgress.clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(height: 24, width: fillWidth, color: color),
        );
      },
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
        Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachedImage(assetPath: Skill.agility.assetPath, size: 14),
                const SizedBox(width: 4),
                Text('${obstacle.xp} Skill XP'),
              ],
            ),
            ...obstacle.currencyRewards.map(
              (r) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CachedImage(assetPath: r.currency.assetPath, size: 14),
                  const SizedBox(width: 4),
                  Text('${r.amount} ${r.currency.abbreviation}'),
                ],
              ),
            ),
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
          ...obstacle.modifiers.modifiers.expand((mod) {
            return mod.entries.map((entry) {
              final isPositive = entry.value >= 0;
              return Text(
                _formatModifierEntry(mod, entry),
                style: TextStyle(
                  color: isPositive ? Style.successColor : Style.errorColor,
                ),
              );
            });
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
                  purchaseCount: slotState.purchaseCount,
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
    required this.purchaseCount,
  });

  final AgilityObstacle obstacle;
  final int slot;
  final double discount;
  final int purchaseCount;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(obstacle.id);
    final durationSec = obstacle.minDuration.inMilliseconds / 1000;

    // Calculate discounted currency costs
    var canAffordCurrency = true;
    final currencyCosts = <(Currency, int, bool)>[];
    for (final cost in obstacle.currencyCosts.costs) {
      final discounted = (cost.amount * (1 - discount)).round();
      final have = state.currencies[cost.currency] ?? 0;
      final canAfford = have >= discounted;
      currencyCosts.add((cost.currency, discounted, canAfford));
      if (!canAfford) canAffordCurrency = false;
    }

    // Check item costs
    var canAffordItems = true;
    final itemCosts = <(MelvorId, int, bool)>[];
    for (final entry in obstacle.inputs.entries) {
      final discountedQty = (entry.value * (1 - discount)).ceil();
      final have = state.inventory.countById(entry.key);
      final canAffordItem = have >= discountedQty;
      itemCosts.add((entry.key, discountedQty, canAffordItem));
      if (!canAffordItem) canAffordItems = false;
    }
    final canAfford = canAffordCurrency && canAffordItems;

    // Calculate mastery percentage (0-100)
    final masteryPercent = actionState.masteryXp > 0
        ? (actionState.masteryLevel / 99 * 100).clamp(0, 100)
        : 0.0;

    // Get modifiers for display
    final modifiers = obstacle.modifiers.modifiers;
    final hasCosts = currencyCosts.isNotEmpty || itemCosts.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name, duration, mastery
            Row(
              children: [
                Expanded(
                  child: Text(
                    obstacle.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(Icons.timer_outlined, size: 16),
                const SizedBox(width: 4),
                Text('${durationSec.toStringAsFixed(2)}s'),
                const SizedBox(width: 12),
                const CachedImage(
                  assetPath: 'assets/media/main/mastery_header.png',
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${actionState.masteryLevel} '
                  '(${masteryPercent.toStringAsFixed(1)}%)',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Built count (only if > 0)
            if (purchaseCount > 0)
              Text(
                'Built $purchaseCount times',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),

            // Cost reduction (only if > 0)
            if (discount > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Cost Reduction: ${(discount * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Style.successColor, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),

            // Cost section
            if (hasCosts) ...[
              const Text(
                'Cost:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  ...currencyCosts.map(
                    (c) => _CostChip(
                      assetPath: c.$1.assetPath,
                      value: '${_formatNumber(c.$2)} ${c.$1.abbreviation}',
                      canAfford: c.$3,
                    ),
                  ),
                  ...itemCosts.map((cost) {
                    final item = state.registries.items.byId(cost.$1);
                    return _CostChip(
                      assetPath: item.media,
                      value: '${cost.$2} ${item.name}',
                      canAfford: cost.$3,
                    );
                  }),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Grants section
            const Text(
              'Grants per obstacle completion:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _GrantChip(
                  assetPath: Skill.agility.assetPath,
                  value: '${obstacle.xp} Skill XP',
                ),
                ...obstacle.currencyRewards.map(
                  (r) => _GrantChip(
                    assetPath: r.currency.assetPath,
                    value: '${r.amount} ${r.currency.abbreviation}',
                  ),
                ),
              ],
            ),

            // Global Active Passives section
            if (modifiers.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Global Active Passives:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 4),
              ...modifiers.expand((mod) {
                return mod.entries.map((entry) {
                  final isPositive = entry.value >= 0;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _formatModifierEntry(mod, entry),
                      style: TextStyle(
                        color: isPositive
                            ? Style.successColor
                            : Style.errorColor,
                        fontSize: 12,
                      ),
                    ),
                  );
                });
              }),
            ],

            const SizedBox(height: 12),

            // Build button
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
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
          ],
        ),
      ),
    );
  }
}

/// Small chip showing a cost with affordability coloring.
class _CostChip extends StatelessWidget {
  const _CostChip({
    required this.assetPath,
    required this.value,
    required this.canAfford,
  });

  final String? assetPath;
  final String value;
  final bool canAfford;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (assetPath != null)
          CachedImage(assetPath: assetPath, size: 14)
        else
          Icon(
            Icons.inventory_2,
            size: 14,
            color: canAfford ? null : Style.errorColor,
          ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: canAfford ? null : Style.errorColor,
          ),
        ),
      ],
    );
  }
}

/// Small chip showing a grant/reward.
class _GrantChip extends StatelessWidget {
  const _GrantChip({required this.assetPath, required this.value});

  final String assetPath;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachedImage(assetPath: assetPath, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Formats a number with commas for readability.
String _formatNumber(int value) {
  if (value < 1000) return value.toString();
  final str = value.toString();
  final result = StringBuffer();
  final len = str.length;
  for (var i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) {
      result.write(',');
    }
    result.write(str[i]);
  }
  return result.toString();
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
                      formatModifierDescription(name: e.key, value: e.value),
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
                      formatModifierDescription(name: e.key, value: e.value),
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

/// Formats a single modifier entry for display.
///
/// Takes a modifier and one of its entries and formats it using the scope
/// information to produce a human-readable description.
String _formatModifierEntry(ModifierData mod, ModifierEntry entry) {
  // Extract scope information
  String? skillName;
  String? currencyName;

  final scope = entry.scope;
  if (scope != null) {
    // Look up skill name if present
    if (scope.skillId != null) {
      try {
        skillName = Skill.fromId(scope.skillId!).name;
      } on ArgumentError {
        // Unknown skill ID, leave as null
      }
    }
    // Look up currency name if present
    if (scope.currencyId != null) {
      try {
        currencyName = Currency.fromIdString(scope.currencyId!.fullId).name;
      } on ArgumentError {
        // Unknown currency ID, leave as null
      }
    }
  }

  return formatModifierDescription(
    name: mod.name,
    value: entry.value,
    skillName: skillName,
    currencyName: currencyName,
  );
}
