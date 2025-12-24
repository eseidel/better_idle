import 'package:meta/meta.dart';

import 'action_id.dart';
import 'actions.dart';
import 'melvor_id.dart';

/// A firemaking action parsed from Melvor data.
///
/// Firemaking actions consume logs and produce XP, with chances for
/// bonus drops like Coal and Ash.
@immutable
class FiremakingAction extends SkillAction {
  FiremakingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.inputs,
    required super.duration,
    required this.logId,
    required this.bonfireInterval,
    required this.bonfireXPBonus,
  }) : super(skill: Skill.firemaking, outputs: const {});

  factory FiremakingAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final logId = MelvorId.fromJsonWithNamespace(
      json['logID'] as String,
      defaultNamespace: namespace,
    );
    final baseInterval = json['baseInterval'] as int;
    final baseBonfireInterval = json['baseBonfireInterval'] as int;
    final bonfireXPBonus = json['bonfireXPBonus'] as int;

    // Action name is "Burn X Logs" based on the log name.
    final actionName = 'Burn ${logId.name}';

    return FiremakingAction(
      id: ActionId(Skill.firemaking.id, json['id'] as String),
      name: actionName,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      inputs: {logId: 1},
      duration: Duration(milliseconds: baseInterval),
      logId: logId,
      bonfireInterval: Duration(milliseconds: baseBonfireInterval),
      bonfireXPBonus: bonfireXPBonus,
    );
  }

  /// The Melvor log ID (e.g., "melvorD:Normal_Logs").
  final MelvorId logId;

  /// Duration of the bonfire effect.
  final Duration bonfireInterval;

  /// XP bonus percentage when bonfire is active.
  final int bonfireXPBonus;
}
