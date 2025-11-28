import 'activities.dart';

export 'package:async_redux/async_redux.dart';

typedef Tick = int;
final Duration tickDuration = const Duration(milliseconds: 100);

class Inventory {
  Inventory.fromJson(Map<String, dynamic> json)
    : _counts = Map<String, int>.from(json['counts']),
      _orderedItems = List<String>.from(json['orderedItems']);

  Map<String, dynamic> toJson() {
    return {'counts': _counts, 'orderedItems': _orderedItems};
  }

  Inventory.fromItems(List<ItemStack> items)
    : _counts = {},
      _orderedItems = [] {
    for (var item in items) {
      _counts[item.name] = item.count;
      _orderedItems.add(item.name);
    }
  }

  Inventory.empty() : this.fromItems([]);

  Inventory._({
    required Map<String, int> counts,
    required List<String> orderedItems,
  }) : _counts = counts,
       _orderedItems = orderedItems;

  final Map<String, int> _counts;
  final List<String> _orderedItems;

  List<ItemStack> get items =>
      _orderedItems.map((e) => ItemStack(name: e, count: _counts[e]!)).toList();

  Inventory adding(ItemStack item) {
    final counts = Map<String, int>.from(_counts);
    final orderedItems = List<String>.from(_orderedItems);
    final existingCount = counts[item.name];
    if (existingCount == null) {
      counts[item.name] = item.count;
      orderedItems.add(item.name);
    } else {
      counts[item.name] = existingCount + item.count;
    }
    return Inventory._(counts: counts, orderedItems: orderedItems);
  }
}

