import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A Township building definition.
@immutable
class TownshipBuilding {
  const TownshipBuilding({
    required this.id,
    required this.name,
    required this.levelRequired,
    required this.populationRequired,
    required this.costs,
    required this.gpCost,
    this.production = const {},
    this.populationBonus = 0,
    this.happinessBonus = 0,
    this.educationBonus = 0,
    this.healthBonus = 0,
    this.storageBonus = 0,
    this.worshipBonus = 0,
    this.validBiomes = const {},
    this.degradable = true,
  });

  final MelvorId id;
  final String name;

  /// Township level required to build.
  final int levelRequired;

  /// Population required to build.
  final int populationRequired;

  /// Resource costs (resourceId -> amount).
  final Map<MelvorId, int> costs;

  /// GP cost to build.
  final int gpCost;

  /// Resources produced per town update (resourceId -> amount).
  final Map<MelvorId, int> production;

  /// Population bonus per building.
  final int populationBonus;

  /// Happiness bonus per building (percentage points).
  final double happinessBonus;

  /// Education bonus per building (percentage points).
  final double educationBonus;

  /// Health bonus per building (percentage points).
  final double healthBonus;

  /// Storage capacity bonus per building.
  final int storageBonus;

  /// Worship points bonus per building.
  final int worshipBonus;

  /// Biomes where this building can be built.
  final Set<MelvorId> validBiomes;

  /// Whether this building degrades over time.
  /// Storage buildings typically don't degrade.
  final bool degradable;

  /// Returns true if this building can be built in the given biome.
  bool canBuildInBiome(MelvorId biomeId) => validBiomes.contains(biomeId);
}

/// A Township biome definition.
@immutable
class TownshipBiome {
  const TownshipBiome({
    required this.id,
    required this.name,
    this.populationRequired = 0,
    this.bonuses = const {},
  });

  final MelvorId id;
  final String name;

  /// Population required to unlock this biome.
  final int populationRequired;

  /// Modifier bonuses for this biome (modifier name -> value).
  final Map<String, double> bonuses;
}

/// A Township resource definition.
@immutable
class TownshipResource {
  const TownshipResource({
    required this.id,
    required this.name,
    this.depositsToBank = false,
  });

  final MelvorId id;
  final String name;

  /// If true, this resource (like GP) deposits directly to player bank.
  final bool depositsToBank;
}

/// A Township deity for worship.
@immutable
class TownshipDeity {
  const TownshipDeity({
    required this.id,
    required this.name,
    this.bonuses = const {},
    this.seasonBonuses = const {},
  });

  final MelvorId id;
  final String name;

  /// Worship bonuses at different thresholds.
  /// Map of threshold percentage (5, 25, 50, 85, 95) to modifiers.
  final Map<int, Map<String, double>> bonuses;

  /// Season-specific bonuses (season name -> modifiers).
  final Map<String, Map<String, double>> seasonBonuses;

  /// Returns the total bonus for a modifier at the given worship percentage.
  double bonusAtWorshipPercent(String modifierName, double worshipPercent) {
    var total = 0.0;
    for (final entry in bonuses.entries) {
      if (worshipPercent >= entry.key) {
        total += entry.value[modifierName] ?? 0;
      }
    }
    return total;
  }
}

/// A Township trade (resource to item conversion).
@immutable
class TownshipTrade {
  const TownshipTrade({
    required this.id,
    required this.itemId,
    required this.costs,
    this.itemQuantity = 1,
  });

  final MelvorId id;

  /// The item received from the trade.
  final MelvorId itemId;

  /// Quantity of items received.
  final int itemQuantity;

  /// Township resource costs (resourceId -> amount).
  final Map<MelvorId, int> costs;

  /// Returns costs after Trading Post discount.
  /// Each Trading Post provides 0.33% discount, max 49.5%.
  Map<MelvorId, int> costsWithDiscount(int tradingPostCount) {
    final discount = (tradingPostCount * 0.0033).clamp(0.0, 0.495);
    return costs.map(
      (key, value) => MapEntry(key, (value * (1 - discount)).ceil()),
    );
  }
}

