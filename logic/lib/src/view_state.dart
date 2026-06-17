import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';

/// UI-only state that the game logic and solver do not depend on.
///
/// This groups navigation preferences (e.g. last-selected skill action) and
/// view preferences (e.g. filter settings) so they can be cleanly separated
/// from game-mechanical state.
class ViewState {
  const ViewState({
    this.selectedSkillActions = const {},
    this.viewPreferences = const {},
  });

  const ViewState.empty()
    : selectedSkillActions = const {},
      viewPreferences = const {};

  factory ViewState.fromJson(Map<String, dynamic> json) {
    return ViewState(
      selectedSkillActions: _selectedSkillActionsFromJson(json),
      viewPreferences: _viewPreferencesFromJson(json),
    );
  }

  /// The last selected action per skill for UI navigation.
  /// Used to remember which action (e.g., which log type in firemaking) the
  /// player was viewing when they navigate away and back to a skill screen.
  final Map<Skill, MelvorId> selectedSkillActions;

  /// Generic string-keyed preferences for UI state (filters, toggles, etc.).
  final Map<String, String> viewPreferences;

  /// Gets the last selected action ID for a skill, or null if none.
  MelvorId? selectedSkillAction(Skill skill) => selectedSkillActions[skill];

  /// Gets a view preference by key, or null if not set.
  String? viewPreference(String key) => viewPreferences[key];

  /// Returns a new ViewState with the given skill action selected.
  ViewState setSelectedSkillAction(Skill skill, MelvorId actionId) {
    final newActions = Map<Skill, MelvorId>.from(selectedSkillActions);
    newActions[skill] = actionId;
    return copyWith(selectedSkillActions: newActions);
  }

  /// Returns a new ViewState with the given preference set.
  ViewState setViewPreference(String key, String value) {
    final newPrefs = Map<String, String>.from(viewPreferences);
    newPrefs[key] = value;
    return copyWith(viewPreferences: newPrefs);
  }

  ViewState copyWith({
    Map<Skill, MelvorId>? selectedSkillActions,
    Map<String, String>? viewPreferences,
  }) {
    return ViewState(
      selectedSkillActions: selectedSkillActions ?? this.selectedSkillActions,
      viewPreferences: viewPreferences ?? this.viewPreferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedSkillActions': selectedSkillActions.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
      'viewPreferences': viewPreferences,
    };
  }

  static Map<Skill, MelvorId> _selectedSkillActionsFromJson(
    Map<String, dynamic> json,
  ) {
    final actionsJson =
        json['selectedSkillActions'] as Map<String, dynamic>? ?? {};
    return actionsJson.map((key, value) {
      return MapEntry(Skill.fromName(key), MelvorId.fromJson(value as String));
    });
  }

  static Map<String, String> _viewPreferencesFromJson(
    Map<String, dynamic> json,
  ) {
    final prefsJson = json['viewPreferences'] as Map<String, dynamic>? ?? {};
    return prefsJson.map((key, value) => MapEntry(key, value as String));
  }
}
