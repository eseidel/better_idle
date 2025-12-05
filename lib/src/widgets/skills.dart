import 'package:better_idle/src/data/actions.dart';
import 'package:flutter/material.dart';

extension SkillExtensions on Skill {
  IconData get icon => switch (this) {
    Skill.woodcutting => Icons.forest,
    Skill.firemaking => Icons.local_fire_department,
  };

  String get routeName => name.toLowerCase();
}
