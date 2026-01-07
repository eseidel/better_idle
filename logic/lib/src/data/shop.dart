import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/currency.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// An item cost for a shop purchase.
@immutable
class ItemCost extends Equatable {
  const ItemCost({required this.itemId, required this.quantity});

  factory ItemCost.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return ItemCost(
      itemId: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      quantity: json['quantity'] as int,
    );
  }

  final MelvorId itemId;
  final int quantity;

  @override
  List<Object?> get props => [itemId, quantity];
}

/// The complete cost structure for a shop purchase.
@immutable
class ShopCost extends Equatable {
  const ShopCost({required this.currencies, required this.items});

  factory ShopCost.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final currenciesJson = json['currencies'] as List<dynamic>? ?? [];
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return ShopCost(
      currencies: currenciesJson
          .map((e) => CurrencyCost.fromJson(e as Map<String, dynamic>))
          .toList(),
      items: itemsJson
          .map(
            (e) => ItemCost.fromJson(
              e as Map<String, dynamic>,
              namespace: namespace,
            ),
          )
          .toList(),
    );
  }

  final List<CurrencyCost> currencies;
  final List<ItemCost> items;

  /// Returns the GP cost if this is a fixed-price GP purchase, null otherwise.
  int? get gpCost {
    for (final c in currencies) {
      if (c.currency == Currency.gp && c.type == CostType.fixed) {
        return c.fixedCost;
      }
    }
    return null;
  }

  /// Returns true if this purchase uses the bank slot pricing formula.
  bool get _usesBankSlotPricing {
    return currencies.any(
      (c) => c.currency == Currency.gp && c.type == CostType.bankSlot,
    );
  }

  /// Returns all fixed currency costs as a list of (Currency, amount) pairs.
  List<(Currency, int)> get _fixedCurrencyCosts {
    final result = <(Currency, int)>[];
    for (final c in currencies) {
      if (c.type == CostType.fixed && c.fixedCost != null) {
        result.add((c.currency, c.fixedCost!));
      }
    }
    return result;
  }

  /// Returns all currency costs as a list of (Currency, amount) pairs.
  ///
  /// For purchases with dynamic bank slot pricing, calculates the cost
  /// based on [bankSlotsPurchased]. For fixed pricing, returns the fixed costs.
  List<(Currency, int)> currencyCosts({required int bankSlotsPurchased}) {
    if (_usesBankSlotPricing) {
      final cost = calculateBankSlotCost(bankSlotsPurchased);
      return [(Currency.gp, cost)];
    }
    return _fixedCurrencyCosts;
  }

  @override
  List<Object?> get props => [currencies, items];
}

/// What a shop purchase contains/grants.
@immutable
class ShopContents extends Equatable {
  const ShopContents({required this.modifiers});

  factory ShopContents.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final modifiersJson = json['modifiers'] as Map<String, dynamic>? ?? {};
    return ShopContents(
      modifiers: ModifierDataSet.fromJson(modifiersJson, namespace: namespace),
    );
  }

  final ModifierDataSet modifiers;

  /// Bank space modifier value, or null if not present.
  int? get bankSpace => modifiers.byName('bankSpace')?.totalValue.toInt();

  @override
  List<Object?> get props => [modifiers];
}

/// Base class for shop requirements.
@immutable
sealed class ShopRequirement extends Equatable {
  const ShopRequirement();

  static ShopRequirement? fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final type = json['type'] as String;
    return switch (type) {
      'SkillLevel' => SkillLevelRequirement.fromJson(json),
      'ShopPurchase' => ShopPurchaseRequirement.fromJson(
        json,
        namespace: namespace,
      ),
      'DungeonCompletion' => DungeonCompletionRequirement.fromJson(
        json,
        namespace: namespace,
      ),
      _ => null, // Ignore unsupported requirement types
    };
  }
}

/// Requires a skill to be at a certain level.
@immutable
class SkillLevelRequirement extends ShopRequirement {
  const SkillLevelRequirement({required this.skill, required this.level});

  /// Returns null if the skill is not supported.
  static SkillLevelRequirement? fromJson(Map<String, dynamic> json) {
    final skillId = MelvorId(json['skillID'] as String);
    final skill = Skill.fromId(skillId);
    return SkillLevelRequirement(skill: skill, level: json['level'] as int);
  }

  final Skill skill;
  final int level;

  @override
  List<Object?> get props => [skill, level];
}

/// Requires owning a previous shop purchase.
@immutable
class ShopPurchaseRequirement extends ShopRequirement {
  const ShopPurchaseRequirement({
    required this.purchaseId,
    required this.count,
  });

