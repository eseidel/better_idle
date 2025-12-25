import 'package:better_idle/src/widgets/simple_skill_page.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.woodcutting,
      skillName: 'Woodcutting',
      cellSize: Size(300, 220),
    );
  }
}
