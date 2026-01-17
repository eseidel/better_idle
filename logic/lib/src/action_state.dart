import 'dart:math';

import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/xp.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Mining-specific state for rock HP and respawn.
@immutable
class MiningState {
  const MiningState({
    this.totalHpLost = 0,
    this.respawnTicksRemaining,
    this.hpRegenTicksRemaining = 0,
  });

  const MiningState.empty() : this();

  factory MiningState.fromJson(Map<String, dynamic> json) {
    return MiningState(
      totalHpLost: json['totalHpLost'] as int? ?? 0,
      respawnTicksRemaining: json['respawnTicksRemaining'] as int?,
      hpRegenTicksRemaining: json['hpRegenTicksRemaining'] as int? ?? 0,
    );
  }

  /// Deserializes a [MiningState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static MiningState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return MiningState.fromJson(json as Map<String, dynamic>);
  }

  /// Gets the current HP of a mining node.
  int currentHp(MiningAction action, int masteryXp) {
    final masteryLevel = levelForXp(masteryXp);
    final maxHp = action.maxHpForMasteryLevel(masteryLevel);
    return max(0, maxHp - totalHpLost);
  }

  /// How much HP this mining node has lost.
  final int totalHpLost;

  /// How many ticks until this mining node respawns if depleted.
  final Tick? respawnTicksRemaining; // Null if not depleted

  /// How many ticks until this mining node regens 1 HP.
  final Tick hpRegenTicksRemaining; // Ticks until next HP regen

  /// Returns true if the node is currently depleted and not yet respawned.
  bool get isDepleted {
    final respawnTicks = respawnTicksRemaining;
    return respawnTicks != null && respawnTicks > 0;
  }

  MiningState copyWith({
    int? totalHpLost,
    Tick? respawnTicksRemaining,
    Tick? hpRegenTicksRemaining,
  }) {
    return MiningState(
      totalHpLost: totalHpLost ?? this.totalHpLost,
      respawnTicksRemaining:
          respawnTicksRemaining ?? this.respawnTicksRemaining,
      hpRegenTicksRemaining:
          hpRegenTicksRemaining ?? this.hpRegenTicksRemaining,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalHpLost': totalHpLost,
      'respawnTicksRemaining': respawnTicksRemaining,
      'hpRegenTicksRemaining': hpRegenTicksRemaining,
    };
  }
}

/// Spawn time for monsters.
const Duration monsterSpawnDuration = Duration(seconds: 3);

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
  factory CombatActionState.start(CombatAction action, Stats playerStats) {
    final playerAttackTicks = secondsToTicks(playerStats.attackSpeed);
    final monsterAttackTicks = secondsToTicks(action.stats.attackSpeed);
    return CombatActionState(
      monsterId: action.id,
      monsterHp: 0,
      playerAttackTicksRemaining: playerAttackTicks,
      monsterAttackTicksRemaining: monsterAttackTicks,
      spawnTicksRemaining: ticksFromDuration(monsterSpawnDuration),
    );
  }

  /// Start a new dungeon run, fighting monsters in order.
  factory CombatActionState.startDungeon(
    CombatAction firstMonster,
    Stats playerStats,
    MelvorId dungeonId,
  ) {
    final playerAttackTicks = secondsToTicks(playerStats.attackSpeed);
    final monsterAttackTicks = secondsToTicks(firstMonster.stats.attackSpeed);
    return CombatActionState(
      monsterId: firstMonster.id,
      monsterHp: 0,
      playerAttackTicksRemaining: playerAttackTicks,
      monsterAttackTicksRemaining: monsterAttackTicks,
      spawnTicksRemaining: ticksFromDuration(monsterSpawnDuration),
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
    this.mining,
    this.combat,
    this.selectedRecipeIndex,
  });

  const ActionState.empty() : this(masteryXp: 0);

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(
      masteryXp: json['masteryXp'] as int,
      cumulativeTicks: json['cumulativeTicks'] as int? ?? 0,
      mining: MiningState.maybeFromJson(json['mining']),
      combat: CombatActionState.maybeFromJson(json['combat']),
      selectedRecipeIndex: json['selectedRecipeIndex'] as int?,
    );
  }

  /// How much accumulated mastery xp this action has.
  final int masteryXp;

  /// Cumulative ticks spent performing this action.
  final int cumulativeTicks;

  /// Mining-specific state (null for non-mining actions).
  final MiningState? mining;

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
  int get masteryLevel => levelForXp(masteryXp);

  ActionState copyWith({
    int? masteryXp,
    int? cumulativeTicks,
    MiningState? mining,
    CombatActionState? combat,
    int? selectedRecipeIndex,
  }) {
    return ActionState(
      masteryXp: masteryXp ?? this.masteryXp,
      cumulativeTicks: cumulativeTicks ?? this.cumulativeTicks,
      mining: mining ?? this.mining,
      combat: combat ?? this.combat,
      selectedRecipeIndex: selectedRecipeIndex ?? this.selectedRecipeIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'masteryXp': masteryXp,
      'cumulativeTicks': cumulativeTicks,
      if (mining != null) 'mining': mining!.toJson(),
      if (combat != null) 'combat': combat!.toJson(),
      if (selectedRecipeIndex != null)
        'selectedRecipeIndex': selectedRecipeIndex,
    };
  }
}
