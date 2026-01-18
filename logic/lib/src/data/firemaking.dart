import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A firemaking action parsed from Melvor data.
///
/// Firemaking actions consume logs and produce XP, with chances for
/// bonus drops like Coal and Ash.
@immutable
class FiremakingAction extends SkillAction {
  const FiremakingAction({
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

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return FiremakingAction(
      id: ActionId(Skill.firemaking.id, localId),
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

/// Registry for firemaking skill data.
@immutable
class FiremakingRegistry {
  const FiremakingRegistry(this.actions) : _byId = null;

  const FiremakingRegistry._withCache(this.actions, this._byId);

  /// All firemaking actions.
  final List<FiremakingAction> actions;

  final Map<MelvorId, FiremakingAction>? _byId;

  Map<MelvorId, FiremakingAction> get _actionMap {
    if (_byId != null) return _byId;
    return {for (final a in actions) a.id.localId: a};
  }

  /// Look up a firemaking action by its local ID.
  FiremakingAction? byId(MelvorId localId) => _actionMap[localId];

  /// Create a cached version for faster lookups.
  FiremakingRegistry withCache() {
    if (_byId != null) return this;
    return FiremakingRegistry._withCache(actions, _actionMap);
  }
}
