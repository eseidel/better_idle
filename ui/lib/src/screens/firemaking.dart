import 'package:better_idle/src/widgets/action_grid.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class FiremakingPage extends StatelessWidget {
  const FiremakingPage({super.key});

  @override
  Widget build(BuildContext context) {
    const skill = Skill.firemaking;
    final actions = context.state.registries.actions.forSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    return Scaffold(
      appBar: AppBar(title: const Text('Firemaking')),
      drawer: const AppNavigationDrawer(),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
          Expanded(child: ActionGrid(actions: actions)),
        ],
      ),
    );
  }
}
