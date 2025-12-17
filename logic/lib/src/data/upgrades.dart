import 'package:logic/src/data/actions.dart';
import 'package:meta/meta.dart';

/// Types of skill upgrades available in the shop.
enum UpgradeType {
  axe,
  // Future: pickaxe, fishingRod, etc.
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

  /// Duration reduction as a decimal (0.05 = 5% reduction)
  final double durationPercentModifier;
}

/// Registry of all upgrades, organized by type.
final Map<UpgradeType, List<SkillUpgrade>> upgradeRegistry = {
  UpgradeType.axe: _axes,
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
