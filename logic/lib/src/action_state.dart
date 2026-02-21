import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Base spawn time for monsters (3 seconds).
const Duration monsterSpawnDuration = Duration(seconds: 3);

/// Minimum monster spawn time (0.25 seconds = 250ms).
/// Even with maximum modifiers, spawn time cannot go below this.
const int minMonsterSpawnTicks = 3; // 0.25 seconds at 100ms/tick rounded up

/// Calculates the monster spawn ticks after applying modifiers.
///
/// [flatModifierMs] is the flatMonsterRespawnInterval modifier in milliseconds
/// (negative values reduce spawn time, e.g., -200 means -0.2s).
Tick calculateMonsterSpawnTicks(int flatModifierMs) {
  final baseMs = monsterSpawnDuration.inMilliseconds;
  final modifiedMs = baseMs + flatModifierMs;
  // Convert to ticks (100ms per tick), clamping to minimum
  final ticks = (modifiedMs / 100).ceil();
  return ticks.clamp(minMonsterSpawnTicks, 1000); // Max ~100 seconds
}

/// Combat-specific state for fighting a monster.
@immutable
class CombatActionState {
  const CombatActionState({
    required this.monsterId,
    required this.monsterHp,
    required this.playerAttackTicksRemaining,
    required this.monsterAttackTicksRemaining,
    this.spawnTicksRemaining,
    this.dungeonId,
    this.dungeonMonsterIndex,
  });

  /// Start a new combat against a monster, beginning with a spawn timer.
  ///
  /// [spawnTicks] is the number of ticks until the monster spawns,
  /// calculated using [calculateMonsterSpawnTicks] with modifiers.
  factory CombatActionState.start(
    CombatAction action,
    Stats playerStats, {
    required Tick spawnTicks,
  }) {
    final playerAttackTicks = secondsToTicks(playerStats.attackSpeed);
    final monsterAttackTicks = secondsToTicks(action.stats.attackSpeed);
    return CombatActionState(
      monsterId: action.id,
      monsterHp: 0,
      playerAttackTicksRemaining: playerAttackTicks,
      monsterAttackTicksRemaining: monsterAttackTicks,
      spawnTicksRemaining: spawnTicks,
    );
  }

  /// Start a new dungeon run, fighting monsters in order.
  ///
  /// [spawnTicks] is the number of ticks until the first monster spawns,
  /// calculated using [calculateMonsterSpawnTicks] with modifiers.
  factory CombatActionState.startDungeon(
    CombatAction firstMonster,
    Stats playerStats,
    MelvorId dungeonId, {
    required Tick spawnTicks,
  }) {
    final playerAttackTicks = secondsToTicks(playerStats.attackSpeed);
    final monsterAttackTicks = secondsToTicks(firstMonster.stats.attackSpeed);
    return CombatActionState(
      monsterId: firstMonster.id,
      monsterHp: 0,
      playerAttackTicksRemaining: playerAttackTicks,
      monsterAttackTicksRemaining: monsterAttackTicks,
      spawnTicksRemaining: spawnTicks,
      dungeonId: dungeonId,
      dungeonMonsterIndex: 0,
    );
  }

  factory CombatActionState.fromJson(Map<String, dynamic> json) {
    return CombatActionState(
      monsterId: ActionId.fromJson(json['monsterId'] as String),
      monsterHp: json['monsterHp'] as int,
      playerAttackTicksRemaining: json['playerAttackTicksRemaining'] as int,
      monsterAttackTicksRemaining: json['monsterAttackTicksRemaining'] as int,
      spawnTicksRemaining: json['spawnTicksRemaining'] as int?,
      dungeonId: json['dungeonId'] != null
          ? MelvorId.fromJson(json['dungeonId'] as String)
          : null,
      dungeonMonsterIndex: json['dungeonMonsterIndex'] as int?,
    );
  }

