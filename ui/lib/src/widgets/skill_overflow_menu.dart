import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/mastery_unlocks_dialog.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/skill_milestones_dialog.dart';

/// An overflow menu for skill pages with mastery unlocks and skill milestones.
class SkillOverflowMenu extends StatelessWidget {
  const SkillOverflowMenu({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SkillMenuItem>(
      icon: const Icon(Icons.more_vert),
      onSelected: (item) => _onItemSelected(context, item),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _SkillMenuItem.masteryUnlocks,
          child: Row(
            children: [
              CachedImage(
                assetPath: 'assets/media/main/mastery_header.png',
                size: 20,
              ),
              SizedBox(width: 12),
              Text('Mastery Unlocks'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _SkillMenuItem.skillMilestones,
          child: Row(
            children: [
              SkillImage(skill: skill, size: 20),
              const SizedBox(width: 12),
              const Text('Skill Milestones'),
            ],
          ),
        ),
      ],
    );
  }

  void _onItemSelected(BuildContext context, _SkillMenuItem item) {
    switch (item) {
      case _SkillMenuItem.masteryUnlocks:
        showDialog<void>(
          context: context,
          builder: (context) => MasteryUnlocksDialog(skill: skill),
        );
      case _SkillMenuItem.skillMilestones:
        showDialog<void>(
          context: context,
          builder: (context) => SkillMilestonesDialog(skill: skill),
        );
    }
  }
}

enum _SkillMenuItem { masteryUnlocks, skillMilestones }
