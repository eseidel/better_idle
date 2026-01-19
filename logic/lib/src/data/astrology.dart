import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// The base interval for studying constellations (3 seconds).
const _astrologyStudyDuration = Duration(seconds: 3);

/// An astrology constellation action parsed from Melvor data.
///
/// Astrology actions represent constellations that can be studied to gain XP
/// and unlock modifiers that affect other skills.
@immutable
class AstrologyAction extends SkillAction {
  const AstrologyAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.media,
    required this.skillIds,
  }) : super(skill: Skill.astrology, duration: _astrologyStudyDuration);

  factory AstrologyAction.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse the skillIDs that this constellation affects
    final skillIdsJson = json['skillIDs'] as List<dynamic>? ?? [];
    final skillIds = skillIdsJson
        .map((s) => MelvorId.fromJson(s as String))
        .toList();

    return AstrologyAction(
      id: ActionId(Skill.astrology.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      xp: json['baseExperience'] as int,
      media: json['media'] as String,
      skillIds: skillIds,
    );
  }

  /// The media path for the constellation icon.
  final String media;

  /// The skill IDs that this constellation provides modifiers for.
  final List<MelvorId> skillIds;
}

/// Registry for astrology skill data.
@immutable
class AstrologyRegistry {
  const AstrologyRegistry(this.actions) : _byId = null;

  const AstrologyRegistry._withCache(this.actions, this._byId);

  /// All astrology constellation actions.
  final List<AstrologyAction> actions;

  final Map<MelvorId, AstrologyAction>? _byId;

  Map<MelvorId, AstrologyAction> get _actionMap {
    if (_byId != null) return _byId;
    return {for (final a in actions) a.id.localId: a};
  }

  /// Look up an astrology action by its local ID.
  AstrologyAction? byId(MelvorId localId) => _actionMap[localId];

  /// Create a cached version for faster lookups.
  AstrologyRegistry withCache() {
    if (_byId != null) return this;
    return AstrologyRegistry._withCache(actions, _actionMap);
  }
}
