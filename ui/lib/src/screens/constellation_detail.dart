import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/duration_badge_cell.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/mastery_pool.dart';
import 'package:ui/src/widgets/skill_image.dart';
import 'package:ui/src/widgets/style.dart';
import 'package:ui/src/widgets/xp_badges_row.dart';

/// Detail page for a constellation, showing study action and modifier shop.
class ConstellationDetailPage extends StatelessWidget {
  const ConstellationDetailPage({required this.constellationId, super.key});

  final MelvorId constellationId;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final action = state.registries.astrology.byId(constellationId);
    if (action == null) {
      return const Scaffold(
        body: Center(child: Text('Constellation not found')),
      );
    }

    final actionState = state.actionState(action.id);
    final canStart = state.canStartAction(action);
    final isRunning = state.isActionActive(action);
    final isStunned = state.isStunned;
    final canToggle = (canStart || isRunning) && !isStunned;
    final skillDrops = state.registries.drops.forSkill(Skill.astrology);

    return GameScaffold(
      title: Text(action.name),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConstellationHeader(action: action),
            const SizedBox(height: 16),
            _StudyButton(
              action: action,
              canToggle: canToggle,
              isRunning: isRunning,
            ),
            const SizedBox(height: 8),
            MasteryProgressCell(masteryXp: actionState.masteryXp),
            const SizedBox(height: 24),
            _StardustInventory(skillDrops: skillDrops),
            const SizedBox(height: 24),
            _ModifierShop(action: action),
          ],
        ),
      ),
    );
  }
}

class _ConstellationHeader extends StatelessWidget {
  const _ConstellationHeader({required this.action});

  final AstrologyAction action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CachedImage(assetPath: action.media, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  if (action.skillIds.isNotEmpty)
                    Row(
                      children: [
                        Text(
                          'Affects: ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...action.skillIds
                            .where(
                              (MelvorId id) =>
                                  Skill.values.any((s) => s.id == id),
                            )
                            .map((MelvorId skillId) {
                              final skill = Skill.fromId(skillId);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: SkillImage(skill: skill, size: 20),
                              );
                            }),
                      ],
                    ),
                  const SizedBox(height: 8),
                  XpBadgesRow(
                    action: action,
                    inradius: TextBadgeCell.smallInradius,
                    trailing: DurationBadgeCell(
                      seconds: action.minDuration.inSeconds,
                      inradius: TextBadgeCell.smallInradius,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyButton extends StatelessWidget {
  const _StudyButton({
    required this.action,
    required this.canToggle,
    required this.isRunning,
  });

  final AstrologyAction action;
  final bool canToggle;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: canToggle
          ? () => context.dispatch(ToggleActionAction(action: action))
          : null,
      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
      label: Text(isRunning ? 'Stop Studying' : 'Study Constellation'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: isRunning ? Style.activeColor : null,
      ),
    );
  }
}

class _StardustInventory extends StatelessWidget {
  const _StardustInventory({required this.skillDrops});

  final List<Droppable> skillDrops;

  @override
  Widget build(BuildContext context) {
    final state = context.state;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Stardust',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: skillDrops.whereType<Drop>().map((drop) {
                final item = state.registries.items.byId(drop.itemId);
                final count = state.inventory.countOfItem(item);
                return Column(
                  children: [
                    ItemImage(item: item),
                    const SizedBox(height: 4),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModifierShop extends StatelessWidget {
  const _ModifierShop({required this.action});

  final AstrologyAction action;

  @override
  Widget build(BuildContext context) {
    final affectedSkills = action.skillIds
        .where((MelvorId id) => Skill.values.any((s) => s.id == id))
        .map((MelvorId id) => Skill.fromId(id).name)
        .join(' and ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Constellation Modifiers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Style.cellBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Modifier shop coming soon\n\n'
                  'Spend stardust to unlock bonuses\n'
                  'for $affectedSkills',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Style.textColorMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
