import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// Monster selection criteria for a slayer task category.
@immutable
sealed class MonsterSelection {
  const MonsterSelection();

  factory MonsterSelection.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'CombatLevel' => CombatLevelSelection.fromJson(json),
      _ => throw ArgumentError('Unknown monster selection type: $type'),
    };
  }
}

/// Selects monsters based on their combat level range.
@immutable
class CombatLevelSelection extends MonsterSelection {
  const CombatLevelSelection({required this.minLevel, required this.maxLevel});

  factory CombatLevelSelection.fromJson(Map<String, dynamic> json) {
    return CombatLevelSelection(
      minLevel: json['minLevel'] as int,
      maxLevel: json['maxLevel'] as int,
    );
  }

  final int minLevel;
  final int maxLevel;
}

/// A currency reward as a percentage of monster HP.
@immutable
class CurrencyReward {
  const CurrencyReward({required this.currency, required this.percent});

  factory CurrencyReward.fromJson(Map<String, dynamic> json) {
    final currencyId = MelvorId.fromJson(json['id'] as String);
    final currency = Currency.fromId(currencyId);
    return CurrencyReward(currency: currency, percent: json['percent'] as int);
  }

  final Currency currency;
  final int percent;
}

/// A slayer task category (tier) like Easy, Normal, Hard, Elite, Master.
@immutable
class SlayerTaskCategory {
  const SlayerTaskCategory({
    required this.id,
    required this.name,
    required this.level,
    required this.rollCost,
    required this.extensionCost,
    required this.extensionMultiplier,
    required this.currencyRewards,
    required this.monsterSelection,
    required this.baseTaskLength,
    this.previousCategoryId,
  });

  factory SlayerTaskCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final rewardsJson = json['currencyRewards'] as List<dynamic>? ?? [];
    final rewards = rewardsJson
        .map((e) => CurrencyReward.fromJson(e as Map<String, dynamic>))
        .toList();

    final selectionJson = json['monsterSelection'] as Map<String, dynamic>;

    final previousCategory = json['previousCategory'] as String?;

    return SlayerTaskCategory(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      level: json['level'] as int,
      rollCost: CurrencyCosts.fromJson(json['rollCost'] as List<dynamic>?),
      extensionCost: CurrencyCosts.fromJson(
        json['extensionCost'] as List<dynamic>?,
      ),
      extensionMultiplier: json['extensionMultiplier'] as int,
      currencyRewards: rewards,
      monsterSelection: MonsterSelection.fromJson(selectionJson),
      baseTaskLength: json['baseTaskLength'] as int,
      previousCategoryId: previousCategory != null
          ? MelvorId.fromJson(previousCategory)
          : null,
    );
  }

  final MelvorId id;
  final String name;
  final int level;
  final CurrencyCosts rollCost;
  final CurrencyCosts extensionCost;
  final int extensionMultiplier;
  final List<CurrencyReward> currencyRewards;
  final MonsterSelection monsterSelection;
  final int baseTaskLength;
  final MelvorId? previousCategoryId;
}

/// An area effect applied to players in a slayer area.
@immutable
class SlayerAreaEffect {
  const SlayerAreaEffect({
    required this.target,
    required this.modifiers,
    required this.magnitude,
  });

  factory SlayerAreaEffect.fromJson(Map<String, dynamic> json) {
    final modifiers = <String, int>{};
    final modifiersJson = json['modifiers'] as Map<String, dynamic>? ?? {};
    for (final entry in modifiersJson.entries) {
      modifiers[entry.key] = entry.value as int;
    }

    return SlayerAreaEffect(
      target: json['target'] as String,
      modifiers: modifiers,
      magnitude: json['magnitude'] as int,
    );
  }

  final String target;
  final Map<String, int> modifiers;
  final int magnitude;
}

/// Requirement to enter a slayer area.
@immutable
sealed class SlayerAreaRequirement {
  const SlayerAreaRequirement();

  factory SlayerAreaRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final type = json['type'] as String;
    return switch (type) {
      'SkillLevel' => SlayerLevelRequirement.fromJson(json),
      'SlayerItem' => SlayerItemRequirement.fromJson(
        json,
        namespace: namespace,
      ),
      'DungeonCompletion' => SlayerDungeonRequirement.fromJson(
        json,
        namespace: namespace,
      ),
      'ShopPurchase' => SlayerShopPurchaseRequirement.fromJson(
        json,
        namespace: namespace,
      ),
      _ => throw ArgumentError('Unknown slayer area requirement type: $type'),
    };
  }
}

/// Requires a minimum slayer level.
@immutable
class SlayerLevelRequirement extends SlayerAreaRequirement {
  const SlayerLevelRequirement({required this.level});

