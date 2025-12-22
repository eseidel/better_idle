import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

@immutable
class FishingArea {
  const FishingArea(
    this.name, {
    required int fish,
    int junk = 0,
    int special = 0,
  }) : fishChance = fish / 100,
       junkChance = junk / 100,
       specialChance = special / 100,
       assert(fish + junk + special == 100);

  final String name;
  final double fishChance;
  final double junkChance;
  final double specialChance;
}

final _fishingAreas = <FishingArea>[
  FishingArea('Shallow Shores', fish: 75, junk: 25),
  FishingArea('Shrapnel River', fish: 80, junk: 20),
  FishingArea('Rubble Pits', fish: 50, junk: 50),
  FishingArea('Trench of Despair', fish: 70, junk: 28, special: 2),
];

/// Fishing action with area-based catch mechanics.
@immutable
class FishingAction extends SkillAction {
  const FishingAction({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.minDuration,
    required super.maxDuration,
    required this.area,
    super.outputs = const {},
  }) : super.ranged(skill: Skill.fishing);

  final FishingArea area;
}

FishingAction _fishing(
  String name, {
  required int level,
  required int xp,
  required int min,
  required int max,
  required String area,
}) {
  final areaObject = _fishingAreas.firstWhere((a) => a.name == area);
  final fishName = 'Raw $name';
  return FishingAction(
    id: MelvorId.fromName(fishName),
    name: fishName,
    unlockLevel: level,
    xp: xp,
    minDuration: Duration(seconds: min),
    maxDuration: Duration(seconds: max),
    outputs: {MelvorId.fromName(fishName): 1},
    area: areaObject,
  );
}

final fishingActions = <FishingAction>[
  _fishing('Shrimp', level: 1, xp: 10, min: 4, max: 8, area: 'Shallow Shores'),
  _fishing(
    'Lobster',
    level: 40,
    xp: 50,
    min: 4,
    max: 11,
    area: 'Shallow Shores',
  ),
  _fishing('Crab', level: 60, xp: 120, min: 5, max: 12, area: 'Shallow Shores'),
  _fishing('Sardine', level: 5, xp: 10, min: 4, max: 8, area: 'Shrapnel River'),
  _fishing(
    'Herring',
    level: 10,
    xp: 15,
    min: 4,
    max: 8,
    area: 'Shrapnel River',
  ),
];