Tick ticksFromDuration(Duration duration) {
  return duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

Tick ticksSince(DateTime start) {
  return ticksFromDuration(DateTime.timestamp().difference(start));
}

class ItemStack {
  const ItemStack({required this.name, required this.count});
  final String name;
  final int count;

  ItemStack copyWith({int? count}) {
    return ItemStack(name: name, count: count ?? this.count);
  }
}

class ActiveAction {
  const ActiveAction({required this.name, required this.progressTicks});
  final String name;
  final int progressTicks;

  ActiveAction copyWith({String? name, int? progressTicks}) {
    return ActiveAction(
      name: name ?? this.name,
      progressTicks: progressTicks ?? this.progressTicks,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'progressTicks': progressTicks,
  };

  factory ActiveAction.fromJson(Map<String, dynamic> json) {
    return ActiveAction(
      name: json['name'],
      progressTicks: json['progressTicks'],
    );
  }
}

class Action {
  const Action({
    required this.skill,
    required this.name,
    required this.duration,
    required this.xp,
    required this.rewards,
  });
  final Skill skill;
  final String name;
  final int xp;
  final List<ItemStack> rewards;
  final Duration duration;
  Tick get maxValue => duration.inMilliseconds ~/ tickDuration.inMilliseconds;
}

class SkillState {
  const SkillState({required this.xp, required this.masteryXp});
  final int xp;
  final int masteryXp;

  SkillState.empty() : this(xp: 0, masteryXp: 0);

  SkillState copyWith({int? xp, int? masteryXp}) {
    return SkillState(
      xp: xp ?? this.xp,
      masteryXp: masteryXp ?? this.masteryXp,
    );
  }

  SkillState.fromJson(Map<String, dynamic> json)
    : xp = json['xp'],
      masteryXp = json['masteryXp'];

  Map<String, dynamic> toJson() {
    return {'xp': xp, 'masteryXp': masteryXp};
  }
}

class ActionState {
  const ActionState({required this.masteryXp});
  final int masteryXp;

  const ActionState.empty() : this(masteryXp: 0);

  ActionState copyWith({int? masteryXp}) {
    return ActionState(masteryXp: masteryXp ?? this.masteryXp);
  }

  Map<String, dynamic> toJson() {
    return {'masteryXp': masteryXp};
  }

  factory ActionState.fromJson(Map<String, dynamic> json) {
    return ActionState(masteryXp: json['masteryXp']);
  }
}

class GlobalState {
  const GlobalState({
    required this.inventory,
    required this.activeAction,
    required this.skillStates,
    required this.actionStates,
    required this.updatedAt,
  });

  GlobalState.empty()
    : this(
        inventory: Inventory.empty(),
        activeAction: null,
        skillStates: {},
        actionStates: {},
        updatedAt: DateTime.timestamp(),
      );

  GlobalState.fromJson(Map<String, dynamic> json)
    : updatedAt = DateTime.parse(json['updatedAt']),
      inventory = Inventory.fromJson(json['inventory']),
      activeAction = json['activeAction'] != null
          ? ActiveAction.fromJson(json['activeAction'])
          : null,
      skillStates =
          (json['skillStates'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              Skill.fromName(key),
              SkillState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
      actionStates =
          (json['actionStates'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              ActionState.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {};
  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'inventory': inventory.toJson(),
      'activeAction': activeAction?.toJson(),
      'skillStates': skillStates.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
      'actionStates': actionStates.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  final DateTime updatedAt;
  final Inventory inventory;
  final ActiveAction? activeAction;
  final Map<Skill, SkillState> skillStates;
  final Map<String, ActionState> actionStates;

  String? get activeActionName => activeAction?.name;

  bool get isActive => activeAction != null;

  Skill? get activeSkill {
    final name = activeActionName;
    if (name == null) {
      return null;
    }
    return actionRegistry.byName(name).skill;
  }

  GlobalState startAction(Action action) {
    final name = action.name;
    return copyWith(activeAction: ActiveAction(name: name, progressTicks: 0));
  }

  GlobalState clearAction() {
    // This can't be copyWith since null means no-update.
    return GlobalState(
      inventory: inventory,
      activeAction: null,
      skillStates: skillStates,
      actionStates: actionStates,
      updatedAt: DateTime.timestamp(),
    );
  }

  SkillState skillState(Skill skill) =>
      skillStates[skill] ?? SkillState.empty();

  /// TODO(eseidel): Implement this.
  int unlockedActionsCount(Skill skill) => 1;

  ActionState actionState(String action) =>
      actionStates[action] ?? ActionState.empty();

  int activeProgress(Action action) {
    if (activeAction?.name != action.name) {
      return 0;
    }
    return activeAction!.progressTicks;
  }

  GlobalState updateActiveAction(String actionName, int progressTicks) {
    final activeAction = this.activeAction;
    if (activeAction == null || activeAction.name != actionName) {
      throw Exception('Active action is not $actionName');
    }
    final newActiveAction = activeAction.copyWith(progressTicks: progressTicks);
    return copyWith(activeAction: newActiveAction);
  }

  GlobalState addSkillXp(Skill skill, int amount) {
    final oldState = skillState(skill);
    final newState = oldState.copyWith(xp: oldState.xp + amount);
    return _updateSkillState(skill, newState);
  }

  GlobalState addSkillMasteryXp(Skill skill, int amount) {
    final oldState = skillState(skill);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    return _updateSkillState(skill, newState);
  }

  GlobalState _updateSkillState(Skill skill, SkillState state) {
    final newSkillStates = Map<Skill, SkillState>.from(skillStates);
    newSkillStates[skill] = state;
    return copyWith(skillStates: newSkillStates);
  }

  GlobalState addActionMasteryXp(String actionName, int amount) {
    final oldState = actionState(actionName);
    final newState = oldState.copyWith(masteryXp: oldState.masteryXp + amount);
    final newActionStates = Map<String, ActionState>.from(actionStates);
    newActionStates[actionName] = newState;
    return copyWith(actionStates: newActionStates);
  }

  GlobalState copyWith({
    Inventory? inventory,
    ActiveAction? activeAction,
    Map<Skill, SkillState>? skillStates,
    Map<String, ActionState>? actionStates,
  }) {
    return GlobalState(
      inventory: inventory ?? this.inventory,
      activeAction: activeAction ?? this.activeAction,
      skillStates: skillStates ?? this.skillStates,
      actionStates: actionStates ?? this.actionStates,
      updatedAt: DateTime.timestamp(),
    );
  }
}
