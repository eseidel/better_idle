import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Township statistics that can be displayed with icons.
enum TownshipStat {
  population,
  health,
  happiness,
  education,
  worship,
  storage;

  /// Returns the display label for this stat.
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';

  /// Returns the asset path for this stat's icon.
  String get assetPath => 'assets/media/skills/township/$name.png';
}

class TownshipPage extends StatefulWidget {
  const TownshipPage({super.key});

  @override
  State<TownshipPage> createState() => _TownshipPageState();
}

class _TownshipPageState extends State<TownshipPage> {
  final Set<MelvorId> _collapsedBiomes = {};
  _BuildingFilter _buildingFilter = _BuildingFilter.all;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Township'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: CachedImage(
                  assetPath: 'assets/media/skills/township/menu_town.png',
                  size: 24,
                ),
                text: 'Town',
              ),
              Tab(
                icon: CachedImage(
                  assetPath: 'assets/media/skills/township/menu_tasks.png',
                  size: 24,
                ),
                text: 'Tasks',
              ),
            ],
          ),
        ),
        drawer: const AppNavigationDrawer(),
        body: StoreConnector<GlobalState, TownshipViewModel>(
          converter: (store) => TownshipViewModel(store.state),
          builder: (context, viewModel) {
            // Show deity selection if no deity chosen yet
            if (!viewModel.hasSelectedDeity) {
              return _DeitySelectionView(viewModel: viewModel);
            }

            return TabBarView(
              children: [
                _TownView(
                  viewModel: viewModel,
                  collapsedBiomes: _collapsedBiomes,
                  onToggleBiome: (biomeId) {
                    setState(() {
                      if (_collapsedBiomes.contains(biomeId)) {
                        _collapsedBiomes.remove(biomeId);
                      } else {
                        _collapsedBiomes.add(biomeId);
                      }
                    });
                  },
                  buildingFilter: _buildingFilter,
                  onFilterChanged: (filter) =>
                      setState(() => _buildingFilter = filter),
                ),
                _TasksView(viewModel: viewModel),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The main town view with biomes and buildings.
class _TownView extends StatelessWidget {
  const _TownView({
    required this.viewModel,
    required this.collapsedBiomes,
    required this.onToggleBiome,
    required this.buildingFilter,
    required this.onFilterChanged,
  });

  final TownshipViewModel viewModel;
  final Set<MelvorId> collapsedBiomes;
  final void Function(MelvorId) onToggleBiome;
  final _BuildingFilter buildingFilter;
  final void Function(_BuildingFilter) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SkillProgress(xp: viewModel.townshipXp),
        _TownshipStatsCard(viewModel: viewModel),
        _TownshipResourcesCard(viewModel: viewModel),
        _BuildingFilterHeader(
          filter: buildingFilter,
          onFilterChanged: onFilterChanged,
        ),
        const Divider(),
        ...viewModel.township.registry.biomes.map(
          (TownshipBiome biome) => _BiomeSection(
            viewModel: viewModel,
            biome: biome,
            isCollapsed: collapsedBiomes.contains(biome.id),
            onToggleCollapse: () => onToggleBiome(biome.id),
            buildingFilter: buildingFilter,
          ),
        ),
      ],
    );
  }
}

/// Filter modes for buildings.
enum _BuildingFilter {
  all,
  affordable;

  String get label => switch (this) {
    all => 'All',
    affordable => 'Affordable',
  };
}

/// Sort modes for tasks.
enum _TaskSortMode { difficulty, completion }

/// The tasks view showing township tasks.
class _TasksView extends StatefulWidget {
  const _TasksView({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  State<_TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<_TasksView> {
  _TaskSortMode _sortMode = _TaskSortMode.difficulty;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final allTasks = <TownshipTask>[];
    for (final category in TaskCategory.values) {
      allTasks.addAll(viewModel.township.registry.tasksForCategory(category));
    }

    // Filter out completed tasks.
    final completedTasks = viewModel.township.completedMainTasks;
    final incompleteTasks = allTasks
        .where((t) => !completedTasks.contains(t.id))
        .toList();

    // Sort based on mode.
    if (_sortMode == _TaskSortMode.completion) {
      incompleteTasks.sort((a, b) {
        final aProgress = _taskCompletionProgress(viewModel, a);
        final bProgress = _taskCompletionProgress(viewModel, b);
        return bProgress.compareTo(aProgress); // Higher progress first.
      });
    }
    // For difficulty mode, tasks are already in category order.

    final totalCount = allTasks.length;
    final completedCount = completedTasks.length;

    return ListView(
      children: [
        SkillProgress(xp: viewModel.townshipXp),
        _TaskSortHeader(
          sortMode: _sortMode,
          onSortChanged: (mode) => setState(() => _sortMode = mode),
          completedCount: completedCount,
          totalCount: totalCount,
        ),
        for (final task in incompleteTasks)
          _TaskCard(viewModel: viewModel, task: task),
      ],
    );
  }

  /// Returns completion progress as a ratio (0.0 to 1.0).
  double _taskCompletionProgress(
    TownshipViewModel viewModel,
    TownshipTask task,
  ) {
    if (task.goals.isEmpty) return 0;
    var totalProgress = 0.0;
    for (final goal in task.goals) {
      final current = viewModel.getGoalProgress(task.id, goal);
      final progress = (current / goal.quantity).clamp(0.0, 1.0);
      totalProgress += progress;
    }
    return totalProgress / task.goals.length;
  }
}

/// Header with sort toggle for tasks.
class _TaskSortHeader extends StatelessWidget {
  const _TaskSortHeader({
    required this.sortMode,
    required this.onSortChanged,
    required this.completedCount,
    required this.totalCount,
  });

  final _TaskSortMode sortMode;
  final void Function(_TaskSortMode) onSortChanged;
  final int completedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final sortLabel = switch (sortMode) {
      _TaskSortMode.difficulty => 'Difficulty',
      _TaskSortMode.completion => 'Completion',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$completedCount / $totalCount completed',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          PopupMenuButton<_TaskSortMode>(
            initialValue: sortMode,
            onSelected: onSortChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TaskSortMode.difficulty,
                child: Text('Difficulty'),
              ),
              PopupMenuItem(
                value: _TaskSortMode.completion,
                child: Text('Completion'),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort, size: 18),
                const SizedBox(width: 4),
                Text(sortLabel, style: Theme.of(context).textTheme.bodySmall),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header with filter toggle for buildings.
class _BuildingFilterHeader extends StatelessWidget {
  const _BuildingFilterHeader({
    required this.filter,
    required this.onFilterChanged,
  });

  final _BuildingFilter filter;
  final void Function(_BuildingFilter) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Spacer(),
          PopupMenuButton<_BuildingFilter>(
            initialValue: filter,
            onSelected: onFilterChanged,
            itemBuilder: (context) => [
              for (final f in _BuildingFilter.values)
                PopupMenuItem(value: f, child: Text(f.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list, size: 18),
                const SizedBox(width: 4),
                Text(
                  filter.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card showing a single task with its goals and rewards.
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.viewModel, required this.task});

  final TownshipViewModel viewModel;
  final TownshipTask task;

  @override
  Widget build(BuildContext context) {
    final canClaim = viewModel.isTaskClaimable(task.id);
    final categoryName = '${task.category.displayName} Task';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category header (e.g., "Easy Task")
            Text(categoryName, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final goal in task.goals)
                  _GoalChip(viewModel: viewModel, task: task, goal: goal),
              ],
            ),
            const SizedBox(height: 8),

            // Rewards section with Claim button
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rewards:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          // Show currencies first, then other rewards.
                          for (final reward in task.rewards.where(
                            (r) => r.type == TaskRewardType.currency,
                          ))
                            _RewardChip(reward: reward, viewModel: viewModel),
                          for (final reward in task.rewards.where(
                            (r) => r.type != TaskRewardType.currency,
                          ))
                            _RewardChip(reward: reward, viewModel: viewModel),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StoreConnector<GlobalState, VoidCallback?>(
                  converter: (store) => canClaim
                      ? () => store.dispatch(ClaimTownshipTaskAction(task.id))
                      : null,
                  builder: (context, onPressed) => ElevatedButton(
                    onPressed: onPressed,
                    child: const Text('Claim'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a single goal as a chip.
/// Format: "Defeat 0 / 50 icon Kraken" or "Give 0 / 300 icon Bones"
class _GoalChip extends StatelessWidget {
  const _GoalChip({
    required this.viewModel,
    required this.task,
    required this.goal,
  });

  final TownshipViewModel viewModel;
  final TownshipTask task;
  final TaskGoal goal;

  @override
  Widget build(BuildContext context) {
    final current = viewModel.getGoalProgress(task.id, goal);
    final isMet = current >= goal.quantity;
    final registries = viewModel.registries;
    final goalName = goal.displayName(registries.items, registries.actions);
    final goalAsset = goal.asset(registries.items, registries.actions);

    final progress = _formatProgress(current, goal.quantity);
    final verb = switch (goal.type) {
      TaskGoalType.monsters => 'Defeat',
      TaskGoalType.items => 'Donate',
      TaskGoalType.skillXP => 'Earn',
    };

    final textStyle = TextStyle(
      fontSize: 12,
      decoration: isMet ? TextDecoration.lineThrough : null,
      color: isMet ? Colors.grey : Style.textColorPrimary,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Style.containerBackgroundLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$verb $progress ', style: textStyle),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CachedImage(assetPath: goalAsset, size: 20),
            ),
            TextSpan(text: ' $goalName', style: textStyle),
          ],
        ),
      ),
    );
  }

  String _formatProgress(int current, int total) {
    return '${approximateCountString(current)} / '
        '${approximateCountString(total)}';
  }
}

/// Shows a reward as a chip.
/// Currencies display as "icon 5,000", others as "25 icon Stardust".
class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.reward, required this.viewModel});

  final TaskReward reward;
  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final registries = viewModel.registries;
    final rewardName = reward.displayName(
      registries.items,
      registries.township,
    );
    final rewardAsset = reward.asset(registries.items, registries.township);

    final qty = approximateCountString(reward.quantity);
    final isCurrency = reward.type == TaskRewardType.currency;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Style.containerBackgroundLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrency) ...[
            // Currencies: [icon] 5,000
            CachedImage(assetPath: rewardAsset, size: 20),
            const SizedBox(width: 4),
            Text(
              qty,
              style: const TextStyle(
                fontSize: 12,
                color: Style.textColorPrimary,
              ),
            ),
          ] else ...[
            // Others: 25 [icon] Stardust
            Text(
              qty,
              style: const TextStyle(
                fontSize: 12,
                color: Style.textColorPrimary,
              ),
            ),
            const SizedBox(width: 4),
            CachedImage(assetPath: rewardAsset, size: 20),
            const SizedBox(width: 4),
            Text(
              rewardName,
              style: const TextStyle(
                fontSize: 12,
                color: Style.textColorPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TownshipViewModel {
  TownshipViewModel(this._state);

  final GlobalState _state;

  /// The township state - use this for direct access to township data.
  TownshipState get township => _state.township;

  /// Access to all game registries.
  Registries get registries => _state.registries;

  int get townshipXp => _state.skillState(Skill.town).xp;
  int get townshipLevel => _state.skillState(Skill.town).skillLevel;

  int get gp => _state.gp;

  bool get hasSelectedDeity => township.worshipId != null;

  String? get seasonMedia {
    final name = township.season.name;
    final capitalized = '${name[0].toUpperCase()}${name.substring(1)}';
    final seasonId = MelvorId('melvorF:$capitalized');
    return township.registry.seasonById(seasonId)?.media;
  }

  String get seasonTimeRemaining =>
      compactDurationFromTicks(township.seasonTicksRemaining);

  String get nextUpdateTime =>
      compactDurationFromTicks(township.ticksUntilUpdate);

  List<TownshipBuilding> buildingsForBiome(MelvorId biomeId) {
    final registry = township.registry;
    return registry.buildingsForBiome(biomeId)
      ..sort((a, b) => registry.compareBuildings(a.id, b.id));
  }

  String? canBuild(MelvorId biomeId, MelvorId buildingId) {
    return _state.canBuildTownshipBuilding(biomeId, buildingId);
  }

  bool canAffordRepair(MelvorId biomeId, MelvorId buildingId) =>
      _state.canAffordTownshipRepair(biomeId, buildingId);

  /// Returns true if the player can afford the building costs (ignoring level
  /// requirements).
  bool canAffordBuildingCosts(MelvorId biomeId, MelvorId buildingId) =>
      _state.canAffordTownshipBuildingCosts(biomeId, buildingId);

  bool canAffordGp(int cost) => gp >= cost;

  bool canAffordResource(MelvorId resourceId, int cost) =>
      township.resourceAmount(resourceId) >= cost;

  bool get canAffordAllRepairs => _state.canAffordAllTownshipRepairs();

  bool get needsHealing => township.health < TownshipState.maxHealth;

  // Task-related methods

  /// Returns whether a task can be claimed (all goals met, not completed).
  bool isTaskClaimable(MelvorId taskId) => _state.isTaskComplete(taskId);

  /// Gets the current progress toward a specific goal within a task.
  int getGoalProgress(MelvorId taskId, TaskGoal goal) {
    // For item goals, check inventory
    if (goal.type == TaskGoalType.items) {
      final item = _state.registries.items.byId(goal.id);
      return _state.inventory.countOfItem(item);
    }
    // For XP and monster goals, check tracked progress
    return township.getGoalProgress(taskId, goal);
  }

  bool canHealOneWith(HealingResource resource) =>
      township.healingResourceAmount(resource) >=
      township.costPerHealthPercent(resource);

  bool hasHealingResource(HealingResource resource) =>
      township.healingResourceAmount(resource) > 0;

  TownshipResource healingResourceData(HealingResource resource) =>
      township.registry.resourceById(resource.id);
}

class _DeitySelectionView extends StatelessWidget {
  const _DeitySelectionView({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final deities = viewModel.township.registry.deities;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Choose Your Deity',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Select a deity to begin your township. Each deity provides '
          'unique bonuses as your worship increases.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (deities.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No deities available. Township data may not be loaded.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...deities.map((TownshipDeity deity) => _DeityCard(deity: deity)),
      ],
    );
  }
}

class _DeityCard extends StatelessWidget {
  const _DeityCard({required this.deity});

  final TownshipDeity deity;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectDeity(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deity.name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to select this deity and begin your township.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectDeity(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Select ${deity.name}?'),
        content: const Text(
          'Are you sure you want to choose this deity? '
          'You can change your deity later, but your worship '
          'progress will be reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.dispatch(SelectTownshipDeityAction(deityId: deity.id));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _TownshipStatsCard extends StatelessWidget {
  const _TownshipStatsCard({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final township = viewModel.township;
    final stats = township.stats;
    final happinessIndicator = _formatModifier(
      township.season.happinessModifier,
    );
    final educationIndicator = _formatModifier(
      township.season.educationModifier,
    );

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Town Statistics',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    stat: TownshipStat.population,
                    value:
                        '${stats.population} '
                        '(eff: ${stats.effectivePopulation})',
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    stat: TownshipStat.health,
                    value: percentValueToString(stats.health),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    stat: TownshipStat.happiness,
                    value:
                        '${percentValueToString(stats.happiness)}'
                        '$happinessIndicator',
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    stat: TownshipStat.education,
                    value:
                        '${percentValueToString(stats.education)}'
                        '$educationIndicator',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _StatItem(
              stat: TownshipStat.worship,
              value: '${stats.worship} / 2000',
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Season',
                    value: _formatSeason(viewModel),
                    valueIconPath: viewModel.seasonMedia,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Next Update',
                    value: viewModel.nextUpdateTime,
                  ),
                ),
              ],
            ),
            if (township.hasAnyBuildingNeedingRepair) ...[
              const Divider(),
              _RepairAllSection(viewModel: viewModel),
            ],
            if (viewModel.needsHealing) ...[
              const Divider(),
              _HealSection(viewModel: viewModel),
            ],
          ],
        ),
      ),
    );
  }

  String _formatModifier(double modifier) {
    if (modifier == 0) return '';
    return ' (${signedCountString(modifier.toInt())})';
  }

  String _formatSeason(TownshipViewModel viewModel) {
    final name = viewModel.township.season.name;
    final capitalized = '${name[0].toUpperCase()}${name.substring(1)}';
    return '$capitalized (${viewModel.seasonTimeRemaining})';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    this.stat,
    this.label,
    this.valueIconPath,
  }) : assert(stat != null || label != null, 'Either stat or label required');

  final TownshipStat? stat;
  final String? label;
  final String value;
  final String? valueIconPath;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Style.textColorSecondary);
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stat != null) ...[
              CachedImage(assetPath: stat!.assetPath, size: 14),
              const SizedBox(width: 4),
            ],
            Text(stat?.label ?? label!, style: labelStyle),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (valueIconPath != null) ...[
              CachedImage(assetPath: valueIconPath, size: 14),
              const SizedBox(width: 4),
            ],
            Text(value, style: valueStyle),
          ],
        ),
      ],
    );
  }
}

