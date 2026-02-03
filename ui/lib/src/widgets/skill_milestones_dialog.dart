import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/action_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that displays the skill level milestones for a skill.
/// Shows what actions unlock at each level.
class SkillMilestonesDialog extends StatelessWidget {
  const SkillMilestonesDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final skillState = state.skillState(skill);
    final currentLevel = levelForXp(skillState.xp);

    // Get all skill actions for this skill, sorted by unlock level.
    final actions = state.registries.actionsForSkill(skill).toList()
      ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

    return AlertDialog(
      title: Row(
        children: [
          SkillImage(skill: skill, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('${skill.name} Milestones')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: actions.isEmpty
            ? const Text(
                'No milestones available for this skill.',
                style: TextStyle(color: Style.textColorSecondary),
              )
            : SingleChildScrollView(
                child: _SkillMilestonesTable(
                  actions: actions,
                  currentLevel: currentLevel,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SkillMilestonesTable extends StatelessWidget {
  const _SkillMilestonesTable({
    required this.actions,
    required this.currentLevel,
  });

  final List<SkillAction> actions;
  final int currentLevel;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        const TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Style.textColorSecondary)),
          ),
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 8, right: 16),
                child: Text(
                  'Level',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Unlocks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        ...actions.map((action) {
          final isUnlocked = currentLevel >= action.unlockLevel;
          return TableRow(
            children: [
              Container(
                padding: const EdgeInsets.only(top: 8, right: 16),
                alignment: Alignment.center,
                decoration: isUnlocked
                    ? BoxDecoration(
                        color: Style.successColor.withValues(alpha: 0.2),
                      )
                    : null,
                child: Text(
                  '${action.unlockLevel}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    ActionImage(action: action),
                    const SizedBox(width: 8),
                    Expanded(child: Text(action.name)),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

/// A button that opens the skill milestones dialog for a skill.
class SkillMilestonesButton extends StatelessWidget {
  const SkillMilestonesButton({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => SkillMilestonesDialog(skill: skill),
      ),
      icon: SkillImage(skill: skill, size: 20),
      label: const Text('Skill Milestones'),
    );
  }
}
