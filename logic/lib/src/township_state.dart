import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/township_update.dart';
import 'package:meta/meta.dart';

/// The four seasons in Township, rotating every 3 days.
enum Season {
  spring,
  summer,
  fall,
  winter;

  factory Season.fromJson(String value) {
    return Season.values.firstWhere((e) => e.name == value);
  }

  String toJson() => name;

  /// Returns the next season in the cycle.
  Season get next {
    return Season.values[(index + 1) % Season.values.length];
  }

  /// Season modifiers for happiness (percentage points).
  double get happinessModifier {
    return switch (this) {
      Season.spring => 50,
      Season.summer => 0,
      Season.fall => 0,
      Season.winter => -50,
    };
  }

  /// Season modifiers for education (percentage points).
  double get educationModifier {
    return switch (this) {
      Season.spring => 50,
      Season.summer => 0,
      Season.fall => 0,
      Season.winter => 0,
    };
  }
}

/// Ticks per hour (3600 seconds * 10 ticks/second).
const int ticksPerHour = 36000;

/// Ticks per season cycle (3 days).
const int ticksPerSeasonCycle = ticksPerHour * 24 * 3;

/// State for a single building type in a biome.
@immutable
class BuildingState {
  const BuildingState({required this.count, this.efficiency = 100.0});

  const BuildingState.empty() : this(count: 0);

  factory BuildingState.fromJson(Map<String, dynamic> json) {
    return BuildingState(
      count: json['count'] as int,
      efficiency: (json['efficiency'] as num?)?.toDouble() ?? 100.0,
    );
  }

  /// Number of this building type built.
  final int count;

  /// Building efficiency (20-100%), degrades over time.
  final double efficiency;

  BuildingState copyWith({int? count, double? efficiency}) {
    return BuildingState(
      count: count ?? this.count,
      efficiency: efficiency ?? this.efficiency,
    );
  }

  Map<String, dynamic> toJson() {
    return {'count': count, if (efficiency != 100.0) 'efficiency': efficiency};
  }
}

/// State for a single biome containing buildings.
@immutable
class BiomeState {
  const BiomeState({this.buildings = const {}});

  const BiomeState.empty() : this();

  factory BiomeState.fromJson(Map<String, dynamic> json) {
    final buildingsJson = json['buildings'] as Map<String, dynamic>? ?? {};
    final buildings = <MelvorId, BuildingState>{};
    for (final entry in buildingsJson.entries) {
      buildings[MelvorId.fromJson(entry.key)] = BuildingState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return BiomeState(buildings: buildings);
  }

  /// Buildings in this biome (buildingId -> state).
  final Map<MelvorId, BuildingState> buildings;

  /// Returns the state for a specific building, or empty if not built.
  BuildingState buildingState(MelvorId buildingId) {
    return buildings[buildingId] ?? const BuildingState.empty();
  }

  /// Returns the total count of a specific building type.
  int buildingCount(MelvorId buildingId) {
    return buildings[buildingId]?.count ?? 0;
  }

  BiomeState copyWith({Map<MelvorId, BuildingState>? buildings}) {
    return BiomeState(buildings: buildings ?? this.buildings);
  }

  /// Returns a copy with the building state updated.
  BiomeState withBuildingState(MelvorId buildingId, BuildingState state) {
    final newBuildings = Map<MelvorId, BuildingState>.from(buildings);
    if (state.count > 0) {
      newBuildings[buildingId] = state;
    } else {
      newBuildings.remove(buildingId);
    }
    return BiomeState(buildings: newBuildings);
  }

  Map<String, dynamic> toJson() {
    return {
      if (buildings.isNotEmpty)
        'buildings': buildings.map(
          (key, value) => MapEntry(key.toJson(), value.toJson()),
        ),
    };
  }
}

/// State for a Township task (main or casual).
@immutable
class TownshipTaskState {
  const TownshipTaskState({
    required this.taskId,
    this.progress = const {},
    this.completed = false,
  });

  factory TownshipTaskState.fromJson(Map<String, dynamic> json) {
    final progressJson = json['progress'] as Map<String, dynamic>? ?? {};
    final progress = progressJson.map(
      (key, value) => MapEntry(key, value as int),
    );
    return TownshipTaskState(
      taskId: MelvorId.fromJson(json['taskId'] as String),
      progress: progress,
      completed: json['completed'] as bool? ?? false,
    );
  }

  final MelvorId taskId;

  /// Progress toward task requirements (requirement type -> current value).
  final Map<String, int> progress;

