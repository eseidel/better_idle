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

  TownshipState get _township => _state.township;
  TownshipRegistry get _registry => _township.registry;

  int get townshipXp => _state.skillState(Skill.town).xp;
  int get townshipLevel => _state.skillState(Skill.town).skillLevel;

  TownshipStats get stats => _township.stats;

  int get gp => _state.gp;

  // Deity/worship
  MelvorId? get selectedDeityId => _township.worshipId;
  bool get hasSelectedDeity => selectedDeityId != null;
  List<TownshipDeity> get deities => _township.registry.deities;

  TownshipDeity? get selectedDeity => _township.selectedDeity;

  List<TownshipBiome> get biomes => _township.registry.biomes;

  List<TownshipResource> get resources => _township.registry.resources;

  int resourceAmount(MelvorId resourceId) =>
      _township.resourceAmount(resourceId);

  int get totalResourcesStored => _township.totalResourcesStored;

  Map<MelvorId, double> get productionRates => _township.productionRatesPerHour;

  double resourceProductionRate(MelvorId resourceId) =>
      productionRates[resourceId] ?? 0;

  Season get season => _township.season;

  String get seasonTimeRemaining =>
      compactDurationFromTicks(_township.seasonTicksRemaining);

  String get nextUpdateTime =>
      compactDurationFromTicks(_township.ticksUntilUpdate);

  bool isBiomeUnlocked(TownshipBiome biome) => _township.isBiomeUnlocked(biome);

  List<TownshipBuilding> buildingsForBiome(MelvorId biomeId) {
    return _township.registry.buildingsForBiome(biomeId)
      ..sort((a, b) => _registry.compareBuildings(a.id, b.id));
  }

  BuildingState buildingState(MelvorId biomeId, MelvorId buildingId) {
    return _township.buildingState(biomeId, buildingId);
  }

  String? canBuild(MelvorId biomeId, MelvorId buildingId) {
    return _state.canBuildTownshipBuilding(biomeId, buildingId);
  }

  /// Returns true if the building needs repair (efficiency < 100).
  bool needsRepair(MelvorId biomeId, MelvorId buildingId) {
    return _township.buildingNeedsRepair(biomeId, buildingId);
  }

  /// Returns the repair costs for a building.
  /// Uses the formula: (Base Cost / 3) × Buildings Built × (1 - Efficiency%)
  Map<MelvorId, int> repairCosts(MelvorId biomeId, MelvorId buildingId) {
    return _township.repairCosts(biomeId, buildingId);
  }

  /// Returns true if the player can afford all repair costs.
  bool canAffordRepair(MelvorId biomeId, MelvorId buildingId) =>
      _state.canAffordTownshipRepair(biomeId, buildingId);

  bool canAffordGp(int cost) => gp >= cost;

  bool canAffordResource(MelvorId resourceId, int cost) =>
      resourceAmount(resourceId) >= cost;

  /// Returns true if any building needs repair.
  bool get hasAnyBuildingNeedingRepair => _township.hasAnyBuildingNeedingRepair;

  /// Returns the total repair costs for all buildings.
  Map<MelvorId, int> get totalRepairCosts => _township.totalRepairCosts;

  /// Returns true if the player can afford all repair costs for all buildings.
  bool get canAffordAllRepairs => _state.canAffordAllTownshipRepairs();

  // ---------------------------------------------------------------------------
  // Health / Healing
  // ---------------------------------------------------------------------------

  /// Current health percentage (20-100).
  double get health => _township.health;

  /// Returns true if health is below 100%.
  bool get needsHealing => health < TownshipState.maxHealth;

  /// Amount of Herbs available.
  int get herbsAmount => _township.herbsAmount;

  /// Amount of Potions available.
  int get potionsAmount => _township.potionsAmount;

  /// Cost in Herbs to heal 1% health.
  int get herbsCostPerHealthPercent => _township.herbsCostPerHealthPercent;

  /// Cost in Potions to heal 1% health.
  int get potionsCostPerHealthPercent => _township.potionsCostPerHealthPercent;

  /// Maximum health percent that can be healed with current Herbs.
  int get maxHealableWithHerbs => _township.maxHealableWithHerbs();

  /// Maximum health percent that can be healed with current Potions.
  int get maxHealableWithPotions => _township.maxHealableWithPotions();

  /// Returns true if we can afford to heal 1% with herbs.
  bool get canHealOneWithHerbs => herbsAmount >= herbsCostPerHealthPercent;

  /// Returns true if we can afford to heal 1% with potions.
  bool get canHealOneWithPotions =>
      potionsAmount >= potionsCostPerHealthPercent;

  /// Returns true if we have any herbs (for showing the heal section).
  bool get hasHerbs => herbsAmount > 0;

  /// Returns true if we have any potions (for showing the heal section).
  bool get hasPotions => potionsAmount > 0;

  /// Returns true if we should show the heal section.
  /// Show if health < 100% (we'll show a message if no herbs/potions).
  bool get shouldShowHealSection => needsHealing;

  /// Media path for Herbs resource.
  String? get herbsMedia =>
      _registry.resourceById(TownshipState.herbsId)?.media;

  /// Media path for Potions resource.
  String? get potionsMedia =>
      _registry.resourceById(TownshipState.potionsId)?.media;
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
                    value: percentValueToString(stats.health),
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
                        '${percentValueToString(stats.happiness)}'
                        '$happinessIndicator',
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Education',
                    value:
                        '${percentValueToString(stats.education)}'
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
            if (viewModel.hasAnyBuildingNeedingRepair) ...[
              const Divider(),
              _RepairAllSection(viewModel: viewModel),
            ],
            if (viewModel.shouldShowHealSection) ...[
              const Divider(),
              _HealSection(viewModel: viewModel),
            ],
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
    final used = approximateCreditString(viewModel.totalResourcesStored);
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

