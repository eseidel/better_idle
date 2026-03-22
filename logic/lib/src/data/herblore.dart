import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

const _herbloreDuration = Duration(seconds: 2);

/// A herblore category parsed from Melvor data.
@immutable
class HerbloreCategory {
  const HerbloreCategory({
    required this.id,
    required this.name,
    required this.media,
  });

  factory HerbloreCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return HerbloreCategory(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      media: json['media'] as String,
    );
  }

  final MelvorId id;
  final String name;
  final String media;
}

/// A herblore action parsed from Melvor data.
///
/// Herblore actions consume herbs and secondary ingredients to produce potions.
/// Each recipe can produce multiple tiers of potions (I, II, III, IV) based on
/// mastery level. Use [productIdForMasteryLevel] to get the correct output.
@immutable
class HerbloreAction extends SkillAction {
  HerbloreAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.potionIds,
    required this.categoryId,
  }) : super(
         skill: Skill.herblore,
         duration: _herbloreDuration,
         rewardsAtLevel: (action, selection) => [TieredDrop(potionIds)],
       );

  factory HerbloreAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Herblore recipes have potionIDs array with tier variants.
    // We use the first tier (I) as the default product.
    final potionIds = (json['potionIDs'] as List<dynamic>)
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    final productId = potionIds.first;

    // Parse item costs into inputs map.
    final itemCosts = json['itemCosts'] as List<dynamic>? ?? [];
    final inputs = <MelvorId, int>{};
    for (final cost in itemCosts) {
      final costMap = cost as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = costMap['quantity'] as int;
      inputs[itemId] = quantity;
    }

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return HerbloreAction(
      id: ActionId(Skill.herblore.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: inputs,
      outputs: {productId: 1},
      productId: productId,
      potionIds: potionIds,
      categoryId: json['categoryID'] != null
          ? MelvorId.fromJsonWithNamespace(
              json['categoryID'] as String,
              defaultNamespace: namespace,
            )
          : null,
    );
  }

  /// The Melvor product ID for the base potion (tier I).
  final MelvorId productId;

  /// All potion tier IDs (I, II, III, IV).
  final List<MelvorId> potionIds;

  /// The category ID (e.g., "melvorF:CombatPotions", "melvorF:SkillPotions").
  @override
  final MelvorId? categoryId;

  /// Returns the potion tier index (0-3) for the given mastery level.
  ///
  /// Melvor Idle mastery thresholds:
  /// - Tier I (0): mastery level 1+
  /// - Tier II (1): mastery level 20+
  /// - Tier III (2): mastery level 50+
  /// - Tier IV (3): mastery level 90+
  static int tierIndexForMasteryLevel(int masteryLevel) {
    if (masteryLevel >= 90) return 3;
    if (masteryLevel >= 50) return 2;
    if (masteryLevel >= 20) return 1;
    return 0;
  }

  /// Returns the potion ID to produce at the given mastery level.
  MelvorId productIdForMasteryLevel(int masteryLevel) {
    final tierIndex = tierIndexForMasteryLevel(masteryLevel);
    return potionIds[tierIndex.clamp(0, potionIds.length - 1)];
  }

  @override
  Map<MelvorId, int> outputsForRecipe(
    RecipeSelection selection, {
    required int masteryLevel,
  }) {
    return {productIdForMasteryLevel(masteryLevel): 1};
  }
}

/// Unified registry for all herblore-related data.
@immutable
class HerbloreRegistry {
  HerbloreRegistry({
    required List<HerbloreAction> actions,
    required List<HerbloreCategory> categories,
  }) : _actions = actions,
       _categories = categories {
    _byId = {for (final a in _actions) a.id.localId: a};
    _categoryById = {for (final c in _categories) c.id: c};
    _recipeByPotionItemId = {
      for (final a in _actions)
        for (final potionId in a.potionIds) potionId: a.id.localId,
    };
  }

  final List<HerbloreAction> _actions;
  final List<HerbloreCategory> _categories;
  late final Map<MelvorId, HerbloreAction> _byId;
  late final Map<MelvorId, HerbloreCategory> _categoryById;
  late final Map<MelvorId, MelvorId> _recipeByPotionItemId;

  /// All herblore actions.
  List<HerbloreAction> get actions => _actions;

  /// All herblore categories.
  List<HerbloreCategory> get categories => _categories;

  /// Look up a herblore action by its local ID.
  HerbloreAction? byId(MelvorId localId) => _byId[localId];

  /// Returns a herblore category by ID, or null if not found.
  HerbloreCategory? categoryById(MelvorId id) => _categoryById[id];

  /// Returns the herblore recipe local ID for a potion item ID.
  MelvorId? recipeIdForPotionItem(MelvorId potionItemId) =>
      _recipeByPotionItemId[potionItemId];
}
