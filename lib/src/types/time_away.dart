import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/types/inventory.dart';

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
    return {
      'startLevel': startLevel,
      'endLevel': endLevel,
    };
  }

  LevelChange merge(LevelChange other) {
    // When merging level changes, take the earliest start and latest end
    return LevelChange(
      startLevel: startLevel,
      endLevel: other.endLevel,
    );
  }
}

class TimeAway {
  const TimeAway({
    required this.startTime,
    required this.endTime,
    required this.activeSkill,
    required this.changes,
  });

  TimeAway.empty()
    : this(
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
        endTime: DateTime.fromMillisecondsSinceEpoch(0),
        activeSkill: null,
        changes: const Changes.empty(),
      );

  factory TimeAway.fromJson(Map<String, dynamic> json) {
    return TimeAway(
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'] as String)
          : null,
      changes: Changes.fromJson(json['changes'] as Map<String, dynamic>),
    );
  }
  final DateTime startTime;
  final DateTime endTime;
  final Skill? activeSkill;
  final Changes changes;

  Duration get duration => endTime.difference(startTime);

  TimeAway copyWith({
    DateTime? startTime,
    DateTime? endTime,
    Skill? activeSkill,
    Changes? changes,
  }) {
    return TimeAway(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activeSkill: activeSkill ?? this.activeSkill,
      changes: changes ?? this.changes,
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
    return TimeAway(
      startTime: mergedStartTime,
      endTime: mergedEndTime,
      activeSkill: activeSkill ?? other.activeSkill,
      changes: changes.merge(other.changes),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'activeSkill': activeSkill?.name,
      'changes': changes.toJson(),
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
  });
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
        droppedItems: const Counts<String>.empty(),
        skillLevelChanges: const LevelChanges.empty(),
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
    );
  }
  final Counts<String> inventoryChanges;
  final Counts<Skill> skillXpChanges;
  final Counts<String> droppedItems;
  final LevelChanges skillLevelChanges;

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      skillXpChanges: skillXpChanges.add(other.skillXpChanges),
      droppedItems: droppedItems.add(other.droppedItems),
      skillLevelChanges: skillLevelChanges.add(other.skillLevelChanges),
    );
  }

  bool get isEmpty =>
      inventoryChanges.isEmpty &&
      skillXpChanges.isEmpty &&
      droppedItems.isEmpty &&
      skillLevelChanges.isEmpty;

  Changes adding(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(stack.item.name, stack.count),
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
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
    );
  }

  Changes dropping(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges,
      droppedItems: droppedItems.addCount(stack.item.name, stack.count),
      skillLevelChanges: skillLevelChanges,
    );
  }

  Changes addingSkillXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges.addCount(skill, amount),
      droppedItems: droppedItems,
      skillLevelChanges: skillLevelChanges,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventoryChanges': inventoryChanges.toJson(),
      'skillXpChanges': skillXpChanges.toJson(),
      'droppedItems': droppedItems.toJson(),
      'skillLevelChanges': skillLevelChanges.toJson(),
    };
  }
}
