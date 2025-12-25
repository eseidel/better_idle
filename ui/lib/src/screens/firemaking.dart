import 'package:better_idle/src/widgets/simple_skill_page.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class FiremakingPage extends StatelessWidget {
  const FiremakingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleSkillPage(
      skill: Skill.firemaking,
      skillName: 'Firemaking',
    );
  }
}
