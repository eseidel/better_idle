import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A woodcutting tree action parsed from Melvor data.
///
/// Extends SkillAction so it can be used directly in the game.
@immutable
class WoodcuttingTree extends SkillAction {
  const WoodcuttingTree({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required super.duration,
    required this.productId,
    required this.media,
  }) : super(skill: Skill.woodcutting);

  factory WoodcuttingTree.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final productId = MelvorId.fromJsonWithNamespace(
      json['productId'] as String,
      defaultNamespace: namespace,
    );
    final baseInterval = json['baseInterval'] as int;

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );
    return WoodcuttingTree(
      id: ActionId(Skill.woodcutting.id, localId),
      name: json['name'] as String,
      unlockLevel: json['level'] as int,
      duration: Duration(milliseconds: baseInterval),
      xp: json['baseExperience'] as int,
      outputs: {productId: 1},
      productId: productId,
      media: json['media'] as String,
    );
  }

  /// The Melvor product ID (e.g., "melvorD:Normal_Logs").
  final MelvorId productId;

  /// The media path for the tree icon.
  final String media;

  /// Duration in seconds.
  int get durationSeconds => minDuration.inSeconds;
}
