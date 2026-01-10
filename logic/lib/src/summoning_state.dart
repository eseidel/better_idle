import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// Mark level thresholds for summoning familiars.
/// Each level requires cumulative marks: 1, 6, 16, 31, 46, 61.
const List<int> markLevelThresholds = [1, 6, 16, 31, 46, 61];

/// Calculates the mark level for a given mark count.
/// Returns 0 if marks < 1, otherwise returns 1-6 based on thresholds.
int markLevelForCount(int marks) {
  if (marks < 1) return 0;
  for (var level = markLevelThresholds.length; level >= 1; level--) {
    if (marks >= markLevelThresholds[level - 1]) {
      return level;
    }
  }
  return 0;
}

/// Calculates the chance of discovering a summoning mark.
///
/// Formula: (actionTimeSeconds / ((tier + 1)² × 200)) × equipmentModifier
///
/// [actionTimeSeconds] - Duration of the action in seconds
/// [tier] - Familiar tier (1, 2, or 3)
/// [equipmentModifier] - 2.5 for non-combat skills with familiar equipped,
///                       2.0 for combat skills, 1.0 otherwise
///
/// Returns a probability between 0 and 1.
double markDiscoveryChance({
  required double actionTimeSeconds,
  required int tier,
  required double equipmentModifier,
}) {
  final tierFactor = (tier + 1) * (tier + 1); // (tier + 1)²
  final baseChance = actionTimeSeconds / (tierFactor * 200);
  return baseChance * equipmentModifier;
}

/// State for tracking discovered summoning marks per familiar.
///
/// Marks are discovered while performing skill actions. Once the first mark
/// for a familiar is found, no more marks can be found until a tablet is
/// crafted for that familiar.
@immutable
class SummoningState {
  const SummoningState({
    this.marks = const {},
    this.hasCraftedTablet = const {},
  });

  const SummoningState.empty() : this();

  factory SummoningState.fromJson(Map<String, dynamic> json) {
    final marksJson = json['marks'] as Map<String, dynamic>? ?? {};
    final marks = <MelvorId, int>{};
    for (final entry in marksJson.entries) {
      marks[MelvorId.fromJson(entry.key)] = entry.value as int;
    }

    final hasCraftedJson = json['hasCraftedTablet'] as List<dynamic>? ?? [];
    final hasCrafted = <MelvorId>{};
    for (final id in hasCraftedJson) {
      hasCrafted.add(MelvorId.fromJson(id as String));
    }

    return SummoningState(marks: marks, hasCraftedTablet: hasCrafted);
  }

  static SummoningState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return SummoningState.fromJson(json as Map<String, dynamic>);
  }

  /// Map of familiar ID to number of marks discovered.
  final Map<MelvorId, int> marks;

  /// Set of familiar IDs for which the player has crafted at least one tablet.
  /// Used to unlock further mark discovery after finding the first mark.
  final Set<MelvorId> hasCraftedTablet;

  /// Returns true if no marks have been discovered.
  bool get isEmpty => marks.isEmpty;

  /// Returns the number of marks for a specific familiar.
  int marksFor(MelvorId familiarId) => marks[familiarId] ?? 0;

  /// Returns the mark level (0-6) for a specific familiar.
  int markLevel(MelvorId familiarId) => markLevelForCount(marksFor(familiarId));

  /// Returns true if the player can craft tablets for this familiar
  /// (i.e., has at least 1 mark).
  bool canCraftTablet(MelvorId familiarId) => marksFor(familiarId) >= 1;

  /// Returns true if the player has crafted at least one tablet for this
  /// familiar.
  bool hasCrafted(MelvorId familiarId) => hasCraftedTablet.contains(familiarId);

  /// Returns true if mark discovery is blocked for this familiar.
  /// This happens when the player has found one mark but hasn't crafted
  /// a tablet yet.
  bool isMarkDiscoveryBlocked(MelvorId familiarId) {
    return marksFor(familiarId) >= 1 && !hasCrafted(familiarId);
  }

  /// Returns a new state with marks added for a familiar.
  SummoningState withMarks(MelvorId familiarId, int count) {
    final newMarks = Map<MelvorId, int>.from(marks);
    newMarks[familiarId] = (newMarks[familiarId] ?? 0) + count;
    return SummoningState(marks: newMarks, hasCraftedTablet: hasCraftedTablet);
  }

  /// Returns a new state marking that a tablet was crafted for a familiar.
  SummoningState withTabletCrafted(MelvorId familiarId) {
    if (hasCraftedTablet.contains(familiarId)) {
      return this;
    }
    final newHasCrafted = Set<MelvorId>.from(hasCraftedTablet)..add(familiarId);
    return SummoningState(marks: marks, hasCraftedTablet: newHasCrafted);
  }

  SummoningState copyWith({
    Map<MelvorId, int>? marks,
    Set<MelvorId>? hasCraftedTablet,
  }) {
    return SummoningState(
      marks: marks ?? this.marks,
      hasCraftedTablet: hasCraftedTablet ?? this.hasCraftedTablet,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (marks.isNotEmpty)
        'marks': marks.map((key, value) => MapEntry(key.toJson(), value)),
      if (hasCraftedTablet.isNotEmpty)
        'hasCraftedTablet': hasCraftedTablet.map((e) => e.toJson()).toList(),
    };
  }
}
