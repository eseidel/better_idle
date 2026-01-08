import 'package:logic/logic.dart';

extension SkillExtensions on Skill {
  String get routeName => switch (this) {
    Skill.hitpoints ||
    Skill.attack ||
    Skill.strength ||
    Skill.defence ||
    Skill.ranged ||
    Skill.magic ||
    Skill.prayer ||
    Skill.slayer => 'combat',
    Skill.altMagic => 'alt_magic',
    _ => name.toLowerCase(),
  };

  /// Returns the asset path for this skill in the media directory.
  String get assetPath {
    final lower = name.toLowerCase();

    if (this == Skill.altMagic) {
      return 'assets/media/skills/magic/magic.png';
    }
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
