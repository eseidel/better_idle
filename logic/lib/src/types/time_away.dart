import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/inventory.dart';

/// Reason why an action stopped during time away processing.
enum ActionStopReason {
  /// Action is still running (not stopped).
  stillRunning,

  /// Ran out of input items required for the action.
  outOfInputs,

  /// Inventory is full and can't add new item types.
  inventoryFull,

  /// Player died during combat or thieving.
  playerDied,
}

class LevelChange {
  const LevelChange({required this.startLevel, required this.endLevel});

  factory LevelChange.fromJson(Map<String, dynamic> json) {
    return LevelChange(
      startLevel: json['startLevel'] as int,
      endLevel: json['endLevel'] as int,
    );
  }

  final int startLevel;
  final int endLevel;

  int get levelsGained => endLevel - startLevel;

  Map<String, dynamic> toJson() {
    return {'startLevel': startLevel, 'endLevel': endLevel};
  }

  LevelChange merge(LevelChange other) {
    // When merging level changes, take the earliest start and latest end
    return LevelChange(startLevel: startLevel, endLevel: other.endLevel);
  }
}

class TimeAway {
  const TimeAway({
    required this.registries,
    required this.startTime,
    required this.endTime,
    required this.activeSkill,
    required this.changes,
    required this.masteryLevels,
    this.activeAction,
    this.stopReason = ActionStopReason.stillRunning,
    this.stoppedAfter,
  });

  factory TimeAway.test(
    Registries registries, {
    DateTime? startTime,
    DateTime? endTime,
    Skill? activeSkill,
    Action? activeAction,
    Changes? changes,
    Map<MelvorId, int>? masteryLevels,
    ActionStopReason? stopReason,
    Duration? stoppedAfter,
  }) {
    return TimeAway(
      registries: registries,
      startTime: startTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      endTime: endTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      activeSkill: activeSkill,
      activeAction: activeAction,
      changes: changes ?? const Changes.empty(),
      masteryLevels: masteryLevels ?? const {},
      stopReason: stopReason ?? ActionStopReason.stillRunning,
      stoppedAfter: stoppedAfter,
    );
  }

  TimeAway.empty(Registries registries)
    : this(
        registries: registries,
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
        endTime: DateTime.fromMillisecondsSinceEpoch(0),
        activeSkill: null,
        activeAction: null,
        changes: const Changes.empty(),
        masteryLevels: const {},
      );

  static TimeAway? maybeFromJson(Registries registries, dynamic json) {
    if (json == null) return null;
    return TimeAway.fromJson(registries, json as Map<String, dynamic>);
  }

  factory TimeAway.fromJson(Registries registries, Map<String, dynamic> json) {
    final actionName = json['activeAction'] as String?;
    // Only reconstruct SkillActions - CombatActions are only used for
    // predictions which return empty for combat anyway.
    SkillAction? action;
    if (actionName != null) {
      final lookedUp = registries.actions.byName(actionName);
      if (lookedUp is SkillAction) {
        action = lookedUp;
      }
    }
    final stopReasonName = json['stopReason'] as String?;
    final stopReason = stopReasonName != null
        ? ActionStopReason.values.firstWhere(
            (e) => e.name == stopReasonName,
            orElse: () => ActionStopReason.stillRunning,
          )
        : ActionStopReason.stillRunning;
    final stoppedAfterMs = json['stoppedAfterMs'] as int?;
    return TimeAway(
      registries: registries,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'] as String)
          : null,
      activeAction: action,
      changes: Changes.fromJson(json['changes'] as Map<String, dynamic>),
      masteryLevels:
          maybeMap(json['masteryLevels'], toValue: (value) => value as int) ??
          {},
      stopReason: stopReason,
      stoppedAfter: stoppedAfterMs != null
          ? Duration(milliseconds: stoppedAfterMs)
          : null,
    );
  }
  final DateTime startTime;
  final DateTime endTime;
  final Skill? activeSkill;
  final Action? activeAction;
  final Changes changes;
  final Map<MelvorId, int> masteryLevels;
  final ActionStopReason stopReason;
  final Registries registries;

