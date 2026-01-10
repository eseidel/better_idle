import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
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

/// Registry for herblore categories.
@immutable
class HerbloreCategoryRegistry {
  HerbloreCategoryRegistry(List<HerbloreCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<HerbloreCategory> _categories;
  late final Map<MelvorId, HerbloreCategory> _byId;

  /// Returns all herblore categories.
  List<HerbloreCategory> get all => _categories;

  /// Returns a herblore category by ID, or null if not found.
  HerbloreCategory? byId(MelvorId id) => _byId[id];
}

/// A herblore action parsed from Melvor data.
///
/// Herblore actions consume herbs and secondary ingredients to produce potions.
/// Each recipe can produce multiple tiers of potions (I, II, III, IV) based on
/// mastery level, but for simplicity we produce the first tier by default.
@immutable
class HerbloreAction extends SkillAction {
  const HerbloreAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.potionIds,
    required this.categoryId,
  }) : super(skill: Skill.herblore, duration: _herbloreDuration);

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
}
