import 'package:better_idle/src/widgets/simple_skill_page.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class MiningPage extends StatelessWidget {
  const MiningPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.mining,
      skillName: 'Mining',
      cellSize: Size(300, 290),
    );
  }
}