  factory SlayerLevelRequirement.fromJson(Map<String, dynamic> json) {
    return SlayerLevelRequirement(level: json['level'] as int);
  }

  final int level;
}

/// Requires a specific item equipped (like Mirror Shield).
@immutable
class SlayerItemRequirement extends SlayerAreaRequirement {
  const SlayerItemRequirement({required this.itemId});

  factory SlayerItemRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return SlayerItemRequirement(
      itemId: MelvorId.fromJsonWithNamespace(
        json['itemID'] as String,
        defaultNamespace: namespace,
      ),
    );
  }

  final MelvorId itemId;
}

/// Requires completing a dungeon a certain number of times.
@immutable
class SlayerDungeonRequirement extends SlayerAreaRequirement {
  const SlayerDungeonRequirement({
    required this.dungeonId,
    required this.count,
  });

  factory SlayerDungeonRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return SlayerDungeonRequirement(
      dungeonId: MelvorId.fromJsonWithNamespace(
        json['dungeonID'] as String,
        defaultNamespace: namespace,
      ),
      count: json['count'] as int,
    );
  }

  final MelvorId dungeonId;
  final int count;
}

/// Requires purchasing a shop item.
@immutable
class SlayerShopPurchaseRequirement extends SlayerAreaRequirement {
  const SlayerShopPurchaseRequirement({
    required this.purchaseId,
    required this.count,
  });

  factory SlayerShopPurchaseRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return SlayerShopPurchaseRequirement(
      purchaseId: MelvorId.fromJsonWithNamespace(
        json['purchaseID'] as String,
        defaultNamespace: namespace,
      ),
      count: json['count'] as int,
    );
  }

  final MelvorId purchaseId;
  final int count;
}

/// A slayer area containing monsters that require slayer level/items.
@immutable
class SlayerArea {
  const SlayerArea({
    required this.id,
    required this.name,
    required this.monsterIds,
    required this.difficulty,
    required this.entryRequirements,
    this.media,
    this.areaEffect,
    this.areaEffectDescription,
  });

  factory SlayerArea.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final monsterIds = (json['monsterIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final difficultyRaw = json['difficulty'] as List<dynamic>? ?? [];
    final difficulty = difficultyRaw.map((e) => e as int).toList();

    final requirementsJson = json['entryRequirements'] as List<dynamic>? ?? [];
    final requirements = requirementsJson
        .map(
          (e) => SlayerAreaRequirement.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();

    SlayerAreaEffect? areaEffect;
    final areaEffectJson = json['areaEffect'] as Map<String, dynamic>?;
    if (areaEffectJson != null) {
      areaEffect = SlayerAreaEffect.fromJson(areaEffectJson);
    }

    return SlayerArea(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      monsterIds: monsterIds,
      difficulty: difficulty,
      entryRequirements: requirements,
      media: json['media'] as String?,
      areaEffect: areaEffect,
      areaEffectDescription: json['areaEffectDescription'] as String?,
    );
  }

  final MelvorId id;
  final String name;
  final List<MelvorId> monsterIds;
  final List<int> difficulty;
  final List<SlayerAreaRequirement> entryRequirements;
  final String? media;
  final SlayerAreaEffect? areaEffect;
  final String? areaEffectDescription;

  /// Returns the minimum slayer level required to enter this area.
  int get requiredSlayerLevel {
    for (final req in entryRequirements) {
      if (req is SlayerLevelRequirement) {
        return req.level;
      }
    }
    return 1;
  }
}

/// Registry for slayer task categories.
@immutable
class SlayerTaskCategoryRegistry {
  SlayerTaskCategoryRegistry(List<SlayerTaskCategory> categories)
    : _categories = categories {
    _byId = {for (final cat in _categories) cat.id: cat};
  }

  final List<SlayerTaskCategory> _categories;
  late final Map<MelvorId, SlayerTaskCategory> _byId;

  /// Returns all task categories.
  List<SlayerTaskCategory> get all => _categories;

  /// Returns a category by ID.
  SlayerTaskCategory? byId(MelvorId id) => _byId[id];
}

/// Registry for slayer areas.
@immutable
class SlayerAreaRegistry {
  SlayerAreaRegistry(List<SlayerArea> areas) : _areas = areas {
    _byId = {for (final area in _areas) area.id: area};
  }

  final List<SlayerArea> _areas;
  late final Map<MelvorId, SlayerArea> _byId;

  /// Returns all slayer areas.
  List<SlayerArea> get all => _areas;

  /// Returns an area by ID.
  SlayerArea? byId(MelvorId id) => _byId[id];
}

/// Combined registry for all slayer-related data.
@immutable
class SlayerRegistry {
  const SlayerRegistry({required this.taskCategories, required this.areas});

  final SlayerTaskCategoryRegistry taskCategories;
  final SlayerAreaRegistry areas;
}