  /// Whether the task has been completed.
  final bool completed;

  TownshipTaskState copyWith({
    MelvorId? taskId,
    Map<String, int>? progress,
    bool? completed,
  }) {
    return TownshipTaskState(
      taskId: taskId ?? this.taskId,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId.toJson(),
      if (progress.isNotEmpty) 'progress': progress,
      if (completed) 'completed': completed,
    };
  }
}

/// Complete Township state.
@immutable
class TownshipState {
  const TownshipState({
    required this.registry,
    this.biomes = const {},
    this.resources = const {},
    this.worshipId,
    this.worship = 0,
    this.season = Season.spring,
    this.seasonTicksRemaining = ticksPerSeasonCycle,
    this.ticksUntilUpdate = ticksPerHour,
    this.tasks = const {},
    this.completedMainTasks = const {},
  });

  const TownshipState.empty() : this(registry: const TownshipRegistry.empty());

  /// Creates a new TownshipState with resources initialized to their starting
  /// amounts from the registry.
  factory TownshipState.initial(TownshipRegistry registry) {
    final resources = <MelvorId, int>{};
    for (final resource in registry.resources) {
      if (resource.startingAmount > 0) {
        resources[resource.id] = resource.startingAmount;
      }
    }
    return TownshipState(registry: registry, resources: resources);
  }

