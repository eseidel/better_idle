import 'dart:math';

import 'package:logic/src/data/actions.dart';
import 'package:meta/meta.dart';

/// Duration for all thieving actions.
const thievingDuration = Duration(seconds: 3);

/// Thieving area - groups NPCs together.
@immutable
class ThievingArea {
  const ThievingArea(this.name);

  final String name;
}

final _thievingAreas = <ThievingArea>[
  ThievingArea('Low Town'),
  ThievingArea('Golbin Village'),
];

ThievingArea _thievingAreaByName(String name) {
  return _thievingAreas.firstWhere((a) => a.name == name);
}

/// Thieving action with success/fail mechanics.
/// On success: grants 1-maxGold GP and rolls for drops.
/// On failure: deals 1-maxHit damage and stuns the player.
@immutable
class ThievingAction extends SkillAction {
  const ThievingAction({
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required this.perception,
    required this.maxHit,
    required this.maxGold,
    required this.area,
    super.outputs = const {},
  }) : super(skill: Skill.thieving, duration: thievingDuration);

  /// NPC perception - used to calculate success rate.
  final int perception;

  /// Maximum damage dealt on failure (1-maxHit).
  final int maxHit;

  /// Maximum gold granted on success (1-maxGold).
  final int maxGold;

  /// The area this NPC belongs to.
  final ThievingArea area;

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
}) {
  return ThievingAction(
    name: name,
    unlockLevel: level,
    xp: xp,
    perception: perception,
    maxHit: maxHit,
    maxGold: maxGold,
    area: _thievingAreaByName(area),
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
