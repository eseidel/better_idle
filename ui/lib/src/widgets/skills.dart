import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

extension SkillExtensions on Skill {
  IconData get icon => switch (this) {
    Skill.hitpoints => Icons.favorite,
    Skill.attack => Icons.sports_martial_arts,
    Skill.woodcutting => Icons.forest,
    Skill.firemaking => Icons.local_fire_department,
    Skill.fishing => Icons.set_meal,
    Skill.cooking => Icons.restaurant,
    Skill.mining => Icons.construction,
    Skill.smithing => Icons.hardware,
    Skill.fletching => Icons.keyboard_double_arrow_up,
    Skill.thieving => Icons.back_hand,
    Skill.crafting => Icons.handyman,
  };

  String get routeName => switch (this) {
    Skill.hitpoints => 'combat',
    Skill.attack => 'combat',
    _ => name.toLowerCase(),
  };

  /// Returns the asset path for this skill in the media directory.
  String get assetPath {
    final lower = name.toLowerCase();
    return 'assets/media/skills/$lower/$lower.png';
  }
}

extension AttackTypeExtensions on AttackType {
  /// Returns the asset path for this attack type icon.
  String get assetPath => switch (this) {
    AttackType.melee => 'assets/media/skills/combat/attack.png',
    AttackType.ranged => 'assets/media/skills/ranged/ranged.png',
    AttackType.magic => 'assets/media/skills/magic/magic.png',
    AttackType.random => 'assets/media/skills/combat/combat.png',
  };
}