  /// How long after startTime the action stopped, or null if still running.
  final Duration? stoppedAfter;

  Duration get duration => endTime.difference(startTime);

  /// Calculates the predicted XP per hour for each skill based on the active
  /// action. Returns a map of Skill to XP per hour.
  /// Returns empty map for CombatActions (combat xp is handled differently).
  Map<Skill, int> get predictedXpPerHour {
    final action = activeAction;
    if (action is! SkillAction) {
      return {};
    }

    final meanDurationSeconds = action.meanDuration.inSeconds;
    if (meanDurationSeconds == 0) {
      return {};
    }

    // XP per hour = (XP per action) * (3600 seconds / mean duration in seconds)
    final xpPerHour = action.xp * (3600.0 / meanDurationSeconds);
    return {action.skill: xpPerHour.round()};
  }

  int levelForMastery(MelvorId actionId) {
    return masteryLevels[actionId] ?? 0;
  }

  /// Calculates the predicted items gained per hour based on the active
  /// action's drops (including outputs, skill-level drops, and global drops).
  /// Returns a map of item name to items per hour.
  /// Returns empty map for CombatActions (combat drops are handled
  /// differently).
  Map<String, double> get itemsGainedPerHour {
    final action = activeAction;
    if (action is! SkillAction) {
      return {};
    }

    final meanDurationSeconds = action.meanDuration.inSeconds;
    if (meanDurationSeconds == 0) {
      return {};
    }

    // Get all possible drops for this action
    // This will be an approximation since mastery level would change over time.
    final masteryLevel = levelForMastery(action.id);
    final allDrops = registries.drops.allDropsForAction(
      action,
      masteryLevel: masteryLevel,
    );
    if (allDrops.isEmpty) {
      return {};
    }

    // Calculate expected items per hour for each drop
    // Items per hour = (expected items per action) * (3600 / mean duration)
    final actionsPerHour = 3600.0 / meanDurationSeconds;
    final result = <String, double>{};

    final expectedItems = expectedItemsForDrops(allDrops);
    for (final entry in expectedItems.entries) {
      result[entry.key] = entry.value * actionsPerHour;
    }

    return result;
  }

  /// Calculates the predicted items consumed per hour based on the active
  /// action's inputs. Returns a map of item name to items per hour.
  /// Returns empty map for CombatActions (combat has no inputs).
  Map<String, double> get itemsConsumedPerHour {
    final action = activeAction;
    if (action is! SkillAction || action.inputs.isEmpty) {
      return {};
    }

    final meanDurationSeconds = action.meanDuration.inSeconds;
    if (meanDurationSeconds == 0) {
      return {};
    }

    // Calculate expected items consumed per hour for each input
    // Items per hour = (items per action) * (3600 / mean duration)
    final actionsPerHour = 3600.0 / meanDurationSeconds;
    final result = <String, double>{};

    for (final entry in action.inputs.entries) {
      final itemsPerHour = entry.value * actionsPerHour;
      result[entry.key.name] = itemsPerHour;
    }

    return result;
  }

  TimeAway copyWith({
    DateTime? startTime,
    DateTime? endTime,
    Skill? activeSkill,
    Action? activeAction,
    Changes? changes,
    Map<MelvorId, int>? masteryLevels,
    ActionStopReason? stopReason,
    Duration? stoppedAfter,
  }) {
    return TimeAway(
      registries: registries,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activeSkill: activeSkill ?? this.activeSkill,
      activeAction: activeAction ?? this.activeAction,
      changes: changes ?? this.changes,
      masteryLevels: masteryLevels ?? this.masteryLevels,
      stopReason: stopReason ?? this.stopReason,
      stoppedAfter: stoppedAfter ?? this.stoppedAfter,
    );
  }

  TimeAway mergeChanges(Changes changes) {
    return copyWith(changes: this.changes.merge(changes));
  }

