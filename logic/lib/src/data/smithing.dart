import 'package:meta/meta.dart';

import 'actions.dart';
import 'melvor_id.dart';

const _smithingDuration = Duration(seconds: 2);

/// A smithing category parsed from Melvor data.
@immutable
class SmithingCategory {
  const SmithingCategory({
    required this.id,
    required this.name,
    required this.media,
  });

  factory SmithingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return SmithingCategory(
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

  @override
  String toString() => name;
}

/// Registry for smithing categories.
class SmithingCategoryRegistry {
  SmithingCategoryRegistry(List<SmithingCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<SmithingCategory> _categories;
  late final Map<MelvorId, SmithingCategory> _byId;

  /// Returns all smithing categories.
  List<SmithingCategory> get all => _categories;

  /// Returns a smithing category by ID, or null if not found.
  SmithingCategory? byId(MelvorId id) => _byId[id];
}

/// A smithing action parsed from Melvor data.
///
/// Smithing actions consume ore/bars and produce equipment or bars.
@immutable
class SmithingAction extends SkillAction {
  SmithingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.baseQuantity,
    required this.categoryId,
  }) : super(skill: Skill.smithing, duration: _smithingDuration);

  factory SmithingAction.fromJson(
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

    return SmithingAction(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
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

  /// The Melvor product ID (e.g., "melvorD:Bronze_Bar").
  final MelvorId productId;

  /// Base quantity of items produced per smithing action.
  final int baseQuantity;

  /// The category ID (e.g., "melvorD:Bars", "melvorD:Weapons").
  final MelvorId? categoryId;
}
