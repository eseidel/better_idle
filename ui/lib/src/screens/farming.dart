import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/currency_display.dart';
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
          onTap: () {
            // Handle tap based on plot state:
            // - If locked: show unlock dialog
            // - If empty: show crop selection
            // - If growing: show details or compost options
            // - If ready: harvest
            // Implementation requires Redux actions
          },
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
                  _GrowingPlotContent(plotState: plotState)
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
  const _GrowingPlotContent({required this.plotState});

  final PlotState plotState;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final crop = state.registries.farmingCrops.byId(plotState.cropId!);

    if (crop == null) {
      return const Text('Unknown crop');
    }

    // For now, show indeterminate progress until we add real-time tracking.
    // The plot state will update to "ready" when the background action
    // completes.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          crop.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
        const SizedBox(height: 4),
        const Text('Growing...'),
        if (plotState.compostApplied > 0) ...[
          const SizedBox(height: 8),
          Text('Compost: ${plotState.compostApplied}'),
        ],
      ],
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
