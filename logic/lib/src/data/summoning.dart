import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

const _summoningDuration = Duration(seconds: 5);

/// A summoning action parsed from Melvor data.
///
/// Summoning actions consume shards and an item to produce familiar tablets.
/// The nonShardItemCosts from JSON are converted to alternativeRecipes,
/// where each alternative uses the same shards plus one of the non-shard items.
@immutable
class SummoningAction extends SkillAction {
  const SummoningAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.outputs,
    required this.productId,
    required this.tier,
    required this.markMedia,
    required this.markSkillIds,
    super.alternativeRecipes,
  }) : super(skill: Skill.summoning, duration: _summoningDuration);

  factory SummoningAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productID'] as String,
      defaultNamespace: namespace,
    );
    final baseQuantity = json['baseQuantity'] as int? ?? 25;

    // Parse shard costs from itemCosts.
    final itemCosts = json['itemCosts'] as List<dynamic>? ?? [];
    final shardInputs = <MelvorId, int>{};
    for (final cost in itemCosts) {
      final costMap = cost as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = costMap['quantity'] as int;
      shardInputs[itemId] = quantity;
    }

    // Parse nonShardItemCosts as alternative recipes.
    // Each non-shard item becomes an alternative recipe with shards + 1 item.
    final nonShardItems = json['nonShardItemCosts'] as List<dynamic>? ?? [];
    List<AlternativeRecipe>? alternativeRecipes;

    if (nonShardItems.isNotEmpty) {
      alternativeRecipes = nonShardItems.map((itemIdJson) {
        final itemId = MelvorId.fromJsonWithNamespace(
          itemIdJson as String,
          defaultNamespace: namespace,
        );
        return AlternativeRecipe(
          inputs: {...shardInputs, itemId: 1},
          quantityMultiplier: 1,
        );
      }).toList();
    }

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse skillIDs - the skills where marks for this familiar can be found.
    final skillIdsJson = json['skillIDs'] as List<dynamic>? ?? [];
    final markSkillIds = skillIdsJson
        .map(
          (id) => MelvorId.fromJsonWithNamespace(
            id as String,
            defaultNamespace: namespace,
          ),
        )
        .toList();

    // For display, use shards as base inputs (first alternative is default).
    final baseInputs =
        alternativeRecipes != null && alternativeRecipes.isNotEmpty
        ? alternativeRecipes.first.inputs
        : shardInputs;

    return SummoningAction(
      id: ActionId(Skill.summoning.id, localId),
      name: productId.name,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: baseInputs,
      outputs: {productId: baseQuantity},
      alternativeRecipes: alternativeRecipes,
      productId: productId,
      tier: json['tier'] as int? ?? 1,
      markMedia: json['markMedia'] as String?,
      markSkillIds: markSkillIds,
    );
  }

  /// The Melvor product ID (e.g., "melvorF:Summoning_Familiar_Golbin_Thief").
  final MelvorId productId;

  /// The summoning tier (1, 2, or 3).
  final int tier;

  /// Media path for the summoning mark icon.
  final String? markMedia;

  /// The skill IDs that can discover marks for this familiar.
  /// When performing actions in these skills, players have a chance to
  /// discover marks for this familiar.
  final List<MelvorId> markSkillIds;
}
