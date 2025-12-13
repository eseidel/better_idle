import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/data/xp.dart';
import 'package:better_idle/src/logic/consume_ticks.dart';
import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/state.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:flutter/material.dart' hide Action;

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
              final actionState = context.state.actionState(action.name);
              return SizedBox(
                width: cellSize.width,
                height: cellSize.height,
                child: ActionCell(
                  action: action,
                  actionState: actionState,
                  progressTicks: progressTicks,
                ),
              );
            }).toList(),
          ),
        ),
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

  Widget _buildUnlocked(BuildContext context) {
    final actionName = action.name;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final activeAction = context.state.activeAction;
    double progress;
    if (activeAction?.name == actionName && activeAction != null) {
      progress =
          (activeAction.totalTicks - activeAction.remainingTicks) /
          activeAction.totalTicks;
    } else {
      progress = 0.0;
    }
    final actionState = context.state.actionState(actionName);
    final canStart = context.state.canStartAction(action);
    final isRunning = context.state.activeAction?.name == actionName;
    final canToggle = canStart || isRunning;

    // Check if this is a mining action
    final masteryLevel = levelForXp(actionState.masteryXp);

    int? currentHp;
    int? maxHp;
    Duration? respawnTimeRemaining;
    double? respawnProgress;

    if (action case final MiningAction miningAction) {
      final miningState = actionState.mining ?? const MiningState.empty();
      maxHp = miningAction.maxHpForMasteryLevel(masteryLevel);
      currentHp = getCurrentHp(
        miningAction,
        miningState,
        actionState.masteryXp,
      );

      final respawnTicks = miningState.respawnTicksRemaining;
      if (respawnTicks != null && respawnTicks > 0) {
        respawnTimeRemaining = Duration(
          milliseconds: respawnTicks * tickDuration.inMilliseconds,
        );
        respawnProgress = miningAction.respawnProgress(actionState);
      }
    }

    final isDepleted = respawnTimeRemaining != null;

    return GestureDetector(
      onTap: canToggle && !isDepleted
          ? () {
              context.dispatch(ToggleActionAction(action: action));
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDepleted ? Colors.grey[200] : Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            const Text('Cut'),
            Text(actionName, style: labelStyle),
            if (action case final MiningAction miningAction) ...[
              const SizedBox(height: 4),
              RockTypeBadge(rockType: miningAction.rockType),
            ],
            Text(
              '${action.xp} Skill XP, ${action.minDuration.inSeconds} seconds',
            ),
            if (action is MiningAction) ...[
              const SizedBox(height: 4),
              if (respawnTimeRemaining case final respawnTime?) ...[
                Text(
                  'Respawning in ${respawnTime.inSeconds}s',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                LinearProgressIndicator(
                  value: respawnProgress ?? 0,
                  backgroundColor: Colors.grey[300],
                  color: Colors.grey[600],
                ),
              ] else ...[
                Text('HP: $currentHp / $maxHp'),
                LinearProgressIndicator(
                  value: currentHp! / maxHp!,
                  backgroundColor: Colors.grey[300],
                  color: Colors.blue,
                ),
              ],
            ],
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
            MasteryProgressCell(masteryXp: actionState.masteryXp),
          ],
        ),
      ),
    );
  }

  Widget _buildLocked(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [const Text('Locked'), Text('Level ${action.unlockLevel}')],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skillState = context.state.skillState(action.skill);
    final skillLevel = levelForXp(skillState.xp);
    final isUnlocked = skillLevel >= action.unlockLevel;
    if (isUnlocked) {
      return _buildUnlocked(context);
    } else {
      return _buildLocked(context);
    }
  }
}

class RockTypeBadge extends StatelessWidget {
  const RockTypeBadge({required this.rockType, super.key});

  final RockType rockType;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (rockType) {
      RockType.essence => ('Essence', Colors.purple[100]!),
      RockType.ore => ('Ore', Colors.brown[200]!),
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
