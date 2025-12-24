import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// A dialog that displays the mastery level unlocks for a skill.
class MasteryUnlocksDialog extends StatelessWidget {
  const MasteryUnlocksDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final unlocks = context.state.registries.masteryUnlocks.forSkill(skill.id);

    return AlertDialog(
      title: Row(
        children: [
          const CachedImage(
            assetPath: 'assets/media/main/mastery_header.png',
            size: 28,
          ),
          const SizedBox(width: 8),
          SkillImage(skill: skill, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('${skill.name} Mastery')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: unlocks == null || unlocks.unlocks.isEmpty
            ? const Text(
                'No mastery unlocks available for this skill.',
                style: TextStyle(color: Style.textColorSecondary),
              )
            : SingleChildScrollView(
                child: _MasteryUnlocksTable(unlocks: unlocks.unlocks),
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

class _MasteryUnlocksTable extends StatelessWidget {
  const _MasteryUnlocksTable({required this.unlocks});

  final List<MasteryLevelUnlock> unlocks;

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
            Padding(
              padding: EdgeInsets.only(bottom: 8, right: 16),
              child: Text(
                'Mastery',
                style: TextStyle(fontWeight: FontWeight.bold),
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
        ...unlocks.map(
          (unlock) => TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: Text(
                  '${unlock.level}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(unlock.description),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A button that opens the mastery unlocks dialog for a skill.
class MasteryUnlocksButton extends StatelessWidget {
  const MasteryUnlocksButton({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => MasteryUnlocksDialog(skill: skill),
      ),
      icon: const CachedImage(
        assetPath: 'assets/media/main/mastery_header.png',
        size: 20,
      ),
      label: const Text('Mastery Unlocks'),
    );
  }
}