class _RepairAllSection extends StatelessWidget {
  const _RepairAllSection({required this.viewModel});

  final TownshipViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final canAfford = viewModel.canAffordAllRepairs;
    final totalCosts = viewModel.totalRepairCosts;

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

      if (resourceId.localId == 'GP') {
        final canAfford = viewModel.canAffordGp(amount);
        chips.add(
          _CostBenefitChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final resource = viewModel._registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        chips.add(
          _CostBenefitChip(
            assetPath: resource?.media,
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
    final hasResources = viewModel.hasHerbs || viewModel.hasPotions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Heal Town (${viewModel.health.toStringAsFixed(0)}%)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (!hasResources)
          _buildNeedResourcesMessage(context)
        else ...[
          // Herbs row
          if (viewModel.hasHerbs) _buildHerbsRow(context),
          // Potions row
          if (viewModel.hasPotions) ...[
            if (viewModel.hasHerbs) const SizedBox(height: 8),
            _buildPotionsRow(context),
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
        if (viewModel.herbsMedia != null)
          CachedImage(assetPath: viewModel.herbsMedia!, size: 16)
        else
          const Icon(Icons.grass, size: 16),
        Text(' or ', style: textStyle),
        if (viewModel.potionsMedia != null)
          CachedImage(assetPath: viewModel.potionsMedia!, size: 16)
        else
          const Icon(Icons.science, size: 16),
        Text(' to heal', style: textStyle),
      ],
    );
  }

  Widget _buildHerbsRow(BuildContext context) {
    final maxHeal = viewModel.maxHealableWithHerbs;
    final canHealOne = viewModel.canHealOneWithHerbs;
    final cost = viewModel.herbsCostPerHealthPercent;
    final assetPath = viewModel.herbsMedia;

    return Row(
      children: [
        // +1 button (always shown if we have herbs)
        _HealButton(
          label: '+1%',
          cost: cost,
          assetPath: assetPath,
          enabled: canHealOne,
          onPressed: canHealOne ? () => _healWithHerbs(context, 1) : null,
        ),
        const SizedBox(width: 8),
        // Max button (show amount we can heal, or disabled +1 if we can't)
        if (maxHeal > 1)
          _HealButton(
            label: '+$maxHeal%',
            cost: cost * maxHeal,
            assetPath: assetPath,
            enabled: true,
            onPressed: () => _healWithHerbs(context, maxHeal),
          )
        else if (!canHealOne)
          _HealButton(
            label: '+1%',
            cost: cost,
            assetPath: assetPath,
            enabled: false,
            onPressed: null,
          ),
      ],
    );
  }

  Widget _buildPotionsRow(BuildContext context) {
    final maxHeal = viewModel.maxHealableWithPotions;
    final canHealOne = viewModel.canHealOneWithPotions;
    final cost = viewModel.potionsCostPerHealthPercent;
    final assetPath = viewModel.potionsMedia;

    return Row(
      children: [
        // +1 button (always shown if we have potions)
        _HealButton(
          label: '+1%',
          cost: cost,
          assetPath: assetPath,
          enabled: canHealOne,
          onPressed: canHealOne ? () => _healWithPotions(context, 1) : null,
        ),
        const SizedBox(width: 8),
        // Max button (show amount we can heal, or disabled +1 if we can't)
        if (maxHeal > 1)
          _HealButton(
            label: '+$maxHeal%',
            cost: cost * maxHeal,
            assetPath: assetPath,
            enabled: true,
            onPressed: () => _healWithPotions(context, maxHeal),
          )
        else if (!canHealOne)
          _HealButton(
            label: '+1%',
            cost: cost,
            assetPath: assetPath,
            enabled: false,
            onPressed: null,
          ),
      ],
    );
  }

  void _healWithHerbs(BuildContext context, int amount) {
    try {
      context.dispatch(HealTownshipWithHerbsAction(amount: amount));
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _healWithPotions(BuildContext context, int amount) {
    try {
      context.dispatch(HealTownshipWithPotionsAction(amount: amount));
    } on Exception catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _HealButton extends StatelessWidget {
  const _HealButton({
    required this.label,
    required this.cost,
    required this.assetPath,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final int cost;
  final String? assetPath;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final borderColor = enabled ? Style.successColor : Colors.grey;
    final textColor = enabled ? Style.textColorPrimary : Style.textColorMuted;

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
            label,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          if (assetPath != null)
            CachedImage(assetPath: assetPath!, size: 14)
          else
            Icon(Icons.inventory_2, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            '$cost',
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
                final rate = viewModel.resourceProductionRate(resource.id);
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
            CachedImage(assetPath: media!, size: 16)
          else
            const Icon(Icons.inventory_2, size: 16),
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approximateCreditString(amount),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (ratePerHour > 0)
                Text(
                  '+${approximateCreditString(ratePerHour.round())}/hr',
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
    final buildingState = viewModel.buildingState(biomeId, building.id);
    final needsRepair = viewModel.needsRepair(biomeId, building.id);

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
                if (building.media != null)
                  CachedImage(assetPath: building.media!, size: 48)
                else
                  const Icon(Icons.home, size: 48),
                const SizedBox(height: 4),
                // Building name
                Text(
                  building.name,
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
                        ? '${buildingState.count} built '
                              '(${percentValueToString(buildingState.efficiency)})'
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

    final costWidgets = <Widget>[
      const Text(
        'Cost:',
        style: TextStyle(fontSize: 9, color: Style.textColorSecondary),
      ),
    ];
    for (final entry in biomeData.costs.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (resourceId.localId == 'GP') {
        final canAfford = viewModel.canAffordGp(amount);
        costWidgets.add(
          _CostBenefitChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final resource = viewModel._registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costWidgets.add(
          _CostBenefitChip(
            assetPath: resource?.media,
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

  Widget _buildBenefitsSection(BuildContext context) {
    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) return const SizedBox.shrink();

    final benefitWidgets = <Widget>[
      const Text(
        'Per Upgrade:',
        style: TextStyle(fontSize: 9, color: Style.textColorSecondary),
      ),
    ];

    // Population bonus
    if (biomeData.population > 0) {
      benefitWidgets.add(
        _CostBenefitChip(
          assetPath: 'assets/media/skills/township/population.png',
          value: '+${biomeData.population}',
          isAffordable: true,
          isBenefit: true,
        ),
      );
    }

    // Storage bonus
    if (biomeData.storage > 0) {
      benefitWidgets.add(
        _CostBenefitChip(
          assetPath: 'assets/media/skills/township/storage.png',
          value: '+${approximateCreditString(biomeData.storage)}',
          isAffordable: true,
          isBenefit: true,
        ),
      );
    }

    // Production bonuses
    for (final entry in biomeData.production.entries) {
      final resource = viewModel._registry.resourceById(entry.key);
      final perHour = entry.value.toStringAsFixed(0);
      benefitWidgets.add(
        _CostBenefitChip(
          assetPath: resource?.media,
          value: '+$perHour/h',
          isAffordable: true,
          isBenefit: true,
        ),
      );
    }

    // Happiness bonus
    if (biomeData.happiness != 0) {
      final sign = biomeData.happiness > 0 ? '+' : '';
      benefitWidgets.add(
        _CostBenefitChip(
          assetPath: 'assets/media/skills/township/happiness.png',
          value: '$sign${percentValueToString(biomeData.happiness)}',
          isAffordable: true,
          isBenefit: true,
        ),
      );
    }

    // Education bonus
    if (biomeData.education != 0) {
      final sign = biomeData.education > 0 ? '+' : '';
      benefitWidgets.add(
        _CostBenefitChip(
          assetPath: 'assets/media/skills/township/education.png',
          value: '$sign${percentValueToString(biomeData.education)}',
          isAffordable: true,
          isBenefit: true,
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
    final repairCosts = viewModel.repairCosts(biomeId, building.id);
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

      if (resourceId.localId == 'GP') {
        final canAfford = viewModel.canAffordGp(amount);
        costWidgets.add(
          _CostBenefitChip(
            assetPath: Currency.gp.assetPath,
            value: approximateCreditString(amount),
            isAffordable: canAfford,
          ),
        );
      } else {
        final resource = viewModel._registry.resourceById(resourceId);
        final canAfford = viewModel.canAffordResource(resourceId, amount);
        costWidgets.add(
          _CostBenefitChip(
            assetPath: resource?.media,
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
    final buildingState = viewModel.buildingState(biomeId, building.id);
    final needsRepair = viewModel.needsRepair(biomeId, building.id);

    final canPerformAction = needsRepair
        ? viewModel.canAffordRepair(biomeId, building.id)
        : viewModel.canBuild(biomeId, building.id) == null;

    final actionLabel = needsRepair ? 'Repair' : 'Build';

    return AlertDialog(
      title: Text('$actionLabel ${building.name}'),
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
    final repairCosts = viewModel.repairCosts(biomeId, building.id);
    if (repairCosts.isEmpty) {
      return const Text('Free', style: TextStyle(color: Style.successColor));
    }

    final costs = <Widget>[];

    for (final entry in repairCosts.entries) {
      final resourceId = entry.key;
      final amount = entry.value;

      if (resourceId.localId == 'GP') {
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

/// A compact chip showing a cost or benefit with an image.
class _CostBenefitChip extends StatelessWidget {
  const _CostBenefitChip({
    required this.assetPath,
    required this.value,
    required this.isAffordable,
    this.isBenefit = false,
  });

  final String? assetPath;
  final String value;
  final bool isAffordable;
  final bool isBenefit;

  @override
  Widget build(BuildContext context) {
    final color = isBenefit
        ? Style.successColor
        : (isAffordable ? Style.successColor : Style.errorColor);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (assetPath != null)
          CachedImage(assetPath: assetPath!, size: 14)
        else
          const Icon(Icons.inventory_2, size: 14),
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
