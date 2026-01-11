import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// Costs and provides for a building in a specific biome.
@immutable
class BuildingBiomeData {
  const BuildingBiomeData({
    required this.biomeId,
    required this.costs,
    required this.population,
    required this.happiness,
    required this.education,
    required this.storage,
    required this.production,
  });

  factory BuildingBiomeData.fromJson(
    Map<String, dynamic> costJson,
    Map<String, dynamic> providesJson, {
    required String namespace,
  }) {
    final biomeId = MelvorId.fromJsonWithNamespace(
      costJson['biomeID'] as String,
      defaultNamespace: namespace,
    );

    // Parse costs
    final costsJson = costJson['cost'] as List<dynamic>? ?? [];
    final costs = <MelvorId, int>{};
    for (final cost in costsJson) {
      final costMap = cost as Map<String, dynamic>;
      final resourceId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = (costMap['quantity'] as num).toInt();
      costs[resourceId] = quantity;
    }

    // Parse provides
    final resourcesJson = providesJson['resources'] as List<dynamic>? ?? [];
    final production = <MelvorId, double>{};
    for (final resource in resourcesJson) {
      final resourceMap = resource as Map<String, dynamic>;
      final resourceId = MelvorId.fromJsonWithNamespace(
        resourceMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = (resourceMap['quantity'] as num).toDouble();
      production[resourceId] = quantity;
    }

    return BuildingBiomeData(
      biomeId: biomeId,
      costs: costs,
      population: providesJson['population'] as int? ?? 0,
      happiness: (providesJson['happiness'] as num?)?.toDouble() ?? 0,
      education: (providesJson['education'] as num?)?.toDouble() ?? 0,
      storage: providesJson['storage'] as int? ?? 0,
      production: production,
    );
  }

  final MelvorId biomeId;

  /// Resource costs (resourceId -> amount). Includes GP.
  final Map<MelvorId, int> costs;

  /// Population provided by this building in this biome.
  final int population;

  /// Happiness provided by this building in this biome.
  final double happiness;

  /// Education provided by this building in this biome.
  final double education;

  /// Storage provided by this building in this biome.
  final int storage;

  /// Resources produced per town update (resourceId -> amount per tick).
  final Map<MelvorId, double> production;
}

/// A Township building definition.
@immutable
class TownshipBuilding {
  const TownshipBuilding({
    required this.id,
    required this.name,
    required this.tier,
    required this.biomeData,
    required this.validBiomes,
    this.media,
    this.maxUpgrades = 0,
    this.upgradesFrom,
    this.canDegrade = true,
  });

  factory TownshipBuilding.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final id = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse biome list
    final biomesJson = json['biomes'] as List<dynamic>? ?? [];
    final validBiomes = <MelvorId>{};
    for (final biome in biomesJson) {
      validBiomes.add(
        MelvorId.fromJsonWithNamespace(
          biome as String,
          defaultNamespace: namespace,
        ),
      );
    }

    // Parse costs and provides (paired by biomeID)
    final costsJson = json['cost'] as List<dynamic>? ?? [];
    final providesJson = json['provides'] as List<dynamic>? ?? [];

    // Build a map of biomeID -> provides data
    final providesMap = <String, Map<String, dynamic>>{};
    for (final provides in providesJson) {
      final providesData = provides as Map<String, dynamic>;
      final biomeId = providesData['biomeID'] as String;
      providesMap[biomeId] = providesData;
    }

    // Parse biome data
    final biomeData = <MelvorId, BuildingBiomeData>{};
    for (final cost in costsJson) {
      final costMap = cost as Map<String, dynamic>;
      final biomeIdStr = costMap['biomeID'] as String;
      final providesData = providesMap[biomeIdStr] ?? {};

      final data = BuildingBiomeData.fromJson(
        costMap,
        providesData,
        namespace: namespace,
      );
      biomeData[data.biomeId] = data;
    }

    // Parse media path, stripping query params (e.g., "?2").
    final media = (json['media'] as String?)?.split('?').first;

    return TownshipBuilding(
      id: id,
      name: json['name'] as String,
      tier: json['tier'] as int? ?? 1,
      biomeData: biomeData,
      validBiomes: validBiomes,
      media: media,
      maxUpgrades: json['maxUpgrades'] as int? ?? 0,
      upgradesFrom: json['upgradesFrom'] != null
          ? MelvorId.fromJsonWithNamespace(
              json['upgradesFrom'] as String,
              defaultNamespace: namespace,
            )
          : null,
      canDegrade: json['canDegrade'] as bool? ?? true,
    );
  }

  final MelvorId id;
  final String name;

  /// Building tier (1-4), determines unlock requirements.
  final int tier;

  /// Biome-specific costs and provides.
  final Map<MelvorId, BuildingBiomeData> biomeData;

  /// Biomes where this building can be built.
  final Set<MelvorId> validBiomes;

  /// The asset path for this building's icon.
  final String? media;

  /// Maximum number of this building that can be built.
  final int maxUpgrades;

  /// The building this upgrades from, if any.
  final MelvorId? upgradesFrom;

  /// Whether this building degrades over time.
  final bool canDegrade;

  /// Returns true if this building can be built in the given biome.
  bool canBuildInBiome(MelvorId biomeId) => validBiomes.contains(biomeId);

  /// Returns the biome data for the given biome, or null if not found.
  BuildingBiomeData? dataForBiome(MelvorId biomeId) => biomeData[biomeId];
}

/// A Township biome definition.
@immutable
class TownshipBiome {
  const TownshipBiome({
    required this.id,
    required this.name,
    required this.tier,
  });

