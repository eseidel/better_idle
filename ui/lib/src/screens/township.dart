import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class TownshipPage extends StatefulWidget {
  const TownshipPage({super.key});

  @override
  State<TownshipPage> createState() => _TownshipPageState();
}

class _TownshipPageState extends State<TownshipPage> {
  final Set<MelvorId> _collapsedBiomes = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Township')),
      drawer: const AppNavigationDrawer(),
      body: StoreConnector<GlobalState, TownshipViewModel>(
        converter: (store) => TownshipViewModel(store.state),
        builder: (context, viewModel) {
          // Show deity selection if no deity chosen yet
          if (!viewModel.hasSelectedDeity) {
            return _DeitySelectionView(viewModel: viewModel);
          }

          return ListView(
            children: [
              SkillProgress(xp: viewModel.townshipXp),
              _TownshipStatsCard(viewModel: viewModel),
              _TownshipResourcesCard(viewModel: viewModel),
              const Divider(),
              ...viewModel.biomes.map(
                (biome) => _BiomeSection(
                  viewModel: viewModel,
                  biome: biome,
                  isCollapsed: _collapsedBiomes.contains(biome.id),
                  onToggleCollapse: () {
                    setState(() {
                      if (_collapsedBiomes.contains(biome.id)) {
                        _collapsedBiomes.remove(biome.id);
                      } else {
                        _collapsedBiomes.add(biome.id);
                      }
                    });
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class TownshipViewModel {
  TownshipViewModel(this._state);

  final GlobalState _state;

  TownshipRegistry get _registry => _state.registries.township;
  TownshipState get _township => _state.township;

  int get townshipXp => _state.skillState(Skill.town).xp;
  int get townshipLevel => levelForXp(townshipXp);

  TownshipStats get stats => TownshipStats.calculate(_township, _registry);

  int get gp => _state.gp;

  // Deity/worship
  MelvorId? get selectedDeityId => _township.worshipId;
  bool get hasSelectedDeity => selectedDeityId != null;
  List<TownshipDeity> get deities => _registry.deities;

  TownshipDeity? get selectedDeity {
    final id = selectedDeityId;
    if (id == null) return null;
    return _registry.deityById(id);
  }

  List<TownshipBiome> get biomes => _registry.biomes;

  List<TownshipResource> get resources => _registry.resources;

  int resourceAmount(MelvorId resourceId) =>
      _township.resourceAmount(resourceId);

  int totalResourcesStored() {
    var total = 0;
    for (final resource in resources) {
      if (!resource.depositsToBank) {
        total += resourceAmount(resource.id);
      }
    }
    return total;
  }

  Season get season => _township.season;

  String get seasonTimeRemaining {
    final ticks = _township.seasonTicksRemaining;
    final seconds = ticks ~/ 10;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    final days = hours ~/ 24;
    if (days > 0) return '${days}d ${hours % 24}h';
    if (hours > 0) return '${hours}h ${minutes % 60}m';
    return '${minutes}m';
  }

  String get nextUpdateTime {
    final ticks = _township.ticksUntilUpdate;
    final seconds = ticks ~/ 10;
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '${hours}h ${minutes % 60}m';
    }
    return '${minutes}m';
  }

  bool isBiomeUnlocked(TownshipBiome biome) {
    return stats.population >= biome.populationRequired;
  }

  List<TownshipBuilding> buildingsForBiome(MelvorId biomeId) {
    return _registry.buildingsForBiome(biomeId);
  }

  BuildingState buildingState(MelvorId biomeId, MelvorId buildingId) {
    return _township.biomeState(biomeId).buildingState(buildingId);
  }

  String? canBuild(MelvorId biomeId, MelvorId buildingId) {
    return _state.canBuildTownshipBuilding(biomeId, buildingId);
  }

  bool canAffordGp(int cost) => gp >= cost;

  bool canAffordResource(MelvorId resourceId, int cost) =>
      resourceAmount(resourceId) >= cost;
}

class _DeitySelectionView extends StatelessWidget {
  const _DeitySelectionView({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final deities = viewModel.deities;

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
          ...deities.map((deity) => _DeityCard(deity: deity)),
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
    final stats = viewModel.stats;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Style.textColorSecondary);
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);

    final happinessIndicator = _seasonIndicator(
      viewModel.season.happinessModifier,
    );
    final educationIndicator = _seasonIndicator(
      viewModel.season.educationModifier,
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
                    label: 'Population',
                    value:
                        '${stats.population} '
                        '(eff: ${stats.effectivePopulation})',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Health',
                    value: '${stats.health.toStringAsFixed(0)}%',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Happiness',
                    value:
                        '${stats.happiness.toStringAsFixed(0)}%'
                        '$happinessIndicator',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Education',
                    value:
                        '${stats.education.toStringAsFixed(0)}%'
                        '$educationIndicator',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Storage',
                    value: _formatStorage(viewModel, stats),
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Worship',
                    value: '${stats.worship} / 2000',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Season',
                    value: _formatSeason(viewModel),
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Next Update',
                    value: viewModel.nextUpdateTime,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _seasonIndicator(double modifier) {
    if (modifier > 0) return ' (+${modifier.toStringAsFixed(0)})';
    if (modifier < 0) return ' (${modifier.toStringAsFixed(0)})';
    return '';
  }

  String _formatSeason(TownshipViewModel viewModel) {
    final name = viewModel.season.name;
    final capitalized = '${name[0].toUpperCase()}${name.substring(1)}';
    return '$capitalized (${viewModel.seasonTimeRemaining})';
  }

  String _formatStorage(TownshipViewModel viewModel, TownshipStats stats) {
    final used = approximateCreditString(viewModel.totalResourcesStored());
    final capacity = approximateCreditString(stats.storage);
    return '$used / $capacity';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _TownshipResourcesCard extends StatelessWidget {
  const _TownshipResourcesCard({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final nonZeroResources = viewModel.resources.where((r) {
      // Exclude GP (depositsToBank) as it's shown elsewhere
      if (r.depositsToBank) return false;
      return viewModel.resourceAmount(r.id) > 0;
    }).toList();

    if (nonZeroResources.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resources', style: Theme.of(context).textTheme.titleMedium),
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
            Text('Resources', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: nonZeroResources.map((resource) {
                final amount = viewModel.resourceAmount(resource.id);
                return _ResourceChip(name: resource.name, amount: amount);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({required this.name, required this.amount});

  final String name;
  final int amount;

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
          Text(
            name,
            style: const TextStyle(fontSize: 12, color: Style.textColorPrimary),
          ),
          const SizedBox(width: 4),
          Text(
            approximateCreditString(amount),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Style.currencyValueColor,
            ),
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
  });

  final TownshipViewModel viewModel;
  final TownshipBiome biome;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final isUnlocked = viewModel.isBiomeUnlocked(biome);
    final buildings = viewModel.buildingsForBiome(biome.id);

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
          ...buildings.map(
            (building) => _BuildingRow(
              viewModel: viewModel,
              biomeId: biome.id,
              building: building,
            ),
          ),
      ],
    );
  }
}

class _BuildingRow extends StatelessWidget {
  const _BuildingRow({
    required this.viewModel,
    required this.biomeId,
    required this.building,
  });

  final TownshipViewModel viewModel;
  final MelvorId biomeId;
  final TownshipBuilding building;

  @override
  Widget build(BuildContext context) {
    final buildingState = viewModel.buildingState(biomeId, building.id);
    final error = viewModel.canBuild(biomeId, building.id);
    final canBuild = error == null;

    return InkWell(
      onTap: () => _showBuildDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 32), // Indent under biome header
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    building.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: canBuild
                          ? Style.textColorPrimary
                          : Style.textColorMuted,
                    ),
                  ),
                  if (buildingState.count > 0)
                    Text(
                      '${buildingState.count} built '
                      '(${buildingState.efficiency.toStringAsFixed(0)}% eff)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Style.textColorSecondary,
                      ),
                    )
                  else
                    Text(
                      _getBuildingDescription(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Style.textColorSecondary,
                      ),
                    ),
                  if (!canBuild)
                    Text(
                      error,
                      style: TextStyle(
                        fontSize: 11,
                        color: Style.unmetRequirementColor,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.add_circle_outline,
                color: canBuild ? Style.successColor : Style.textColorMuted,
              ),
              onPressed: canBuild ? () => _showBuildDialog(context) : null,
            ),
          ],
        ),
      ),
    );
  }

  String _getBuildingDescription() {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) return 'No data for this biome';

    final parts = <String>[];
    if (biomeData.population > 0) {
      parts.add('+${biomeData.population} pop');
    }
    if (biomeData.production.isNotEmpty) {
      parts.add('produces resources');
    }
    if (biomeData.happiness != 0) {
      parts.add('+${biomeData.happiness} happiness');
    }
    if (biomeData.education != 0) {
      parts.add('+${biomeData.education} education');
    }
    if (biomeData.storage > 0) {
      parts.add('+${biomeData.storage} storage');
    }
    return parts.isEmpty ? 'No bonuses' : parts.join(', ');
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
    final buildingState = viewModel.buildingState(biomeId, building.id);
    final error = viewModel.canBuild(biomeId, building.id);
    final canBuild = error == null;

    return AlertDialog(
      title: Text('Build ${building.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (buildingState.count > 0) ...[
              Text(
                'Currently: ${buildingState.count} built '
                '(${buildingState.efficiency.toStringAsFixed(0)}% efficiency)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Text('Costs', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _buildCosts(context),
            const SizedBox(height: 12),
            if (building.tier > 1) ...[
              Text(
                'Requirements',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              _buildRequirements(context),
              const SizedBox(height: 12),
            ],
            Text('Bonuses', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _buildBonuses(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canBuild
              ? () {
                  try {
                    context.dispatch(
                      BuildTownshipBuildingAction(
                        biomeId: biomeId,
                        buildingId: building.id,
                      ),
                    );
                    Navigator.of(context).pop();
                  } on Exception catch (e) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              : null,
          child: const Text('Build'),
        ),
      ],
    );
  }

  Widget _buildCosts(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) {
      return const Text(
        'No cost data',
        style: TextStyle(color: Style.errorColor),
      );
    }

    final costs = <Widget>[];

    // All costs including GP (GP has localId 'GP')
    for (final entry in biomeData.costs.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (resourceId.localId == 'GP') {
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
        final resource = viewModel._registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costs.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${resource?.name ?? resourceId.localId}: ',
                style: const TextStyle(fontSize: 13),
              ),
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
    final levelRequired = _tierToLevel(building.tier);
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

  int _tierToLevel(int tier) {
    switch (tier) {
      case 1:
        return 1;
      case 2:
        return 30;
      case 3:
        return 60;
      case 4:
        return 80;
      default:
        return 1;
    }
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
      bonuses.add('$sign${biomeData.happiness.toStringAsFixed(0)}% Happiness');
    }
    if (biomeData.education != 0) {
      final sign = biomeData.education > 0 ? '+' : '';
      bonuses.add('$sign${biomeData.education.toStringAsFixed(0)}% Education');
    }
    if (biomeData.storage > 0) {
      bonuses.add('+${biomeData.storage} Storage');
    }

    // Production
    if (biomeData.production.isNotEmpty) {
      for (final entry in biomeData.production.entries) {
        final resource = viewModel._registry.resourceById(entry.key);
        bonuses.add(
          'Produces ${entry.value} ${resource?.name ?? entry.key.localId}/hr',
        );
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