  factory TownshipState.fromJson(
    TownshipRegistry registry,
    Map<String, dynamic> json,
  ) {
    // Parse biomes
    final biomesJson = json['biomes'] as Map<String, dynamic>? ?? {};
    final biomes = <MelvorId, BiomeState>{};
    for (final entry in biomesJson.entries) {
      biomes[MelvorId.fromJson(entry.key)] = BiomeState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    // Parse resources
    final resourcesJson = json['resources'] as Map<String, dynamic>? ?? {};
    final resources = <MelvorId, int>{};
    for (final entry in resourcesJson.entries) {
      resources[MelvorId.fromJson(entry.key)] = entry.value as int;
    }

    // Parse tasks
    final tasksJson = json['tasks'] as Map<String, dynamic>? ?? {};
    final tasks = <MelvorId, TownshipTaskState>{};
    for (final entry in tasksJson.entries) {
      tasks[MelvorId.fromJson(entry.key)] = TownshipTaskState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    // Parse completed main tasks
    final completedJson = json['completedMainTasks'] as List<dynamic>? ?? [];
    final completedMainTasks = completedJson
        .map((e) => MelvorId.fromJson(e as String))
        .toSet();

    return TownshipState(
      registry: registry,
      biomes: biomes,
      resources: resources,
      worshipId: json['worshipId'] != null
          ? MelvorId.fromJson(json['worshipId'] as String)
          : null,
      worship: json['worship'] as int? ?? 0,
      season: json['season'] != null
          ? Season.fromJson(json['season'] as String)
          : Season.spring,
      seasonTicksRemaining:
          json['seasonTicksRemaining'] as int? ?? ticksPerSeasonCycle,
      ticksUntilUpdate: json['ticksUntilUpdate'] as int? ?? ticksPerHour,
      tasks: tasks,
      completedMainTasks: completedMainTasks,
    );
  }

  static TownshipState? maybeFromJson(TownshipRegistry registry, dynamic json) {
    if (json == null) return null;
    return TownshipState.fromJson(registry, json as Map<String, dynamic>);
  }

  /// The township registry containing all static data.
  final TownshipRegistry registry;

  /// Biome states (biomeId -> biome state).
  final Map<MelvorId, BiomeState> biomes;

  /// Township resources (resourceId -> amount).
  /// Note: GP is not stored here, it goes directly to player currencies.
  final Map<MelvorId, int> resources;

  /// Selected deity for worship (null if none selected).
  final MelvorId? worshipId;

  /// Current worship points (0-2000).
  final int worship;

  /// Current season.
  final Season season;

  /// Ticks remaining until the season changes.
  final Tick seasonTicksRemaining;

  /// Ticks remaining until the next town update.
  final Tick ticksUntilUpdate;

  /// Active casual tasks (taskId -> task state).
  final Map<MelvorId, TownshipTaskState> tasks;

  /// Set of completed main task IDs.
  final Set<MelvorId> completedMainTasks;

  /// Base storage capacity.
  static const int baseStorage = 50000;

  // ---------------------------------------------------------------------------
  // Computed Properties
  // ---------------------------------------------------------------------------

  /// Returns the state for a specific biome, or empty if not unlocked.
  BiomeState biomeState(MelvorId biomeId) {
    return biomes[biomeId] ?? const BiomeState.empty();
  }

  /// Returns the state for a specific building in a biome.
  BuildingState buildingState(MelvorId biomeId, MelvorId buildingId) {
    return biomeState(biomeId).buildingState(buildingId);
  }

  /// Returns true if a building in a biome needs repair (efficiency < 100).
  bool buildingNeedsRepair(MelvorId biomeId, MelvorId buildingId) {
    final state = buildingState(biomeId, buildingId);
    return state.count > 0 && state.efficiency < 100;
  }

  /// Returns the total count of a building across all biomes.
  int totalBuildingCount(MelvorId buildingId) {
    var count = 0;
    for (final biome in biomes.values) {
      count += biome.buildingCount(buildingId);
    }
    return count;
  }

  /// Returns the amount of a specific resource.
  int resourceAmount(MelvorId resourceId) {
    return resources[resourceId] ?? 0;
  }

  /// Returns the number of completed main tasks.
  int get completedMainTaskCount => completedMainTasks.length;

  /// Returns the current township stats.
  TownshipStats get stats => TownshipStats.calculate(this, registry);

  /// Returns true if a biome is unlocked based on current population.
  bool isBiomeUnlocked(TownshipBiome biome) {
    return stats.population >= biome.populationRequired;
  }

  /// Returns the selected deity for worship, or null if none selected.
  TownshipDeity? get selectedDeity {
    final id = worshipId;
    if (id == null) return null;
    return registry.deityById(id);
  }

  /// Returns the total resources stored in the township (excluding bank items).
  int get totalResourcesStored {
    var total = 0;
    for (final resource in registry.resources) {
      if (!resource.depositsToBank) {
        total += resourceAmount(resource.id);
      }
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Task Methods
  // ---------------------------------------------------------------------------

  /// Checks if a task requirement is met.
  /// [townshipLevel] is the player's Township skill level, needed for
  /// 'townshipLevel' requirement type.
  bool isTaskRequirementMet(TaskRequirement req, {required int townshipLevel}) {
    return switch (req.type) {
      'population' => stats.population >= req.target,
      'buildBuilding' =>
        req.targetId != null && totalBuildingCount(req.targetId!) >= req.target,
      'townshipLevel' => townshipLevel >= req.target,
      'resource' =>
        req.targetId != null && resourceAmount(req.targetId!) >= req.target,
      _ => false, // Unknown requirement type
    };
  }

  /// Checks if all requirements for a task are met.
  /// [townshipLevel] is the player's Township skill level.
  bool isTaskComplete(MelvorId taskId, {required int townshipLevel}) {
    final task = registry.taskById(taskId);
    if (task == null) return false;

    // Check if already completed (for main tasks)
    if (task.isMainTask && completedMainTasks.contains(taskId)) {
      return false; // Already claimed
    }

    return task.requirements.every(
      (req) => isTaskRequirementMet(req, townshipLevel: townshipLevel),
    );
  }

  // ---------------------------------------------------------------------------
  // Worship Methods
  // ---------------------------------------------------------------------------

  /// Selects a deity for worship.
  /// Resets worship points if changing to a different deity.
  TownshipState selectWorship(MelvorId deityId) {
    final deity = registry.deityById(deityId);
    if (deity == null) throw StateError('Unknown deity: $deityId');

    // Reset worship points if changing deity
    final resetPoints = worshipId != null && worshipId != deityId;

    return copyWith(worshipId: deityId, worship: resetPoints ? 0 : worship);
  }

  /// Gets the current worship bonus for a modifier.
  /// Returns 0 if no deity is selected.
  double getWorshipBonus(String modifierName) {
    final deityId = worshipId;
    if (deityId == null) return 0;

    final deity = registry.deityById(deityId);
    if (deity == null) return 0;

    // Calculate worship percentage (0-100 based on 0-2000 points)
    final worshipPercent = (worship / 20).clamp(0.0, 100.0);

    return deity.bonusAtWorshipPercent(modifierName, worshipPercent);
  }

  // ---------------------------------------------------------------------------
  // Repair Methods
  // ---------------------------------------------------------------------------

  /// Calculates the repair costs for a Township building.
  /// Returns a map of resourceId -> cost.
  /// Formula: (Base Cost / 3) × Buildings Built × (1 - Efficiency%)
  /// Minimum cost is 1 per resource.
  Map<MelvorId, int> repairCosts(MelvorId biomeId, MelvorId buildingId) {
    final building = registry.buildingById(buildingId);
    if (building == null) return {};

    final biomeData = building.dataForBiome(biomeId);
    if (biomeData == null) return {};

    final bState = buildingState(biomeId, buildingId);

    if (bState.count == 0 || bState.efficiency >= 100) {
      return {};
    }

    final damagePercent = (100 - bState.efficiency) / 100;
    final costs = <MelvorId, int>{};

    for (final entry in biomeData.costs.entries) {
      // Repair cost = (base cost / 3) × buildings built × damage%
      final repairCost = (entry.value / 3 * bState.count * damagePercent)
          .ceil();
      // Minimum cost is 1
      costs[entry.key] = repairCost < 1 ? 1 : repairCost;
    }

    return costs;
  }

  // ---------------------------------------------------------------------------
  // State Updates
  // ---------------------------------------------------------------------------

  TownshipState copyWith({
    Map<MelvorId, BiomeState>? biomes,
    Map<MelvorId, int>? resources,
    MelvorId? worshipId,
    int? worship,
    Season? season,
    Tick? seasonTicksRemaining,
    Tick? ticksUntilUpdate,
    Map<MelvorId, TownshipTaskState>? tasks,
    Set<MelvorId>? completedMainTasks,
  }) {
    return TownshipState(
      registry: registry,
      biomes: biomes ?? this.biomes,
      resources: resources ?? this.resources,
      worshipId: worshipId ?? this.worshipId,
      worship: worship ?? this.worship,
      season: season ?? this.season,
      seasonTicksRemaining: seasonTicksRemaining ?? this.seasonTicksRemaining,
      ticksUntilUpdate: ticksUntilUpdate ?? this.ticksUntilUpdate,
      tasks: tasks ?? this.tasks,
      completedMainTasks: completedMainTasks ?? this.completedMainTasks,
    );
  }

  /// Returns a copy with the biome state updated.
  TownshipState withBiomeState(MelvorId biomeId, BiomeState state) {
    final newBiomes = Map<MelvorId, BiomeState>.from(biomes);
    newBiomes[biomeId] = state;
    return copyWith(biomes: newBiomes);
  }

  /// Returns a copy with resources added.
  TownshipState addResource(MelvorId resourceId, int amount) {
    final newResources = Map<MelvorId, int>.from(resources);
    newResources[resourceId] = (newResources[resourceId] ?? 0) + amount;
    return copyWith(resources: newResources);
  }

  /// Returns a copy with resources removed.
  /// Throws if insufficient resources.
  TownshipState removeResource(MelvorId resourceId, int amount) {
    final current = resources[resourceId] ?? 0;
    if (current < amount) {
      throw StateError('Insufficient $resourceId: have $current, need $amount');
    }
    final newResources = Map<MelvorId, int>.from(resources);
    final newAmount = current - amount;
    if (newAmount > 0) {
      newResources[resourceId] = newAmount;
    } else {
      newResources.remove(resourceId);
    }
    return copyWith(resources: newResources);
  }

  /// Advances to the next season.
  TownshipState advanceSeason() {
    return copyWith(
      season: season.next,
      seasonTicksRemaining: ticksPerSeasonCycle,
    );
  }

  /// Clears worship selection and resets points.
  TownshipState clearWorship() {
    return TownshipState(
      registry: registry,
      biomes: biomes,
      resources: resources,
      season: season,
      seasonTicksRemaining: seasonTicksRemaining,
      ticksUntilUpdate: ticksUntilUpdate,
      tasks: tasks,
      completedMainTasks: completedMainTasks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (biomes.isNotEmpty)
        'biomes': biomes.map(
          (key, value) => MapEntry(key.toJson(), value.toJson()),
        ),
      if (resources.isNotEmpty)
        'resources': resources.map(
          (key, value) => MapEntry(key.toJson(), value),
        ),
      if (worshipId != null) 'worshipId': worshipId!.toJson(),
      if (worship != 0) 'worship': worship,
      if (season != Season.spring) 'season': season.toJson(),
      if (seasonTicksRemaining != ticksPerSeasonCycle)
        'seasonTicksRemaining': seasonTicksRemaining,
      if (ticksUntilUpdate != ticksPerHour)
        'ticksUntilUpdate': ticksUntilUpdate,
      if (tasks.isNotEmpty)
        'tasks': tasks.map(
          (key, value) => MapEntry(key.toJson(), value.toJson()),
        ),
      if (completedMainTasks.isNotEmpty)
        'completedMainTasks': completedMainTasks
            .map((e) => e.toJson())
            .toList(),
    };
  }
}
