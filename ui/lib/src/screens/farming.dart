import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/cost_row.dart';
import 'package:ui/src/widgets/disabled_button_tooltip.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_count_badge_cell.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/shard_purchase_dialog.dart';
import 'package:ui/src/widgets/skill_fab.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_overflow_menu.dart';
import 'package:ui/src/widgets/skill_progress.dart';
import 'package:ui/src/widgets/style.dart';

class FarmingPage extends StatelessWidget {
  const FarmingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.farming;
    final skillState = context.state.skillState(skill);
    final registries = context.state.registries;

    // Group plots by category
    final plotsByCategory = <FarmingCategory, List<FarmingPlot>>{};
    for (final plot in registries.farmingPlots) {
      final category = registries.farming.categoryById(plot.categoryId);
      if (category != null) {
        plotsByCategory.putIfAbsent(category, () => []).add(plot);
      }
    }

    return GameScaffold(
      title: const Text('Farming'),
      actions: const [SkillOverflowMenu(skill: skill)],
      floatingActionButton: const SkillFab(skill: skill),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          _CompostIndicators(registries: registries),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in plotsByCategory.entries)
                    _CategorySection(category: entry.key, plots: entry.value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompostIndicators extends StatelessWidget {
  const _CompostIndicators({required this.registries});

  final Registries registries;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final compostItems = registries.items.all
        .where((item) => item.compostValue != null && item.compostValue != 0)
        .toList();

    if (compostItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in compostItems)
            GestureDetector(
              onTap: () {
                final purchases = registries.shop.purchasesContainingItem(
                  item.id,
                );
                if (purchases.isNotEmpty) {
                  showShardPurchaseDialog(context, item);
                }
              },
              child: ItemCountBadgeCell(
                item: item,
                count: state.inventory.countOfItem(item),
                showShopBadge: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.plots});

  final FarmingCategory category;
  final List<FarmingPlot> plots;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final farmingLevel = state.skillState(Skill.farming).skillLevel;

    // Filter plots to show:
    // 1. All unlocked plots
    // 2. All locked plots where player has met the level requirement
    // 3. One additional locked plot (the next closest in level)
    final unlockedPlots = <FarmingPlot>[];
    final lockedWithLevel = <FarmingPlot>[];
    final lockedWithoutLevel = <FarmingPlot>[];

    for (final plot in plots) {
      if (state.unlockedPlots.contains(plot.id)) {
        unlockedPlots.add(plot);
      } else if (farmingLevel >= plot.level) {
        lockedWithLevel.add(plot);
      } else {
        lockedWithoutLevel.add(plot);
      }
    }

    // Sort locked plots without level by their level requirement
    lockedWithoutLevel.sort((a, b) => a.level.compareTo(b.level));

    // Build the list of visible plots, sorted by level for consistent display
    final visiblePlots = <FarmingPlot>[
      ...unlockedPlots,
      ...lockedWithLevel,
      // Add only the next closest locked plot (if any)
      if (lockedWithoutLevel.isNotEmpty) lockedWithoutLevel.first,
    ]..sort((a, b) => a.level.compareTo(b.level));

    // Count ready and empty plots for bulk action buttons
    final readyCount = unlockedPlots.where((plot) {
      final ps = state.plotStates[plot.id];
      return ps != null && ps.isReadyToHarvest;
    }).length;
    final emptyCount = unlockedPlots.where((plot) {
      final ps = state.plotStates[plot.id];
      return ps == null || ps.isEmpty;
    }).length;

    final canAffordHarvest = state.gp >= 2000;
    final canAffordPlant = state.gp >= 5000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              DisabledButtonTooltip(
                message: readyCount == 0
                    ? 'No crops ready to harvest'
                    : !canAffordHarvest
                    ? 'Not enough GP'
                    : null,
                child: FilledButton.tonal(
                  onPressed: readyCount > 0 && canAffordHarvest
                      ? () => context.dispatch(
                          HarvestAllCropsAction(categoryId: category.id),
                        )
                      : null,
                  child: Text('Harvest All ($readyCount)'),
                ),
              ),
              const SizedBox(width: 8),
              DisabledButtonTooltip(
                message: emptyCount == 0
                    ? 'No empty plots'
                    : !canAffordPlant
                    ? 'Not enough GP'
                    : null,
                child: FilledButton.tonal(
                  onPressed: emptyCount > 0 && canAffordPlant
                      ? () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => _PlantAllDialog(
                            category: category,
                            state: state,
                            emptyCount: emptyCount,
                            outerContext: context,
                          ),
                        )
                      : null,
                  child: Text('Plant All ($emptyCount)'),
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final plot in visiblePlots)
              _PlotCard(plot: plot, category: category),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PlotCard extends StatelessWidget {
  const _PlotCard({required this.plot, required this.category});

  final FarmingPlot plot;
  final FarmingCategory category;

  void _handlePlotTap(
    BuildContext context,
    GlobalState state,
    bool isUnlocked,
    PlotState? plotState,
  ) {
    if (!isUnlocked) {
      _showUnlockDialog(context, state);
    } else if (plotState == null || plotState.isEmpty) {
      _showCropSelectionDialog(context, state);
    } else if (plotState.isReadyToHarvest) {
      context.dispatch(HarvestCropAction(plotId: plot.id));
    }
    // If growing, do nothing for now (could show details in the future)
  }

  bool _canUnlockPlot(GlobalState state) {
    final farmingLevel = state.skillState(Skill.farming).skillLevel;
    final hasLevel = farmingLevel >= plot.level;

    // Check if player can afford all currency costs
    final canAffordAllCosts = plot.currencyCosts.costs.every(
      (cost) => state.currency(cost.currency) >= cost.amount,
    );

    return hasLevel && canAffordAllCosts;
  }

  void _showUnlockDialog(BuildContext context, GlobalState state) {
    final farmingLevel = state.skillState(Skill.farming).skillLevel;
    final hasLevel = farmingLevel >= plot.level;

    // Build canAfford map for each currency cost
    final canAffordCosts = <Currency, bool>{};
    for (final cost in plot.currencyCosts.costs) {
      canAffordCosts[cost.currency] =
          state.currency(cost.currency) >= cost.amount;
    }

    final canUnlock = _canUnlockPlot(state);

    // Colors for level display
    final levelColor = hasLevel ? Style.successColor : Style.errorColor;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock Plot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Required Level: '),
                Text(
                  '${plot.level}',
                  style: TextStyle(
                    color: levelColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ' (yours: $farmingLevel)',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
            if (plot.currencyCosts.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Cost:'),
              CostRow(
                currencyCosts: plot.currencyCosts.costs
                    .map((c) => (c.currency, c.amount))
                    .toList(),
                canAffordCosts: canAffordCosts,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: canUnlock
                ? () {
                    context.dispatch(UnlockPlotAction(plotId: plot.id));
                    Navigator.of(dialogContext).pop();
                  }
                : null,
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _showCropSelectionDialog(BuildContext context, GlobalState state) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _CropSelectionDialog(
        plot: plot,
        category: category,
        state: state,
        outerContext: context,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isUnlocked = state.unlockedPlots.contains(plot.id);
    final plotState = state.plotStates[plot.id];

    // Check if locked plot can be unlocked (has level and can afford)
    final canUnlock = _canUnlockPlot(state);

    // Determine if plot should be tappable:
    // - Locked plots: only when can unlock
    // - Empty plots: always tappable
    // - Growing plots: not tappable (only trash icon is clickable)
    // - Ready to harvest: tappable
    final isGrowing = plotState?.isGrowing ?? false;
    final isTappable = !isGrowing && (isUnlocked || canUnlock);

    return SizedBox(
      width: 200,
      height: 200,
      child: Card(
        child: InkWell(
          onTap: isTappable
              ? () => _handlePlotTap(context, state, isUnlocked, plotState)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUnlocked)
                  _LockedPlotContent(plot: plot)
                else if (plotState == null || plotState.isEmpty)
                  const _EmptyPlotContent()
                else if (plotState.isGrowing)
                  _GrowingPlotContent(plot: plot, plotState: plotState)
                else if (plotState.isReadyToHarvest)
                  _ReadyPlotContent(plotState: plotState)
                else
                  const _EmptyPlotContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedPlotContent extends StatelessWidget {
  const _LockedPlotContent({required this.plot});

  final FarmingPlot plot;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final farmingLevel = state.skillState(Skill.farming).skillLevel;
    final hasLevel = farmingLevel >= plot.level;

    // Build canAfford map for each currency cost
    final canAffordCosts = <Currency, bool>{};
    for (final cost in plot.currencyCosts.costs) {
      canAffordCosts[cost.currency] =
          state.currency(cost.currency) >= cost.amount;
    }

    final levelColor = hasLevel
        ? Style.successColor
        : Style.unmetRequirementColor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock, size: 48),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkillImage(skill: Skill.farming, size: 16),
            const SizedBox(width: 4),
            Text(
              'Level ${plot.level}',
              style: TextStyle(color: levelColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (plot.currencyCosts.isNotEmpty)
          CostRow(
            currencyCosts: plot.currencyCosts.costs
                .map((c) => (c.currency, c.amount))
                .toList(),
            canAffordCosts: canAffordCosts,
          ),
      ],
    );
  }
}

class _EmptyPlotContent extends StatelessWidget {
  const _EmptyPlotContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_circle_outline, size: 48),
        SizedBox(height: 8),
        Text('Plant Crop'),
      ],
    );
  }
}

class _GrowingPlotContent extends StatelessWidget {
  const _GrowingPlotContent({required this.plot, required this.plotState});

  final FarmingPlot plot;
  final PlotState plotState;

  String _formatTimeRemaining(int ticks) {
    final duration = durationFromTicks(ticks);
    final totalMinutes = (duration.inSeconds / 60).round();

    if (totalMinutes < 1) {
      return '< 1 min';
    } else if (totalMinutes < 60) {
      return '$totalMinutes min';
    } else {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (minutes == 0) {
        return '${hours}h';
      }
      return '${hours}h ${minutes}m';
    }
  }

  int _getSuccessChance(int compostValue) {
    // Base success chance is 50%, compost value is already in percent
    return (50 + compostValue).clamp(0, 100);
  }

  void _showDestroyDialog(BuildContext context, Item product) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Destroy Crop?'),
        content: Text(
          'This will destroy the growing ${product.name} and any compost '
          'applied to this plot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.dispatch(ClearPlotAction(plotId: plot.id));
              Navigator.of(dialogContext).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Destroy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final crop = state.registries.farming.cropById(plotState.cropId!);

    if (crop == null) {
      return const Text('Unknown crop');
    }

    final product = state.registries.items.byId(crop.productId);
    final ticks = plotState.growthTicksRemaining ?? 0;
    final timeRemaining = _formatTimeRemaining(ticks);
    final successChance = _getSuccessChance(plotState.compostApplied);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ItemImage(item: product, size: 48),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$timeRemaining remaining'),
          Text('Success: $successChance%'),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => _showDestroyDialog(context, product),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Destroy crop',
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyPlotContent extends StatelessWidget {
  const _ReadyPlotContent({required this.plotState});

  final PlotState plotState;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final crop = state.registries.farming.cropById(plotState.cropId!);

    if (crop == null) {
      return const Text('Unknown crop');
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 48, color: Colors.green),
        const SizedBox(height: 8),
        Text(
          crop.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        const Text('Ready to Harvest!'),
      ],
    );
  }
}

/// Represents a compost option for the crop selection dialog.
class _CompostOption {
  const _CompostOption({
    required this.item,
    required this.count,
    required this.available,
  });

  final Item? item; // null for "None"
  final int count; // number to apply (e.g., 5 for Compost, 1 for Weird Gloop)
  final int available; // how many the player has

  bool get hasEnough => item == null || available >= count;
  int get successBoost => (item?.compostValue ?? 0) * count;
  int get harvestBonus => (item?.harvestBonus ?? 0) * count;
}

List<_CompostOption> _getCompostOptions(GlobalState state) {
  final registries = state.registries;
  final inventory = state.inventory;
  final options = <_CompostOption>[
    const _CompostOption(item: null, count: 0, available: 0),
  ];

  for (final item in registries.items.all) {
    final compostValue = item.compostValue;
    if (compostValue == null || compostValue == 0) continue;

    final available = inventory.countOfItem(item);
    if (compostValue <= 10) {
      options.add(_CompostOption(item: item, count: 5, available: available));
    } else {
      options.add(_CompostOption(item: item, count: 1, available: available));
    }
  }

  return options;
}

/// Dialog for selecting a crop to plant with optional compost.
class _CropSelectionDialog extends StatefulWidget {
  const _CropSelectionDialog({
    required this.plot,
    required this.category,
    required this.state,
    required this.outerContext,
  });

  final FarmingPlot plot;
  final FarmingCategory category;
  final GlobalState state;
  final BuildContext outerContext;

  @override
  State<_CropSelectionDialog> createState() => _CropSelectionDialogState();
}

class _CropSelectionDialogState extends State<_CropSelectionDialog> {
  int _selectedCompostIndex = 0;

  int _getSuccessChance(int compostValue) {
    // Base success chance is 50%, compost adds to it
    // Each 10 compost = +10% success, max 80 compost = +80%
    // So with 50 compost (5x regular), success = 50 + 50 = 100%
    return (50 + compostValue).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final registries = widget.state.registries;
    final farmingLevel = widget.state.skillState(Skill.farming).skillLevel;

    // Get all crops for this plot's category
    final allCrops = registries.farming.cropsForCategory(widget.category.id);

    // Filter to crops the player can plant (has level and seeds)
    final availableCrops = allCrops.where((crop) {
      if (crop.level > farmingLevel) return false;
      final seed = registries.items.byId(crop.seedId);
      final seedCount = widget.state.inventory.countOfItem(seed);
      return seedCount >= crop.seedCost;
    }).toList()..sort((a, b) => a.level.compareTo(b.level));

    final compostOptions = _getCompostOptions(widget.state);
    final selectedCompost = compostOptions[_selectedCompostIndex];
    final compostValue =
        (selectedCompost.item?.compostValue ?? 0) * selectedCompost.count;
    final successChance = _getSuccessChance(compostValue);

    return AlertDialog(
      title: const Text('Select Crop'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compost selection
            if (compostOptions.length > 1) ...[
              const Text('Compost:'),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < compostOptions.length; i++)
                    ButtonSegment(
                      value: i,
                      label: _buildCompostLabel(compostOptions[i]),
                    ),
                ],
                selected: {_selectedCompostIndex},
                onSelectionChanged: (selected) {
                  setState(() => _selectedCompostIndex = selected.first);
                },
              ),
              const SizedBox(height: 8),
              Text('Success chance: $successChance%'),
              if (selectedCompost.harvestBonus > 0)
                Text('Harvest bonus: +${selectedCompost.harvestBonus}%'),
              const Divider(),
            ],
            // Crop list
            Flexible(
              child: availableCrops.isEmpty
                  ? const Text(
                      'No crops available. You need seeds and the required '
                      'farming level to plant crops.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableCrops.length,
                      itemBuilder: (context, index) {
                        final crop = availableCrops[index];
                        final seed = registries.items.byId(crop.seedId);
                        final product = registries.items.byId(crop.productId);
                        final seedCount = widget.state.inventory.countOfItem(
                          seed,
                        );

                        final canPlant = selectedCompost.hasEnough;

                        return ListTile(
                          leading: ItemImage(item: product, size: 40),
                          title: Text(product.name),
                          subtitle: Text(
                            'Level ${crop.level} · '
                            '${crop.seedCost} ${seed.name} '
                            '(have $seedCount)',
                          ),
                          enabled: canPlant,
                          onTap: canPlant
                              ? () => _plantCrop(crop, selectedCompost)
                              : null,
                        );
                      },
                    ),
            ),
          ],
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

  Widget _buildCompostLabel(_CompostOption option) {
    if (option.item == null) {
      return const Text('None', style: TextStyle(fontSize: 12));
    }

    final countColor = option.hasEnough ? null : Style.errorColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${option.count}',
          style: TextStyle(fontSize: 12, color: countColor),
        ),
        const SizedBox(width: 4),
        ItemImage(item: option.item!, size: 16),
      ],
    );
  }

  void _plantCrop(FarmingCrop crop, _CompostOption compostOption) {
    final outerContext = widget.outerContext;

    // Apply compost first if selected
    if (compostOption.item != null) {
      for (var i = 0; i < compostOption.count; i++) {
        outerContext.dispatch(
          ApplyCompostAction(
            plotId: widget.plot.id,
            compost: compostOption.item!,
          ),
        );
      }
    }

    // Then plant the crop
    outerContext.dispatch(PlantCropAction(plotId: widget.plot.id, crop: crop));

    Navigator.of(context).pop();
  }
}

/// Dialog for selecting a crop to plant in all empty plots.
class _PlantAllDialog extends StatefulWidget {
  const _PlantAllDialog({
    required this.category,
    required this.state,
    required this.emptyCount,
    required this.outerContext,
  });

  final FarmingCategory category;
  final GlobalState state;
  final int emptyCount;
  final BuildContext outerContext;

  @override
  State<_PlantAllDialog> createState() => _PlantAllDialogState();
}

class _PlantAllDialogState extends State<_PlantAllDialog> {
  int _selectedCompostIndex = 0;

  int _getSuccessChance(int compostValue) {
    return (50 + compostValue).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final registries = widget.state.registries;
    final farmingLevel = widget.state.skillState(Skill.farming).skillLevel;

    final allCrops = registries.farming.cropsForCategory(widget.category.id);
    final availableCrops = allCrops.where((crop) {
      if (crop.level > farmingLevel) return false;
      final seed = registries.items.byId(crop.seedId);
      final seedCount = widget.state.inventory.countOfItem(seed);
      return seedCount >= crop.seedCost;
    }).toList()..sort((a, b) => a.level.compareTo(b.level));

    final compostOptions = _getCompostOptions(widget.state);
    final selectedCompost = compostOptions[_selectedCompostIndex];
    final compostValue =
        (selectedCompost.item?.compostValue ?? 0) * selectedCompost.count;
    final successChance = _getSuccessChance(compostValue);

    final gpCost = 5000 + (selectedCompost.item != null ? 2000 : 0);
    final canAfford = widget.state.gp >= gpCost;
    final gpColor = canAfford ? Style.successColor : Style.errorColor;

    // Total compost needed for all empty plots
    final totalCompostNeeded = selectedCompost.count * widget.emptyCount;

    return AlertDialog(
      title: const Text('Plant All'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // GP cost
            Row(
              children: [
                const Text('Cost: '),
                Text(
                  '${gpCost}gp',
                  style: TextStyle(color: gpColor, fontWeight: FontWeight.bold),
                ),
                Text(
                  ' (have ${widget.state.gp})',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Compost selection
            if (compostOptions.length > 1) ...[
              const Text('Compost:'),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < compostOptions.length; i++)
                    ButtonSegment(
                      value: i,
                      label: _buildCompostLabel(compostOptions[i]),
                    ),
                ],
                selected: {_selectedCompostIndex},
                onSelectionChanged: (selected) {
                  setState(() => _selectedCompostIndex = selected.first);
                },
              ),
              const SizedBox(height: 8),
              Text('Success chance: $successChance%'),
              if (selectedCompost.harvestBonus > 0)
                Text('Harvest bonus: +${selectedCompost.harvestBonus}%'),
              if (selectedCompost.item != null) ...[
                Text(
                  'Need $totalCompostNeeded ${selectedCompost.item!.name} '
                  '(have ${selectedCompost.available})',
                  style: TextStyle(
                    color: selectedCompost.available >= totalCompostNeeded
                        ? null
                        : Style.errorColor,
                  ),
                ),
              ],
              const Divider(),
            ],
            // Crop list
            Flexible(
              child: availableCrops.isEmpty
                  ? const Text(
                      'No crops available. You need seeds and the required '
                      'farming level to plant crops.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableCrops.length,
                      itemBuilder: (context, index) {
                        final crop = availableCrops[index];
                        final seed = registries.items.byId(crop.seedId);
                        final product = registries.items.byId(crop.productId);
                        final seedCount = widget.state.inventory.countOfItem(
                          seed,
                        );
                        final totalSeedsNeeded =
                            crop.seedCost * widget.emptyCount;
                        final plotsPlantable = seedCount ~/ crop.seedCost;

                        return ListTile(
                          leading: ItemImage(item: product, size: 40),
                          title: Text(product.name),
                          subtitle: Text(
                            'Level ${crop.level} · '
                            '${crop.seedCost} seeds each · '
                            'need $totalSeedsNeeded '
                            '(have $seedCount, '
                            'enough for $plotsPlantable)',
                          ),
                          enabled: canAfford,
                          onTap: canAfford
                              ? () => _plantAll(crop, selectedCompost)
                              : null,
                        );
                      },
                    ),
            ),
          ],
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

  Widget _buildCompostLabel(_CompostOption option) {
    if (option.item == null) {
      return const Text('None', style: TextStyle(fontSize: 12));
    }

    final countColor = option.hasEnough ? null : Style.errorColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${option.count}',
          style: TextStyle(fontSize: 12, color: countColor),
        ),
        const SizedBox(width: 4),
        ItemImage(item: option.item!, size: 16),
      ],
    );
  }

  void _plantAll(FarmingCrop crop, _CompostOption compostOption) {
    widget.outerContext.dispatch(
      PlantAllCropsAction(
        categoryId: widget.category.id,
        crop: crop,
        compost: compostOption.item,
        compostCount: compostOption.count,
      ),
    );
    Navigator.of(context).pop();
  }
}
