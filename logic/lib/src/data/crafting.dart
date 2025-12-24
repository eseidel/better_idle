import 'package:meta/meta.dart';

import 'action_id.dart';
import 'actions.dart';
import 'melvor_id.dart';

const _craftingDuration = Duration(seconds: 2);

/// A crafting category parsed from Melvor data.
@immutable
class CraftingCategory {
  const CraftingCategory({
    required this.id,
    required this.name,
    required this.media,
  });

  factory CraftingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return CraftingCategory(
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

/// Registry for crafting categories.
class CraftingCategoryRegistry {
  CraftingCategoryRegistry(List<CraftingCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<CraftingCategory> _categories;
  late final Map<MelvorId, CraftingCategory> _byId;

  /// Returns all crafting categories.
  List<CraftingCategory> get all => _categories;

  /// Returns a crafting category by ID, or null if not found.
  CraftingCategory? byId(MelvorId id) => _byId[id];
}

/// A crafting action parsed from Melvor data.
///
/// Crafting actions consume materials and produce items like leather armor,
/// jewelry, and other craftable goods.
@immutable
class CraftingAction extends SkillAction {
  CraftingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.baseQuantity,
    required this.categoryId,
  }) : super(skill: Skill.crafting, duration: _craftingDuration);

  factory CraftingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productID'] as String,
      defaultNamespace: namespace,
    );
    final baseQuantity = json['baseQuantity'] as int? ?? 1;

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

    return CraftingAction(
      id: ActionId(Skill.crafting.id, json['id'] as String),
      name: productId.name,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: inputs,
      outputs: {productId: baseQuantity},
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

  /// The Melvor product ID (e.g., "melvorD:Leather_Boots").
  final MelvorId productId;

  /// Base quantity of items produced per crafting action.
  final int baseQuantity;

  /// The category ID (e.g., "melvorD:Leather", "melvorD:Dragonhide").
  final MelvorId? categoryId;
}
