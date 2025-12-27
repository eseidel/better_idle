import 'package:meta/meta.dart';

import 'action_id.dart';
import 'actions.dart';
import 'melvor_id.dart';

const _fletchingDuration = Duration(seconds: 2);

/// A fletching category parsed from Melvor data.
@immutable
class FletchingCategory {
  const FletchingCategory({
    required this.id,
    required this.name,
    required this.media,
  });

  factory FletchingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return FletchingCategory(
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

/// Registry for fletching categories.
@immutable
class FletchingCategoryRegistry {
  FletchingCategoryRegistry(List<FletchingCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<FletchingCategory> _categories;
  late final Map<MelvorId, FletchingCategory> _byId;

  /// Returns all fletching categories.
  List<FletchingCategory> get all => _categories;

  /// Returns a fletching category by ID, or null if not found.
  FletchingCategory? byId(MelvorId id) => _byId[id];
}

/// A fletching action parsed from Melvor data.
///
/// Fletching actions consume logs/materials and produce arrows, bows, etc.
@immutable
class FletchingAction extends SkillAction {
  FletchingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    super.alternativeRecipes,
    required this.productId,
    required this.baseQuantity,
    required this.categoryId,
  }) : super(skill: Skill.fletching, duration: _fletchingDuration);

  factory FletchingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productID'] as String,
      defaultNamespace: namespace,
    );
    final baseQuantity = json['baseQuantity'] as int? ?? 1;

    // Parse alternativeCosts (replaces itemCosts when present).
    final alternativeRecipes = parseAlternativeCosts(
      json,
      namespace: namespace,
    );

    // Parse item costs into inputs map (only if no alternativeCosts).
    final inputs = <MelvorId, int>{};
    if (alternativeRecipes == null) {
      final itemCosts = json['itemCosts'] as List<dynamic>? ?? [];
      for (final cost in itemCosts) {
        final costMap = cost as Map<String, dynamic>;
        final itemId = MelvorId.fromJsonWithNamespace(
          costMap['id'] as String,
          defaultNamespace: namespace,
        );
        final quantity = costMap['quantity'] as int;
        inputs[itemId] = quantity;
      }
    }

    // Assert that we don't have both itemCosts and alternativeCosts populated.
    assert(
      alternativeRecipes == null ||
          (json['itemCosts'] as List<dynamic>? ?? []).isEmpty,
      'Action cannot have both itemCosts and alternativeCosts',
    );

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return FletchingAction(
      id: ActionId(Skill.fletching.id, localId),
      name: productId.name,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: inputs,
      outputs: {productId: baseQuantity},
      alternativeRecipes: alternativeRecipes,
      productId: productId,
      baseQuantity: baseQuantity,
      categoryId: json['categoryID'] != null
          ? MelvorId.fromJsonWithNamespace(
              json['categoryID'] as String,
              defaultNamespace: namespace,
            )
          : null,
    );
  }

  /// The Melvor product ID (e.g., "melvorD:Bronze_Arrows").
  final MelvorId productId;

  /// Base quantity of items produced per fletching action.
  final int baseQuantity;

  /// The category ID (e.g., "melvorF:Arrows", "melvorF:Shortbows").
  final MelvorId? categoryId;
}
