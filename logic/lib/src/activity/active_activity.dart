import 'package:logic/src/activity/combat_context.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// Base class for tracking the currently active activity.
///
/// Provides a type-safe model:
/// - [SkillActivity] for skill-based actions (woodcutting, mining, etc.)
/// - [CombatActivity] for combat (monsters, dungeons)
///
/// The key insight is that switching between skills is a top-level state
/// change, while switching within a skill (e.g., different recipes, different
/// monsters in a dungeon) is sub-state that doesn't change the activity
/// identity.
@immutable
sealed class ActiveActivity {
  const ActiveActivity({required this.progressTicks, required this.totalTicks});

  /// How many ticks have been spent on the current action/activity.
  final Tick progressTicks;

  /// Total ticks needed to complete the current action (for skill actions).
  /// For combat, this represents the attack timer.
  final Tick totalTicks;

  /// How many ticks remain until the current action completes.
  Tick get remainingTicks => totalTicks - progressTicks;

  /// Creates a copy with updated progress.
  ActiveActivity withProgress({required Tick progressTicks});

  /// Serializes the activity to JSON.
  Map<String, dynamic> toJson();

  /// Deserializes an activity from JSON.
  static ActiveActivity fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'skill' => SkillActivity.fromJson(json),
      'combat' => CombatActivity.fromJson(json),
      _ => throw ArgumentError('Unknown activity type: $type'),
    };
  }

  /// Deserializes an activity from JSON, returning null if [json] is null.
  static ActiveActivity? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return fromJson(json as Map<String, dynamic>);
  }
}

/// Activity state for performing a skill action.
///
/// This represents actively performing a skill action like woodcutting,
/// mining, cooking, etc. The [skill] identifies which skill is active,
/// and [actionId] identifies the specific action within that skill.
///
/// Recipe selection for actions with alternative costs is stored here
/// rather than in a separate map, keeping all activity state together.
@immutable
class SkillActivity extends ActiveActivity {
  const SkillActivity({
    required this.skill,
    required this.actionId,
    required super.progressTicks,
    required super.totalTicks,
    this.selectedRecipeIndex,
  });

  factory SkillActivity.fromJson(Map<String, dynamic> json) {
    return SkillActivity(
      skill: Skill.values.firstWhere((s) => s.id.toJson() == json['skill']),
      actionId: MelvorId.fromJson(json['actionId'] as String),
      progressTicks: json['progressTicks'] as int,
      totalTicks: json['totalTicks'] as int,
      selectedRecipeIndex: json['selectedRecipeIndex'] as int?,
    );
  }

  /// The skill being performed.
  final Skill skill;

  /// The specific action within the skill (e.g., Oak_Tree for Woodcutting).
  final MelvorId actionId;

  /// Selected recipe index for actions with alternative costs.
  /// Null if the action has no alternatives or the default is selected.
  final int? selectedRecipeIndex;

  @override
  SkillActivity withProgress({required Tick progressTicks}) {
    return SkillActivity(
      skill: skill,
      actionId: actionId,
      progressTicks: progressTicks,
      totalTicks: totalTicks,
      selectedRecipeIndex: selectedRecipeIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'skill',
      'skill': skill.id.toJson(),
      'actionId': actionId.toJson(),
      'progressTicks': progressTicks,
      'totalTicks': totalTicks,
      if (selectedRecipeIndex != null)
        'selectedRecipeIndex': selectedRecipeIndex,
    };
  }
}

/// Activity state for combat (monsters and dungeons).
///
/// This represents actively fighting, either a single monster or
/// progressing through a dungeon. The [context] identifies what type
/// of combat we're in, and [progress] tracks the combat state.
@immutable
class CombatActivity extends ActiveActivity {
  const CombatActivity({
    required this.context,
    required this.progress,
    required super.progressTicks,
    required super.totalTicks,
  });

  factory CombatActivity.fromJson(Map<String, dynamic> json) {
    return CombatActivity(
      context: CombatContext.fromJson(json['context'] as Map<String, dynamic>),
      progress: CombatProgressState.fromJson(
        json['progress'] as Map<String, dynamic>,
      ),
      progressTicks: json['progressTicks'] as int,
      totalTicks: json['totalTicks'] as int,
    );
  }

  /// The combat context (monster, dungeon, etc.).
  final CombatContext context;

  /// Combat progress state (HP, attack timers, etc.).
  final CombatProgressState progress;

  @override
  CombatActivity withProgress({required Tick progressTicks}) {
    return CombatActivity(
      context: context,
      progress: progress,
      progressTicks: progressTicks,
      totalTicks: totalTicks,
    );
  }

  CombatActivity copyWith({
    CombatContext? context,
    CombatProgressState? progress,
    Tick? progressTicks,
    Tick? totalTicks,
  }) {
    return CombatActivity(
      context: context ?? this.context,
      progress: progress ?? this.progress,
      progressTicks: progressTicks ?? this.progressTicks,
      totalTicks: totalTicks ?? this.totalTicks,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'combat',
      'context': context.toJson(),
      'progress': progress.toJson(),
      'progressTicks': progressTicks,
      'totalTicks': totalTicks,
    };
  }
}

/// Combat progress state tracking HP and attack timers.
@immutable
class CombatProgressState {
  const CombatProgressState({
    required this.monsterHp,
    required this.playerAttackTicksRemaining,
    required this.monsterAttackTicksRemaining,
    this.spawnTicksRemaining,
  });

  factory CombatProgressState.fromJson(Map<String, dynamic> json) {
    return CombatProgressState(
      monsterHp: json['monsterHp'] as int,
      playerAttackTicksRemaining: json['playerAttackTicksRemaining'] as int,
      monsterAttackTicksRemaining: json['monsterAttackTicksRemaining'] as int,
      spawnTicksRemaining: json['spawnTicksRemaining'] as int?,
    );
  }

  /// Current HP of the monster being fought.
  final int monsterHp;

  /// Ticks until the player's next attack.
  final int playerAttackTicksRemaining;

  /// Ticks until the monster's next attack.
  final int monsterAttackTicksRemaining;

  /// Ticks until the monster spawns (null if already spawned).
  final int? spawnTicksRemaining;

  /// Returns true if the monster is currently spawning.
  bool get isSpawning => spawnTicksRemaining != null;

  CombatProgressState copyWith({
    int? monsterHp,
    int? playerAttackTicksRemaining,
    int? monsterAttackTicksRemaining,
    int? spawnTicksRemaining,
  }) {
    return CombatProgressState(
      monsterHp: monsterHp ?? this.monsterHp,
      playerAttackTicksRemaining:
          playerAttackTicksRemaining ?? this.playerAttackTicksRemaining,
      monsterAttackTicksRemaining:
          monsterAttackTicksRemaining ?? this.monsterAttackTicksRemaining,
      spawnTicksRemaining: spawnTicksRemaining ?? this.spawnTicksRemaining,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'monsterHp': monsterHp,
      'playerAttackTicksRemaining': playerAttackTicksRemaining,
      'monsterAttackTicksRemaining': monsterAttackTicksRemaining,
      if (spawnTicksRemaining != null)
        'spawnTicksRemaining': spawnTicksRemaining,
    };
  }
}
