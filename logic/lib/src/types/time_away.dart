import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/json.dart';
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
    this.recipeSelection = const NoSelectedRecipe(),
    this.stopReason = ActionStopReason.stillRunning,
    this.stoppedAfter,
    this.doublingChance = 0.0,
  });

  factory TimeAway.fromJson(Registries registries, Map<String, dynamic> json) {
    final actionId = ActionId.maybeFromJson(json['activeAction'] as String?);
    // Only reconstruct SkillActions - CombatActions are only used for
    // predictions which return empty for combat anyway.
    SkillAction? action;
    if (actionId != null) {
      final lookedUp = registries.actions.byId(actionId);
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
    final recipeIndex = json['recipeIndex'] as int?;
    final recipeSelection = recipeIndex != null
        ? SelectedRecipe(index: recipeIndex)
        : const NoSelectedRecipe();

    return TimeAway(
      registries: registries,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'] as String)
          : null,
      activeAction: action,
      recipeSelection: recipeSelection,
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

  factory TimeAway.test(
    Registries registries, {
    DateTime? startTime,
    DateTime? endTime,
    Skill? activeSkill,
    Action? activeAction,
    RecipeSelection? recipeSelection,
    Changes? changes,
    Map<ActionId, int>? masteryLevels,
    ActionStopReason? stopReason,
    Duration? stoppedAfter,
    double? doublingChance,
  }) {
    return TimeAway(
      registries: registries,
      startTime: startTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      endTime: endTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      activeSkill: activeSkill,
      activeAction: activeAction,
      recipeSelection: recipeSelection ?? const NoSelectedRecipe(),
      changes: changes ?? const Changes.empty(),
      masteryLevels: masteryLevels ?? const {},
      stopReason: stopReason ?? ActionStopReason.stillRunning,
      stoppedAfter: stoppedAfter,
      doublingChance: doublingChance ?? 0.0,
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

  final DateTime startTime;
  final DateTime endTime;
  final Skill? activeSkill;
  final Action? activeAction;
  final RecipeSelection recipeSelection;
  final Changes changes;
  final Map<ActionId, int> masteryLevels;
  final ActionStopReason stopReason;
  final Registries registries;

  /// How long after startTime the action stopped, or null if still running.
  final Duration? stoppedAfter;

  /// The item doubling chance (0.0-1.0) from skillItemDoublingChance modifier.
  final double doublingChance;

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

  int levelForMastery(ActionId actionId) {
    return masteryLevels[actionId] ?? 0;
  }

  /// Calculates the predicted items gained per hour based on the active
  /// action's drops (including outputs, skill-level drops, and global drops).
  /// Returns a map of item name to items per hour.
  /// Returns empty map for CombatActions (combat drops are handled
  /// differently).
  Map<MelvorId, double> get itemsGainedPerHour {
    final action = activeAction;
    if (action is! SkillAction) {
      return {};
    }

    final meanDurationSeconds = action.meanDuration.inSeconds;
    if (meanDurationSeconds == 0) {
      return {};
    }

    // Get all possible drops for this action using the selected recipe.
    final allDrops = registries.drops.allDropsForAction(
      action,
      recipeSelection,
    );
    if (allDrops.isEmpty) {
      return {};
    }

    // Calculate expected items per hour for each drop
    // Items per hour = (expected items per action) * (3600 / mean duration)
    final actionsPerHour = 3600.0 / meanDurationSeconds;
    final multiplier = 1.0 + doublingChance;
    final result = <MelvorId, double>{};

    // Compute expected items using base drop rates
    // TODO(future): Account for randomProductChance modifiers for more accuracy
    for (final drop in allDrops) {
      for (final entry in drop.expectedItems.entries) {
        final value = entry.value * multiplier * actionsPerHour;
        result[entry.key] = (result[entry.key] ?? 0) + value;
      }
    }

    return result;
  }

  /// Calculates the predicted items consumed per hour based on the active
  /// action's inputs. Returns a map of item name to items per hour.
  /// Returns empty map for CombatActions (combat has no inputs).
  Map<MelvorId, double> get itemsConsumedPerHour {
    final action = activeAction;
    if (action is! SkillAction) {
      return {};
    }

    final inputs = action.inputsForRecipe(recipeSelection);
    if (inputs.isEmpty) {
      return {};
    }

    final meanDurationSeconds = action.meanDuration.inSeconds;
    if (meanDurationSeconds == 0) {
      return {};
    }

    // Calculate expected items consumed per hour for each input
    // Items per hour = (items per action) * (3600 / mean duration)
    final actionsPerHour = 3600.0 / meanDurationSeconds;
    final result = <MelvorId, double>{};

    for (final entry in inputs.entries) {
      final itemsPerHour = entry.value * actionsPerHour;
      result[entry.key] = itemsPerHour;
    }

    return result;
  }

  TimeAway copyWith({
    DateTime? startTime,
    DateTime? endTime,
    Skill? activeSkill,
    Action? activeAction,
    RecipeSelection? recipeSelection,
    Changes? changes,
    Map<ActionId, int>? masteryLevels,
    ActionStopReason? stopReason,
    Duration? stoppedAfter,
    double? doublingChance,
  }) {
    return TimeAway(
      registries: registries,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activeSkill: activeSkill ?? this.activeSkill,
      activeAction: activeAction ?? this.activeAction,
      recipeSelection: recipeSelection ?? this.recipeSelection,
      changes: changes ?? this.changes,
      masteryLevels: masteryLevels ?? this.masteryLevels,
      stopReason: stopReason ?? this.stopReason,
      stoppedAfter: stoppedAfter ?? this.stoppedAfter,
      doublingChance: doublingChance ?? this.doublingChance,
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
    final mergedMasteryLevels = <ActionId, int>{};
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
    // Use the higher doubling chance (most recent state)
    final mergedDoublingChance = doublingChance > other.doublingChance
        ? doublingChance
        : other.doublingChance;
    // Prefer the most recent recipe selection (from this)
    final mergedRecipeSelection = recipeSelection is SelectedRecipe
        ? recipeSelection
        : other.recipeSelection;
    return TimeAway(
      registries: registries,
      startTime: mergedStartTime,
      endTime: mergedEndTime,
      activeSkill: activeSkill ?? other.activeSkill,
      activeAction: activeAction ?? other.activeAction,
      recipeSelection: mergedRecipeSelection,
      changes: changes.merge(other.changes),
      masteryLevels: mergedMasteryLevels,
      stopReason: mergedStopReason,
      stoppedAfter: mergedStoppedAfter,
      doublingChance: mergedDoublingChance,
    );
  }

  Map<String, dynamic> toJson() {
    final recipeIndex = switch (recipeSelection) {
      NoSelectedRecipe() => null,
      SelectedRecipe(:final index) => index,
    };
    return {
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'activeSkill': activeSkill?.name,
      'activeAction': activeAction?.id.toJson(),
      'recipeIndex': ?recipeIndex,
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
    if (T == MelvorId) {
      return MelvorId.fromJson(key as String) as T;
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
    this.currenciesGained = const {},
    this.lostOnDeath = const Counts<MelvorId>.empty(),
    this.deathCount = 0,
  });
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<MelvorId>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
        droppedItems: const Counts<MelvorId>.empty(),
        skillLevelChanges: const LevelChanges.empty(),
        currenciesGained: const {},
        lostOnDeath: const Counts<MelvorId>.empty(),
        deathCount: 0,
      );

  factory Changes.fromJson(Map<String, dynamic> json) {
    return Changes(
      inventoryChanges: Counts<MelvorId>.fromJson(
        json['inventoryChanges'] as Map<String, dynamic>,
      ),
      skillXpChanges: Counts<Skill>.fromJson(
        json['skillXpChanges'] as Map<String, dynamic>,
      ),
      droppedItems: Counts<MelvorId>.fromJson(
        json['droppedItems'] as Map<String, dynamic>? ?? {},
      ),
      skillLevelChanges: LevelChanges.fromJson(
        json['skillLevelChanges'] as Map<String, dynamic>? ?? {},
      ),
      currenciesGained: _currenciesFromJson(json),
      lostOnDeath: Counts<MelvorId>.fromJson(
        json['lostOnDeath'] as Map<String, dynamic>? ?? {},
      ),
      deathCount: json['deathCount'] as int? ?? 0,
    );
  }

  static Map<Currency, int> _currenciesFromJson(Map<String, dynamic> json) {
    final currenciesJson =
        json['currenciesGained'] as Map<String, dynamic>? ?? {};
    return currenciesJson.map((key, value) {
      final currency = Currency.fromIdString(key);
      return MapEntry(currency, value as int);
    });
  }

  final Counts<Skill> skillXpChanges;
  final Counts<MelvorId> inventoryChanges;
  final Counts<MelvorId> droppedItems;
  final LevelChanges skillLevelChanges;
  final Map<Currency, int> currenciesGained;
  final Counts<MelvorId> lostOnDeath;
  final int deathCount;

  /// Helper to merge two currency maps.
  static Map<Currency, int> _mergeCurrencies(
    Map<Currency, int> a,
    Map<Currency, int> b,
  ) {
    final result = Map<Currency, int>.from(a);
    for (final entry in b.entries) {
      result[entry.key] = (result[entry.key] ?? 0) + entry.value;
    }
    return result;
  }

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      skillXpChanges: skillXpChanges.add(other.skillXpChanges),
      droppedItems: droppedItems.add(other.droppedItems),
      skillLevelChanges: skillLevelChanges.add(other.skillLevelChanges),
      currenciesGained: _mergeCurrencies(
        currenciesGained,
        other.currenciesGained,
      ),
      lostOnDeath: lostOnDeath.add(other.lostOnDeath),
      deathCount: deathCount + other.deathCount,
    );
  }

  bool get isEmpty =>
      inventoryChanges.isEmpty &&
      skillXpChanges.isEmpty &&
      droppedItems.isEmpty &&
      skillLevelChanges.isEmpty &&
      currenciesGained.isEmpty &&
      lostOnDeath.isEmpty &&
      deathCount == 0;

  Changes adding(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(stack.item.id, stack.count),
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
    );
  }

  Changes removing(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(stack.item.id, -stack.count),
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
    );
  }

  Changes dropping(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems.addCount(stack.item.id, stack.count),
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
    );
  }

  Changes addingSkillXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges.addCount(skill, amount),
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
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
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
    );
  }

  Changes addingCurrency(Currency currency, int amount) {
    final newCurrencies = Map<Currency, int>.from(currenciesGained);
    newCurrencies[currency] = (newCurrencies[currency] ?? 0) + amount;
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: newCurrencies,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount,
    );
  }

  /// Tracks an item lost due to death penalty.
  Changes losingOnDeath(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath.addCount(stack.item.id, stack.count),
      deathCount: deathCount,
    );
  }

  /// Records a death occurrence (increments death count).
  Changes recordingDeath() {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
      currenciesGained: currenciesGained,
      lostOnDeath: lostOnDeath,
      deathCount: deathCount + 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventoryChanges': inventoryChanges.toJson(),
      'skillXpChanges': skillXpChanges.toJson(),
      'droppedItems': droppedItems.toJson(),
      'skillLevelChanges': skillLevelChanges.toJson(),
      'currenciesGained': currenciesGained.map(
        (key, value) => MapEntry(key.id.toJson(), value),
      ),
      'lostOnDeath': lostOnDeath.toJson(),
      'deathCount': deathCount,
    };
  }
}