  factory ShopPurchaseRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return ShopPurchaseRequirement(
      purchaseId: MelvorId.fromJsonWithNamespace(
        json['purchaseID'] as String,
        defaultNamespace: namespace,
      ),
      count: json['count'] as int,
    );
  }

  final MelvorId purchaseId;
  final int count;

  @override
  List<Object?> get props => [purchaseId, count];
}

/// Requires completing a dungeon a certain number of times.
@immutable
class DungeonCompletionRequirement extends ShopRequirement {
  const DungeonCompletionRequirement({
    required this.dungeonId,
    required this.count,
  });

  factory DungeonCompletionRequirement.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return DungeonCompletionRequirement(
      dungeonId: MelvorId.fromJsonWithNamespace(
        json['dungeonID'] as String,
        defaultNamespace: namespace,
      ),
      count: json['count'] as int,
    );
  }

  final MelvorId dungeonId;
  final int count;

  @override
  List<Object?> get props => [dungeonId, count];
}

/// A shop category.
@immutable
class ShopCategory extends Equatable {
  const ShopCategory({required this.id, required this.name, this.media});

  factory ShopCategory.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return ShopCategory(
      id: MelvorId.fromJsonWithNamespace(
        json['id'] as String,
        defaultNamespace: namespace,
      ),
      name: json['name'] as String,
      media: json['media'] as String?,
    );
  }

  final MelvorId id;
  final String name;

  /// The asset path for the category icon (e.g., "assets/media/main/...").
  final String? media;

  @override
  List<Object?> get props => [id, name, media];
}

/// A shop purchase definition.
@immutable
class ShopPurchase extends Equatable {
  const ShopPurchase({
    required this.id,
    required this.name,
    required this.category,
    required this.cost,
    required this.unlockRequirements,
    required this.purchaseRequirements,
    required this.contains,
    required this.buyLimit,
    this.description,
    this.media,
  });

  factory ShopPurchase.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final id = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Use customName if available, otherwise fall back to ID name.
    final name = json['customName'] as String? ?? id.name;

    final unlockReqsJson = json['unlockRequirements'] as List<dynamic>? ?? [];
    final purchaseReqsJson =
        json['purchaseRequirements'] as List<dynamic>? ?? [];

    return ShopPurchase(
      id: id,
      name: name,
      description: json['customDescription'] as String?,
      media: json['media'] as String?,
      category: MelvorId.fromJsonWithNamespace(
        json['category'] as String,
        defaultNamespace: namespace,
      ),
      cost: ShopCost.fromJson(
        json['cost'] as Map<String, dynamic>,
        namespace: namespace,
      ),
      unlockRequirements: unlockReqsJson
          .map(
            (e) => ShopRequirement.fromJson(
              e as Map<String, dynamic>,
              namespace: namespace,
            ),
          )
          .whereType<ShopRequirement>()
          .toList(),
      purchaseRequirements: purchaseReqsJson
          .map(
            (e) => ShopRequirement.fromJson(
              e as Map<String, dynamic>,
              namespace: namespace,
            ),
          )
          .whereType<ShopRequirement>()
          .toList(),
      contains: ShopContents.fromJson(
        json['contains'] as Map<String, dynamic>,
        namespace: namespace,
      ),
      buyLimit: json['defaultBuyLimit'] as int,
    );
  }

  final MelvorId id;
  final String name;
  final String? description;

  /// The asset path for the purchase icon (e.g., "assets/media/shop/...").
  final String? media;

  final MelvorId category;
  final ShopCost cost;
  final List<ShopRequirement> unlockRequirements;
  final List<ShopRequirement> purchaseRequirements;
  final ShopContents contains;

  /// The maximum number of times this can be purchased. 0 = unlimited.
  final int buyLimit;

  /// Whether this purchase has unlimited buy limit.
  bool get isUnlimited => buyLimit == 0;

  /// Whether this purchase has skill interval modifiers for the given skill.
  bool hasSkillIntervalFor(MelvorId skillId) =>
      contains.modifiers.hasSkillIntervalFor(skillId);

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    media,
    category,
    cost,
    unlockRequirements,
    purchaseRequirements,
    contains,
    buyLimit,
  ];
}

/// Registry of all shop purchases and categories.
@immutable
class ShopRegistry {
  ShopRegistry(this._purchases, this._categories) {
    _byId = {for (final p in _purchases) p.id.toJson(): p};
  }

  final List<ShopPurchase> _purchases;
  final List<ShopCategory> _categories;
  late final Map<String, ShopPurchase> _byId;

  /// All registered purchases.
  List<ShopPurchase> get all => _purchases;

  /// All registered categories.
  List<ShopCategory> get categories => _categories;

