import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/combat.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/mining.dart';
import 'package:logic/src/data/summoning.dart';
import 'package:logic/src/data/thieving.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

export 'package:logic/src/action_state.dart'
    show NoSelectedRecipe, RecipeSelection, SelectedRecipe;

export 'agility.dart';
export 'alt_magic.dart';
export 'astrology.dart';
export 'combat.dart';
export 'cooking.dart';
export 'crafting.dart';
export 'farming.dart';
export 'firemaking.dart';
export 'fishing.dart';
export 'fletching.dart';
export 'herblore.dart';
export 'items.dart';
export 'mining.dart';
export 'runecrafting.dart';
export 'smithing.dart';
export 'summoning.dart';
export 'thieving.dart';
export 'woodcutting.dart';

/// Hard-coded list of skills.  We sometimes wish to refer to a skill in code
/// this allows us to do that at compile time rather than at runtime.
/// These are essentially "Action Types" in the sense that they are the types
/// of actions that can be performed by the player.
enum Skill {
  // Combat skills
  combat('Combat'),
  hitpoints('Hitpoints'),
  attack('Attack'),
  strength('Strength'),
  defence('Defence'),
  ranged('Ranged'),
  magic('Magic'),
  prayer('Prayer'),
  slayer('Slayer'),
  // Passive skills
  town('Township'),
  farming('Farming'),

  // Other skills
  woodcutting('Woodcutting'),
  firemaking('Firemaking'),
  fishing('Fishing'),
  cooking('Cooking'),
  mining('Mining'),
  smithing('Smithing'),
  thieving('Thieving'),
  fletching('Fletching'),
  crafting('Crafting'),
  herblore('Herblore'),
  runecrafting('Runecrafting'),
  agility('Agility'),
  summoning('Summoning'),
  astrology('Astrology'),
  altMagic('Alt. Magic');

  const Skill(this.name);

  /// Returns the skill for the given name (e.g., "Woodcutting").
  /// Used for deserializing saved game state. Throws if not recognized.
  factory Skill.fromName(String name) {
    return Skill.values.firstWhere((e) => e.name == name);
  }

  /// Returns the skill for the given ID.
  /// Throws if the skill is not recognized.
  factory Skill.fromId(MelvorId id) {
    return values.firstWhere(
      (e) => e.id == id,
      orElse: () => throw ArgumentError('Unknown skill ID: $id'),
    );
  }

  final String name;

  /// The Melvor ID for this skill (e.g., melvorD:Woodcutting).
  /// All skills use the melvorD namespace (e.g., melvorD:Woodcutting).
  MelvorId get id => MelvorId('melvorD:$name');

  /// Skills that have actions requiring inputs (consuming skills).
  /// For solver: these skills need inventory tracking to properly plan
  /// input gathering before training the skill.
  static const Set<Skill> consumingSkills = {
    Skill.firemaking,
    Skill.cooking,
    Skill.smithing,
    Skill.fletching,
    Skill.crafting,
    Skill.herblore,
    Skill.runecrafting,
    Skill.agility,
    Skill.summoning,
    Skill.altMagic,
  };

  /// Returns true if this skill requires inputs to train.
  bool get isConsuming => consumingSkills.contains(this);

  /// Combat-related skills that familiars can provide bonuses for.
  static const Set<Skill> combatSkills = {
    Skill.attack,
    Skill.strength,
    Skill.defence,
    Skill.hitpoints,
    Skill.ranged,
    Skill.magic,
    Skill.prayer,
    Skill.slayer,
  };

  /// Skills that apply to all combat (Defence, Hitpoints, Prayer, Slayer).
  /// These are used regardless of CombatType.
  static const Set<Skill> universalCombatSkills = {
    Skill.defence,
    Skill.hitpoints,
    Skill.prayer,
    Skill.slayer,
  };

  /// Returns true if this is a combat-related skill.
  bool get isCombatSkill => combatSkills.contains(this);

