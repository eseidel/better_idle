import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/time_away.dart';
import 'package:meta/meta.dart';

export 'package:logic/src/data/display_order.dart';

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

/// A biome-specific production modifier (e.g., +25% production in Mountains).
@immutable
class BiomeProductionModifier {
  const BiomeProductionModifier({required this.biomeId, required this.value});

  factory BiomeProductionModifier.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return BiomeProductionModifier(
      biomeId: MelvorId.fromJsonWithNamespace(
        json['categoryID'] as String,
        defaultNamespace: namespace,
      ),
      value: (json['value'] as num).toDouble(),
    );
  }

  /// The biome this modifier applies to.
  final MelvorId biomeId;

  /// The percentage modifier value (e.g., 25 for +25%, -50 for -50%).
  final double value;
}

/// Modifiers for a deity (base or checkpoint).
@immutable
class DeityModifiers {
  const DeityModifiers({
    this.buildingProduction = const [],
    this.buildingCost = 0,
  });

  factory DeityModifiers.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productionJson =
        json['townshipBuildingProduction'] as List<dynamic>? ?? [];
    final production = productionJson
        .map(
          (e) => BiomeProductionModifier.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();

    return DeityModifiers(
      buildingProduction: production,
      buildingCost: (json['townshipBuildingCost'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Per-biome production modifiers.
  final List<BiomeProductionModifier> buildingProduction;

  /// Global building cost modifier (percentage, e.g., -25 for -25% cost).
  final double buildingCost;

  /// Returns true if this modifier set has no effects.
  bool get isEmpty => buildingProduction.isEmpty && buildingCost == 0;

  /// Returns the production modifier for a specific biome, or 0 if none.
  double productionModifierForBiome(MelvorId biomeId) {
    for (final mod in buildingProduction) {
      if (mod.biomeId == biomeId) return mod.value;
    }
    return 0;
  }
}

/// A Township deity for worship.
@immutable
class TownshipDeity {
  const TownshipDeity({
    required this.id,
    required this.name,
    this.isHidden = false,
    this.statueName = '',
    this.statueMedia,
    this.baseModifiers = const DeityModifiers(),
    this.checkpoints = const [],
  });

  factory TownshipDeity.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Parse base modifiers (always active when deity is selected)
    final modifiersJson = json['modifiers'] as Map<String, dynamic>? ?? {};
    final baseModifiers = DeityModifiers.fromJson(
      modifiersJson,
      namespace: namespace,
    );

    // Parse checkpoint modifiers (unlocked at 5%, 25%, 50%, 85%, 95%)
    final checkpointsJson = json['checkpoints'] as List<dynamic>? ?? [];
    final checkpoints = checkpointsJson
        .map(
          (e) => DeityModifiers.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();

    // Parse media path, stripping query params (e.g., "?2").
    final statueMedia = (json['statueMedia'] as String?)?.split('?').first;

    return TownshipDeity(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      isHidden: json['isHidden'] as bool? ?? false,
      statueName: json['statueName'] as String? ?? '',
      statueMedia: statueMedia,
      baseModifiers: baseModifiers,
      checkpoints: checkpoints,
    );
  }

  /// Worship checkpoint thresholds (percentages).
  /// Checkpoints unlock at 5%, 25%, 50%, 85%, and 95% worship.
  static const List<double> checkpointThresholds = [5, 25, 50, 85, 95];

  final MelvorId id;
  final String name;

  /// Whether this deity is hidden from the UI.
  final bool isHidden;

  /// Name of the statue for this deity.
  final String statueName;

  /// Media path for this deity's statue.
  final String? statueMedia;

  /// Base modifiers that are always active when this deity is selected.
  final DeityModifiers baseModifiers;

  /// Checkpoint modifiers unlocked at increasing worship levels.
  /// Index 0 = 5%, Index 1 = 25%, Index 2 = 50%, Index 3 = 85%, Index 4 = 95%.
  final List<DeityModifiers> checkpoints;

  /// Returns the total production modifier for a biome at the given worship %.
  /// Includes base modifiers plus all unlocked checkpoint bonuses.
  double productionModifierForBiome(MelvorId biomeId, double worshipPercent) {
    var total = baseModifiers.productionModifierForBiome(biomeId);

    // Add checkpoint bonuses that are unlocked
    for (
      var i = 0;
      i < checkpoints.length && i < checkpointThresholds.length;
      i++
    ) {
      if (worshipPercent >= checkpointThresholds[i]) {
        total += checkpoints[i].productionModifierForBiome(biomeId);
      }
    }

    return total;
  }

  /// Returns the total building cost modifier at the given worship %.
  /// Includes base modifiers plus all unlocked checkpoint bonuses.
  double buildingCostModifier(double worshipPercent) {
    var total = baseModifiers.buildingCost;

    // Add checkpoint bonuses that are unlocked
    for (
      var i = 0;
      i < checkpoints.length && i < checkpointThresholds.length;
      i++
    ) {
      if (worshipPercent >= checkpointThresholds[i]) {
        total += checkpoints[i].buildingCost;
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
    required this.media,
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
      media: json['media'] as String?,
      seasonLength: json['seasonLength'] as int? ?? 72,
      order: json['order'] as int? ?? 0,
    );
  }

  final MelvorId id;
  final String name;

  /// Media path for the season icon.
  final String? media;

  /// Season length in hours.
  final int seasonLength;

  /// Display order.
  final int order;
}

/// Types of goals for Township tasks.
enum TaskGoalType {
  /// Gain XP in a specific skill.
  skillXP,

  /// Obtain specific items (consumed on task completion).
  items,

  /// Kill specific monsters.
  monsters,
}

/// A single goal within a Township task.
@immutable
class TaskGoal {
  const TaskGoal({
    required this.type,
    required this.id,
    required this.quantity,
  });

  factory TaskGoal.fromJson(
    Map<String, dynamic> json, {
    required TaskGoalType type,
    required String namespace,
  }) {
    return TaskGoal(
      type: type,
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      quantity: json['quantity'] as int,
    );
  }

  /// Type of goal.
  final TaskGoalType type;

  /// Target ID (skill, item, or monster).
  final MelvorId id;

  /// Required quantity (XP amount, item count, or kill count).
  final int quantity;

  /// Returns the display name for this goal.
  ///
  /// For skill XP goals, returns the skill name + " XP".
  /// For item goals, returns the item name.
  /// For monster goals, returns the monster name.
  String displayName(ItemRegistry items, ActionRegistry actions) =>
      switch (type) {
        TaskGoalType.skillXP => '${id.localId} XP',
        TaskGoalType.items => items.byId(id).name,
        TaskGoalType.monsters => actions.combatWithId(id).name,
      };

  /// Returns the asset path for this goal's icon.
  ///
  /// For skill XP goals, returns the skill icon path.
  /// For item goals, returns the item's media path.
  /// For monster goals, returns the monster's media path.
  String asset(ItemRegistry items, ActionRegistry actions) => switch (type) {
    TaskGoalType.skillXP => Skill.fromId(id).assetPath,
    TaskGoalType.items => items.byId(id).media!,
    TaskGoalType.monsters => actions.combatWithId(id).media!,
  };
}

/// Types of rewards for Township tasks.
enum TaskRewardType {
  /// Item reward.
  item,

  /// Currency reward (GP, Slayer Coins, etc.).
  currency,

  /// Skill XP reward.
  skillXP,

  /// Township resource reward.
  townshipResource,
}

/// A reward for completing a Township task.
@immutable
class TaskReward {
  const TaskReward({
    required this.type,
    required this.id,
    required this.quantity,
  });

  factory TaskReward.fromJson(
    Map<String, dynamic> json, {
    required TaskRewardType type,
    required String namespace,
  }) {
    return TaskReward(
      type: type,
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      quantity: json['quantity'] as int,
    );
  }

  /// Type of reward.
  final TaskRewardType type;

  /// Reward ID (item, currency, skill, or resource).
  final MelvorId id;

  /// Quantity of the reward.
  final int quantity;

  /// Returns the display name for this reward.
  ///
  /// For item rewards, returns the item name.
  /// For currency rewards, returns the currency abbreviation.
  /// For skill XP rewards, returns the skill name + " XP".
  /// For township resource rewards, returns the resource name.
  String displayName(ItemRegistry items, TownshipRegistry township) =>
      switch (type) {
        TaskRewardType.item => items.byId(id).name,
        TaskRewardType.currency => Currency.fromIdString(
          id.fullId,
        ).abbreviation,
        TaskRewardType.skillXP => '${Skill.fromId(id).name} XP',
        TaskRewardType.townshipResource => township.resourceById(id).name,
      };

  /// Returns the asset path for this reward's icon.
  ///
  /// For item rewards, returns the item's media path.
  /// For currency rewards, returns the currency's asset path.
  /// For skill XP rewards, returns the skill's icon path.
  /// For township resource rewards, returns the resource's media path.
  String? asset(ItemRegistry items, TownshipRegistry township) =>
      switch (type) {
        TaskRewardType.item => items.byId(id).media,
        TaskRewardType.currency => Currency.fromIdString(id.fullId).assetPath,
        TaskRewardType.skillXP => Skill.fromId(id).assetPath,
        TaskRewardType.townshipResource => township.resourceById(id).media,
      };
}

/// Task difficulty categories.
enum TaskCategory {
  easy,
  normal,
  hard,
  veryHard,
  elite;

  /// Parses a category from the API string format.
  static TaskCategory fromString(String value) {
    return switch (value) {
      'Easy' => TaskCategory.easy,
      'Normal' => TaskCategory.normal,
      'Hard' => TaskCategory.hard,
      'VeryHard' => TaskCategory.veryHard,
      'Elite' => TaskCategory.elite,
      _ => throw ArgumentError('Unknown task category: $value'),
    };
  }

  /// Returns the display name for this category.
  String get displayName {
    return switch (this) {
      TaskCategory.easy => 'Easy',
      TaskCategory.normal => 'Normal',
      TaskCategory.hard => 'Hard',
      TaskCategory.veryHard => 'Very Hard',
      TaskCategory.elite => 'Elite',
    };
  }
}

/// A Township task definition.
@immutable
class TownshipTask {
  const TownshipTask({
    required this.id,
    required this.category,
    this.description = '',
    this.goals = const [],
    this.rewards = const [],
  });

  factory TownshipTask.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Parse goals
    final goals = <TaskGoal>[];
    final goalsJson = json['goals'] as Map<String, dynamic>? ?? {};

    // Parse skillXP goals
    final skillXPJson = goalsJson['skillXP'] as List<dynamic>? ?? [];
    for (final goal in skillXPJson) {
      goals.add(
        TaskGoal.fromJson(
          goal as Map<String, dynamic>,
          type: TaskGoalType.skillXP,
          namespace: namespace,
        ),
      );
    }

    // Parse items goals
    final itemsJson = goalsJson['items'] as List<dynamic>? ?? [];
    for (final goal in itemsJson) {
      goals.add(
        TaskGoal.fromJson(
          goal as Map<String, dynamic>,
          type: TaskGoalType.items,
          namespace: namespace,
        ),
      );
    }

    // Parse monsters goals
    final monstersJson = goalsJson['monsters'] as List<dynamic>? ?? [];
    for (final goal in monstersJson) {
      goals.add(
        TaskGoal.fromJson(
          goal as Map<String, dynamic>,
          type: TaskGoalType.monsters,
          namespace: namespace,
        ),
      );
    }

    // Parse rewards
    final rewards = <TaskReward>[];
    final rewardsJson = json['rewards'] as Map<String, dynamic>? ?? {};

    // Parse item rewards
    final itemRewardsJson = rewardsJson['items'] as List<dynamic>? ?? [];
    for (final reward in itemRewardsJson) {
      rewards.add(
        TaskReward.fromJson(
          reward as Map<String, dynamic>,
          type: TaskRewardType.item,
          namespace: namespace,
        ),
      );
    }

    // Parse currency rewards
    final currencyJson = rewardsJson['currencies'] as List<dynamic>? ?? [];
    for (final reward in currencyJson) {
      rewards.add(
        TaskReward.fromJson(
          reward as Map<String, dynamic>,
          type: TaskRewardType.currency,
          namespace: namespace,
        ),
      );
    }

    // Parse skill XP rewards
    final skillXPRewardsJson = rewardsJson['skillXP'] as List<dynamic>? ?? [];
    for (final reward in skillXPRewardsJson) {
      rewards.add(
        TaskReward.fromJson(
          reward as Map<String, dynamic>,
          type: TaskRewardType.skillXP,
          namespace: namespace,
        ),
      );
    }

    // Parse township resource rewards
    final resourceJson =
        rewardsJson['townshipResources'] as List<dynamic>? ?? [];
    for (final reward in resourceJson) {
      rewards.add(
        TaskReward.fromJson(
          reward as Map<String, dynamic>,
          type: TaskRewardType.townshipResource,
          namespace: namespace,
        ),
      );
    }

    return TownshipTask(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      category: TaskCategory.fromString(json['category'] as String),
      description: json['description'] as String? ?? '',
      goals: goals,
      rewards: rewards,
    );
  }

  final MelvorId id;

  /// Task difficulty category.
  final TaskCategory category;

  /// Optional description/hint for the task.
  final String description;

  /// Goals that must be completed.
  final List<TaskGoal> goals;

  /// Rewards for completing this task.
  final List<TaskReward> rewards;

  /// Converts task rewards to Changes for display in toasts/dialogs.
  ///
  /// Note: Township resource rewards are not included since they don't
  /// appear in the standard toast display.
  Changes rewardsToChanges(ItemRegistry items) {
    var changes = const Changes.empty();
    for (final reward in rewards) {
      switch (reward.type) {
        case TaskRewardType.item:
          final item = items.byId(reward.id);
          changes = changes.adding(ItemStack(item, count: reward.quantity));
        case TaskRewardType.currency:
          final currency = Currency.fromIdString(reward.id.fullId);
          changes = changes.addingCurrency(currency, reward.quantity);
        case TaskRewardType.skillXP:
          final skill = Skill.fromId(reward.id);
          changes = changes.addingSkillXp(skill, reward.quantity);
        case TaskRewardType.townshipResource:
          // Township resources don't show in the standard toast
          break;
      }
    }
    return changes;
  }
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
    this.buildingSortIndex = const {},
  });

  // TODO(eseidel): copyWith could end up with an empty registry.
  const TownshipRegistry.empty() : this();

  final List<TownshipBuilding> buildings;
  final List<TownshipBiome> biomes;
  final List<TownshipResource> resources;
  final List<TownshipDeity> deities;
  final List<TownshipTrade> trades;
  final List<TownshipSeason> seasons;
  final List<TownshipTask> tasks;

  /// Maps building ID to its display order index.
  final Map<MelvorId, int> buildingSortIndex;

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

  /// Comparator for sorting building IDs according to display order.
  /// Buildings in sort order come before buildings not in sort order.
  /// Buildings not in sort order maintain stable relative ordering.
  int compareBuildings(MelvorId a, MelvorId b) {
    final indexA = buildingSortIndex[a];
    final indexB = buildingSortIndex[b];

    // Both not in sort order - maintain original order (return 0)
    if (indexA == null && indexB == null) return 0;
    // Buildings in sort order come before buildings not in sort order
    if (indexA == null) return 1;
    if (indexB == null) return -1;

    return indexA.compareTo(indexB);
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

  /// Returns a resource by ID, or throws if not found.
  TownshipResource resourceById(MelvorId id) {
    for (final resource in resources) {
      if (resource.id == id) return resource;
    }
    throw StateError('Unknown township resource: $id');
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

  /// Returns a task by ID, or throws if not found.
  TownshipTask taskById(MelvorId id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    throw StateError('Unknown township task: $id');
  }

  /// Returns all tasks for a specific category.
  List<TownshipTask> tasksForCategory(TaskCategory category) {
    return tasks.where((t) => t.category == category).toList();
  }

  // ---------------------------------------------------------------------------
  // Statue building resolution
  // ---------------------------------------------------------------------------

  /// The ID of the Statue building which has dynamic name/media based on deity.
  static const statuesBuildingId = MelvorId('melvorF:Statues');

  /// Returns the display name for a building, resolving the Statue building's
  /// name based on the selected deity.
  ///
  /// If [deity] is null or the building is not the Statue, returns the
  /// building's default name.
  String buildingDisplayName(TownshipBuilding building, TownshipDeity? deity) {
    if (building.id == statuesBuildingId && deity != null) {
      return deity.statueName.isNotEmpty ? deity.statueName : building.name;
    }
    return building.name;
  }

  /// Returns the display media for a building, resolving the Statue building's
  /// media based on the selected deity.
  ///
  /// If [deity] is null or the building is not the Statue, returns the
  /// building's default media.
  String? buildingDisplayMedia(
    TownshipBuilding building,
    TownshipDeity? deity,
  ) {
    if (building.id == statuesBuildingId && deity != null) {
      return deity.statueMedia ?? building.media;
    }
    return building.media;
  }
}
