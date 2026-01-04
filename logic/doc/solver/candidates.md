# Candidate Enumeration

Candidate enumeration proposes a small, deterministic set of actions to try at each decision point. This controls the branching factor of the A* search.

## Two Distinct Outputs

* **Branch candidates** (`switchToActivities`, `buyUpgrades`, `sellPolicy`): Actions we're willing to consider now.
* **Watch candidates** (`WatchList`): Events that define "interesting times" for waiting (affordability, unlocks, inventory).

## Key Invariant: Watch ≠ Action

`buyUpgrades` must contain only upgrades that are **actionable and competitive** under the current policy:
- Apply to current activity or top candidate activities
- Positive gain under ValueModel
- Pass heuristics / top-K filters

`WatchList.upgradePurchaseIds` may include a broader set to compute time-to-afford / future replan moments.

**Never promote watch-only upgrades into buyUpgrades just because they are affordable.**

## The Candidates Structure

```dart
class Candidates {
  final List<ActionId> switchToActivities;  // Actions to try
  final List<MelvorId> buyUpgrades;          // Upgrades to purchase
  final SellPolicy sellPolicy;               // Policy from goal (always present)
  final bool shouldEmitSellCandidate;        // Heuristic: whether to branch on selling
  final WatchList watch;                     // Future events
  final List<MacroCandidate> macros;         // Macro candidates
  final ConsumingSkillCandidateStats? consumingSkillStats;  // Diagnostics
}

class WatchList {
  final List<MelvorId> upgradePurchaseIds;    // Upgrades to watch for affordability
  final List<ActionId> lockedActivityIds;     // Locked actions to watch for unlocking
  final List<ActionId> consumingActivityIds;  // Consuming actions (for inputs available)
  final bool inventory;                       // Watch inventory fill
}
```

## Candidate Selection

### Activities

Select top K actions ranked by goal rate:

```dart
// 1. Get all unlocked actions for relevant skills
// 2. Compute rate for each action
// 3. Rank by goal.activityRate()
// 4. Take top K (default 8)
```

For consuming skills, special pruning avoids "near-tie explosion":
- Take top 2 consumers by sustainable rate
- Include best producer for each consumer

**Producer Inclusion**: For goals involving consuming skills, producers are unconditionally included as candidates (not gated on feasibility). This provides an escape hatch when inputs are needed.

### Upgrades

Select top M upgrades by payback time:

```dart
paybackTime = upgradeCost / (newRate - currentRate)

// Only consider if:
// 1. Would improve current best rate
// 2. New rate beats or matches best current rate (competitive)
// 3. Meets skill requirements
// 4. Relevant to goal skills
```

Key guard: Skip upgrades where the upgraded rate wouldn't beat the best current rate. This prevents "buy axe while thieving" bugs.

### Sell Policy

The sell policy is a **POLICY decision** from the goal, not a heuristic:
- GP goals: `SellAllPolicy` (all items contribute to GP)
- Skill goals: `SellExceptPolicy(keepItems)` where keepItems are inputs for consuming skills

