import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

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

  /// Creates a test category with sensible defaults.
  const FarmingCategory.test({
    required this.id,
    this.name = 'Test Category',
    this.returnSeeds = true,
    this.scaleXPWithQuantity = true,
    this.harvestMultiplier = 1,
    this.masteryXPDivider = 1,
    this.giveXPOnPlant = false,
    this.description = '',
    this.seedNotice = '',
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

/// A farming crop parsed from Melvor data.
///
/// Crops are never the player's active action - they grow in the background
/// and are harvested - but they do track mastery, so [canBeActiveAction] is
/// false while the rest of the [SkillAction] machinery (xp, unlockLevel,
/// maxDuration) drives the mastery calculations.
@immutable
class FarmingCrop extends SkillAction {
  FarmingCrop({
    required super.id,
    required super.name,
    required this.categoryId,
    required super.unlockLevel,
    required super.xp,
    required this.seedCost,
    required int baseInterval,
    required this.seedId,
    required this.productId,
    required this.baseQuantity,
    required this.media,
    required this.masteryXPDivider,
  }) : super(
         skill: Skill.farming,
         duration: Duration(milliseconds: baseInterval),
       );

  /// Creates a test crop with sensible defaults.
  FarmingCrop.test({
    required String name,
    required MelvorId categoryId,
    required MelvorId seedId,
    required MelvorId productId,
    int masteryXPDivider = 1,
  }) : this(
         id: ActionId.test(Skill.farming, name),
         name: name,
         categoryId: categoryId,
         unlockLevel: 1,
         xp: 8,
         seedCost: 1,
         baseInterval: 30000,
         seedId: seedId,
         productId: productId,
         baseQuantity: 5,
         media: '',
         masteryXPDivider: masteryXPDivider,
       );

  factory FarmingCrop.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
    required int Function(MelvorId categoryId) masteryXPDividerFor,
  }) {
    final seedId = MelvorId.fromJsonWithNamespace(
      (json['seedCost'] as Map<String, dynamic>)['id'] as String,
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

    final categoryId = MelvorId.fromJsonWithNamespace(
      json['categoryID'] as String,
      defaultNamespace: namespace,
    );

    return FarmingCrop(
      id: ActionId(Skill.farming.id, localId),
      // recipes do not have a name, so use the id
      name: json['id'] as String,
      categoryId: categoryId,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      seedCost: (json['seedCost'] as Map<String, dynamic>)['quantity'] as int,
      baseInterval: json['baseInterval'] as int,
      seedId: seedId,
      productId: productId,
      baseQuantity: json['baseQuantity'] as int? ?? 1,
      media: json['media'] as String? ?? '',
      masteryXPDivider: masteryXPDividerFor(categoryId),
    );
  }

  @override
  final MelvorId categoryId;

  final int seedCost;
  final MelvorId seedId;
  final MelvorId productId;
  final int baseQuantity;
  final String media;

  /// The crop category's `masteryXPDivider`, copied in at parse time.
  ///
  /// Held on the crop rather than looked up through the category so that
  /// [masteryActionTime] stays a property of the action, like every other
  /// skill's.
  final int masteryXPDivider;

  /// Crops grow in the background; they are never the active action.
  @override
  bool get canBeActiveAction => false;

  /// Farming charges mastery for the growth interval divided by the crop
  /// category's `masteryXPDivider` (3 for Allotments and Herbs, 10 for
  /// Trees). Trees grow for hours longer than allotments; the divider puts
  /// every category on the same scale, 1800s to 5760s across all 24 crops.
  @override
  double get masteryActionTime =>
      maxDuration.inSeconds / max(1, masteryXPDivider);

  /// Growth duration for this crop.
  Duration get growthDuration => maxDuration;

  /// Growth time in ticks.
  int get growthTicks => ticksFromDuration(growthDuration);

  @override
  String toString() => 'FarmingCrop($name)';
}

/// Unified registry for all farming-related data.
@immutable
class FarmingRegistry {
  FarmingRegistry({
    required List<FarmingCrop> crops,
    required List<FarmingCategory> categories,
    required List<FarmingPlot> plots,
  }) : _crops = crops,
       _categories = categories,
       _plots = plots {
    _cropById = {for (final crop in _crops) crop.id: crop};
    _categoryById = {for (final cat in _categories) cat.id: cat};
    _plotById = {for (final plot in _plots) plot.id: plot};
  }

  final List<FarmingCrop> _crops;
  final List<FarmingCategory> _categories;
  final List<FarmingPlot> _plots;
  late final Map<ActionId, FarmingCrop> _cropById;
  late final Map<MelvorId, FarmingCategory> _categoryById;
  late final Map<MelvorId, FarmingPlot> _plotById;

  /// All farming crops.
  List<FarmingCrop> get crops => _crops;

  /// All farming categories.
  List<FarmingCategory> get categories => _categories;

  /// All farming plots.
  List<FarmingPlot> get plots => _plots;

  /// Returns a farming crop by ID, or null if not found.
  FarmingCrop? cropById(ActionId id) => _cropById[id];

  /// Returns a farming category by ID, or null if not found.
  FarmingCategory? categoryById(MelvorId id) => _categoryById[id];

  /// Returns a farming plot by ID, or null if not found.
  FarmingPlot? plotById(MelvorId id) => _plotById[id];

  /// Returns all crops for a given category.
  List<FarmingCrop> cropsForCategory(MelvorId categoryId) =>
      _crops.where((crop) => crop.categoryId == categoryId).toList();

  /// Returns all plots for a given category.
  List<FarmingPlot> plotsForCategory(MelvorId categoryId) =>
      _plots.where((plot) => plot.categoryId == categoryId).toList();

  /// Returns the set of plot IDs that should be unlocked initially.
  /// These are plots with level 1 and no cost (free starter plots).
  Set<MelvorId> initialPlots() {
    return {
      for (final plot in _plots)
        if (plot.level == 1 && plot.currencyCosts.isEmpty) plot.id,
    };
  }
}
