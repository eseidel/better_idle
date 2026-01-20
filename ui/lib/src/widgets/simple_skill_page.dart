import 'package:better_idle/src/widgets/action_grid.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

/// A simple skill page that displays actions in a grid layout.
///
/// Used by Woodcutting, Mining, and Firemaking screens which share the same
/// layout: skill progress, mastery pool progress, mastery unlocks button,
/// and an action grid.
class SimpleSkillPage extends StatelessWidget {
  const SimpleSkillPage({
    required this.skill,
    required this.skillName,
    this.cellSize = const Size(300, 150),
    super.key,
  });

  final Skill skill;
  final String skillName;
  final Size cellSize;

  @override
  Widget build(BuildContext context) {
    final actions = context.state.registries.actionsForSkill(skill).toList();
    final skillState = context.state.skillState(skill);

    return GameScaffold(
      title: Text(skillName),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          MasteryPoolProgress(xp: skillState.masteryPoolXp),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MasteryUnlocksButton(skill: skill),
              SkillMilestonesButton(skill: skill),
            ],
          ),
          Expanded(
            child: ActionGrid(actions: actions, cellSize: cellSize),
          ),
        ],
      ),
    );
  }
}
