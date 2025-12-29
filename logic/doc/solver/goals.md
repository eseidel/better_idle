# Goals

Goals define what the solver is trying to achieve. Each goal type affects:
- How progress is measured
- What actions are considered relevant
- How the heuristic is computed
- How states are bucketed for deduplication

## Goal Types

### ReachGpGoal

Accumulate a target amount of gold pieces.

```dart
final goal = ReachGpGoal(1000);  // Reach 1000 GP
```

**Progress**: Effective credits = GP + inventory sell value

**Rate metric**: Gold per tick (from sales + direct GP gains)

**Selling**: Relevant (converts items to GP)

**Relevant skills**: All (any skill can produce sellable items)

### ReachSkillLevelGoal

Train a specific skill to a target level.

```dart
final goal = ReachSkillLevelGoal(Skill.woodcutting, 50);
```

**Progress**: Current XP in the skill

**Rate metric**: XP per tick for the target skill

**Selling**: Irrelevant (doesn't contribute XP)

**Relevant skills**: Only the target skill (for bucketing)

### MultiSkillGoal

Train multiple skills to target levels (AND semantics).

```dart
final goal = MultiSkillGoal([
  ReachSkillLevelGoal(Skill.woodcutting, 50),
  ReachSkillLevelGoal(Skill.firemaking, 50),
]);
```

**Progress**: Sum of XP remaining across unfinished skills

**Subgoals**: Each must be satisfied (trained serially)

**Heuristic**: Sum of estimated times for each unfinished skill

## Goal Interface

```dart
abstract class Goal {
  /// Check if goal is reached
  bool isSatisfied(GlobalState state);

  /// How much progress remains (units are goal-specific)
  double remaining(GlobalState state);

  /// Progress per tick given current rates
  double progressPerTick(Rates rates);

  /// Should this skill factor into bucketing?
  bool isSkillRelevant(Skill skill);

  /// Rate for this activity towards this goal
  double activityRate(MelvorId actionId, Rates rates);

  /// Human-readable description
  String describe();
}
```

## How Goals Affect Planning

### Heuristic Calculation

```dart
h(state) = remaining(state) / bestUnlockedRate
```

For multi-skill goals, this sums the time for each unfinished skill.

### State Bucketing

Only goal-relevant skills are included in the bucket key:

| Goal Type | Tracked in Bucket |
|-----------|-------------------|
| ReachGpGoal | All skills (coarse GP buckets) |
| ReachSkillLevelGoal | Only target skill |
| MultiSkillGoal | Only target skills |

### Candidate Filtering

The goal's `activityRate()` method ranks actions:
- GP goal: ranks by gold value per tick
- Skill goal: ranks by XP per tick for that skill
- Actions with zero rate for the goal are excluded

## Example: How a Skill Goal Works

For `ReachSkillLevelGoal(Skill.woodcutting, 50)`:

1. **Progress check**: `state.skillState(woodcutting).xp >= xpForLevel(50)`

2. **Rate calculation**: Only woodcutting XP/tick matters

3. **Candidate selection**:
   - Cut Normal Logs: 10 XP/tick
   - Cut Oak Logs: 15 XP/tick (if unlocked)
   - Fishing: 0 XP/tick (wrong skill, excluded)

4. **Bucketing**: Only woodcutting level tracked, not fishing

5. **Heuristic**: `remainingXp / bestWoodcuttingXpPerTick`

## Example: Multi-Skill Goal

For `MultiSkillGoal([Woodcutting=50, Firemaking=50])`:

1. **Training order**: Typically woodcutting first (provides logs)

2. **Progress**: Sum of remaining XP for unfinished skills

3. **Heuristic**: Sum of individual times
   - Time to 50 woodcutting at best rate
   - Time to 50 firemaking at best sustainable rate

4. **Consuming skill handling**: Firemaking uses logs from woodcutting
   - Sustainable rate accounts for log production
   - Producer skill gets implicit XP during consumer training
