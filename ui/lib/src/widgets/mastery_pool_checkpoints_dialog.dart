import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';

/// A dialog that displays the mastery pool checkpoints for a skill.
class MasteryPoolCheckpointsDialog extends StatelessWidget {
  const MasteryPoolCheckpointsDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final bonuses = state.registries.masteryPoolBonuses.forSkill(skill.id);
    final skillState = state.skillState(skill);
    final currentXp = skillState.masteryPoolXp;
    final maxXp = maxMasteryPoolXpForSkill(state.registries, skill);
    final currentPercent = maxXp > 0 ? (currentXp / maxXp) * 100 : 0.0;

    return AlertDialog(
      title: Row(
        children: [
          const CachedImage(
            assetPath: 'assets/media/main/mastery_pool.png',
            size: 28,
          ),
          const SizedBox(width: 8),
          SkillImage(skill: skill, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('${skill.name} Pool Checkpoints')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: bonuses == null || bonuses.bonuses.isEmpty
            ? const Text(
                'No pool checkpoints available for this skill.',
                style: TextStyle(color: Style.textColorSecondary),
              )
            : SingleChildScrollView(
                child: _MasteryPoolCheckpointsTable(
                  bonuses: bonuses.bonuses,
                  currentPercent: currentPercent,
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

class _MasteryPoolCheckpointsTable extends StatelessWidget {
  const _MasteryPoolCheckpointsTable({
    required this.bonuses,
    required this.currentPercent,
  });

  final List<MasteryPoolBonus> bonuses;
  final double currentPercent;

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
                'Pool %',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Bonus',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        ...bonuses.map((bonus) {
          final isActive = currentPercent >= bonus.percent;
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Style.successColor,
                      )
                    else
                      const Icon(
                        Icons.circle_outlined,
                        size: 16,
                        color: Style.textColorSecondary,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      '${bonus.percent}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isActive ? null : Style.textColorSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _formatModifiers(bonus.modifiers),
                  style: TextStyle(
                    color: isActive ? null : Style.textColorSecondary,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  String _formatModifiers(ModifierDataSet modifiers) {
    if (modifiers.modifiers.isEmpty) return 'No modifiers';

    final descriptions = <String>[];
    for (final mod in modifiers.modifiers) {
      descriptions.add(_formatModifierData(mod));
    }
    return descriptions.join(', ');
  }

  String _formatModifierData(ModifierData mod) {
    final name = _formatModifierName(mod.name);

    // Sum up all entry values for this modifier
    final totalValue = mod.entries.fold<num>(0, (sum, e) => sum + e.value);

    // Format based on common modifier patterns
    if (mod.name.contains('XP') || mod.name.contains('Xp')) {
      return '+$totalValue% $name';
    }
    if (mod.name.contains('Chance') || mod.name.contains('chance')) {
      return '+$totalValue% $name';
    }
    if (mod.name.contains('Interval') || mod.name.contains('interval')) {
      return '${totalValue}ms $name';
    }
    if (mod.name.contains('Cost') || mod.name.contains('cost')) {
      return '$totalValue $name';
    }
    return '+$totalValue $name';
  }

  String _formatModifierName(String name) {
    // Convert camelCase to readable format
    final result = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      if (i > 0 && char.toUpperCase() == char && char.toLowerCase() != char) {
        result.write(' ');
      }
      result.write(i == 0 ? char.toUpperCase() : char);
    }
    return result.toString();
  }
}

/// A button that opens the mastery pool checkpoints dialog for a skill.
class MasteryPoolCheckpointsButton extends StatelessWidget {
  const MasteryPoolCheckpointsButton({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => MasteryPoolCheckpointsDialog(skill: skill),
      ),
      icon: const CachedImage(
        assetPath: 'assets/media/main/mastery_pool.png',
        size: 20,
      ),
      label: const Text('Pool Checkpoints'),
    );
  }
}