  TimeAway maybeMergeInto(TimeAway? other) {
    if (other == null) {
      return this;
    }
    // When merging, take the earliest startTime and the latest endTime
    final mergedStartTime = startTime.isBefore(other.startTime)
        ? startTime
        : other.startTime;
    final mergedEndTime = endTime.isAfter(other.endTime)
        ? endTime
        : other.endTime;
    // Take the higher of the two mastery levels for each skill
    final actionIds = masteryLevels.keys.toSet().union(
      other.masteryLevels.keys.toSet(),
    );
    final mergedMasteryLevels = <MelvorId, int>{};
    for (final actionId in actionIds) {
      mergedMasteryLevels[actionId] =
          (masteryLevels[actionId] ?? 0) > (other.masteryLevels[actionId] ?? 0)
          ? masteryLevels[actionId]!
          : other.masteryLevels[actionId] ?? 0;
    }
    // For stop reason, prefer a non-stillRunning value (the most recent stop)
    final mergedStopReason = stopReason != ActionStopReason.stillRunning
        ? stopReason
        : other.stopReason;
    // Prefer a non-null stoppedAfter (the first stop)
    final mergedStoppedAfter = stoppedAfter ?? other.stoppedAfter;
    return TimeAway(
      registries: registries,
      startTime: mergedStartTime,
      endTime: mergedEndTime,
      activeSkill: activeSkill ?? other.activeSkill,
      activeAction: activeAction ?? other.activeAction,
      changes: changes.merge(other.changes),
      masteryLevels: mergedMasteryLevels,
      stopReason: mergedStopReason,
      stoppedAfter: mergedStoppedAfter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'activeSkill': activeSkill?.name,
      'activeAction': activeAction?.name,
      'changes': changes.toJson(),
      'stopReason': stopReason.name,
      'stoppedAfterMs': stoppedAfter?.inMilliseconds,
    };
  }
}

class Counts<T> {
  const Counts({required this.counts});

  const Counts.empty() : this(counts: const {});

  factory Counts.fromJson(Map<String, dynamic> json) {
    return Counts<T>(
      counts: Map<T, int>.from(
        json.map(
          (key, value) => MapEntry(Counts.fromJsonKey<T>(key), value as int),
        ),
      ),
    );
  }
  final Map<T, int> counts;

  // There must be a better way to do this in Dart?
  static String toJsonKey<T>(T key) {
    if (key is Skill) {
      return key.name;
    }
    return key.toString();
  }

  // There must be a better way to do this in Dart?
  static T fromJsonKey<T>(dynamic key) {
    if (T == Skill) {
      return Skill.fromName(key as String) as T;
    }
    return key as T;
  }

  Counts<T> add(Counts<T> other) {
    final newCounts = Map<T, int>.from(counts);
    for (final entry in other.counts.entries) {
      newCounts[entry.key] = (newCounts[entry.key] ?? 0) + entry.value;
    }
    return Counts(counts: newCounts);
  }

  Counts<T> addCount(T key, int value) {
    final newCounts = Map<T, int>.from(counts);
    newCounts[key] = (newCounts[key] ?? 0) + value;
    return Counts(counts: newCounts);
  }

  Iterable<MapEntry<T, int>> get entries => counts.entries;

  bool get isEmpty => counts.isEmpty;

  bool get isNotEmpty => counts.isNotEmpty;

  Map<String, dynamic> toJson() {
    return counts.map((key, value) => MapEntry(Counts.toJsonKey(key), value));
  }
}

class LevelChanges {
  const LevelChanges({required this.changes});

  const LevelChanges.empty() : this(changes: const {});