/// A Township task definition.
@immutable
class TownshipTask {
  const TownshipTask({
    required this.id,
    required this.name,
    this.description = '',
    this.requirements = const [],
    this.rewards = const [],
    this.isMainTask = false,
  });

  final MelvorId id;
  final String name;
  final String description;

  /// Requirements to complete this task.
  final List<TaskRequirement> requirements;

  /// Rewards for completing this task.
  final List<TaskReward> rewards;

  /// True for main (one-time) tasks, false for casual tasks.
  final bool isMainTask;
}

/// A requirement for a Township task.
@immutable
class TaskRequirement {
  const TaskRequirement({
    required this.type,
    required this.target,
    this.targetId,
  });

  /// Type of requirement (e.g., 'buildBuilding', 'reachPopulation').
  final String type;

  /// Target value to reach.
  final int target;

  /// Optional target ID (e.g., building ID for 'buildBuilding').
  final MelvorId? targetId;
}

/// A reward for completing a Township task.
@immutable
class TaskReward {
  const TaskReward({required this.type, required this.amount, this.itemId});

  /// Type of reward (e.g., 'xp', 'gp', 'item').
  final String type;

  /// Amount of reward.
  final int amount;

  /// Optional item ID for item rewards.
  final MelvorId? itemId;
}

/// Registry containing all Township data.
@immutable
class TownshipRegistry {
  const TownshipRegistry({
    this.buildings = const [],
    this.biomes = const [],
    this.resources = const [],
    this.deities = const [],
    this.trades = const [],
    this.tasks = const [],
  });

  const TownshipRegistry.empty() : this();

  final List<TownshipBuilding> buildings;
  final List<TownshipBiome> biomes;
  final List<TownshipResource> resources;
  final List<TownshipDeity> deities;
  final List<TownshipTrade> trades;
  final List<TownshipTask> tasks;

  // ---------------------------------------------------------------------------
  // Building lookups
  // ---------------------------------------------------------------------------

  /// Returns a building by ID, or null if not found.
  TownshipBuilding? buildingById(MelvorId id) {
    for (final building in buildings) {
      if (building.id == id) return building;
    }
    return null;
  }

  /// Returns all buildings that can be built in a biome.
  List<TownshipBuilding> buildingsForBiome(MelvorId biomeId) {
    return buildings.where((b) => b.canBuildInBiome(biomeId)).toList();
  }

  // ---------------------------------------------------------------------------
  // Biome lookups
  // ---------------------------------------------------------------------------

  /// Returns a biome by ID, or null if not found.
  TownshipBiome? biomeById(MelvorId id) {
    for (final biome in biomes) {
      if (biome.id == id) return biome;
    }
    return null;
  }

  /// Returns biomes available at the given population.
  List<TownshipBiome> biomesAtPopulation(int population) {
    return biomes.where((b) => b.populationRequired <= population).toList();
  }

  // ---------------------------------------------------------------------------
  // Resource lookups
  // ---------------------------------------------------------------------------

  /// Returns a resource by ID, or null if not found.
  TownshipResource? resourceById(MelvorId id) {
    for (final resource in resources) {
      if (resource.id == id) return resource;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Deity lookups
  // ---------------------------------------------------------------------------

  /// Returns a deity by ID, or null if not found.
  TownshipDeity? deityById(MelvorId id) {
    for (final deity in deities) {
      if (deity.id == id) return deity;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Trade lookups
  // ---------------------------------------------------------------------------

  /// Returns a trade by ID, or null if not found.
  TownshipTrade? tradeById(MelvorId id) {
    for (final trade in trades) {
      if (trade.id == id) return trade;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Task lookups
  // ---------------------------------------------------------------------------

  /// Returns a task by ID, or null if not found.
  TownshipTask? taskById(MelvorId id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// Returns all main (one-time) tasks.
  List<TownshipTask> get mainTasks {
    return tasks.where((t) => t.isMainTask).toList();
  }

  /// Returns all casual tasks.
  List<TownshipTask> get casualTasks {
    return tasks.where((t) => !t.isMainTask).toList();
  }
}
