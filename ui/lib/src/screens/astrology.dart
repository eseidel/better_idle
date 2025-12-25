import 'package:better_idle/src/widgets/simple_skill_page.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class AstrologyPage extends StatelessWidget {
  const AstrologyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.astrology,
      skillName: 'Astrology',
      cellSize: Size(300, 220),
    );
  }
}
