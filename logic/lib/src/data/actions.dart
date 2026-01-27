import 'dart:math';

import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/fishing.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/mining.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/modifier_names.dart';
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

  /// Returns the item doubling probability (0.0-1.0) for this action.
  ///
  /// Queries the skillItemDoublingChance modifier with the action's skill,
  /// action ID, and category, then converts from percentage to probability.
  double doublingChance(ModifierAccessors modifiers) {
    return (modifiers.skillItemDoublingChance(
              skillId: skill.id,
              actionId: id.localId,
              categoryId: categoryId,
            ) /
            100.0)
        .clamp(0.0, 1.0);
  }
}

class DropsRegistry {
  DropsRegistry(
    this._skillDrops, {
    required this.miningGems,
    this.fishingJunk,
    this.fishingSpecial,
  });

  final Map<Skill, List<Droppable>> _skillDrops;

  /// The gem drop for mining (only applies to rocks with giveGems: true).
  final Droppable miningGems;

  /// The junk drop table for fishing (shared across all areas).
  final DropTable? fishingJunk;

  /// The special drop table for fishing (shared across all areas).
  final DropTable? fishingSpecial;

  /// Returns all skill-level drops for a given skill.
  List<Droppable> forSkill(Skill skill) {
    return _skillDrops[skill] ?? [];
  }

  /// Returns the mastery token drop for a skill, or null if the skill
  /// doesn't have mastery tokens (combat skills, Township, Alt. Magic).
  MasteryTokenDrop? masteryTokenForSkill(Skill skill) {
    if (!MasteryTokenDrop.skillHasMasteryToken(skill)) {
      return null;
    }
    return MasteryTokenDrop(skill: skill);
  }

  /// Returns all drops that should be processed when a skill action completes.
  /// This combines action-level drops (from the action), skill-level drops,
  /// and global drops into a single list. Includes both simple Drops and
  /// DropTables, which are processed uniformly via Droppable.roll().
  /// Note: Only SkillActions have rewards - CombatActions handle drops
  /// differently.
  ///
  /// Mastery token drops are NOT included here because they require context
  /// (unlocked action count) to roll. They are handled separately in
  /// rollAndCollectDrops.
  List<Droppable> allDropsForAction(
    SkillAction action,
    RecipeSelection selection,
  ) {
    return [
      ...action.rewardsForSelection(selection),
      ...forSkill(action.skill), // Skill-level drops (may include DropTables)
      if (action is MiningAction && action.giveGems) miningGems,
      // Fishing junk/special drops based on area's chances.
      if (action is FishingAction) ..._fishingDrops(action),
    ];
  }

  /// Returns fishing junk/special drops for the given action's area.
  List<Droppable> _fishingDrops(FishingAction action) {
    final area = action.area;
    return [
      if (fishingJunk != null && area.junkChance > 0)
        DropChance(fishingJunk!, rate: area.junkChance),
      if (fishingSpecial != null && area.specialChance > 0)
        DropChance(fishingSpecial!, rate: area.specialChance),
    ];
  }
}