  /// Returns the purchase by ID, or null if not found.
  ShopPurchase? byId(MelvorId id) => _byId[id.toJson()];

  /// Returns purchases that affect the given skill via interval modifiers.
  List<ShopPurchase> purchasesAffectingSkill(Skill skill) {
    return _purchases.where((p) => p.hasSkillIntervalFor(skill.id)).toList();
  }

  /// Calculates total skill interval modifier from owned purchases.
  /// The purchaseCounts map should contain purchase ID -> count owned.
  int totalSkillIntervalModifier(
    Skill skill,
    Map<MelvorId, int> purchaseCounts,
  ) {
    var total = 0;
    for (final purchase in purchasesAffectingSkill(skill)) {
      final owned = purchaseCounts[purchase.id] ?? 0;
      if (owned > 0) {
        total += purchase.contains.modifiers.skillIntervalForSkill(skill.id);
      }
    }
    return total;
  }

  /// Returns all purchases that are visible in the shop.
  ///
  /// A purchase is visible if:
  /// - Its unlock requirements are met (owns prerequisite purchases)
  /// - It hasn't reached its buy limit
  ///
  /// Note: Skill level requirements do NOT hide purchases - they should be
  /// shown as disabled with requirements listed.
  List<ShopPurchase> visiblePurchases(Map<MelvorId, int> purchaseCounts) {
    final result = <ShopPurchase>[];
    for (final purchase in _purchases) {
      // Check buy limit
      final owned = purchaseCounts[purchase.id] ?? 0;
      if (!purchase.isUnlimited && owned >= purchase.buyLimit) continue;

      // Check unlock requirements (must own prerequisite purchases)
      // Only ShopPurchaseRequirement hides purchases, not SkillLevelRequirement
      var unlocked = true;
      for (final req in purchase.unlockRequirements) {
        if (req is ShopPurchaseRequirement) {
          if ((purchaseCounts[req.purchaseId] ?? 0) < req.count) {
            unlocked = false;
            break;
          }
        }
      }
      if (!unlocked) continue;

      result.add(purchase);
    }
    return result;
  }

  /// Returns skill upgrade purchases that are available for purchase.
  ///
  /// A purchase is available if:
  /// - It has skill interval modifiers (is a skill upgrade)
  /// - Its unlock requirements are met (owns prerequisite purchases)
  /// - It hasn't reached its buy limit
  ///
  /// Returns purchases paired with the first skill they affect.
  /// Only includes purchases that affect skills we support.
  List<(ShopPurchase, Skill)> availableSkillUpgrades(
    Map<MelvorId, int> purchaseCounts,
  ) {
    final result = <(ShopPurchase, Skill)>[];
    for (final purchase in visiblePurchases(purchaseCounts)) {
      final skillIds = purchase.contains.modifiers.skillIntervalSkillIds;
      if (skillIds.isEmpty) continue;

      // Find the first supported skill
      for (final skillId in skillIds) {
        final skill = Skill.tryFromId(skillId);
        if (skill != null) {
          result.add((purchase, skill));
          break;
        }
      }
    }
    return result;
  }

  /// Returns all skill level requirements for a purchase.
  /// Checks both unlockRequirements and purchaseRequirements.
  List<SkillLevelRequirement> skillLevelRequirements(ShopPurchase purchase) {
    final requirements = <SkillLevelRequirement>[];
    for (final req in purchase.unlockRequirements) {
      if (req is SkillLevelRequirement) {
        requirements.add(req);
      }
    }
    for (final req in purchase.purchaseRequirements) {
      if (req is SkillLevelRequirement) {
        requirements.add(req);
      }
    }
    return requirements;
  }

  /// Returns the GP cost for a purchase, or null if it uses special pricing.
  int? gpCost(ShopPurchase purchase) {
    return purchase.cost.gpCost;
  }

  /// Returns the duration modifier for a purchase as a multiplier.
  /// For example, 0.95 means 5% reduction (faster).
  /// Returns 1.0 if the purchase has no skill interval modifiers.
  double durationMultiplier(ShopPurchase purchase) {
    final totalPercent = purchase.contains.modifiers.totalSkillInterval;
    // Value of -5 means -5%, so multiplier is 1.0 + (-5/100) = 0.95
    return 1.0 + (totalPercent / 100.0);
  }
}

/// The bank slot pricing formula from Melvor.
/// https://wiki.melvoridle.com/w/Bank
int calculateBankSlotCost(int slotsPurchased) {
  final n = slotsPurchased;
  final cost = (132728500 * (n + 2) / pow(142015, 163 / (122 + n))).floor();
  return cost.clamp(0, 5000000);
}
