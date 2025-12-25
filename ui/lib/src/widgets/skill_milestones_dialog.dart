import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Returns the media path for an action, if available.
/// Different action subclasses store media in different ways.
String? _mediaForAction(SkillAction action) {
  // Check for specific action types that have media fields.
  if (action is WoodcuttingTree) return action.media;
  if (action is FishingAction) {
    final media = action.media;
    if (media.isNotEmpty) return media;
  }
  if (action is MiningAction) return action.media;
  if (action is ThievingAction) return action.media;
  if (action is AgilityObstacle) return action.media;
  if (action is AstrologyAction) return action.media;
  if (action is AltMagicAction) return action.media;
  // For other action types, return null (no direct media).
  return null;
}

/// Returns the primary item ID for an action (output or input).
/// Used for looking up item images when the action has no direct media.
MelvorId? _primaryItemId(SkillAction action) {
  // Check for actions with productId fields.
  if (action is FishingAction) return action.productId;
  if (action is CookingAction) return action.productId;
  if (action is FiremakingAction) return action.logId;
  if (action is SummoningAction) return action.productId;
  // Fall back to first output or input.
  if (action.outputs.isNotEmpty) return action.outputs.keys.first;
  if (action.inputs.isNotEmpty) return action.inputs.keys.first;
  return null;
}

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
    final actions = state.registries.actions.forSkill(skill).toList()
      ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

    return AlertDialog(
      title: Row(
        children: [
          SkillImage(skill: skill, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('${skill.name} Milestones')),
        ],
      ),
      content: actions.isEmpty
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
                    _ActionImage(action: action),
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

/// Displays an image for an action, using its media path if available.
class _ActionImage extends StatelessWidget {
  const _ActionImage({required this.action});

  final SkillAction action;

  @override
  Widget build(BuildContext context) {
    // First try direct media path from action.
    final media = _mediaForAction(action);
    if (media != null && media.isNotEmpty) {
      return CachedImage(assetPath: media, size: 24);
    }

    // Fall back to looking up the primary item's image.
    final itemId = _primaryItemId(action);
    if (itemId != null) {
      final items = context.state.registries.items;
      final item = items.all.where((i) => i.id == itemId).firstOrNull;
      if (item != null) {
        return ItemImage(item: item, size: 24);
      }
    }

    // Last resort: show a generic icon.
    return const SizedBox(
      width: 24,
      height: 24,
      child: Icon(Icons.circle, size: 16, color: Style.iconColorDefault),
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
