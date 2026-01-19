import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/count_badge_cell.dart';
import 'package:better_idle/src/widgets/duration_badge_cell.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:better_idle/src/widgets/tweened_progress_indicator.dart';
import 'package:better_idle/src/widgets/xp_badges_row.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class ActionGrid extends StatelessWidget {
  const ActionGrid({
    required this.actions,
    super.key,
    this.cellSize = const Size(300, 150),
  });

  final List<SkillAction> actions;
  final Size cellSize;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions.map((action) {
              final progressTicks = context.state.activeProgress(action);
              final actionState = context.state.actionState(action.id);
              return SizedBox(
                width: cellSize.width,
                height: cellSize.height,
                child: switch (action) {
                  WoodcuttingTree() => WoodcuttingActionCell(
                    action: action,
                    actionState: actionState,
                  ),
                  MiningAction() => MiningActionCell(
                    action: action,
                    actionState: actionState,
                  ),
                  _ => ActionCell(
                    action: action,
                    actionState: actionState,
                    progressTicks: progressTicks,
                  ),
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Shared Helper Widgets
// ============================================================================

/// Common container for locked action cells.
class LockedActionCell extends StatelessWidget {
  const LockedActionCell({
    required this.unlockLevel,
    required this.imageAsset,
    this.hasBorder = false,
    super.key,
  });

  final int unlockLevel;
  final String imageAsset;
  final bool hasBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: hasBorder ? Border.all(color: Style.textColorSecondary) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Locked'),
          const SizedBox(height: 8),
          CachedImage(assetPath: imageAsset, size: 64),
          const SizedBox(height: 8),
          LockedLevelBadge(level: unlockLevel),
        ],
      ),
    );
  }
}

/// Common container for unlocked action cells.
class UnlockedActionCell extends StatelessWidget {
  const UnlockedActionCell({
    required this.action,
    required this.onTap,
    required this.child,
    this.isDepleted = false,
    this.hasBorder = true,
    super.key,
  });

  final SkillAction action;
  final VoidCallback? onTap;
  final Widget child;
  final bool isDepleted;
  final bool hasBorder;

