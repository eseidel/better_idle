import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

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

/// A smithing action parsed from Melvor data.
///
/// Smithing actions consume ore/bars and produce equipment or bars.
@immutable
class SmithingAction extends SkillAction {
  const SmithingAction({
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

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return SmithingAction(
      id: ActionId(Skill.smithing.id, localId),
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
  @override
  final MelvorId? categoryId;
}

/// Unified registry for all smithing-related data.
@immutable
class SmithingRegistry {
  SmithingRegistry({
    required List<SmithingAction> actions,
    required List<SmithingCategory> categories,
  }) : _actions = actions,
       _categories = categories {
    _byId = {for (final a in _actions) a.id.localId: a};
    _categoryById = {for (final c in _categories) c.id: c};
  }

  final List<SmithingAction> _actions;
  final List<SmithingCategory> _categories;
  late final Map<MelvorId, SmithingAction> _byId;
  late final Map<MelvorId, SmithingCategory> _categoryById;

  /// All smithing actions.
  List<SmithingAction> get actions => _actions;

  /// All smithing categories.
  List<SmithingCategory> get categories => _categories;

  /// Look up a smithing action by its local ID.
  SmithingAction? byId(MelvorId localId) => _byId[localId];

  /// Returns a smithing category by ID, or null if not found.
  SmithingCategory? categoryById(MelvorId id) => _categoryById[id];
}
