import 'package:meta/meta.dart';

import 'action_id.dart';
import 'actions.dart';
import 'melvor_id.dart';

/// The base interval for studying constellations (3 seconds).
const _astrologyStudyDuration = Duration(seconds: 3);

/// An astrology constellation action parsed from Melvor data.
///
/// Astrology actions represent constellations that can be studied to gain XP
/// and unlock modifiers that affect other skills.
@immutable
class AstrologyAction extends SkillAction {
  AstrologyAction({
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
