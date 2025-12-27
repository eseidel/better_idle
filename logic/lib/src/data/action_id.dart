import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';

/// ActionId has two parts, the skill id and the action name.
/// This is necessary to uniquely identify an action, since action names
/// are unique within a skill, but not across skills and skills themselves
/// are namespaced (but also themselves unique without a namespace).
class ActionId extends Equatable {
  const ActionId(this.skillId, this.localId);

  factory ActionId.test(Skill skill, String localName) =>
      ActionId(skill.id, MelvorId('test:${localName.replaceAll(' ', '_')}'));

  factory ActionId.fromJson(String json) {
    final parts = json.split('/');
    return ActionId(MelvorId.fromJson(parts[0]), MelvorId.fromJson(parts[1]));
  }

  final MelvorId skillId;
  final MelvorId localId;

  String toJson() => '${skillId.toJson()}/$localId';

  static ActionId? maybeFromJson(String? json) {
    if (json == null) return null;
    return ActionId.fromJson(json);
  }

  @override
  List<Object?> get props => [skillId, localId];

  @override
  String toString() => '${skillId.fullId}/$localId';
}