  /// Returns the asset path for this skill's icon.
  String get assetPath {
    final lower = name.toLowerCase();
    if (this == Skill.altMagic) {
      return 'assets/media/skills/magic/magic.png';
    }
    return 'assets/media/skills/$lower/$lower.png';
  }
}

/// Base class for all actions that can occupy the "active" slot.
/// Subclasses: SkillAction (duration-based with xp/outputs) and CombatAction.
@immutable
abstract class Action {
  const Action({required this.id, required this.name, required this.skill});

  final ActionId id;

  final String name;
  final Skill skill;
}

/// Represents an alternative recipe for a SkillAction.
/// Used when Melvor data has `alternativeCosts` instead of `itemCosts`.
/// Each alternative has different input costs and may produce different
/// output quantities via the quantityMultiplier.
@immutable
class AlternativeRecipe {
  const AlternativeRecipe({
    required this.inputs,
    required this.quantityMultiplier,
  });

  /// The item costs for this recipe variant.
  final Map<MelvorId, int> inputs;

  /// Multiplier applied to base output quantity.
  final int quantityMultiplier;
}

/// Parses alternativeCosts from Melvor JSON.
/// Returns null if not present.
List<AlternativeRecipe>? parseAlternativeCosts(
  Map<String, dynamic> json, {
  required String namespace,
}) {
  final alternatives = json['alternativeCosts'] as List<dynamic>?;
  if (alternatives == null || alternatives.isEmpty) return null;

  return alternatives.map((alt) {
    final altMap = alt as Map<String, dynamic>;
    final itemCosts = altMap['itemCosts'] as List<dynamic>? ?? [];
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
    return AlternativeRecipe(
      inputs: inputs,
      quantityMultiplier: altMap['quantityMultiplier'] as int? ?? 1,
    );
  }).toList();
}

List<Droppable> defaultRewards(SkillAction action, RecipeSelection selection) {
  final outputs = action.outputsForRecipe(selection);
  return [...outputs.entries.map((e) => Drop(e.key, count: e.value))];
}

/// A skill-based action that completes after a duration, granting xp and drops.
/// This covers woodcutting, firemaking, fishing, smithing, and mining actions.
@immutable
class SkillAction extends Action {
  const SkillAction({
    required super.id,
    required super.skill,
    required super.name,
    required Duration duration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.alternativeRecipes,
    this.rewardsAtLevel = defaultRewards,
  }) : minDuration = duration,
       maxDuration = duration;

  const SkillAction.ranged({
    required super.id,
    required super.skill,
    required super.name,
    required this.minDuration,
    required this.maxDuration,
    required this.xp,
    required this.unlockLevel,
    this.outputs = const {},
    this.inputs = const {},
    this.alternativeRecipes,
    this.rewardsAtLevel = defaultRewards,
  });

  final int xp;
  final int unlockLevel;
  final Duration minDuration;
  final Duration maxDuration;
  final Map<MelvorId, int> inputs;
  final Map<MelvorId, int> outputs;

  /// The category ID for this action, if applicable.
  /// Used for category-scoped modifiers (e.g., cooking Fire/Furnace/Pot).
  /// Override in subclasses that have categories.
  MelvorId? get categoryId => null;

  double expectedOutputPerTick(MelvorId itemId) {
    return (outputs[itemId] ?? 0) / ticksFromDuration(meanDuration).toDouble();
  }

  /// Returns how many times this action must run to produce [quantity] of
  /// [itemId].
  int actionsNeededForOutput(MelvorId itemId, int quantity) {
    final outputsPerAction = outputs[itemId] ?? 1;
    return (quantity / outputsPerAction).ceil();
  }

  /// Alternative recipes (from alternativeCosts in Melvor JSON).
  /// When non-null, this replaces the `inputs` field - the user selects
  /// which recipe to use, and each recipe may have a quantity multiplier.
  final List<AlternativeRecipe>? alternativeRecipes;

