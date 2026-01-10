import 'dart:math';

import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/township_state.dart';

/// Result of a township update containing the new state and produced GP.
class TownshipUpdateResult {
  const TownshipUpdateResult({
    required this.state,
    required this.gpProduced,
    required this.xpGained,
  });

  final TownshipState state;

  /// GP produced during this update (to be added to player currencies).
  final int gpProduced;

  /// XP gained during this update.
  final double xpGained;
}

/// Calculates computed township statistics from buildings and modifiers.
class TownshipStats {
  TownshipStats({
    required this.population,
    required this.happiness,
    required this.education,
    required this.health,
    required this.storage,
    required this.worship,
  });

  /// Calculates stats from current state and registry.
  factory TownshipStats.calculate(
    TownshipState state,
    TownshipRegistry registry,
  ) {
    var population = 0;
    var happiness = 0.0;
    var education = 0.0;
    var health = 0.0;
    var storage = TownshipState.baseStorage;
    var worship = 0;

    // Sum up bonuses from all buildings in all biomes
    for (final biomeEntry in state.biomes.entries) {
      final biomeState = biomeEntry.value;

      for (final buildingEntry in biomeState.buildings.entries) {
        final building = registry.buildingById(buildingEntry.key);
        if (building == null) continue;

        final buildingState = buildingEntry.value;
        final count = buildingState.count;
        final efficiencyMultiplier = buildingState.efficiency / 100.0;

        // Population bonus is not affected by efficiency
        population += building.populationBonus * count;

        // Other bonuses are scaled by efficiency
        happiness += building.happinessBonus * count * efficiencyMultiplier;
        education += building.educationBonus * count * efficiencyMultiplier;
        health += building.healthBonus * count * efficiencyMultiplier;

        // Storage bonus is not affected by efficiency
        storage += building.storageBonus * count;

        // Worship bonus scaled by efficiency
        worship += (building.worshipBonus * count * efficiencyMultiplier)
            .round();
      }
    }

    // Apply season modifiers
    happiness += state.season.happinessModifier;
    education += state.season.educationModifier;

    // Clamp values
    happiness = happiness.clamp(0, double.infinity);
    education = education.clamp(0, double.infinity);
    health = health.clamp(0, 100);
    worship = worship.clamp(0, 2000);

    return TownshipStats(
      population: population,
      happiness: happiness,
      education: education,
      health: health,
      storage: storage,
      worship: worship,
    );
  }

  final int population;
  final double happiness; // Can exceed 100%
  final double education; // Can exceed 100%
  final double health; // 0-100%
  final int storage;
  final int worship; // 0-2000

  /// Happiness modifier for XP (1% bonus per 1% happiness).
  double get happinessXpMultiplier => 1.0 + (happiness / 100.0);

  /// Education modifier for resource production (1% bonus per 1% education).
  double get educationProductionMultiplier => 1.0 + (education / 100.0);

  /// Health modifier for population (reduces if below 100%).
  double get healthPopulationMultiplier => health / 100.0;

  /// Effective population after health modifier.
  int get effectivePopulation =>
      (population * healthPopulationMultiplier).floor();
}

/// Processes building degradation for a single biome.
BiomeState _degradeBuildings(
  BiomeState biomeState,
  TownshipRegistry registry,
  Random random,
) {
  final newBuildings = <MelvorId, BuildingState>{};

  for (final entry in biomeState.buildings.entries) {
    final building = registry.buildingById(entry.key);
    final buildingState = entry.value;

    // Storage buildings don't degrade
    if (building == null || !building.degradable) {
      newBuildings[entry.key] = buildingState;
      continue;
    }

    // Each building has a 25% chance to lose 1% efficiency (min 20%)
    var newEfficiency = buildingState.efficiency;
    for (var i = 0; i < buildingState.count; i++) {
      if (random.nextDouble() < 0.25) {
        newEfficiency = (newEfficiency - 1).clamp(20.0, 100.0);
      }
    }

    newBuildings[entry.key] = buildingState.copyWith(efficiency: newEfficiency);
  }

  return biomeState.copyWith(buildings: newBuildings);
}

/// Calculates resource production from all buildings.
Map<MelvorId, int> _calculateProduction(
  TownshipState state,
  TownshipRegistry registry,
  TownshipStats stats,
) {
  final production = <MelvorId, int>{};

  for (final biomeEntry in state.biomes.entries) {
    final biomeState = biomeEntry.value;

    for (final buildingEntry in biomeState.buildings.entries) {
      final building = registry.buildingById(buildingEntry.key);
      if (building == null) continue;

      final buildingState = buildingEntry.value;
      final count = buildingState.count;
      final efficiencyMultiplier = buildingState.efficiency / 100.0;

      // Calculate production for each resource this building produces
      for (final prodEntry in building.production.entries) {
        final resourceId = prodEntry.key;
        final baseAmount = prodEntry.value;

        // Production is scaled by:
        // - Building count
        // - Building efficiency
        // - Education bonus
        final amount =
            (baseAmount *
                    count *
                    efficiencyMultiplier *
                    stats.educationProductionMultiplier)
                .floor();

        production[resourceId] = (production[resourceId] ?? 0) + amount;
      }
    }
  }

  return production;
}

/// Processes a single Township update (called hourly).
///
/// Returns the updated state along with GP produced and XP gained.
TownshipUpdateResult processTownUpdate(
  TownshipState state,
  TownshipRegistry registry,
  Random random,
) {
  // 1. Calculate current stats before degradation
  final stats = TownshipStats.calculate(state, registry);

  // 2. Apply building degradation
  final newBiomes = <MelvorId, BiomeState>{};
  for (final entry in state.biomes.entries) {
    newBiomes[entry.key] = _degradeBuildings(entry.value, registry, random);
  }

  // 3. Calculate resource production
  final production = _calculateProduction(state, registry, stats);

  // 4. Add produced resources to storage (except GP which goes to player)
  final newResources = Map<MelvorId, int>.from(state.resources);
  var gpProduced = 0;
  var totalStoredResources = newResources.values.fold<int>(0, (a, b) => a + b);

  for (final entry in production.entries) {
    final resource = registry.resourceById(entry.key);
    final amount = entry.value;

    if (resource?.depositsToBank ?? false) {
      // GP goes directly to player
      gpProduced += amount;
    } else {
      // Other resources go to township storage (up to capacity)
      final spaceAvailable = stats.storage - totalStoredResources;
      final amountToAdd = amount.clamp(0, spaceAvailable);
      if (amountToAdd > 0) {
        newResources[entry.key] = (newResources[entry.key] ?? 0) + amountToAdd;
        totalStoredResources += amountToAdd;
      }
    }
  }

  // 5. Calculate XP gained (1 XP per effective citizen, modified by happiness)
  final xpGained = stats.effectivePopulation * stats.happinessXpMultiplier;

  // 6. Create updated state
  final newState = state.copyWith(
    biomes: newBiomes,
    resources: newResources,
    worship: stats.worship.clamp(0, 2000),
  );

  return TownshipUpdateResult(
    state: newState,
    gpProduced: gpProduced,
    xpGained: xpGained,
  );
}
