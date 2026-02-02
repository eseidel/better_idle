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

    // Parse tier for non-shard item cost calculation.
    final tier = json['tier'] as int? ?? 1;

    // Parse nonShardItemCosts as alternative recipes.
    // Each non-shard item becomes an alternative recipe with shards + item.
    // Non-shard item quantity = tier * 6 (per Melvor Idle mechanics).
    final nonShardItems = json['nonShardItemCosts'] as List<dynamic>? ?? [];
    List<AlternativeRecipe>? alternativeRecipes;
    final nonShardQuantity = tier * 6;

    if (nonShardItems.isNotEmpty) {
      alternativeRecipes = nonShardItems.map((itemIdJson) {
        final itemId = MelvorId.fromJsonWithNamespace(
          itemIdJson as String,
          defaultNamespace: namespace,
        );
        return AlternativeRecipe(
          inputs: {...shardInputs, itemId: nonShardQuantity},
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
      tier: tier,
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

  /// The summon/recipe ID for this familiar (e.g., "melvorF:GolbinThief").
  /// This is used for synergy lookups.
  MelvorId get summonId => id.localId;

  @override
  void onComplete(PostCompletionHandler handler) {
    handler.markTabletCrafted(productId);
  }
}

/// Unified registry for all summoning-related data.
@immutable
class SummoningRegistry {
  SummoningRegistry(List<SummoningAction> actions) : _actions = actions {
    _byId = {for (final a in _actions) a.id.localId: a};
    _byProductId = {for (final a in _actions) a.productId: a};
  }

  final List<SummoningAction> _actions;
  late final Map<MelvorId, SummoningAction> _byId;
  late final Map<MelvorId, SummoningAction> _byProductId;

  /// All summoning actions (familiars).
  List<SummoningAction> get actions => _actions;

  /// Look up a summoning action by its local ID.
  SummoningAction? byId(MelvorId localId) => _byId[localId];

  /// Finds the SummoningAction that produces a tablet with the given ID.
  /// Returns null if no matching action is found.
  SummoningAction? actionForTablet(MelvorId tabletId) => _byProductId[tabletId];

  /// Returns all summoning familiars that can have marks discovered while
  /// performing actions in the given skill.
  Iterable<SummoningAction> familiarsForSkill(Skill skill) {
    return _actions.where((action) => action.markSkillIds.contains(skill.id));
  }

  /// Returns true if the familiar (tablet) is relevant to the given skill.
  ///
  /// A familiar is relevant if the skill is in its markSkillIds.
  bool isFamiliarRelevantToSkill(MelvorId tabletId, Skill skill) {
    final action = actionForTablet(tabletId);
    if (action == null) return false;
    return action.markSkillIds.contains(skill.id);
  }

  /// Returns true if the familiar (tablet) is relevant to combat with the
  /// given combat type skills.
  ///
  /// [combatTypeSkills] should be the skills specific to the combat type
  /// (e.g., Attack/Strength for melee, Ranged for ranged, Magic for magic).
  ///
  /// A familiar is combat-relevant if any of its markSkillIds matches:
  /// - The combat type's specific skills
  /// - Universal combat skills (Defence, Hitpoints, Prayer, Slayer)
  bool isFamiliarRelevantToCombat(
    MelvorId tabletId,
    Set<Skill> combatTypeSkills,
  ) {
    final action = actionForTablet(tabletId);
    if (action == null) return false;

    // Check universal combat skills first
    for (final skill in Skill.universalCombatSkills) {
      if (action.markSkillIds.contains(skill.id)) return true;
    }

    // Check combat type specific skills
    for (final skill in combatTypeSkills) {
      if (action.markSkillIds.contains(skill.id)) return true;
    }

    return false;
  }
}
