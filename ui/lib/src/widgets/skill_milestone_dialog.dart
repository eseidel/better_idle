import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A celebratory dialog shown when the player reaches level 99 in a skill.
class SkillMilestoneDialog extends StatelessWidget {
  const SkillMilestoneDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        children: [
          SkillImage(skill: skill, size: 80),
          const SizedBox(height: 12),
          const Text('Level 99!'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            skill.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Congratulations! You have reached the highest level in '
            '${skill.name}!',
            style: TextStyle(fontSize: 14, color: Style.textColorSuccess),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
