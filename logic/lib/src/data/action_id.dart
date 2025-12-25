import 'actions.dart';
import 'melvor_id.dart';

/// ActionId has two parts, the skill id and the action name.
/// This is necessary to uniquely identify an action, since action names
/// are unique within a skill, but not across skills and skills themselves
/// are namespaced (but also themselves unique without a namespace).
class ActionId {
  const ActionId(this.skillId, this.localId);

  final MelvorId skillId;
  final MelvorId localId;

  static ActionId test(Skill skill, String localName) =>
      ActionId(skill.id, MelvorId('test:${localName.replaceAll(' ', '_')}'));

  String toJson() => '${skillId.toJson()}/$localId';

  static ActionId? maybeFromJson(String? json) {
    if (json == null) return null;
    return ActionId.fromJson(json);
  }

  factory ActionId.fromJson(String json) {
    final parts = json.split('/');
    return ActionId(MelvorId.fromJson(parts[0]), MelvorId.fromJson(parts[1]));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionId &&
          runtimeType == other.runtimeType &&
          skillId == other.skillId &&
          localId == other.localId;

  @override
  int get hashCode => Object.hash(skillId, localId);

  @override
  String toString() => '${skillId.fullId}/$localId';
}