  /// Function that returns drops for this action based on recipe selection.
  final List<Droppable> Function(SkillAction action, RecipeSelection selection)
  rewardsAtLevel;

  /// Whether this action has alternative recipes to choose from.
  bool get hasAlternativeRecipes =>
      alternativeRecipes != null && alternativeRecipes!.isNotEmpty;

  /// Returns the inputs for the given recipe selection.
  /// For NoSelectedRecipe, returns the base inputs.
  /// For SelectedRecipe, returns inputs from the selected alternative recipe.
  Map<MelvorId, int> inputsForRecipe(RecipeSelection selection) {
    return switch (selection) {
      NoSelectedRecipe() => inputs,
      SelectedRecipe(:final index) =>
        alternativeRecipes![index.clamp(0, alternativeRecipes!.length - 1)]
            .inputs,
    };
  }

  /// Returns the outputs for the given recipe selection.
  /// For NoSelectedRecipe, returns the base outputs.
  /// For SelectedRecipe, applies quantityMultiplier from the selected recipe.
  Map<MelvorId, int> outputsForRecipe(RecipeSelection selection) {
    return switch (selection) {
      NoSelectedRecipe() => outputs,
      SelectedRecipe(:final index) => () {
        final recipe =
            alternativeRecipes![index.clamp(0, alternativeRecipes!.length - 1)];
        return outputs.map(
          (key, value) => MapEntry(key, value * recipe.quantityMultiplier),
        );
      }(),
    };
  }

  bool get isFixedDuration => minDuration == maxDuration;

  Duration get meanDuration {
    final totalMicroseconds =
        (minDuration.inMicroseconds + maxDuration.inMicroseconds) ~/ 2;
    return Duration(microseconds: totalMicroseconds);
  }

  Tick rollDuration(Random random) {
    if (isFixedDuration) {
      return ticksFromDuration(minDuration);
    }
    final minTicks = ticksFromDuration(minDuration);
    final maxTicks = ticksFromDuration(maxDuration);
    // random.nextInt(n) creates [0, n-1] so use +1 to produce a uniform random
    // value between minTicks and maxTicks (inclusive).
    return minTicks + random.nextInt((maxTicks - minTicks) + 1);
  }

  /// Returns the drops for this action given the recipe selection.
  List<Droppable> rewardsForSelection(RecipeSelection selection) =>
      rewardsAtLevel(this, selection);
}

// Skill-level drops: shared across all actions in a skill.
// This can include both simple Drops and DropTables.
final skillDrops = <Skill, List<Droppable>>{
  Skill.woodcutting: [const Drop(MelvorId('melvorD:Bird_Nest'), rate: 0.005)],
  Skill.firemaking: [
    const Drop(MelvorId('melvorD:Coal_Ore'), rate: 0.40),
    const Drop(MelvorId('melvorF:Ash'), rate: 0.20),
    // Missing Charcoal, Generous Fire Spirit
  ],
  Skill.mining: [miningGemTable],
  Skill.thieving: [
    const Drop(MelvorId('melvorF:Bobbys_Pocket'), rate: 1 / 120),
  ],
};

class ActionRegistry {
  ActionRegistry(this.all) {
    _byId = {for (final action in all) action.id: action};
    _bySkillAndNameMap = {};
    for (final action in all) {
      // Use action.id.skillId rather than action.skill.id because they can
      // differ (e.g. CombatAction has id.skillId=combat but skill=attack).
      _bySkillAndNameMap
          .putIfAbsent(action.id.skillId, () => {})
          .putIfAbsent(action.name, () => action);
    }
  }

  final List<Action> all;
  late final Map<ActionId, Action> _byId;
  late final Map<MelvorId, Map<String, Action>> _bySkillAndNameMap;

