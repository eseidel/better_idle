import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

import 'action_id.dart';

/// An agility obstacle that can be built in a course slot.
///
/// Obstacles are categorized by slot (category 0-9 for standard course).
/// Each obstacle provides modifiers and rewards when the course is run.
@immutable
class AgilityObstacle extends SkillAction {
  const AgilityObstacle({
    required super.id,
    required super.name,
    required super.unlockLevel,
    required super.xp,
    required super.duration,
    required this.category,
    this.media,
    this.currencyCosts = CurrencyCosts.empty,
    this.currencyRewards = const [],
    super.inputs = const {},
  }) : super(skill: Skill.agility, outputs: const {});

  factory AgilityObstacle.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Parse item costs as inputs
    final itemCosts = json['itemCosts'] as List<dynamic>? ?? [];
    final inputs = <MelvorId, int>{};
    for (final cost in itemCosts) {
      final costMap = cost as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = costMap['quantity'] as int;
      inputs[itemId] = quantity;
    }

    // Parse currency costs (mainly GP) - stored separately, not as inputs
    final currencyCosts = CurrencyCosts.fromJson(
      json['currencyCosts'] as List<dynamic>?,
    );

    // Parse currency rewards
    final currencyRewards = parseCurrencyStacks(
      json['currencyRewards'] as List<dynamic>?,
    );

    // Parse item rewards as outputs
    final itemRewards = json['itemRewards'] as List<dynamic>? ?? [];
    if (itemRewards.isNotEmpty) {
      throw ArgumentError('itemRewards are not supported: $itemRewards');
    }

    final localId = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // baseInterval is in milliseconds
    final baseInterval = json['baseInterval'] as int? ?? 3000;

    // Compute unlock level from category.
    // Slots 0-9 have levels 1, 10, 20, ... 90
    // Slots 10+ have levels 100, 105, 110, 115, 118
    final category = json['category'] as int;
    int unlockLevel;
    if (category <= 9) {
      unlockLevel = category == 0 ? 1 : category * 10;
    } else {
      // Slots 10-14 follow a different pattern
      const highLevelSlots = [100, 105, 110, 115, 118];
      final index = (category - 10).clamp(0, highLevelSlots.length - 1);
      unlockLevel = highLevelSlots[index];
    }

    return AgilityObstacle(
      id: ActionId(Skill.agility.id, localId),
      name: json['name'] as String,
      unlockLevel: unlockLevel,
      xp: json['baseExperience'] as int? ?? 0,
      duration: Duration(milliseconds: baseInterval),
      category: json['category'] as int,
      media: json['media'] as String?,
      inputs: inputs,
      currencyCosts: currencyCosts,
      currencyRewards: currencyRewards,
    );
  }

  /// The obstacle category/slot (0-9 for standard course slots).
  final int category;

  /// The media path for the obstacle icon.
  final String? media;

  /// Currency costs to build this obstacle (e.g., GP).
  final CurrencyCosts currencyCosts;

  /// Currency rewards for completing this obstacle.
  final List<CurrencyStack> currencyRewards;
}

/// An agility course configuration.
///
/// Defines the obstacle slots and their level requirements.
@immutable
class AgilityCourse {
  const AgilityCourse({
    required this.realm,
    required this.obstacleSlots,
    required this.pillarSlots,
  });

  factory AgilityCourse.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final obstacleSlots = (json['obstacleSlots'] as List<dynamic>)
        .map((slot) => (slot as Map<String, dynamic>)['level'] as int)
        .toList();

    final pillarSlotsJson = json['pillarSlots'] as List<dynamic>? ?? [];
    final pillarSlots = pillarSlotsJson
        .map(
          (slot) => AgilityPillarSlot.fromJson(
            slot as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .toList();

    return AgilityCourse(
      realm: MelvorId.fromJsonWithNamespace(
        json['realm'] as String,
        defaultNamespace: namespace,
      ),
      obstacleSlots: obstacleSlots,
      pillarSlots: pillarSlots,
    );
  }

  /// The realm this course belongs to (e.g., melvorD:Melvor).
  final MelvorId realm;

  /// Level requirements for each obstacle slot.
  final List<int> obstacleSlots;

  /// Pillar slot configurations.
  final List<AgilityPillarSlot> pillarSlots;
}

/// A pillar slot configuration.
@immutable
class AgilityPillarSlot {
  const AgilityPillarSlot({
    required this.level,
    required this.name,
    required this.obstacleCount,
  });

  factory AgilityPillarSlot.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return AgilityPillarSlot(
      level: json['level'] as int,
      name: json['name'] as String,
      obstacleCount: json['obstacleCount'] as int,
    );
  }

  /// Level required to unlock this pillar slot.
  final int level;

  /// Display name of the pillar slot.
  final String name;

  /// Number of obstacles required to use this pillar.
  final int obstacleCount;
}

/// An agility pillar that provides passive bonuses.
@immutable
class AgilityPillar {
  const AgilityPillar({
    required this.id,
    required this.name,
    required this.slot,
    required this.itemCosts,
    this.currencyCosts = CurrencyCosts.empty,
  });

  factory AgilityPillar.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Parse item costs
    final itemCostsJson = json['itemCosts'] as List<dynamic>? ?? [];
    final itemCosts = <MelvorId, int>{};
    for (final cost in itemCostsJson) {
      final costMap = cost as Map<String, dynamic>;
      final itemId = MelvorId.fromJsonWithNamespace(
        costMap['id'] as String,
        defaultNamespace: namespace,
      );
      final quantity = costMap['quantity'] as int;
      itemCosts[itemId] = quantity;
    }

    // Parse currency costs
    final currencyCosts = CurrencyCosts.fromJson(
      json['currencyCosts'] as List<dynamic>?,
    );

    return AgilityPillar(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      slot: json['slot'] as int,
      itemCosts: itemCosts,
      currencyCosts: currencyCosts,
    );
  }

  /// The unique ID for this pillar.
  final MelvorId id;

  /// Display name of the pillar.
  final String name;

  /// Which pillar slot this pillar can be placed in.
  final int slot;

  /// Item costs to build this pillar.
  final Map<MelvorId, int> itemCosts;

  /// Currency costs to build this pillar.
  final CurrencyCosts currencyCosts;
}

/// Registry for agility courses.
class AgilityCourseRegistry {
  AgilityCourseRegistry(List<AgilityCourse> courses) : _courses = courses;

  final List<AgilityCourse> _courses;

  /// Returns all courses.
  List<AgilityCourse> get all => _courses;

  /// Returns the course for a given realm, or null if not found.
  AgilityCourse? forRealm(MelvorId realm) {
    for (final course in _courses) {
      if (course.realm == realm) {
        return course;
      }
    }
    return null;
  }
}

/// Registry for agility pillars.
class AgilityPillarRegistry {
  AgilityPillarRegistry(List<AgilityPillar> pillars) : _pillars = pillars;

  final List<AgilityPillar> _pillars;

  /// Returns all pillars.
  List<AgilityPillar> get all => _pillars;

  /// Returns pillars for a given slot.
  List<AgilityPillar> forSlot(int slot) {
    return _pillars.where((p) => p.slot == slot).toList();
  }
}