  factory LevelChanges.fromJson(Map<String, dynamic> json) {
    return LevelChanges(
      changes: Map<Skill, LevelChange>.from(
        json.map(
          (key, value) => MapEntry(
            Skill.fromName(key),
            LevelChange.fromJson(value as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }

  final Map<Skill, LevelChange> changes;

  LevelChanges add(LevelChanges other) {
    final newChanges = Map<Skill, LevelChange>.from(changes);
    for (final entry in other.changes.entries) {
      final existing = newChanges[entry.key];
      if (existing != null) {
        newChanges[entry.key] = existing.merge(entry.value);
      } else {
        newChanges[entry.key] = entry.value;
      }
    }
    return LevelChanges(changes: newChanges);
  }

  LevelChanges addLevelChange(Skill skill, LevelChange change) {
    final newChanges = Map<Skill, LevelChange>.from(changes);
    final existing = newChanges[skill];
    if (existing != null) {
      newChanges[skill] = existing.merge(change);
    } else {
      newChanges[skill] = change;
    }
    return LevelChanges(changes: newChanges);
  }

  Iterable<MapEntry<Skill, LevelChange>> get entries => changes.entries;

  bool get isEmpty => changes.isEmpty;

  bool get isNotEmpty => changes.isNotEmpty;

  Map<String, dynamic> toJson() {
    return changes.map((key, value) => MapEntry(key.name, value.toJson()));
  }
}

class Changes {
  const Changes({
    required this.inventoryChanges,
    required this.skillXpChanges,
    required this.droppedItems,
    required this.skillLevelChanges,
    this.gpGained = 0,
  });
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
        droppedItems: const Counts<String>.empty(),
        skillLevelChanges: const LevelChanges.empty(),
        gpGained: 0,
      );

  factory Changes.fromJson(Map<String, dynamic> json) {
    return Changes(
      inventoryChanges: Counts<String>.fromJson(
        json['inventoryChanges'] as Map<String, dynamic>,
      ),
      skillXpChanges: Counts<Skill>.fromJson(
        json['skillXpChanges'] as Map<String, dynamic>,
      ),
      droppedItems: Counts<String>.fromJson(
        json['droppedItems'] as Map<String, dynamic>? ?? {},
      ),
      skillLevelChanges: LevelChanges.fromJson(
        json['skillLevelChanges'] as Map<String, dynamic>? ?? {},
      ),
      gpGained: json['gpGained'] as int? ?? 0,
    );
  }
  final Counts<String> inventoryChanges;
  final Counts<Skill> skillXpChanges;
  final Counts<String> droppedItems;
  final LevelChanges skillLevelChanges;
  final int gpGained;

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      skillXpChanges: skillXpChanges.add(other.skillXpChanges),
      droppedItems: droppedItems.add(other.droppedItems),
      skillLevelChanges: skillLevelChanges.add(other.skillLevelChanges),
      gpGained: gpGained + other.gpGained,
    );
  }

  bool get isEmpty =>
      inventoryChanges.isEmpty &&
      skillXpChanges.isEmpty &&
      droppedItems.isEmpty &&
      skillLevelChanges.isEmpty &&
      gpGained == 0;

  Changes adding(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(stack.item.name, stack.count),
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      gpGained: gpGained,
    );
  }

  Changes removing(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(
        stack.item.name,
        -stack.count,
      ),
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      gpGained: gpGained,
    );
  }

  Changes dropping(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems.addCount(stack.item.name, stack.count),
      skillLevelChanges: skillLevelChanges,
      gpGained: gpGained,
    );
  }

  Changes addingSkillXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges.addCount(skill, amount),
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      gpGained: gpGained,
    );
  }

  Changes addingSkillLevel(Skill skill, int startLevel, int endLevel) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges.addLevelChange(
        skill,
        LevelChange(startLevel: startLevel, endLevel: endLevel),
      ),
      gpGained: gpGained,
    );
  }

  Changes addingGp(int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      gpGained: gpGained + amount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventoryChanges': inventoryChanges.toJson(),
      'skillXpChanges': skillXpChanges.toJson(),
      'droppedItems': droppedItems.toJson(),
      'skillLevelChanges': skillLevelChanges.toJson(),
      'gpGained': gpGained,
    };
  }
}
