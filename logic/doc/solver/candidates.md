# Candidate Enumeration

Candidate enumeration proposes a small, deterministic set of actions to try at each decision point. This controls the branching factor of the A* search.

## The Candidates Structure

```dart
class Candidates {
  final List<MelvorId> switchToActivities;  // Actions to try
  final List<MelvorId> buyUpgrades;         // Upgrades to purchase
  final SellPolicy? sellPolicy;             // How to sell items
  final WatchList watch;                    // Future events
  final List<Macro> macros;                 // Macro candidates
}
```

## Candidate Selection

### Activities

Select top K actions ranked by goal rate:

```dart
// 1. Get all unlocked actions for relevant skills
// 2. Compute rate for each action
// 3. Rank by goal.activityRate()
// 4. Take top K (usually 2-3)
```

For consuming skills, special pruning avoids "near-tie explosion":
- Take top 2 consumers by sustainable rate
- Include best producer for each consumer

### Upgrades

Select top M upgrades by payback time:

```dart
paybackTime = upgradeCost / (newRate - currentRate)

// Only consider if:
// 1. Would improve current best rate
// 2. Is affordable (within watch horizon)
// 3. Makes sense for current goal
```

Heuristic prevents buying irrelevant upgrades (e.g., fishing rod while thieving).

### Sell Policy

For GP goals: `SellAllPolicy` (maximize GP)

For skill goals: `SellExceptPolicy(keepItems)` where keepItems are inputs for consuming skills.

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
  Goal goal,
  Registries registries,
  {SolverProfile? profile}
)
```

### Key Logic

```dart
// 1. Find best current action by goal rate
final currentBest = findBestUnlockedAction(state, goal, registries);

// 2. Collect candidate activities
final activities = <MelvorId>[];
for (final skill in goal.relevantSkills) {
  final unlocked = getUnlockedActions(state, skill, registries);
  final ranked = rankByGoalRate(unlocked, goal, registries);
  activities.addAll(ranked.take(kTopActivities));
}

// 3. Find competitive upgrades
final upgrades = <MelvorId>[];
for (final upgrade in allUpgrades) {
  if (!affordable(upgrade, state)) continue;
  final payback = computePayback(upgrade, currentBest, state, registries);
  if (payback < kMaxPaybackTime) {
    upgrades.add(upgrade);
  }
}

// 4. Build watch list
final watch = WatchList()
  ..watchUpgradeAffordable(relevantUpgrades)
  ..watchUnlockAvailable(lockedActions)
  ..watchInventoryFull()
  ..watchInputsDepleted();

// 5. Generate macros for skill goals
final macros = <Macro>[];
if (goal is SkillGoal) {
  macros.add(TrainSkillUntil(skill, StopAtNextBoundary, [...]));
}
```

## Consuming Skill Handling

For Firemaking/Cooking, the solver must consider producer-consumer pairs:

```dart
// 1. Find all consumer actions for the skill
final consumers = actions.forSkill(Skill.firemaking)
    .where((a) => a.hasInputs);

// 2. For each consumer, find best producer
for (final consumer in consumers) {
  final input = consumer.inputs.first;
  final producer = findBestProducerFor(input, state);

  // 3. Compute sustainable rate
  final cycleTime = inputsNeeded / producerRate + consumerDuration;
  final sustainableRate = consumerXp / cycleTime;
}

// 4. Rank by sustainable rate, take top 2 pairs
// 5. Include both consumer and producer in candidates
```

This avoids explosion from all possible pairs while ensuring optimal pairs are considered.

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
  skill: Skill.woodcutting,
  primaryStop: StopAtGoal(50),
  watchedStops: [
    StopWhenUpgradeAffordable(ironAxeId),
    StopAtNextBoundary(),  // New action unlocks
  ],
)
```

The macro expands to:
1. Find best action for skill
2. Switch to that action
3. Advance until any stop condition triggers
4. Return to normal A* search

## Candidate Count Limits

Typical limits to control branching:
- Activities: 2-3 top choices
- Upgrades: 1-2 with good payback
- Macros: 1-2 skill training options

Total branching factor per node: ~5-10 (including wait edge)
