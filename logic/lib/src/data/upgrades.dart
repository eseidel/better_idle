import 'package:logic/src/data/actions.dart';
import 'package:logic/src/strings.dart';
import 'package:meta/meta.dart';

/// Types of skill upgrades available in the shop.
enum UpgradeType {
  axe(Skill.woodcutting),
  fishingRod(Skill.fishing),
  pickaxe(Skill.mining);

  const UpgradeType(this.skill);

  final Skill skill;
}

/// Returns the upgrade type for a skill, or null if the skill has no upgrades.
UpgradeType? upgradeTypeForSkill(Skill skill) {
  for (final type in UpgradeType.values) {
    if (type.skill == skill) return type;
  }
  return null;
}

/// A single upgrade tier within an upgrade series.
@immutable
class SkillUpgrade {
  const SkillUpgrade({
    required this.name,
    required this.skill,
    required this.requiredLevel,
    required this.cost,
    required this.durationPercentModifier,
  });

  /// Display name (e.g., "Iron Axe")
  final String name;

  /// The skill this upgrade affects
  final Skill skill;

  /// Minimum skill level required to purchase
  final int requiredLevel;

  /// Cost in GP
  final int cost;

  /// Duration modifier as a multiplier (0.95 = 5% reduction, 1.05 = 5% increase)
  final double durationPercentModifier;

  /// Human-readable description of what this upgrade does.
  String get description {
    final percent = signedPercentToString(durationPercentModifier - 1.0);
    return '$percent ${skill.name} time';
  }
}

/// Registry of all upgrades, organized by type.
final Map<UpgradeType, List<SkillUpgrade>> upgradeRegistry = {
  UpgradeType.axe: _axes,
  UpgradeType.fishingRod: _fishingRods,
  UpgradeType.pickaxe: _pickaxes,
};

SkillUpgrade _axe(
  String name, {
  required int level,
  required int cost,
  required int durationPercent,
}) {
  return SkillUpgrade(
    name: '$name Axe',
    skill: Skill.woodcutting,
    requiredLevel: level,
    cost: cost,
    durationPercentModifier: 1.0 + durationPercent / 100.0,
  );
}

final _axes = <SkillUpgrade>[
  _axe('Iron', level: 1, cost: 50, durationPercent: -5),
  _axe('Steel', level: 10, cost: 750, durationPercent: -5),
];

SkillUpgrade _fishingRod(
  String name, {
  required int level,
  required int cost,
  required int durationPercent,
}) {
  return SkillUpgrade(
    name: '$name Fishing Rod',
    skill: Skill.fishing,
    requiredLevel: level,
    cost: cost,
    durationPercentModifier: 1.0 + durationPercent / 100.0,
  );
}

final _fishingRods = <SkillUpgrade>[
  _fishingRod('Iron', level: 1, cost: 100, durationPercent: -5),
  _fishingRod('Steel', level: 10, cost: 1000, durationPercent: -5),
];

SkillUpgrade _pickaxe(
  String name, {
  required int level,
  required int cost,
  required int durationPercent,
}) {
  return SkillUpgrade(
    name: '$name Pickaxe',
    skill: Skill.mining,
    requiredLevel: level,
    cost: cost,
    durationPercentModifier: 1.0 + durationPercent / 100.0,
  );
}

final _pickaxes = <SkillUpgrade>[
  _pickaxe('Iron', level: 1, cost: 250, durationPercent: -5),
  _pickaxe('Steel', level: 10, cost: 2000, durationPercent: -5),
];

/// Returns the next available upgrade for the given type, or null if all owned.
SkillUpgrade? nextUpgrade(UpgradeType type, int currentLevel) {
  final upgrades = upgradeRegistry[type]!;
  if (currentLevel >= upgrades.length) return null;
  return upgrades[currentLevel];
}

// TODO(eseidel): This isn't quite the right design, since there will
// end up being both percentage and absolute reduction modifiers
// and either we will need two calls like this, or one call to apply them both.
/// Returns the total duration reduction for a given upgrade type and level.
double totalDurationPercentModifier(UpgradeType type, int level) {
  final upgrades = upgradeRegistry[type]!;
  var total = 0.0;
  for (var i = 0; i < level && i < upgrades.length; i++) {
    total += upgrades[i].durationPercentModifier;
  }
  return total;
}