  factory TownshipBiome.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return TownshipBiome(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      tier: json['tier'] as int? ?? 1,
    );
  }

  final MelvorId id;
  final String name;

  /// Biome tier (1-3). Tier 1 biomes are available immediately.
  /// Higher tiers require more population.
  final int tier;

  /// Returns the population required to unlock this biome.
  /// Tier 1: 0, Tier 2: 100, Tier 3: 500 (approximate values).
  int get populationRequired {
    switch (tier) {
      case 1:
        return 0;
      case 2:
        return 100;
      case 3:
        return 500;
      default:
        return 0;
    }
  }
}

/// A Township resource definition.
@immutable
class TownshipResource {
  const TownshipResource({
    required this.id,
    required this.name,
    required this.type,
    this.media,
    this.startingAmount = 0,
  });

  factory TownshipResource.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Parse media path, stripping query params (e.g., "?2").
    final media = (json['media'] as String?)?.split('?').first;

    return TownshipResource(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      type: json['type'] as String? ?? 'Raw',
      media: media,
      startingAmount: json['startingAmount'] as int? ?? 0,
    );
  }

  final MelvorId id;
  final String name;

  /// Resource type (e.g., 'Currency', 'Raw').
  final String type;

  /// The asset path for this resource's icon.
  final String? media;

  /// Starting amount when Township is unlocked.
  final int startingAmount;

  /// If true, this resource (like GP) deposits directly to player bank.
  bool get depositsToBank => type == 'Currency';
}

/// A Township deity for worship.
@immutable
class TownshipDeity {
  const TownshipDeity({
    required this.id,
    required this.name,
    this.isHidden = false,
    this.statueName = '',
  });

  factory TownshipDeity.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return TownshipDeity(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      isHidden: json['isHidden'] as bool? ?? false,
      statueName: json['statueName'] as String? ?? '',
    );
  }

  final MelvorId id;
  final String name;

  /// Whether this deity is hidden from the UI.
  final bool isHidden;

  /// Name of the statue for this deity.
  final String statueName;

  /// Returns the total bonus for a modifier at the given worship percentage.
  // TODO(eseidel): Parse and implement actual checkpoint bonuses.
  double bonusAtWorshipPercent(String modifierName, double worshipPercent) {
    // Worship bonuses are not yet parsed from the JSON data.
    // The checkpoint system has thresholds at 5%, 25%, 50%, 85%, 95%.
    return 0;
  }
}

/// A Township trade (resource to item conversion).
@immutable
class TownshipTrade {
  const TownshipTrade({
    required this.id,
    required this.resourceId,
    required this.itemId,
    this.itemQuantity = 1,
    this.costs = const {},
  });

  final MelvorId id;

  /// Resource that is traded (spent).
  final MelvorId resourceId;

  /// Item that is received.
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

/// A Township season definition.
@immutable
class TownshipSeason {
  const TownshipSeason({
    required this.id,
    required this.name,
    required this.seasonLength,
    required this.order,
  });

  factory TownshipSeason.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return TownshipSeason(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      seasonLength: json['seasonLength'] as int? ?? 72,
      order: json['order'] as int? ?? 0,
    );
  }

  final MelvorId id;
  final String name;

  /// Season length in hours.
  final int seasonLength;

  /// Display order.
  final int order;
}

/// A requirement for a Township task.
@immutable
class TaskRequirement {
  const TaskRequirement({
    required this.type,
    required this.target,
    this.targetId,
  });

  /// Type of requirement (e.g., 'buildBuilding', 'population').
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

/// Registry containing all Township data.
@immutable
class TownshipRegistry {
  const TownshipRegistry({
    this.buildings = const [],
    this.biomes = const [],
    this.resources = const [],
    this.deities = const [],
    this.trades = const [],
    this.seasons = const [],
    this.tasks = const [],
  });

  const TownshipRegistry.empty() : this();

  final List<TownshipBuilding> buildings;
  final List<TownshipBiome> biomes;
  final List<TownshipResource> resources;
  final List<TownshipDeity> deities;
  final List<TownshipTrade> trades;
  final List<TownshipSeason> seasons;
  final List<TownshipTask> tasks;

  // ---------------------------------------------------------------------------
  // Building lookups
  // ---------------------------------------------------------------------------

  /// Converts building tier to required Township level.
  static int tierToLevel(int tier) {
    switch (tier) {
      case 1:
        return 1;
      case 2:
        return 15;
      case 3:
        return 35;
      case 4:
        return 60;
      case 5:
        return 80;
      case 6:
        return 100;
      default:
        throw UnimplementedError('Unknown building tier: $tier');
    }
  }

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

  /// Returns all visible deities.
  List<TownshipDeity> get visibleDeities {
    return deities.where((d) => !d.isHidden).toList();
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

  /// Returns a trade by item ID, or null if not found.
  TownshipTrade? tradeByItemId(MelvorId itemId) {
    for (final trade in trades) {
      if (trade.itemId == itemId) return trade;
    }
    return null;
  }

  /// Returns all trades for a resource.
  List<TownshipTrade> tradesForResource(MelvorId resourceId) {
    return trades.where((t) => t.resourceId == resourceId).toList();
  }

  // ---------------------------------------------------------------------------
  // Season lookups
  // ---------------------------------------------------------------------------

  /// Returns a season by ID, or null if not found.
  TownshipSeason? seasonById(MelvorId id) {
    for (final season in seasons) {
      if (season.id == id) return season;
    }
    return null;
  }

  /// Returns seasons in order.
  List<TownshipSeason> get orderedSeasons {
    return List<TownshipSeason>.from(seasons)
      ..sort((a, b) => a.order.compareTo(b.order));
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
