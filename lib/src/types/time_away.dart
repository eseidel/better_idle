import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/types/inventory.dart';

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

class Changes {
  const Changes({required this.inventoryChanges, required this.skillXpChanges});
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
      );

  factory Changes.fromJson(Map<String, dynamic> json) {
    return Changes(
      inventoryChanges: Counts<String>.fromJson(
        json['inventoryChanges'] as Map<String, dynamic>,
      ),
      skillXpChanges: Counts<Skill>.fromJson(
        json['skillXpChanges'] as Map<String, dynamic>,
      ),
    );
  }
  final Counts<String> inventoryChanges;
  final Counts<Skill> skillXpChanges;

  Changes merge(Changes other) {
    return Changes(
      inventoryChanges: inventoryChanges.add(other.inventoryChanges),
      skillXpChanges: skillXpChanges.add(other.skillXpChanges),
    );
  }

  bool get isEmpty => inventoryChanges.isEmpty && skillXpChanges.isEmpty;

  Changes adding(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(stack.item.name, stack.count),
      skillXpChanges: skillXpChanges,
    );
  }

  Changes removing(ItemStack stack) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(
        stack.item.name,
        -stack.count,
      ),
      skillXpChanges: skillXpChanges,
    );
  }

  Changes addingSkillXp(Skill skill, int amount) {
    return Changes(
      inventoryChanges: inventoryChanges,
      skillXpChanges: skillXpChanges.addCount(skill, amount),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventoryChanges': inventoryChanges.toJson(),
      'skillXpChanges': skillXpChanges.toJson(),
    };
  }
}
