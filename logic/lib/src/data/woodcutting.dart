import 'actions.dart';
import 'melvor_id.dart';

/// Parses a Melvor item ID like "melvorD:Normal_Logs" to extract the name.
/// Returns the human-readable name like "Normal Logs".
String parseItemName(String itemId) {
  // Extract the part after the colon (e.g., "Normal_Logs" from "melvorD:Normal_Logs")
  final colonIndex = itemId.indexOf(':');
  if (colonIndex == -1) {
    return itemId.replaceAll('_', ' ');
  }
  return itemId.substring(colonIndex + 1).replaceAll('_', ' ');
}

/// A woodcutting tree action parsed from Melvor data.
///
/// Extends SkillAction so it can be used directly in the game.
class WoodcuttingTree extends SkillAction {
  WoodcuttingTree({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.outputs,
    required super.duration,
    required this.productId,
    required this.media,
  }) : super(
         skill: Skill.woodcutting,
         rewardsAtLevel: woodcuttingRewards,
         durationModifierAtLevel: woodcuttingDurationModifier,
       );

  factory WoodcuttingTree.fromJson(Map<String, dynamic> json) {
    final productId = MelvorId(json['productId'] as String);
    final baseInterval = json['baseInterval'] as int;

    return WoodcuttingTree(
      id: MelvorId.fromJson(json['id'] as String),
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

  /// The output item name (e.g., "Normal Logs").
  String get outputName => outputs.keys.first.name;

  @override
  String toString() {
    return '$name (level $unlockLevel, ${durationSeconds}s, ${xp}xp) '
        '-> $outputName';
  }
}

/// Extracts woodcutting trees from the skillData array in Melvor JSON.
List<WoodcuttingTree> extractWoodcuttingTrees(Map<String, dynamic> json) {
  // The JSON structure is { "data": { "skillData": [...] } }
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) {
    return [];
  }

  final skillData = data['skillData'] as List<dynamic>?;
  if (skillData == null) {
    return [];
  }

  for (final skill in skillData) {
    if (skill is! Map<String, dynamic>) continue;

    final skillId = skill['skillID'] as String?;
    if (skillId != 'melvorD:Woodcutting') continue;

    final skillContent = skill['data'] as Map<String, dynamic>?;
    if (skillContent == null) continue;

    final trees = skillContent['trees'] as List<dynamic>?;
    if (trees == null) continue;

    return trees
        .whereType<Map<String, dynamic>>()
        .map(WoodcuttingTree.fromJson)
        .toList();
  }

  return [];
}