  /// Returns an Action by id, or throws a StateError if not found.
  Action byId(ActionId id) {
    final action = _byId[id];
    if (action == null) {
      throw StateError('Missing action with id: $id');
    }
    return action;
  }

  /// Returns all skill actions for a given skill.
  Iterable<SkillAction> forSkill(Skill skill) {
    return all.whereType<SkillAction>().where(
      (action) => action.skill == skill,
    );
  }

  Action _bySkillAndName(Skill skill, String name) {
    final byName = _bySkillAndNameMap[skill.id];
    if (byName == null) {
      final names = _bySkillAndNameMap.keys.join(', ');
      throw StateError('Missing actions for skill: $skill. Available: $names');
    }
    final action = byName[name];
    if (action == null) {
      final names = byName.keys.join(', ');
      throw StateError(
        'Missing action with skill: $skill and name: $name. Available: $names',
      );
    }
    return action;
  }

  CombatAction combatWithId(MelvorId id) =>
      _byId[ActionId(Skill.combat.id, id)]! as CombatAction;

  @visibleForTesting
  SkillAction woodcutting(String name) =>
      _bySkillAndName(Skill.woodcutting, name) as SkillAction;

  @visibleForTesting
  MiningAction mining(String name) =>
      _bySkillAndName(Skill.mining, name) as MiningAction;

  @visibleForTesting
  SkillAction firemaking(String name) =>
      _bySkillAndName(Skill.firemaking, name) as SkillAction;

  @visibleForTesting
  SkillAction fishing(String name) =>
      _bySkillAndName(Skill.fishing, name) as SkillAction;

  @visibleForTesting
  CombatAction combat(String name) =>
      _bySkillAndName(Skill.combat, name) as CombatAction;

  @visibleForTesting
  ThievingAction thieving(String name) =>
      _bySkillAndName(Skill.thieving, name) as ThievingAction;

  @visibleForTesting
  SkillAction smithing(String name) =>
      _bySkillAndName(Skill.smithing, name) as SkillAction;

  /// Returns all summoning familiars that can have marks discovered while
  /// performing actions in the given skill.
  Iterable<SummoningAction> summoningFamiliarsForSkill(Skill skill) {
    return forSkill(Skill.summoning).whereType<SummoningAction>().where(
      (action) => action.markSkillIds.contains(skill.id),
    );
  }

  /// Finds the SummoningAction that produces a tablet with the given ID.
  /// Returns null if no matching action is found.
  SummoningAction? summoningActionForTablet(MelvorId tabletId) {
    for (final action in forSkill(Skill.summoning)) {
      if (action is SummoningAction && action.productId == tabletId) {
        return action;
      }
    }
    return null;
  }

  /// Returns true if the familiar (tablet) is relevant to the given skill.
  ///
  /// A familiar is relevant if the skill is in its markSkillIds.
  bool isFamiliarRelevantToSkill(MelvorId tabletId, Skill skill) {
    final action = summoningActionForTablet(tabletId);
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
    final action = summoningActionForTablet(tabletId);
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

class DropsRegistry {
  DropsRegistry(this._skillDrops);

  final Map<Skill, List<Droppable>> _skillDrops;

  /// Returns all skill-level drops for a given skill.
  List<Droppable> forSkill(Skill skill) {
    return _skillDrops[skill] ?? [];
  }

  /// Returns all drops that should be processed when a skill action completes.
  /// This combines action-level drops (from the action), skill-level drops,
  /// and global drops into a single list. Includes both simple Drops and
  /// DropTables, which are processed uniformly via Droppable.roll().
  /// Note: Only SkillActions have rewards - CombatActions handle drops
  /// differently.
  List<Droppable> allDropsForAction(
    SkillAction action,
    RecipeSelection selection,
  ) {
    return [
      ...action.rewardsForSelection(selection),
      ...forSkill(action.skill), // Skill-level drops (may include DropTables)
      // Missing global drops.
    ];
  }
}
