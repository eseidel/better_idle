import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/simple_skill_page.dart';

class WoodcuttingPage extends StatelessWidget {
  const WoodcuttingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.woodcutting,
      skillName: 'Woodcutting',
      cellSize: Size(300, 250),
    );
  }
}
