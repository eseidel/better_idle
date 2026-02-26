import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// ActionId has two parts, the skill id and the action name.
/// This is necessary to uniquely identify an action, since action names
/// are unique within a skill, but not across skills and skills themselves
/// are namespaced (but also themselves unique without a namespace).
///
/// ActionId does NOT include alternative recipe selection. Some actions
/// (like Bronze Bar in Smithing) have multiple recipe variants that use
/// different inputs. The recipe selection is stored separately in
/// `SkillActivity.selectedRecipeIndex` because:
/// 1. Mastery XP is shared across all recipe variants of the same action
/// 2. Recipe selection is transient activity state, not a permanent property
/// 3. The action's outputs and XP rewards are the same regardless of recipe
@immutable
class ActionId {
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

  static ActionId? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return ActionId.fromJson(json as String);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionId && skillId == other.skillId && localId == other.localId;

  @override
  int get hashCode => Object.hash(skillId, localId);

  @override
  String toString() => '${skillId.fullId}/$localId';
}