  /// Deserializes a [CombatActionState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static CombatActionState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return CombatActionState.fromJson(json as Map<String, dynamic>);
  }

  /// The ID of the monster being fought.
  final ActionId monsterId;
  final int monsterHp;
  final int playerAttackTicksRemaining;
  final int monsterAttackTicksRemaining;
  final int? spawnTicksRemaining;

  /// The dungeon ID if fighting in a dungeon (null for regular combat).
  final MelvorId? dungeonId;

  /// Current monster index in the dungeon (0-based). Null for regular combat.
  final int? dungeonMonsterIndex;

  bool get isSpawning => spawnTicksRemaining != null;

  /// Returns true if currently in a dungeon run.
  bool get isInDungeon => dungeonId != null;

  CombatActionState copyWith({
    ActionId? monsterId,
    int? monsterHp,
    int? playerAttackTicksRemaining,
    int? monsterAttackTicksRemaining,
    int? spawnTicksRemaining,
    MelvorId? dungeonId,
    int? dungeonMonsterIndex,
  }) {
    return CombatActionState(
      monsterId: monsterId ?? this.monsterId,
      monsterHp: monsterHp ?? this.monsterHp,
      playerAttackTicksRemaining:
          playerAttackTicksRemaining ?? this.playerAttackTicksRemaining,
      monsterAttackTicksRemaining:
          monsterAttackTicksRemaining ?? this.monsterAttackTicksRemaining,
      spawnTicksRemaining: spawnTicksRemaining ?? this.spawnTicksRemaining,
      dungeonId: dungeonId ?? this.dungeonId,
      dungeonMonsterIndex: dungeonMonsterIndex ?? this.dungeonMonsterIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monsterId': monsterId.toJson(),
      'monsterHp': monsterHp,
      'playerAttackTicksRemaining': playerAttackTicksRemaining,
      'monsterAttackTicksRemaining': monsterAttackTicksRemaining,
      'spawnTicksRemaining': spawnTicksRemaining,
      if (dungeonId != null) 'dungeonId': dungeonId!.toJson(),
      if (dungeonMonsterIndex != null)
        'dungeonMonsterIndex': dungeonMonsterIndex,
    };
  }
}

@immutable
sealed class RecipeSelection {
  const RecipeSelection();
}

/// This is used for actions without alternative recipes.
@immutable
class NoSelectedRecipe extends RecipeSelection {
  const NoSelectedRecipe();
}

/// This is used for actions with alternative recipes.
@immutable
class SelectedRecipe extends RecipeSelection {
  const SelectedRecipe({required this.index});
  final int index;
}

/// The serialized state of an Action in progress.
@immutable
class ActionState {
  const ActionState({
    required this.masteryXp,
    this.cumulativeTicks = 0,
    this.combat,
    this.selectedRecipeIndex,
  });

  const ActionState.empty() : this(masteryXp: 0);

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(
      masteryXp: json['masteryXp'] as int,
      cumulativeTicks: json['cumulativeTicks'] as int? ?? 0,
      combat: CombatActionState.maybeFromJson(json['combat']),
      selectedRecipeIndex: json['selectedRecipeIndex'] as int?,
    );
  }

  /// How much accumulated mastery xp this action has.
  final int masteryXp;

  /// Cumulative ticks spent performing this action.
  final int cumulativeTicks;

  /// Combat-specific state (null for non-combat actions).
  final CombatActionState? combat;

  /// The selected recipe index for actions with alternativeCosts.
  /// Null means no recipe has been selected, which can either be that
  /// this state is brand new and hasn't been written to disk yet, or that
  /// the action has no alternative recipes.
  /// Either way, the correct way to read this value is through recipeSelection.
  final int? selectedRecipeIndex;

  RecipeSelection recipeSelection(Action action) {
    if (action is SkillAction && action.hasAlternativeRecipes) {
      final existingIndex = selectedRecipeIndex;
      assert(
        existingIndex == null ||
            (existingIndex >= 0 &&
                existingIndex < action.alternativeRecipes!.length),
        'Selected recipe index $existingIndex '
        'is out of range for action ${action.id}',
      );
      return SelectedRecipe(index: selectedRecipeIndex ?? 0);
    }
    return const NoSelectedRecipe();
  }

  /// The mastery level for this action, derived from mastery XP.
  /// Capped at 99 even if XP exceeds the level 99 threshold.
  int get masteryLevel => levelForXp(masteryXp).clamp(1, 99);

  ActionState copyWith({
    int? masteryXp,
    int? cumulativeTicks,
    CombatActionState? combat,
    int? selectedRecipeIndex,
  }) {
    return ActionState(
      masteryXp: masteryXp ?? this.masteryXp,
      cumulativeTicks: cumulativeTicks ?? this.cumulativeTicks,
      combat: combat ?? this.combat,
      selectedRecipeIndex: selectedRecipeIndex ?? this.selectedRecipeIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'masteryXp': masteryXp,
      'cumulativeTicks': cumulativeTicks,
      if (combat != null) 'combat': combat!.toJson(),
      if (selectedRecipeIndex != null)
        'selectedRecipeIndex': selectedRecipeIndex,
    };
  }
}
