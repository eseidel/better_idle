import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/currency_display.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class FarmingPage extends StatelessWidget {
  const FarmingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.farming;
    final skillState = context.state.skillState(skill);
    final registries = context.state.registries;

    // Group plots by category
    final plotsByCategory = <FarmingCategory, List<FarmingPlot>>{};
    for (final plot in registries.farmingPlots.all) {
      final category = registries.farmingCategories.byId(plot.categoryId);
      if (category != null) {
        plotsByCategory.putIfAbsent(category, () => []).add(plot);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Farming')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
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

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.plots});

  final FarmingCategory category;
  final List<FarmingPlot> plots;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            category.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final plot in plots) _PlotCard(plot: plot, category: category),
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

  void _showUnlockDialog(BuildContext context, GlobalState state) {
    final farmingLevel = state.skillState(Skill.farming).skillLevel;
    final canUnlock =
        farmingLevel >= plot.level &&
        plot.currencyCosts.costs.every(
          (cost) => state.currency(cost.currency) >= cost.amount,
        );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock Plot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Required Level: ${plot.level}'),
            if (farmingLevel < plot.level)
              Text(
                'Your Level: $farmingLevel',
                style: const TextStyle(color: Colors.red),
              ),
            if (plot.currencyCosts.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Cost:'),
              CurrencyListDisplay.fromCosts(plot.currencyCosts),
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
    final registries = state.registries;
    final farmingLevel = state.skillState(Skill.farming).skillLevel;

    // Get all crops for this plot's category
    final allCrops = registries.farmingCrops.forCategory(category.id);

    // Filter to crops the player can plant (has level and seeds)
    final availableCrops =
        allCrops.where((crop) {
            if (crop.level > farmingLevel) return false;
            final seed = registries.items.byId(crop.seedId);
            final seedCount = state.inventory.countOfItem(seed);
            return seedCount >= crop.seedCost;
          }).toList()
          // Sort by level
          ..sort((a, b) => a.level.compareTo(b.level));

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select Crop'),
        content: SizedBox(
          width: double.maxFinite,
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
                    final seedCount = state.inventory.countOfItem(seed);

                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text(
                        'Level ${crop.level} · ${crop.seedCost} ${seed.name} '
                        '(have $seedCount)',
                      ),
                      onTap: () {
                        context.dispatch(
                          PlantCropAction(plotId: plot.id, crop: crop),
                        );
                        Navigator.of(dialogContext).pop();
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isUnlocked = state.unlockedPlots.contains(plot.id);
    final plotState = state.plotStates[plot.id];

    return SizedBox(
      width: 200,
      height: 200,
      child: Card(
        child: InkWell(
          onTap: () => _handlePlotTap(context, state, isUnlocked, plotState),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock, size: 48),
        const SizedBox(height: 8),
        Text('Level ${plot.level}'),
        if (plot.currencyCosts.isNotEmpty)
          CurrencyListDisplay.fromCosts(plot.currencyCosts),
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
    final crop = state.registries.farmingCrops.byId(plotState.cropId!);

    if (crop == null) {
      return const Text('Unknown crop');
    }

    final product = state.registries.items.byId(crop.productId);
    final ticks = plotState.growthTicksRemaining ?? 0;
    final timeRemaining = _formatTimeRemaining(ticks);

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
          if (plotState.compostApplied > 0)
            Text('Compost: ${plotState.compostApplied}'),
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
    final crop = state.registries.farmingCrops.byId(plotState.cropId!);

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