`shouldEmitSellCandidate` is a separate **HEURISTIC decision**:
- For GP goals: true when inventory is getting full
- For skill goals: false (selling doesn't contribute to XP)

### Watch List

Future events that define decision points:
- Upgrade becomes affordable
- Locked action becomes unlockable
- Inventory fills
- Inputs depleted (consuming skills)
- Inputs available for watched activities

## enumerateCandidates() Function

```dart
Candidates enumerateCandidates(
  GlobalState state,
  Goal goal, {
  SellPolicy? sellPolicy,                           // Optional override
  int activityCount = defaultActivityCandidateCount,  // K=8
  int upgradeCount = defaultUpgradeCandidateCount,    // M=8
  int lockedWatchCount = defaultLockedWatchCount,     // L=3
  double inventoryThreshold = defaultInventoryThreshold,  // 0.8
  bool collectStats = false,
})
```

### Key Logic

```dart
// 1. Get cached rate summaries (capability-level, goal-independent)
final rateSummaries = _getRateSummaries(state);

// 2. Generate macro candidates for skill goals
final macros = _generateMacros(state, goal);

// 3. Select unlocked activity candidates
// For consuming skills, use strict pruning
if (goal is ReachSkillLevelGoal && goal.skill.isConsuming) {
  final result = _selectConsumingSkillCandidatesWithStats(...);
  candidateSet.addAll(result.candidates);
} else {
  final selected = _selectUnlockedActivitiesByRanking(...);
  candidateSet.addAll(selected);
}

// 4. ALWAYS include producers for consuming goal skills (UNCONDITIONAL)
for (final consumingSkill in goal.consumingSkills) {
  final producers = _selectTopProducers(rateSummaries, producerSkill, 2);
  candidateSet.addAll(producers);
}

// 5. Select upgrade candidates (only competitive ones)
final upgradeResult = _selectUpgradeCandidates(...);

// 6. Augment macros with upgrade stops
final augmentedMacros = _augmentMacrosWithUpgradeStops(macros, ...);

// 7. Use provided sellPolicy or compute from goal
final effectiveSellPolicy = sellPolicy ?? goal.computeSellPolicy(state);
```

## Consuming Skill Handling

For Firemaking/Cooking/Smithing, the solver must consider producer-consumer pairs:

```dart
// 1. Find all unlocked consumer actions for the skill
final consumerActions = summaries
    .where((s) => s.skill == consumingSkill && s.isUnlocked && s.hasInputs);

// 2. For each consumer, find best producer
for (final consumerSummary in consumerActions) {
  final inputItem = consumerAction.inputs.keys.first;
  final producers = _findProducersForItem(summaries, state, inputItem);

  // Best producer = highest output/tick
  producers.sort((a, b) => bOutputPerTick.compareTo(aOutputPerTick));
  final bestProducer = producers.first;

  // 3. Compute sustainable rate
  final produceActionsPerConsumeAction = inputsNeeded / outputsPerAction;
  final totalTicksPerCycle = (produceActionsPerConsumeAction * produceTicks) + consumeTicks;
  final sustainableXpPerTick = consumeXp / totalTicksPerCycle;
}

// 4. Rank by sustainable rate, take top 2 pairs
// 5. Include both consumer and producer in candidates
```

This avoids explosion from all possible pairs while ensuring optimal pairs are considered.

## Rate Caching

The module uses a capability-level rate cache for expensive computations:

```dart
// Packed capability key includes:
// - All skill levels (7 bits each)
// - Tool tiers (3 bits each)

// Cache is cleared between solver runs
void clearRateCache();

// Cache statistics for profiling
int get rateCacheHits;
int get rateCacheMisses;
```

## Watch vs Action Invariant

**Watch list**: Events that *might* be interesting later
**Action list**: Things to try *now*

Key invariant: Watched events don't force immediate action.

```dart
// Upgrade becomes affordable -> doesn't force dt=0
// Only upgrades in buyUpgrades (competitive set) trigger actions

// This prevents:
// - Branching on every affordable upgrade
// - Buying irrelevant upgrades just because affordable
```

## Macros for Skill Goals

For skill-level goals, macros reduce branching:

```dart
TrainSkillUntil(
  Skill.woodcutting,
  StopAtGoal(Skill.woodcutting, targetXp),
  watchedStops: [
    StopWhenUpgradeAffordable(ironAxeId, cost, 'Iron Axe'),
    StopAtNextBoundary(Skill.woodcutting),
  ],
)
```

The macro expands to:
1. Find best action for skill
2. Switch to that action
3. Advance until any stop condition triggers
4. Return to normal A* search

Macros are augmented with upgrade stops from the watch list to allow early breaking when valuable upgrades become affordable.

## Candidate Count Limits

Default limits to control branching:
- Activities: 8 top choices (`defaultActivityCandidateCount`)
- Upgrades: 8 with good payback (`defaultUpgradeCandidateCount`)
- Locked actions to watch: 3 (`defaultLockedWatchCount`)
- Inventory threshold: 0.8 (80%)

Total branching factor per node: ~5-10 (including wait edge)
