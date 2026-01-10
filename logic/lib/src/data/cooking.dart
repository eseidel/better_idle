import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A cooking category (Fire, Furnace, Pot) parsed from Melvor data.
///
/// Categories define the cooking equipment types and their upgrade chains.
@immutable
class CookingCategory {
  const CookingCategory({
    required this.id,
    required this.name,
    required this.media,
    required this.shopUpgradeIds,
    required this.upgradeRequired,
  });

  factory CookingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final shopUpgradeIdsJson = json['shopUpgradeIDs'] as List<dynamic>? ?? [];
    final shopUpgradeIds = shopUpgradeIdsJson
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    return CookingCategory(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      media: json['media'] as String,
      shopUpgradeIds: shopUpgradeIds,
      upgradeRequired: json['upgradeRequired'] as bool? ?? false,
    );
  }

  /// The category ID (e.g., "melvorD:Fire").
  final MelvorId id;

  /// Display name (e.g., "Basic" for fire, "Furnace Required" for furnace).
  final String name;

  /// Asset path for the category icon.
  final String media;

  /// Ordered list of shop upgrade IDs for this category.
  /// The order in the data is from highest to lowest tier.
  final List<MelvorId> shopUpgradeIds;

  /// Whether an upgrade is required to use this category.
  /// Fire is false (basic fire available by default), Furnace/Pot are true.
  final bool upgradeRequired;

  @override
  String toString() => name;
}

/// Registry for cooking categories.
@immutable
class CookingCategoryRegistry {
  CookingCategoryRegistry(List<CookingCategory> categories)
    : _categories = categories {
    _byId = {for (final category in _categories) category.id: category};
  }

  final List<CookingCategory> _categories;
  late final Map<MelvorId, CookingCategory> _byId;

  /// Returns all cooking categories.
  List<CookingCategory> get all => _categories;

  /// Returns a cooking category by ID, or null if not found.
  CookingCategory? byId(MelvorId id) => _byId[id];
}

/// A cooking action parsed from Melvor data.
///
/// Cooking actions consume raw food and produce cooked food.
/// They can also produce "perfect" versions of the food.
@immutable
class CookingAction extends SkillAction {
  const CookingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required super.duration,
    required this.productId,
    required this.perfectCookId,
    required this.categoryId,
    required this.subcategoryId,
    required this.baseQuantity,
  }) : super(skill: Skill.cooking);

  factory CookingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productID'] as String,
      defaultNamespace: namespace,
    );
    final perfectCookId = json['perfectCookID'] != null
        ? MelvorId.fromJsonWithNamespace(
            json['perfectCookID'] as String,
            defaultNamespace: namespace,
          )
        : null;
    final baseInterval = json['baseInterval'] as int;
    final baseQuantity = json['baseQuantity'] as int? ?? 1;

    // Parse item costs as inputs.
    final itemCosts = json['itemCosts'] as List<dynamic>? ?? [];
    final inputs = <MelvorId, int>{};
    for (final cost in itemCosts) {
      final costMap = cost as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      inputs[itemId] = costMap['quantity'] as int;
    }

    // Parse category and subcategory.
    final categoryId = json['categoryID'] != null
        ? MelvorId.fromJsonWithNamespace(
            json['categoryID'] as String,
            defaultNamespace: namespace,
          )
        : null;
    final subcategoryId = json['subcategoryID'] != null
        ? MelvorId.fromJsonWithNamespace(
            json['subcategoryID'] as String,
            defaultNamespace: namespace,
          )
        : null;

    // Use the product name as the action name.
    final name = productId.name;

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return CookingAction(
      id: ActionId(Skill.cooking.id, localId),
      name: name,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: inputs,
      outputs: {productId: baseQuantity},
      duration: Duration(milliseconds: baseInterval),
      productId: productId,
      perfectCookId: perfectCookId,
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      baseQuantity: baseQuantity,
    );
  }

  /// The Melvor product ID (e.g., "melvorD:Shrimp").
  final MelvorId productId;

  /// The Melvor ID for the perfect cook version (e.g. "melvorD:Shrimp_Perfect")
  final MelvorId? perfectCookId;

  /// The cooking category (e.g., "melvorD:Fire").
  @override
  final MelvorId? categoryId;

  /// The cooking subcategory (e.g., "melvorD:Fish").
  final MelvorId? subcategoryId;

  /// Base quantity produced per action.
  final int baseQuantity;

  /// Returns true if this cooking action belongs to the specified category.
  ///
  /// Categories are: Fire, Furnace, Pot (matched by localId).
  bool isInCategory(String categoryLocalId) {
    return categoryId?.localId == categoryLocalId;
  }
}
