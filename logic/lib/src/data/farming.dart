import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

import 'action_id.dart';
import 'actions.dart';
import 'currency.dart';
import 'melvor_id.dart';

/// A farming category parsed from Melvor data (Allotment, Herb, Tree).
@immutable
class FarmingCategory {
  const FarmingCategory({
    required this.id,
    required this.name,
    required this.returnSeeds,
    required this.scaleXPWithQuantity,
    required this.harvestMultiplier,
    required this.masteryXPDivider,
    required this.giveXPOnPlant,
    required this.description,
    required this.seedNotice,
  });

  factory FarmingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return FarmingCategory(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      returnSeeds: json['returnSeeds'] as bool? ?? false,
      scaleXPWithQuantity: json['scaleXPWithQuantity'] as bool? ?? false,
      harvestMultiplier: json['harvestMultiplier'] as int? ?? 1,
      masteryXPDivider: json['masteryXPDivider'] as int? ?? 1,
      giveXPOnPlant: json['giveXPOnPlant'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      seedNotice: json['seedNotice'] as String? ?? '',
    );
  }

  final MelvorId id;
  final String name;

  /// Whether this category returns seeds on harvest.
  final bool returnSeeds;

  /// Whether XP scales with harvest quantity.
  final bool scaleXPWithQuantity;

  /// Multiplier for harvest quantity (e.g., 3 for Allotments).
  final int harvestMultiplier;

  /// Divider for mastery XP (e.g., 10 for Trees).
  final int masteryXPDivider;

  /// Whether to give XP when planting (instead of harvesting).
  final bool giveXPOnPlant;

  final String description;
  final String seedNotice;

  @override
  String toString() => name;
}

/// Registry for farming categories.
class FarmingCategoryRegistry {
  FarmingCategoryRegistry(List<FarmingCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<FarmingCategory> _categories;
  late final Map<MelvorId, FarmingCategory> _byId;

  /// Returns all farming categories.
  List<FarmingCategory> get all => _categories;

  /// Returns a farming category by ID, or null if not found.
  FarmingCategory? byId(MelvorId id) => _byId[id];
}

/// A farming plot definition parsed from Melvor data.
@immutable
class FarmingPlot {
  const FarmingPlot({
    required this.id,
    required this.categoryId,
    required this.level,
    this.currencyCosts = CurrencyCosts.empty,
  });

  factory FarmingPlot.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return FarmingPlot(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      categoryId: MelvorId.fromJsonWithNamespace(
        json['categoryID'] as String,
        defaultNamespace: namespace,
      ),
      level: json['level'] as int? ?? 1,
      currencyCosts: CurrencyCosts.fromJson(
        json['currencyCosts'] as List<dynamic>?,
      ),
    );
  }

  final MelvorId id;
  final MelvorId categoryId;
  final int level;
  final CurrencyCosts currencyCosts;

  @override
  String toString() => 'FarmingPlot($id)';
}

/// Registry for farming plots.
class FarmingPlotRegistry {
  FarmingPlotRegistry(List<FarmingPlot> plots) : _plots = plots {
    _byId = {for (final plot in _plots) plot.id: plot};
  }

  final List<FarmingPlot> _plots;
  late final Map<MelvorId, FarmingPlot> _byId;

  /// Returns all farming plots.
  List<FarmingPlot> get all => _plots;

  /// Returns a farming plot by ID, or null if not found.
  FarmingPlot? byId(MelvorId id) => _byId[id];

  /// Returns all plots for a given category.
  List<FarmingPlot> forCategory(MelvorId categoryId) {
    return _plots.where((plot) => plot.categoryId == categoryId).toList();
  }

  /// Returns the set of plot IDs that should be unlocked initially.
  /// These are plots with level 1 and no cost (free starter plots).
  Set<MelvorId> initialPlots() {
    return {
      for (final plot in _plots)
        if (plot.level == 1 && plot.currencyCosts.isEmpty) plot.id,
    };
  }
}

/// A farming crop parsed from Melvor data.
///
/// Extends Action (not SkillAction) to get ActionId for mastery tracking.
/// Crops are never activeAction, but mastery XP is tracked per-action using
/// `Map&lt;ActionId, ActionState&gt;` in GlobalState.
@immutable
class FarmingCrop extends Action {
  const FarmingCrop({
    required super.id,
    required super.name,
    required this.categoryId,
    required this.level,
    required this.baseXP,
    required this.seedCost,
    required this.baseInterval,
    required this.seedId,
    required this.productId,
    required this.baseQuantity,
    required this.media,
  }) : super(skill: Skill.farming);

  factory FarmingCrop.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final seedId = MelvorId.fromJsonWithNamespace(
      json['seedCost']['id'] as String,
      defaultNamespace: namespace,
    );
    final productId = MelvorId.fromJsonWithNamespace(
      json['productId'] as String,
      defaultNamespace: namespace,
    );

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    return FarmingCrop(
      id: ActionId(Skill.farming.id, localId),
      // recipes do not have a name, so use the id
      name: json['id'] as String,
      categoryId: MelvorId.fromJsonWithNamespace(
        json['categoryID'] as String,
        defaultNamespace: namespace,
      ),
      level: json['level'] as int,
      baseXP: json['baseExperience'] as int,
      seedCost: json['seedCost']['quantity'] as int,
      baseInterval: json['baseInterval'] as int,
      seedId: seedId,
      productId: productId,
      baseQuantity: json['baseQuantity'] as int? ?? 1,
      media: json['media'] as String? ?? '',
    );
  }

  final MelvorId categoryId;
  final int level;
  final int baseXP;
  final int seedCost;
  final int baseInterval; // milliseconds
  final MelvorId seedId;
  final MelvorId productId;
  final int baseQuantity;
  final String media;

  /// Growth duration for this crop.
  Duration get growthDuration => Duration(milliseconds: baseInterval);

  /// Growth time in ticks.
  int get growthTicks => ticksFromDuration(growthDuration);

  @override
  String toString() => 'FarmingCrop($name)';
}

/// Registry for farming crops.
class FarmingCropRegistry {
  FarmingCropRegistry(List<FarmingCrop> crops) : _crops = crops {
    _byId = {for (final crop in _crops) crop.id: crop};
  }

  final List<FarmingCrop> _crops;
  late final Map<ActionId, FarmingCrop> _byId;

  /// Returns all farming crops.
  List<FarmingCrop> get all => _crops;

  /// Returns a farming crop by ID, or null if not found.
  FarmingCrop? byId(ActionId id) => _byId[id];

  /// Returns all crops for a given category.
  List<FarmingCrop> forCategory(MelvorId categoryId) {
    return _crops.where((crop) => crop.categoryId == categoryId).toList();
  }
}