  @override
  Widget build(BuildContext context) {
    final isStunned = context.state.isStunned;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isStunned
              ? Style.cellBackgroundColorStunned
              : isDepleted
              ? Style.cellBackgroundColorDepleted
              : Style.cellBackgroundColor,
          border: hasBorder
              ? Border.all(
                  color: isStunned
                      ? Style.activeColor
                      : Style.textColorSecondary,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

/// Stunned indicator text shown at top of action cells.
class StunnedIndicator extends StatelessWidget {
  const StunnedIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.state.isStunned) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Stunned',
          style: TextStyle(
            color: Style.textColorWarning,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Action progress bar for skill actions.
class ActionProgressBar extends StatelessWidget {
  const ActionProgressBar({
    required this.action,
    this.height = 8.0,
    this.disableWhenDepleted = false,
    super.key,
  });

  final SkillAction action;
  final double height;
  final bool disableWhenDepleted;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final isRunning = state.isActionActive(action);
    final isPlayerActive = state.isPlayerActive;

    return TweenedProgressIndicator(
      progress: isRunning
          ? state.activeActivity!.toProgressAt(state.updatedAt)
          : ProgressAt.zero(state.updatedAt),
      animate: isRunning && isPlayerActive && !disableWhenDepleted,
      height: height,
    );
  }
}

// ============================================================================
// Action Cells
// ============================================================================

class WoodcuttingActionCell extends StatelessWidget {
  const WoodcuttingActionCell({
    required this.action,
    required this.actionState,
    super.key,
  });

  final WoodcuttingTree action;
  final ActionState actionState;

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(action.skill);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
      return LockedActionCell(
        unlockLevel: action.unlockLevel,
        imageAsset: 'assets/media/skills/woodcutting/woodcutting.png',
      );
    }
    return _buildUnlocked(context);
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final canStart = state.canStartAction(action);
    final isRunning = state.isActionActive(action);
    final isStunned = state.isStunned;
    final canToggle = (canStart || isRunning) && !isStunned;

    return UnlockedActionCell(
      action: action,
      hasBorder: false,
      onTap: canToggle
          ? () => context.dispatch(ToggleActionAction(action: action))
          : null,
      child: Column(
        children: [
          const StunnedIndicator(),
          const Text('Cut'),
          Text(action.name, style: labelStyle),
          Text(
            '${action.xp} Skill XP / \u{1F551} '
            '${action.minDuration.inMilliseconds / 1000} seconds',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CachedImage(assetPath: action.media, size: 64),
          const Spacer(),
          ActionProgressBar(action: action),
          const SizedBox(height: 8),
          MasteryProgressCell(masteryXp: actionState.masteryXp),
        ],
      ),
    );
  }
}

class MiningActionCell extends StatelessWidget {
  const MiningActionCell({
    required this.action,
    required this.actionState,
    super.key,
  });

  final MiningAction action;
  final ActionState actionState;

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(action.skill);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
      return LockedActionCell(
        unlockLevel: action.unlockLevel,
        imageAsset: 'assets/media/skills/mining/mining.png',
        hasBorder: true,
      );
    }
    return _buildUnlocked(context);
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final actionState = state.actionState(action.id);
    final canStart = state.canStartAction(action);
    final isRunning = state.isActionActive(action);
    final isStunned = state.isStunned;

    final masteryLevel = levelForXp(actionState.masteryXp);
    final miningState = actionState.mining ?? const MiningState.empty();
    final maxHp = action.maxHpForMasteryLevel(masteryLevel);
    final currentHp = miningState.currentHp(action, actionState.masteryXp);

    Duration? respawnTimeRemaining;
    final respawnTicks = miningState.respawnTicksRemaining;
    if (respawnTicks != null && respawnTicks > 0) {
      respawnTimeRemaining = Duration(
        milliseconds: respawnTicks * tickDuration.inMilliseconds,
      );
    }

    final isDepleted = respawnTimeRemaining != null;
    final canToggle = (canStart || isRunning) && !isStunned && !isDepleted;

    return UnlockedActionCell(
      action: action,
      isDepleted: isDepleted,
      onTap: canToggle
          ? () => context.dispatch(ToggleActionAction(action: action))
          : null,
      child: Column(
        children: [
          const StunnedIndicator(),
          const Text('Mine'),
          Text(action.name, style: labelStyle),
          const SizedBox(height: 4),
          RockTypeBadge(rockType: action.rockType),
          const SizedBox(height: 4),
          XpBadgesRow(
            action: action,
            inradius: TextBadgeCell.smallInradius,
            trailing: DurationBadgeCell(
              seconds: action.minDuration.inSeconds,
              inradius: TextBadgeCell.smallInradius,
            ),
          ),
          const SizedBox(height: 4),
          CachedImage(assetPath: action.media, size: 64),
          const SizedBox(height: 4),
          if (respawnTimeRemaining case final respawnTime?) ...[
            Text(
              'Respawning in ${respawnTime.inSeconds}s',
              style: TextStyle(color: Style.textColorMuted),
            ),
            TweenedProgressIndicator(
              progress: ProgressAt(
                lastUpdateTime: context.state.updatedAt,
                progressTicks: action.respawnTicks - (respawnTicks ?? 0),
                totalTicks: action.respawnTicks,
              ),
              animate: true,
              backgroundColor: Style.progressBackgroundColor,
              color: Style.progressForegroundColorMuted,
            ),
          ] else ...[
            Text('$currentHp / $maxHp'),
            LinearProgressIndicator(
              value: currentHp / maxHp,
              backgroundColor: Style.progressBackgroundColor,
              color: Style.progressForegroundColor,
            ),
          ],
          const SizedBox(height: 4),
          ActionProgressBar(
            action: action,
            height: 16,
            disableWhenDepleted: isDepleted,
          ),
          const SizedBox(height: 8),
          MasteryProgressCell(masteryXp: actionState.masteryXp),
        ],
      ),
    );
  }
}

class ActionCell extends StatelessWidget {
  const ActionCell({
    required this.action,
    required this.actionState,
    required this.progressTicks,
    super.key,
  });

  final SkillAction action;
  final ActionState actionState;
  final int? progressTicks;

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(action.skill);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
      return _buildLocked(context);
    }
    return _buildUnlocked(context);
  }

  Widget _buildLocked(BuildContext context) {
    // Generic fallback for actions without a media asset
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [const Text('Locked'), Text('Level ${action.unlockLevel}')],
      ),
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final state = context.state;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final actionState = state.actionState(action.id);
    final canStart = state.canStartAction(action);
    final isRunning = state.isActionActive(action);
    final isStunned = state.isStunned;
    final canToggle = (canStart || isRunning) && !isStunned;

    return UnlockedActionCell(
      action: action,
      onTap: canToggle
          ? () => context.dispatch(ToggleActionAction(action: action))
          : null,
      child: Column(
        children: [
          const StunnedIndicator(),
          Text(action.name, style: labelStyle),
          Text('${action.minDuration.inSeconds} seconds'),
          const SizedBox(height: 4),
          XpBadgesRow(action: action),
          const SizedBox(height: 4),
          ActionProgressBar(action: action),
          MasteryProgressCell(masteryXp: actionState.masteryXp),
        ],
      ),
    );
  }
}

/// A wide red lozenge (diamond-shaped) badge showing the required level.
class LockedLevelBadge extends StatelessWidget {
  const LockedLevelBadge({required this.level, super.key});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE56767),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Level $level',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class RockTypeBadge extends StatelessWidget {
  const RockTypeBadge({required this.rockType, super.key});

  final RockType rockType;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (rockType) {
      RockType.essence => ('Essence', Style.rockTypeEssenceColor),
      RockType.ore => ('Ore', Style.rockTypeOreColor),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
