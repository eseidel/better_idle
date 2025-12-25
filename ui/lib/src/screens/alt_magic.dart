import 'package:better_idle/src/widgets/simple_skill_page.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class AltMagicPage extends StatelessWidget {
  const AltMagicPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.altMagic,
      skillName: 'Alt. Magic',
      cellSize: Size(300, 220),
    );
  }
}
