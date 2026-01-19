import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

const _runecraftingDuration = Duration(seconds: 2);

/// A runecrafting category parsed from Melvor data.
@immutable
class RunecraftingCategory {
  const RunecraftingCategory({
    required this.id,
    required this.name,
    required this.media,
  });

  factory RunecraftingCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return RunecraftingCategory(
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

/// A runecrafting action parsed from Melvor data.
///
/// Runecrafting actions consume rune essence and produce runes, staves,
/// and magical gear.
@immutable
class RunecraftingAction extends SkillAction {
  const RunecraftingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.baseQuantity,
    required this.categoryId,
  }) : super(skill: Skill.runecrafting, duration: _runecraftingDuration);

  factory RunecraftingAction.fromJson(
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
    return RunecraftingAction(
      id: ActionId(Skill.runecrafting.id, localId),
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

  /// The Melvor product ID (e.g., "melvorD:Air_Rune").
  final MelvorId productId;

  /// Base quantity of items produced per runecrafting action.
  final int baseQuantity;

  /// The category ID ("melvorF:StandardRunes", "melvorF:CombinationRunes").
  @override
  final MelvorId? categoryId;
}

/// Unified registry for all runecrafting-related data.
@immutable
class RunecraftingRegistry {
  RunecraftingRegistry({
    required List<RunecraftingAction> actions,
    required List<RunecraftingCategory> categories,
  }) : _actions = actions,
       _categories = categories {
    _byId = {for (final a in _actions) a.id.localId: a};
    _categoryById = {for (final c in _categories) c.id: c};
  }

  final List<RunecraftingAction> _actions;
  final List<RunecraftingCategory> _categories;
  late final Map<MelvorId, RunecraftingAction> _byId;
  late final Map<MelvorId, RunecraftingCategory> _categoryById;

  /// All runecrafting actions.
  List<RunecraftingAction> get actions => _actions;

  /// All runecrafting categories.
  List<RunecraftingCategory> get categories => _categories;

  /// Look up a runecrafting action by its local ID.
  RunecraftingAction? byId(MelvorId localId) => _byId[localId];

  /// Returns a runecrafting category by ID, or null if not found.
  RunecraftingCategory? categoryById(MelvorId id) => _categoryById[id];
}
