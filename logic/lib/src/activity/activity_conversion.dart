import 'package:logic/src/action_state.dart';
import 'package:logic/src/activity/active_activity.dart';
import 'package:logic/src/activity/combat_context.dart';
import 'package:logic/src/activity/mastery_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/state.dart';

/// Converts old [ActiveAction] + [ActionState] to new [ActiveActivity].
///
/// This is used during the transition period to support both formats.
/// Returns null if [activeAction] is null.
ActiveActivity? convertToActivity(
  ActiveAction? activeAction,
  Map<ActionId, ActionState> actionStates,
  ActionRegistry actions,
  DungeonRegistry dungeons,
) {
  if (activeAction == null) return null;

  final actionId = activeAction.id;
  final action = actions.byId(actionId);
  final actionState = actionStates[actionId];

  if (action is SkillAction) {
    return SkillActivity(
      skill: action.skill,
      actionId: actionId.localId,
      progressTicks: activeAction.progressTicks,
      totalTicks: activeAction.totalTicks,
      selectedRecipeIndex: actionState?.selectedRecipeIndex,
    );
  } else if (action is CombatAction) {
    final combatState = actionState?.combat;
    if (combatState == null) {
      // Combat without combat state shouldn't happen, but handle gracefully
      return CombatActivity(
        context: MonsterCombatContext(monsterId: actionId.localId),
        progress: CombatProgressState(
          monsterHp: 0,
          playerAttackTicksRemaining: activeAction.remainingTicks,
          monsterAttackTicksRemaining: activeAction.remainingTicks,
        ),
        progressTicks: activeAction.progressTicks,
        totalTicks: activeAction.totalTicks,
      );
    }

    // Build combat context based on whether we're in a dungeon
    final CombatContext context;
    if (combatState.dungeonId != null) {
      final dungeon = dungeons.byId(combatState.dungeonId!);
      if (dungeon != null) {
        context = DungeonCombatContext(
          dungeonId: combatState.dungeonId!,
          currentMonsterIndex: combatState.dungeonMonsterIndex ?? 0,
          monsterIds: dungeon.monsterIds,
        );
      } else {
        // Dungeon not found, fall back to monster context
        context = MonsterCombatContext(
          monsterId: combatState.monsterId.localId,
        );
      }
    } else {
      context = MonsterCombatContext(monsterId: combatState.monsterId.localId);
    }

    return CombatActivity(
      context: context,
      progress: CombatProgressState(
        monsterHp: combatState.monsterHp,
        playerAttackTicksRemaining: combatState.playerAttackTicksRemaining,
        monsterAttackTicksRemaining: combatState.monsterAttackTicksRemaining,
        spawnTicksRemaining: combatState.spawnTicksRemaining,
      ),
      progressTicks: activeAction.progressTicks,
      totalTicks: activeAction.totalTicks,
    );
  }

  throw StateError('Unknown action type: ${action.runtimeType}');
}

/// Converts new [ActiveActivity] back to old [ActiveAction].
///
/// This is used during the transition period for backward compatibility.
ActiveAction? convertToActiveAction(ActiveActivity? activity) {
  if (activity == null) return null;

  final ActionId actionId;
  if (activity is SkillActivity) {
    actionId = ActionId(activity.skill.id, activity.actionId);
  } else if (activity is CombatActivity) {
    actionId = ActionId(Skill.combat.id, activity.context.currentMonsterId);
  } else {
    throw StateError('Unknown activity type: ${activity.runtimeType}');
  }

  return ActiveAction(
    id: actionId,
    remainingTicks: activity.remainingTicks,
    totalTicks: activity.totalTicks,
  );
}

/// Converts old [ActionState] to new [MasteryState].
///
/// Extracts only the mastery-related fields, discarding combat/mining state.
MasteryState convertToMasteryState(ActionState actionState) {
  return MasteryState(
    masteryXp: actionState.masteryXp,
    cumulativeTicks: actionState.cumulativeTicks,
  );
}

/// Converts a map of [ActionState] to a map of [MasteryState].
Map<ActionId, MasteryState> convertActionStatesToMasteryStates(
  Map<ActionId, ActionState> actionStates,
) {
  return actionStates.map(
    (key, value) => MapEntry(key, convertToMasteryState(value)),
  );
}

/// Builds [CombatActionState] from [CombatActivity] for backward compatibility.
CombatActionState? buildCombatActionState(CombatActivity activity) {
  final context = activity.context;
  final progress = activity.progress;

  return CombatActionState(
    monsterId: ActionId(Skill.combat.id, context.currentMonsterId),
    monsterHp: progress.monsterHp,
    playerAttackTicksRemaining: progress.playerAttackTicksRemaining,
    monsterAttackTicksRemaining: progress.monsterAttackTicksRemaining,
    spawnTicksRemaining: progress.spawnTicksRemaining,
    dungeonId: context is DungeonCombatContext ? context.dungeonId : null,
    dungeonMonsterIndex: context is DungeonCombatContext
        ? context.currentMonsterIndex
        : null,
  );
}
