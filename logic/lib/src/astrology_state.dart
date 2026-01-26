import 'package:logic/src/data/astrology.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/json.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// Tracks purchased modifier levels for a single constellation.
@immutable
class ConstellationModifierState {
  const ConstellationModifierState({
    this.standardLevels = const [],
    this.uniqueLevels = const [],
  });

  const ConstellationModifierState.empty() : this();

  factory ConstellationModifierState.fromJson(Map<String, dynamic> json) {
    return ConstellationModifierState(
      standardLevels: _parseIntList(json['standardLevels']),
      uniqueLevels: _parseIntList(json['uniqueLevels']),
    );
  }

  static List<int> _parseIntList(dynamic json) {
    if (json == null) return const [];
    return (json as List<dynamic>).cast<int>();
  }

  /// Purchased level for each standard modifier (index matches modifier index).
  final List<int> standardLevels;

  /// Purchased level for each unique modifier (index matches modifier index).
  final List<int> uniqueLevels;

  Map<String, dynamic> toJson() {
    return {'standardLevels': standardLevels, 'uniqueLevels': uniqueLevels};
  }

  /// Get the purchased level for a modifier at the given index.
  int levelFor(AstrologyModifierType type, int index) {
    final levels = type == AstrologyModifierType.standard
        ? standardLevels
        : uniqueLevels;
    if (index >= levels.length) return 0;
    return levels[index];
  }

  /// Yields all active modifier effects for a constellation.
  ///
  /// Each modifier that applies to multiple skills yields one entry per skill.
  Iterable<ModifierData> activeModifiers(AstrologyAction constellation) sync* {
    for (var i = 0; i < constellation.standardModifiers.length; i++) {
      final level = levelFor(AstrologyModifierType.standard, i);
      if (level > 0) {
        yield constellation.standardModifiers[i].toModifierData(level);
      }
    }
    for (var i = 0; i < constellation.uniqueModifiers.length; i++) {
      final level = levelFor(AstrologyModifierType.unique, i);
      if (level > 0) {
        yield constellation.uniqueModifiers[i].toModifierData(level);
      }
    }
  }

  /// Create a copy with an incremented level for the specified modifier.
  ConstellationModifierState withIncrementedLevel(
    AstrologyModifierType type,
    int index,
  ) {
    if (type == AstrologyModifierType.standard) {
      final newLevels = _ensureLength(standardLevels, index + 1);
      newLevels[index]++;
      return ConstellationModifierState(
        standardLevels: newLevels,
        uniqueLevels: uniqueLevels,
      );
    } else {
      final newLevels = _ensureLength(uniqueLevels, index + 1);
      newLevels[index]++;
      return ConstellationModifierState(
        standardLevels: standardLevels,
        uniqueLevels: newLevels,
      );
    }
  }

  List<int> _ensureLength(List<int> list, int length) {
    final newList = List<int>.from(list);
    while (newList.length < length) {
      newList.add(0);
    }
    return newList;
  }
}

/// Tracks all astrology modifier purchases across all constellations.
@immutable
class AstrologyState {
  const AstrologyState({this.constellationStates = const {}});

  const AstrologyState.empty() : this();

  factory AstrologyState.fromJson(Map<String, dynamic> json) {
    return AstrologyState(
      constellationStates:
          maybeMap(
            json['constellationStates'],
            toKey: MelvorId.fromJson,
            toValue: (dynamic v) =>
                ConstellationModifierState.fromJson(v as Map<String, dynamic>),
          ) ??
          const {},
    );
  }

  /// Map of constellation ID to its modifier state.
  final Map<MelvorId, ConstellationModifierState> constellationStates;

  Map<String, dynamic> toJson() {
    return {
      'constellationStates': constellationStates.map(
        (key, value) => MapEntry(key.toJson(), value.toJson()),
      ),
    };
  }

  /// Get the modifier state for a constellation, or empty if none purchased.
  ConstellationModifierState stateFor(MelvorId constellationId) {
    return constellationStates[constellationId] ??
        const ConstellationModifierState.empty();
  }

  /// Create a copy with updated state for a constellation.
  AstrologyState withConstellationState(
    MelvorId constellationId,
    ConstellationModifierState state,
  ) {
    return AstrologyState(
      constellationStates: {...constellationStates, constellationId: state},
    );
  }
}
