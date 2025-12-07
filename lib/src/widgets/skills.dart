import 'package:better_idle/src/data/actions.dart';
import 'package:flutter/material.dart';

extension SkillExtensions on Skill {
  IconData get icon => switch (this) {
    Skill.woodcutting => Icons.forest,
    Skill.firemaking => Icons.local_fire_department,
    Skill.fishing => Icons.set_meal,
    Skill.mining => Icons.construction,
    Skill.smithing => Icons.hardware,
  };

  String get routeName => name.toLowerCase();
}
