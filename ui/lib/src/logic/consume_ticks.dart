// Re-export consume_ticks types from logic package for backward compatibility
export 'package:logic/logic.dart'
    show
        BackgroundTickConsumer,
        BackgroundTickResult,
        Changes,
        ForegroundResult,
        MiningBackgroundAction,
        MiningTickResult,
        StateUpdateBuilder,
        TimeAway,
        XpPerAction,
        applyMiningTicks,
        calculateMasteryXpPerAction,
        completeAction,
        consumeAllTicks,
        consumeManyTicks,
        consumeTicks,
        consumeTicksForAllSystems,
        getCurrentHp,
        masteryXpPerAction,
        ticksPer1Hp,
        xpPerAction;
