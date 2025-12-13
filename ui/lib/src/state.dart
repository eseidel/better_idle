// Re-export state types from logic package for backward compatibility
export 'package:async_redux/async_redux.dart';
export 'package:logic/logic.dart'
    show
        ActionState,
        ActiveAction,
        CombatActionState,
        GlobalState,
        MiningState,
        ShopState,
        SkillState,
        Tick,
        initialBankSlots,
        maxPlayerHp,
        monsterRespawnDuration,
        playerStats,
        tickDuration,
        ticksFromDuration;
