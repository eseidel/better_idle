import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/count_badge_cell.dart';
import 'package:ui/src/widgets/duration_badge_cell.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/item_count_badge_cell.dart';
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

    // Build a map of stardust item IDs to inventory counts
    final stardustItems = <MelvorId, int>{};
    for (final drop in skillDrops.whereType<Drop>()) {
      final item = state.registries.items.byId(drop.itemId);
      stardustItems[drop.itemId] = state.inventory.countOfItem(item);
    }

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
              children: stardustItems.entries.map((entry) {
                final item = state.registries.items.byId(entry.key);
                return ItemCountBadgeCell(item: item, count: entry.value);
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
            if (action.standardModifiers.isNotEmpty) ...[
              _ModifierSection(
                title: 'Standard Modifiers (Stardust)',
                modifiers: action.standardModifiers,
                constellationId: action.id.localId,
              ),
              const SizedBox(height: 16),
            ],
            if (action.uniqueModifiers.isNotEmpty)
              _ModifierSection(
                title: 'Unique Modifiers (Golden Stardust)',
                modifiers: action.uniqueModifiers,
                constellationId: action.id.localId,
              ),
            if (action.standardModifiers.isEmpty &&
                action.uniqueModifiers.isEmpty)
              Center(
                child: Text(
                  'No modifiers available for this constellation',
                  style: TextStyle(color: Style.textColorMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModifierSection extends StatelessWidget {
  const _ModifierSection({
    required this.title,
    required this.modifiers,
    required this.constellationId,
  });

  final String title;
  final List<AstrologyModifier> modifiers;
  final MelvorId constellationId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Style.textColorMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...modifiers.asMap().entries.map((entry) {
          return _ModifierRow(
            modifier: entry.value,
            modifierIndex: entry.key,
            constellationId: constellationId,
          );
        }),
      ],
    );
  }
}

class _ModifierRow extends StatelessWidget {
  const _ModifierRow({
    required this.modifier,
    required this.modifierIndex,
    required this.constellationId,
  });

  final AstrologyModifier modifier;
  final int modifierIndex;
  final MelvorId constellationId;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final constellationState = state.astrology.stateFor(constellationId);
    final currentLevel = constellationState.levelFor(
      modifier.type,
      modifierIndex,
    );
    final isMaxed = currentLevel >= modifier.maxCount;
    final cost = modifier.costForLevel(currentLevel);

    // Check mastery requirement
    final constellation = state.registries.astrology.byId(constellationId);
    final masteryLevel = constellation != null
        ? state.actionState(constellation.id).masteryLevel
        : 0;
    final masteryLocked = masteryLevel < modifier.unlockMasteryLevel;

    final canPurchase = state.canPurchaseAstrologyModifier(
      constellationId: constellationId,
      modifierType: modifier.type,
      modifierIndex: modifierIndex,
    );

    // Get currency item for display
    final currencyItem = state.registries.items.byId(
      modifier.type.currencyItemId,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: masteryLocked
            ? Border.all(color: Colors.grey.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          CachedImage(
            assetPath: modifier.type == AstrologyModifierType.standard
                ? 'assets/media/skills/astrology/star_standard.png'
                : 'assets/media/skills/astrology/star_unique.png',
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (masteryLocked && constellation != null)
                  Row(
                    children: [
                      Text(
                        'Requires ',
                        style: TextStyle(color: Style.textColorMuted),
                      ),
                      const CachedImage(
                        assetPath: 'assets/media/main/mastery_header.png',
                        size: 16,
                      ),
                      Text(
                        ' Mastery Level ${modifier.unlockMasteryLevel} for ',
                        style: TextStyle(color: Style.textColorMuted),
                      ),
                      CachedImage(assetPath: constellation.media, size: 16),
                      Text(
                        ' ${constellation.name}',
                        style: TextStyle(color: Style.textColorMuted),
                      ),
                    ],
                  )
                else
                  ...modifier
                      .formatDescriptionLines(
                        state.registries.modifierMetadata,
                        currentLevel: currentLevel,
                      )
                      .map(Text.new),
                const SizedBox(height: 4),
                _LevelIndicator(current: currentLevel, max: modifier.maxCount),
              ],
            ),
          ),
          if (!isMaxed && !masteryLocked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ItemImage(item: currencyItem, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '$cost',
                      style: TextStyle(
                        color: canPurchase ? null : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: ElevatedButton(
                        onPressed: canPurchase
                            ? () => context.dispatch(
                                PurchaseAstrologyModifierAction(
                                  constellationId: constellationId,
                                  modifierType: modifier.type,
                                  modifierIndex: modifierIndex,
                                ),
                              )
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Buy'),
                      ),
                    ),
                  ],
                ),
                Text(
                  modifier.formatIncrementDescription(
                    state.registries.modifierMetadata,
                  ),
                  style: TextStyle(
                    color: Style.textColorMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          if (isMaxed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'MAX',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelIndicator extends StatelessWidget {
  const _LevelIndicator({required this.current, required this.max});

  final int current;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(max, (index) {
        final isFilled = index < current;
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? Style.activeColor
                : Colors.grey.withValues(alpha: 0.3),
            border: Border.all(
              color: isFilled
                  ? Style.activeColor
                  : Colors.grey.withValues(alpha: 0.5),
            ),
          ),
        );
      }),
    );
  }
}
