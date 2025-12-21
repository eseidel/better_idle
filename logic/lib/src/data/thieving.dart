import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/types/drop.dart';
import 'package:meta/meta.dart';

/// Duration for all thieving actions.
const thievingDuration = Duration(seconds: 3);

/// Thieving area - groups NPCs together.
/// May include area-level drops that apply to all NPCs in the area.
@immutable
class ThievingArea {
  const ThievingArea(this.name, {this.drops = const []});

  final String name;

  /// Drops that apply to all NPCs in this area.
  final List<Droppable> drops;
}

final _thievingAreas = <ThievingArea>[
  ThievingArea('Low Town', drops: [Drop('Jeweled Necklace', rate: 1 / 500)]),
  ThievingArea(
    'Golbin Village',
    drops: [Drop('Crate of Basic Supplies', rate: 1 / 500)],
  ),
];

ThievingArea _thievingAreaByName(String name) {
  return _thievingAreas.firstWhere((a) => a.name == name);
}

// TODO(eseidel): roll this into defaultRewards?
List<Droppable> _thievingRewards(SkillAction action, int masteryLevel) {
  final thievingAction = action as ThievingAction;
  final areaDrops = thievingAction.area.drops;
  final actionDropTable = thievingAction.dropTable;
  if (actionDropTable != null) {
    return [actionDropTable, ...areaDrops];
  }
  assert(
    thievingAction.outputs.isEmpty,
    'ThievingAction ${thievingAction.name} has outputs but no drop table.',
  );
  return [...areaDrops];
}

/// Thieving action with success/fail mechanics.
/// On success: grants 1-maxGold GP and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
@immutable
class ThievingAction extends SkillAction {
  const ThievingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.perception,
    required this.maxHit,
    required this.maxGold,
    required this.area,
    super.outputs = const {},
    this.dropTable,
  }) : super(
         skill: Skill.thieving,
         duration: thievingDuration,
         rewardsAtLevel: _thievingRewards,
       );

  /// NPC perception - used to calculate success rate.
  final int perception;

  /// Maximum damage dealt on failure (1-maxHit).
  final int maxHit;

  /// Maximum gold granted on success (1-maxGold).
  final int maxGold;

  /// The area this NPC belongs to.
  final ThievingArea area;

  /// The drop table for this NPC.
  final Droppable? dropTable;

  /// Rolls damage dealt on failure (1 to maxHit inclusive).
  int rollDamage(Random random) {
    if (maxHit <= 1) return 1;
    return 1 + random.nextInt(maxHit);
  }

  /// Rolls gold granted on success (1 to maxGold inclusive).
  int rollGold(Random random) {
    if (maxGold <= 1) return 1;
    return 1 + random.nextInt(maxGold);
  }

  /// Determines if the thieving attempt succeeds.
  /// Success chance = min(1, (100 + stealth) / (100 + perception))
  /// where stealth = 40 + thievingLevel + actionMasteryLevel
  bool rollSuccess(Random random, int thievingLevel, int actionMasteryLevel) {
    final stealth = calculateStealth(thievingLevel, actionMasteryLevel);
    final successChance = ((100 + stealth) / (100 + perception)).clamp(
      0.0,
      1.0,
    );
    final roll = random.nextDouble();
    return roll < successChance;
  }
}

/// Base stealth value before skill/mastery bonuses.
const int baseStealth = 40;

/// Calculates stealth value for thieving.
/// Stealth = 40 + thieving level + action mastery level
int calculateStealth(int thievingLevel, int actionMasteryLevel) {
  return baseStealth + thievingLevel + actionMasteryLevel;
}

ThievingAction _thieving(
  String name, {
  required int level,
  required int xp,
  required int perception,
  required int maxHit,
  required int maxGold,
  required String area,
  Droppable? dropTable,
}) {
  return ThievingAction(
    id: name.replaceAll(' ', '_'),
    name: name,
    unlockLevel: level,
    xp: xp,
    perception: perception,
    maxHit: maxHit,
    maxGold: maxGold,
    area: _thievingAreaByName(area),
    dropTable: dropTable,
  );
}

final thievingActions = <ThievingAction>[
  _thieving(
    'Man',
    level: 1,
    xp: 5,
    perception: 110,
    maxHit: 22,
    maxGold: 100,
    area: 'Low Town',
  ),
  _thieving(
    'Woman',
    level: 4,
    xp: 7,
    perception: 140,
    maxHit: 32,
    maxGold: 150,
    area: 'Low Town',
  ),
  _thieving(
    'Golbin',
    level: 8,
    xp: 10,
    perception: 175,
    maxHit: 40,
    maxGold: 175,
    area: 'Golbin Village',

    /// Golbin drop table - 75% chance to get an item, 25% nothing.
    /// Fractions expressed with common denominator 1048:
    /// - 150/1048 each: Copper Ore, Bronze Bar, Normal Logs, Tin Ore (14.31%)
    /// - 45/1048 each: Oak Logs, Iron Bar (4.29%)
    /// - 36/1048: Iron Ore (3.44%)
    /// - 30/1048 each: Steel Bar, Willow Logs (2.86%)
    /// Total: 786/1048 = 393/524 ≈ 75%
    // TODO(eseidel): express this exactly as the wiki does.
    dropTable: DropChance(
      DropTable([
        Pick('Copper Ore', weight: 150), // 75/524 = 150/1048
        Pick('Bronze Bar', weight: 150), // 75/524 = 150/1048
        Pick('Normal Logs', weight: 150), // 75/524 = 150/1048
        Pick('Tin Ore', weight: 150), // 75/524 = 150/1048
        Pick('Oak Logs', weight: 45), // 45/1048
        Pick('Iron Bar', weight: 45), // 45/1048
        Pick('Iron Ore', weight: 36), // 9/262 = 36/1048
        Pick('Steel Bar', weight: 30), // 15/524 = 30/1048
        Pick('Willow Logs', weight: 30), // 15/524 = 30/1048
      ]),
      rate: 786 / 1048, // 75% chance of any drop
    ),
  ),
  _thieving(
    'Golbin Chief',
    level: 16,
    xp: 18,
    perception: 280,
    maxHit: 101,
    maxGold: 275,
    area: 'Golbin Village',
  ),
];

/// Look up a ThievingAction by name.
ThievingAction thievingActionByName(String name) {
  return thievingActions.firstWhere((action) => action.name == name);
}
