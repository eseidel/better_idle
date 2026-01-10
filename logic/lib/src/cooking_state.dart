import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/tick.dart';
import 'package:meta/meta.dart';

/// The three cooking areas in Melvor Idle.
/// Each area can cook a subset of recipes and can be upgraded separately.
enum CookingArea {
  fire('Fire'),
  furnace('Furnace'),
  pot('Pot');

  const CookingArea(this.displayName);

  final String displayName;

  /// Creates a CookingArea from a Melvor categoryId.
  /// Expects the localId to be 'Fire', 'Furnace', or 'Pot'.
  static CookingArea? fromCategoryId(MelvorId? categoryId) {
    if (categoryId == null) return null;
    return switch (categoryId.localId) {
      'Fire' => CookingArea.fire,
      'Furnace' => CookingArea.furnace,
      'Pot' => CookingArea.pot,
      _ => null,
    };
  }

  /// Returns the MelvorId for this cooking area.
  MelvorId get categoryId => MelvorId('melvorD:$displayName');
}

/// State for a single cooking area (Fire, Furnace, or Pot).
///
/// Each area can have a recipe assigned and tracks its progress independently.
/// When cooking is active, one area is "active" (full rewards) and others are
/// "passive" (cook at 5x slower rate, no XP/mastery/bonuses).
@immutable
class CookingAreaState {
  const CookingAreaState({
    this.recipeId,
    this.progressTicksRemaining,
    this.totalTicks,
  });

  const CookingAreaState.empty() : this();

  factory CookingAreaState.fromJson(Map<String, dynamic> json) {
    return CookingAreaState(
      recipeId: ActionId.maybeFromJson(json['recipeId']),
      progressTicksRemaining: json['progressTicksRemaining'] as Tick?,
      totalTicks: json['totalTicks'] as Tick?,
    );
  }

  /// Deserializes a [CookingAreaState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static CookingAreaState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return CookingAreaState.fromJson(json as Map<String, dynamic>);
  }

  /// The cooking recipe assigned to this area (null if no recipe assigned).
  final ActionId? recipeId;

  /// Ticks remaining until current cook completes (countdown pattern).
  /// Null if no recipe is actively being cooked.
  final Tick? progressTicksRemaining;

  /// Total ticks for the current recipe (used for progress bar display).
  final Tick? totalTicks;

  /// Returns true if no recipe is assigned to this area.
  bool get isEmpty => recipeId == null;

  /// Returns true if a recipe is assigned and actively cooking.
  bool get isActive => recipeId != null && progressTicksRemaining != null;

  CookingAreaState copyWith({
    ActionId? recipeId,
    Tick? progressTicksRemaining,
    Tick? totalTicks,
  }) {
    return CookingAreaState(
      recipeId: recipeId ?? this.recipeId,
      progressTicksRemaining:
          progressTicksRemaining ?? this.progressTicksRemaining,
      totalTicks: totalTicks ?? this.totalTicks,
    );
  }

  /// Creates a copy with progress cleared (recipe still assigned).
  CookingAreaState withProgressCleared() {
    return CookingAreaState(recipeId: recipeId);
  }

  /// Creates a copy with recipe and progress cleared.
  CookingAreaState cleared() => const CookingAreaState.empty();

  Map<String, dynamic> toJson() {
    return {
      if (recipeId != null) 'recipeId': recipeId!.toJson(),
      if (progressTicksRemaining != null)
        'progressTicksRemaining': progressTicksRemaining,
      if (totalTicks != null) 'totalTicks': totalTicks,
    };
  }
}

/// State for the cooking skill, tracking all three cooking areas.
///
/// Each area can have a recipe assigned and cooks independently.
/// The "active" area is determined by the global active action - if it's
/// a CookingAction, its categoryId determines which area is active.
/// Other areas with recipes cook passively (5x slower, no bonuses).
@immutable
class CookingState {
  const CookingState({
    this.fireArea = const CookingAreaState.empty(),
    this.furnaceArea = const CookingAreaState.empty(),
    this.potArea = const CookingAreaState.empty(),
  });

  const CookingState.empty() : this();

  factory CookingState.fromJson(Map<String, dynamic> json) {
    return CookingState(
      fireArea:
          CookingAreaState.maybeFromJson(json['fire']) ??
          const CookingAreaState.empty(),
      furnaceArea:
          CookingAreaState.maybeFromJson(json['furnace']) ??
          const CookingAreaState.empty(),
      potArea:
          CookingAreaState.maybeFromJson(json['pot']) ??
          const CookingAreaState.empty(),
    );
  }

  /// Deserializes a [CookingState] from a dynamic JSON value.
  /// Returns null if [json] is null.
  static CookingState? maybeFromJson(dynamic json) {
    if (json == null) return null;
    return CookingState.fromJson(json as Map<String, dynamic>);
  }

  final CookingAreaState fireArea;
  final CookingAreaState furnaceArea;
  final CookingAreaState potArea;

  /// Returns the state for a specific cooking area.
  CookingAreaState areaState(CookingArea area) {
    return switch (area) {
      CookingArea.fire => fireArea,
      CookingArea.furnace => furnaceArea,
      CookingArea.pot => potArea,
    };
  }

  /// Returns all areas as a list of (CookingArea, CookingAreaState) pairs.
  List<(CookingArea, CookingAreaState)> get allAreas => [
    (CookingArea.fire, fireArea),
    (CookingArea.furnace, furnaceArea),
    (CookingArea.pot, potArea),
  ];

  /// Returns true if any cooking area has an active recipe.
  bool get hasActiveRecipe =>
      fireArea.isActive || furnaceArea.isActive || potArea.isActive;

  CookingState copyWith({
    CookingAreaState? fireArea,
    CookingAreaState? furnaceArea,
    CookingAreaState? potArea,
  }) {
    return CookingState(
      fireArea: fireArea ?? this.fireArea,
      furnaceArea: furnaceArea ?? this.furnaceArea,
      potArea: potArea ?? this.potArea,
    );
  }

  /// Returns a copy with the specified area updated.
  CookingState withAreaState(CookingArea area, CookingAreaState state) {
    return switch (area) {
      CookingArea.fire => copyWith(fireArea: state),
      CookingArea.furnace => copyWith(furnaceArea: state),
      CookingArea.pot => copyWith(potArea: state),
    };
  }

  /// Returns a copy with progress cleared on all areas (recipes still
  /// assigned). Called when the player switches away from cooking to another
  /// skill.
  CookingState withAllProgressCleared() {
    return CookingState(
      fireArea: fireArea.withProgressCleared(),
      furnaceArea: furnaceArea.withProgressCleared(),
      potArea: potArea.withProgressCleared(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (!fireArea.isEmpty) 'fire': fireArea.toJson(),
      if (!furnaceArea.isEmpty) 'furnace': furnaceArea.toJson(),
      if (!potArea.isEmpty) 'pot': potArea.toJson(),
    };
  }
}
