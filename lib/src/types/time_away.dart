import '../data/actions.dart';
import 'inventory.dart';

class TimeAway {
  const TimeAway({
    required this.duration,
    required this.activeSkill,
    required this.changes,
  });
  final Duration duration;
  final Skill? activeSkill;
  final Changes changes;

  const TimeAway.empty()
    : this(
        duration: Duration.zero,
        activeSkill: null,
        changes: const Changes.empty(),
      );

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

  factory TimeAway.fromJson(Map<String, dynamic> json) {
    return TimeAway(
      duration: Duration(milliseconds: json['duration']),
      activeSkill: json['activeSkill'] != null
          ? Skill.fromName(json['activeSkill'])
          : null,
      changes: Changes.fromJson(json['changes']),
    );
  }
}

class Counts<T> {
  const Counts({required this.counts});
  final Map<T, int> counts;

  // There must be a better way to do this in Dart?
  static dynamic toJsonKey<T>(T key) {
    if (key is Skill) {
      return key.name;
    }
    return key;
  }

  // There must be a better way to do this in Dart?
  static T fromJsonKey<T>(dynamic key) {
    if (T == Skill) {
      return Skill.fromName(key as String) as T;
    }
    return key as T;
  }

  const Counts.empty() : this(counts: const {});

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

  factory Counts.fromJson(Map<String, dynamic> json) {
    return Counts<T>(
      counts: Map<T, int>.from(
        json.map(
          (key, value) => MapEntry(Counts.fromJsonKey<T>(key), value as int),
        ),
      ),
    );
  }
}

class Changes {
  const Changes({required this.inventoryChanges, required this.skillXpChanges});
  final Counts<String> inventoryChanges;
  final Counts<Skill> skillXpChanges;
  // We don't bother tracking mastery XP changes since they're not displayed
  // in the welcome back dialog.

  const Changes.empty()
    : this(
        inventoryChanges: const Counts<String>.empty(),
        skillXpChanges: const Counts<Skill>.empty(),
      );

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

  factory Changes.fromJson(Map<String, dynamic> json) {
    return Changes(
      inventoryChanges: Counts<String>.fromJson(json['inventoryChanges']),
      skillXpChanges: Counts<Skill>.fromJson(json['skillXpChanges']),
    );
  }
}
