import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// An active slayer task — an independent "quest" to kill a specific monster.
///
/// Unlike combat contexts, this persists regardless of what the player is
/// currently fighting. Kills of the assigned monster count toward the task
/// no matter which area the player is in.
@immutable
class SlayerTask {
  const SlayerTask({
    required this.categoryId,
    required this.monsterId,
    required this.killsRequired,
    required this.killsCompleted,
  });

  factory SlayerTask.fromJson(Map<String, dynamic> json) {
    return SlayerTask(
      categoryId: MelvorId.fromJson(json['categoryId'] as String),
      monsterId: MelvorId.fromJson(json['monsterId'] as String),
      killsRequired: json['killsRequired'] as int,
      killsCompleted: json['killsCompleted'] as int,
    );
  }

  /// The slayer task category (Easy, Normal, Hard, etc.).
  final MelvorId categoryId;

  /// The ID of the monster to kill for this task.
  final MelvorId monsterId;

  /// Total number of kills required to complete the task.
  final int killsRequired;

  /// Number of kills completed so far.
  final int killsCompleted;

  /// Returns the number of kills remaining.
  int get killsRemaining => killsRequired - killsCompleted;

  /// Returns true if the task is complete.
  bool get isComplete => killsCompleted >= killsRequired;

  /// Returns a new task with an additional kill recorded.
  SlayerTask recordKill() {
    return SlayerTask(
      categoryId: categoryId,
      monsterId: monsterId,
      killsRequired: killsRequired,
      killsCompleted: killsCompleted + 1,
    );
  }

  SlayerTask copyWith({
    MelvorId? categoryId,
    MelvorId? monsterId,
    int? killsRequired,
    int? killsCompleted,
  }) {
    return SlayerTask(
      categoryId: categoryId ?? this.categoryId,
      monsterId: monsterId ?? this.monsterId,
      killsRequired: killsRequired ?? this.killsRequired,
      killsCompleted: killsCompleted ?? this.killsCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId.toJson(),
      'monsterId': monsterId.toJson(),
      'killsRequired': killsRequired,
      'killsCompleted': killsCompleted,
    };
  }
}