class _RepairAllSection extends StatelessWidget {
  const _RepairAllSection({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final canAfford = viewModel.canAffordAllRepairs;
    final totalCosts = viewModel.township.totalRepairCosts;

    return Row(
      children: [
        ElevatedButton(
          onPressed: canAfford ? () => _repairAll(context) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: canAfford ? Colors.orange : Colors.grey,
          ),
          child: const Text(
            'Repair All',
            style: TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _buildCostChips(totalCosts),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCostChips(Map<MelvorId, int> costs) {
    final chips = <Widget>[];

    for (final entry in costs.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (Currency.isGpId(resourceId)) {
        final canAfford = viewModel.canAffordGp(amount);
        chips.add(
          _CostChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final registry = viewModel.township.registry;
        final resource = registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        chips.add(
          _CostChip(
            assetPath: resource.media,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      }
    }

    return chips;
  }

  void _repairAll(BuildContext context) {
    try {
      context.dispatch(RepairAllTownshipBuildingsAction());
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _HealSection extends StatelessWidget {
  const _HealSection({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final hasHerbs = viewModel.hasHealingResource(HealingResource.herbs);
    final hasPotions = viewModel.hasHealingResource(HealingResource.potions);
    final hasResources = hasHerbs || hasPotions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Heal Town (${viewModel.township.health.toStringAsFixed(0)}%)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (!hasResources)
          _buildNeedResourcesMessage(context)
        else ...[
          if (hasHerbs) _buildResourceRow(context, HealingResource.herbs),
          if (hasPotions) ...[
            if (hasHerbs) const SizedBox(height: 8),
            _buildResourceRow(context, HealingResource.potions),
          ],
        ],
      ],
    );
  }

  Widget _buildNeedResourcesMessage(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Style.textColorSecondary);

    return Row(
      children: [
        Text('Need ', style: textStyle),
        CachedImage(
          assetPath: viewModel.healingResourceData(HealingResource.herbs).media,
          size: 16,
        ),
        Text(' or ', style: textStyle),
        CachedImage(
          assetPath: viewModel
              .healingResourceData(HealingResource.potions)
              .media,
          size: 16,
        ),
        Text(' to heal', style: textStyle),
      ],
    );
  }

  Widget _buildResourceRow(BuildContext context, HealingResource resource) {
    final township = viewModel.township;
    final maxHeal = township.maxHealableWith(resource);
    final canHealOne = viewModel.canHealOneWith(resource);
    final costPerPercent = township.costPerHealthPercent(resource);
    final resourceData = viewModel.healingResourceData(resource);

    return Row(
      children: [
        _HealButton(
          healAmount: 1,
          costPerPercent: costPerPercent,
          resource: resourceData,
          onPressed: canHealOne ? () => _healWith(context, resource, 1) : null,
        ),
        if (maxHeal > 1) ...[
          const SizedBox(width: 8),
          _HealButton(
            healAmount: maxHeal,
            costPerPercent: costPerPercent,
            resource: resourceData,
            onPressed: () => _healWith(context, resource, maxHeal),
          ),
        ],
      ],
    );
  }

  void _healWith(BuildContext context, HealingResource resource, int amount) {
    try {
      context.dispatch(HealTownshipAction(resource: resource, amount: amount));
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _HealButton extends StatelessWidget {
  const _HealButton({
    required this.healAmount,
    required this.costPerPercent,
    required this.resource,
    required this.onPressed,
  });

  final int healAmount;
  final int costPerPercent;
  final TownshipResource? resource;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final borderColor = enabled ? Style.successColor : Colors.grey;
    final textColor = enabled ? Style.textColorPrimary : Style.textColorMuted;
    final totalCost = costPerPercent * healAmount;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+$healAmount%',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          CachedImage(assetPath: resource?.media, size: 14),
          const SizedBox(width: 4),
          Text(
            '$totalCost',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _TownshipResourcesCard extends StatelessWidget {
  const _TownshipResourcesCard({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final township = viewModel.township;
    final nonZeroResources = township.registry.resources.where((
      TownshipResource r,
    ) {
      // Exclude GP (depositsToBank) as it's shown elsewhere
      if (r.depositsToBank) return false;
      return township.resourceAmount(r.id) > 0;
    }).toList();

    final storageTitle = _buildStorageTitle(context);

    if (nonZeroResources.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              storageTitle,
              const SizedBox(height: 8),
              Text(
                'No resources yet. Build production buildings to '
                'start gathering resources.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            storageTitle,
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: nonZeroResources.map((resource) {
                final amount = township.resourceAmount(resource.id);
                final rates = township.productionRatesPerHour;
                final rate = rates[resource.id] ?? 0;
                return _ResourceChip(
                  media: resource.media,
                  amount: amount,
                  ratePerHour: rate,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageTitle(BuildContext context) {
    final township = viewModel.township;
    final used = approximateCreditString(township.totalResourcesStored);
    final capacity = approximateCreditString(township.stats.storage);
    return Row(
      children: [
        CachedImage(assetPath: TownshipStat.storage.assetPath, size: 20),
        const SizedBox(width: 6),
        Text(
          'Storage ($used / $capacity)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({
    required this.media,
    required this.amount,
    this.ratePerHour = 0,
  });

  final String? media;
  final int amount;
  final double ratePerHour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Style.containerBackgroundLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (media != null)
            CachedImage(assetPath: media, size: 16)
          else
            const Icon(Icons.inventory_2, size: 16),
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approximateCountString(amount),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (ratePerHour > 0)
                Text(
                  '+${approximateCountString(ratePerHour.round())}/hr',
                  style: TextStyle(
                    fontSize: 9,
                    color: Style.successColor.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BiomeSection extends StatelessWidget {
  const _BiomeSection({
    required this.viewModel,
    required this.biome,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.buildingFilter,
  });

  final TownshipViewModel viewModel;
  final TownshipBiome biome;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final _BuildingFilter buildingFilter;

  bool _isBuildingAffordable(TownshipBuilding building) {
    final township = viewModel.township;
    final needsRepair = township.buildingNeedsRepair(biome.id, building.id);
    // Check cost affordability only (ignoring level requirements).
    return needsRepair
        ? viewModel.canAffordRepair(biome.id, building.id)
        : viewModel.canAffordBuildingCosts(biome.id, building.id);
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = viewModel.township.isBiomeUnlocked(biome);
    var buildings = viewModel.buildingsForBiome(biome.id);

    // Apply affordability filter.
    if (buildingFilter == _BuildingFilter.affordable) {
      buildings = buildings.where(_isBuildingAffordable).toList();
    }

    return Column(
      children: [
        InkWell(
          onTap: isUnlocked ? onToggleCollapse : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Style.categoryHeaderColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Icon(
                  isCollapsed || !isUnlocked
                      ? Icons.arrow_right
                      : Icons.arrow_drop_down,
                  size: 24,
                  color: isUnlocked
                      ? Style.textColorPrimary
                      : Style.textColorMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    biome.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isUnlocked
                          ? Style.textColorPrimary
                          : Style.textColorMuted,
                    ),
                  ),
                ),
                if (!isUnlocked)
                  Text(
                    'Requires ${biome.populationRequired} pop',
                    style: TextStyle(
                      color: Style.unmetRequirementColor,
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    '${buildings.length} buildings',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        if (isUnlocked && !isCollapsed)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: buildings
                  .map(
                    (building) => _BuildingCard(
                      viewModel: viewModel,
                      biomeId: biome.id,
                      building: building,
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.viewModel,
    required this.biomeId,
    required this.building,
  });

  final TownshipViewModel viewModel;
  final MelvorId biomeId;
  final TownshipBuilding building;

  @override
  Widget build(BuildContext context) {
    final township = viewModel.township;
    final buildingState = township.buildingState(biomeId, building.id);
    final needsRepair = township.buildingNeedsRepair(biomeId, building.id);
    final efficiencyStr = percentValueToString(buildingState.efficiency);

    // Resolve statue building name/media based on selected deity
    final registry = township.registry;
    final deity = township.selectedDeity;
    final displayName = registry.buildingDisplayName(building, deity);
    final displayMedia = registry.buildingDisplayMedia(building, deity);

    // Determine if we can perform the action (build or repair)
    final canPerformAction = needsRepair
        ? viewModel.canAffordRepair(biomeId, building.id)
        : viewModel.canBuild(biomeId, building.id) == null;

    return SizedBox(
      width: 140,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showBuildDialog(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Building image
                if (displayMedia != null)
                  CachedImage(assetPath: displayMedia, size: 48)
                else
                  const Icon(Icons.home, size: 48),
                const SizedBox(height: 4),
                // Building name
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: canPerformAction
                        ? Style.textColorPrimary
                        : Style.textColorMuted,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Count and efficiency display
                if (buildingState.count > 0)
                  Text(
                    needsRepair
                        ? '${buildingState.count} built ($efficiencyStr)'
                        : '${buildingState.count} built',
                    style: TextStyle(
                      fontSize: 10,
                      color: needsRepair
                          ? Style.unmetRequirementColor
                          : Style.textColorSecondary,
                    ),
                  ),
                const SizedBox(height: 4),
                // Costs section (repair costs if needs repair)
                if (needsRepair)
                  _buildRepairCostsSection(context)
                else
                  _buildCostsSection(context),
                const SizedBox(height: 4),
                // Benefits section (hide when repairing)
                if (!needsRepair) _buildBenefitsSection(context),
                if (!needsRepair) const SizedBox(height: 4),
                // Action button (Repair or Build)
                SizedBox(
                  width: double.infinity,
                  height: 28,
                  child: ElevatedButton(
                    onPressed: canPerformAction
                        ? () => needsRepair
                              ? _repairBuilding(context)
                              : _buildBuilding(context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: canPerformAction
                          ? (needsRepair ? Colors.orange : Style.successColor)
                          : Colors.grey,
                    ),
                    child: Text(
                      needsRepair ? 'Repair' : 'Build',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCostsSection(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null || biomeData.costs.isEmpty) {
      return const SizedBox.shrink();
    }

    final registry = viewModel.township.registry;
    final costWidgets = <Widget>[
      const Text(
        'Cost:',
        style: TextStyle(fontSize: 9, color: Style.textColorSecondary),
      ),
    ];
    for (final entry in biomeData.costs.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (Currency.isGpId(resourceId)) {
        final canAfford = viewModel.canAffordGp(amount);
        costWidgets.add(
          _CostChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final resource = registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costWidgets.add(
          _CostChip(
            assetPath: resource.media,
            value: approximateCountString(amount),
            isAffordable: canAfford,
          ),
        );
      }
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: costWidgets,
    );
  }

  Widget _buildBenefitsSection(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) return const SizedBox.shrink();

    final registry = viewModel.township.registry;
    final benefitWidgets = <Widget>[
      const Text(
        'Per Upgrade:',
        style: TextStyle(fontSize: 9, color: Style.textColorSecondary),
      ),
    ];

    // Population bonus
    if (biomeData.population > 0) {
      benefitWidgets.add(
        _BenefitChip(
          assetPath: TownshipStat.population.assetPath,
          value: '+${biomeData.population}',
        ),
      );
    }

    // Storage bonus
    if (biomeData.storage > 0) {
      benefitWidgets.add(
        _BenefitChip(
          assetPath: TownshipStat.storage.assetPath,
          value: '+${approximateCreditString(biomeData.storage)}',
        ),
      );
    }

    // Production bonuses
    for (final entry in biomeData.production.entries) {
      final resource = registry.resourceById(entry.key);
      final perHour = entry.value.toStringAsFixed(0);
      benefitWidgets.add(
        _BenefitChip(assetPath: resource.media, value: '+$perHour/h'),
      );
    }

    // Happiness bonus
    if (biomeData.happiness != 0) {
      final sign = biomeData.happiness > 0 ? '+' : '';
      benefitWidgets.add(
        _BenefitChip(
          assetPath: TownshipStat.happiness.assetPath,
          value: '$sign${percentValueToString(biomeData.happiness)}',
        ),
      );
    }

    // Education bonus
    if (biomeData.education != 0) {
      final sign = biomeData.education > 0 ? '+' : '';
      benefitWidgets.add(
        _BenefitChip(
          assetPath: TownshipStat.education.assetPath,
          value: '$sign${percentValueToString(biomeData.education)}',
        ),
      );
    }

    // Only show label, no benefits
    if (benefitWidgets.length == 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: benefitWidgets,
    );
  }

  Widget _buildRepairCostsSection(BuildContext context) {
    final township = viewModel.township;
    final repairCosts = township.repairCosts(biomeId, building.id);
    if (repairCosts.isEmpty) {
      return const SizedBox.shrink();
    }

    final costWidgets = <Widget>[
      const Text(
        'Repair:',
        style: TextStyle(fontSize: 9, color: Style.textColorSecondary),
      ),
    ];

    for (final entry in repairCosts.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (Currency.isGpId(resourceId)) {
        final canAfford = viewModel.canAffordGp(amount);
        costWidgets.add(
          _CostChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final resource = township.registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costWidgets.add(
          _CostChip(
            assetPath: resource.media,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      }
    }

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: costWidgets,
    );
  }

  void _buildBuilding(BuildContext context) {
    try {
      context.dispatch(
        BuildTownshipBuildingAction(biomeId: biomeId, buildingId: building.id),
      );
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _repairBuilding(BuildContext context) {
    try {
      context.dispatch(
        RepairTownshipBuildingAction(biomeId: biomeId, buildingId: building.id),
      );
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showBuildDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _BuildingPurchaseDialog(
        viewModel: viewModel,
        biomeId: biomeId,
        building: building,
      ),
    );
  }
}

class _BuildingPurchaseDialog extends StatelessWidget {
  const _BuildingPurchaseDialog({
    required this.viewModel,
    required this.biomeId,
    required this.building,
  });

  final TownshipViewModel viewModel;
  final MelvorId biomeId;
  final TownshipBuilding building;

  @override
  Widget build(BuildContext context) {
    final township = viewModel.township;
    final buildingState = township.buildingState(biomeId, building.id);
    final needsRepair = township.buildingNeedsRepair(biomeId, building.id);

    // Resolve statue building name based on selected deity
    final registry = township.registry;
    final deity = township.selectedDeity;
    final displayName = registry.buildingDisplayName(building, deity);

    final canPerformAction = needsRepair
        ? viewModel.canAffordRepair(biomeId, building.id)
        : viewModel.canBuild(biomeId, building.id) == null;

    final actionLabel = needsRepair ? 'Repair' : 'Build';

    return AlertDialog(
      title: Text('$actionLabel $displayName'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (buildingState.count > 0) ...[
              Text(
                'Currently: ${buildingState.count} built '
                '(${percentValueToString(buildingState.efficiency)} '
                'efficiency)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: needsRepair ? Style.unmetRequirementColor : null,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              needsRepair ? 'Repair Costs' : 'Costs',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (needsRepair)
              _buildRepairCosts(context)
            else
              _buildCosts(context),
            const SizedBox(height: 12),
            if (!needsRepair && building.tier > 1) ...[
              Text(
                'Requirements',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              _buildRequirements(context),
              const SizedBox(height: 12),
            ],
            if (!needsRepair) ...[
              Text('Bonuses', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              _buildBonuses(context),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canPerformAction
              ? () {
                  try {
                    if (needsRepair) {
                      context.dispatch(
                        RepairTownshipBuildingAction(
                          biomeId: biomeId,
                          buildingId: building.id,
                        ),
                      );
                    } else {
                      context.dispatch(
                        BuildTownshipBuildingAction(
                          biomeId: biomeId,
                          buildingId: building.id,
                        ),
                      );
                    }
                    Navigator.of(context).pop();
                  } on Exception catch (e) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              : null,
          child: Text(actionLabel),
        ),
      ],
    );
  }

  Widget _buildRepairCosts(BuildContext context) {
    final township = viewModel.township;
    final repairCosts = township.repairCosts(biomeId, building.id);
    if (repairCosts.isEmpty) {
      return const Text('Free', style: TextStyle(color: Style.successColor));
    }

    final costs = <Widget>[];

    for (final entry in repairCosts.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (Currency.isGpId(resourceId)) {
        final canAfford = viewModel.canAffordGp(amount);
        costs.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedImage(assetPath: Currency.gp.assetPath, size: 16),
              const SizedBox(width: 4),
              Text(
                approximateCreditString(amount),
                style: TextStyle(
                  color: canAfford ? Style.successColor : Style.errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      } else {
        final resource = township.registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costs.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${resource.name}: ', style: const TextStyle(fontSize: 13)),
              Text(
                approximateCreditString(amount),
                style: TextStyle(
                  color: canAfford ? Style.successColor : Style.errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Wrap(spacing: 12, runSpacing: 4, children: costs);
  }

  Widget _buildCosts(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) {
      return const Text(
        'No cost data',
        style: TextStyle(color: Style.errorColor),
      );
    }

    final registry = viewModel.township.registry;
    final costs = <Widget>[];

    // All costs including GP (GP has localId 'GP')
    for (final entry in biomeData.costs.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (Currency.isGpId(resourceId)) {
        // GP cost
        final canAfford = viewModel.canAffordGp(amount);
        costs.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CachedImage(assetPath: Currency.gp.assetPath, size: 16),
              const SizedBox(width: 4),
              Text(
                approximateCreditString(amount),
                style: TextStyle(
                  color: canAfford ? Style.successColor : Style.errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      } else {
        // Resource cost
        final resource = registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costs.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${resource.name}: ', style: const TextStyle(fontSize: 13)),
              Text(
                approximateCreditString(amount),
                style: TextStyle(
                  color: canAfford ? Style.successColor : Style.errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    }

    if (costs.isEmpty) {
      return const Text('Free', style: TextStyle(color: Style.successColor));
    }

    return Wrap(spacing: 12, runSpacing: 4, children: costs);
  }

  Widget _buildRequirements(BuildContext context) {
    final reqs = <Widget>[];

    // Level requirement based on tier
    final levelRequired = TownshipRegistry.tierToLevel(building.tier);
    if (levelRequired > 1) {
      final met = viewModel.townshipLevel >= levelRequired;
      reqs.add(
        Text(
          'Township Lv. $levelRequired',
          style: TextStyle(
            color: met ? Style.successColor : Style.unmetRequirementColor,
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: reqs);
  }

  Widget _buildBonuses(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) {
      return const Text('No bonus data');
    }

    final bonuses = <String>[];

    if (biomeData.population > 0) {
      bonuses.add('+${biomeData.population} Population');
    }
    if (biomeData.happiness != 0) {
      final sign = biomeData.happiness > 0 ? '+' : '';
      bonuses.add(
        '$sign${percentValueToString(biomeData.happiness)} Happiness',
      );
    }
    if (biomeData.education != 0) {
      final sign = biomeData.education > 0 ? '+' : '';
      bonuses.add(
        '$sign${percentValueToString(biomeData.education)} Education',
      );
    }
    if (biomeData.storage > 0) {
      bonuses.add('+${biomeData.storage} Storage');
    }

    // Production
    if (biomeData.production.isNotEmpty) {
      final registry = viewModel.township.registry;
      for (final entry in biomeData.production.entries) {
        final resource = registry.resourceById(entry.key);
        bonuses.add('Produces ${entry.value} ${resource.name}/hr');
      }
    }

    if (bonuses.isEmpty) {
      return const Text(
        'No bonuses',
        style: TextStyle(color: Style.textColorSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bonuses.map(Text.new).toList(),
    );
  }
}

/// A compact chip showing a benefit with an image (always green).
class _BenefitChip extends StatelessWidget {
  const _BenefitChip({required this.assetPath, required this.value});

  final String? assetPath;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _IconValueChip(
      assetPath: assetPath,
      value: value,
      color: Style.successColor,
    );
  }
}

/// A compact chip showing a cost with an image.
/// Green if affordable, red if not.
class _CostChip extends StatelessWidget {
  const _CostChip({
    required this.assetPath,
    required this.value,
    required this.isAffordable,
  });

  final String? assetPath;
  final String value;
  final bool isAffordable;

  @override
  Widget build(BuildContext context) {
    return _IconValueChip(
      assetPath: assetPath,
      value: value,
      color: isAffordable ? Style.successColor : Style.errorColor,
    );
  }
}

/// Base chip widget showing an icon and value with a specified color.
class _IconValueChip extends StatelessWidget {
  const _IconValueChip({
    required this.assetPath,
    required this.value,
    required this.color,
  });

  final String? assetPath;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachedImage(
          assetPath: assetPath,
          size: 14,
          fallback: const Icon(Icons.inventory_2, size: 14),
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
