import 'package:better_idle/src/data/actions.dart';
import 'package:better_idle/src/types/inventory.dart';

class TimeAway {
  const TimeAway({
    required this.duration,
    required this.activeSkill,
    required this.changes,
  });

  const TimeAway.empty()
    : this(
        duration: Duration.zero,
        activeSkill: null,
        changes: const Changes.empty(),
      );

  factory TimeAway.fromJson(Map<String, dynamic> json) {
    return TimeAway(
      duration: Duration(milliseconds: json['duration'] as int),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'] as String)
          : null,
      changes: Changes.fromJson(json['changes'] as Map<String, dynamic>),
    );
  }
  final Duration duration;
  final Skill? activeSkill;
  final Changes changes;

  TimeAway copyWith({
    Duration? duration,
    Skill? activeSkill,
    Changes? changes,
  }) {
    return TimeAway(
      duration: duration ?? this.duration,
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
    return mergeChanges(other.changes);
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration.inMilliseconds,
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
    return counts.map(
      (key, value) => MapEntry(Counts.toJsonKey(key), value),
    );
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
        json['inventoryChanges'] as Map<String, int>,
      ),
      skillXpChanges: Counts<Skill>.fromJson(
        json['skillXpChanges'] as Map<String, int>,
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

  Changes adding(ItemStack item) {
    return Changes(
      inventoryChanges: inventoryChanges.addCount(item.name, item.count),
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
