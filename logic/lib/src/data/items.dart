// cspell:words summoningMaxhit succesful
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/combat.dart' show AttackType;
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/shop.dart' show ShopRequirement;
import 'package:logic/src/json.dart';
import 'package:logic/src/state.dart' show CombatType;
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:meta/meta.dart';

/// Equipment stat modifiers that can be queried via
/// [EquipmentStats.getAsModifier].
enum EquipmentStatModifier {
  equipmentAttackSpeed('attackSpeed'),
  flatStabAttackBonus('stabAttackBonus'),
  flatSlashAttackBonus('slashAttackBonus'),
  flatBlockAttackBonus('blockAttackBonus'),
  flatMeleeStrengthBonus('meleeStrengthBonus'),
  flatRangedStrengthBonus('rangedStrengthBonus'),
  flatRangedAttackBonus('rangedAttackBonus'),
  flatMagicAttackBonus('magicAttackBonus'),
  magicDamageBonus('magicDamageBonus'),
  flatMeleeDefenceBonus('meleeDefenceBonus'),
  flatRangedDefenceBonus('rangedDefenceBonus'),
  flatMagicDefenceBonus('magicDefenceBonus'),
  flatResistance('damageReduction');

  const EquipmentStatModifier(this.statKey);

  /// The JSON key used in Melvor equipment stats.
  final String statKey;

  /// Lookup by modifier name string. Returns null if not an equipment stat.
  static EquipmentStatModifier? tryFromName(String name) => _byName[name];

  static final Map<String, EquipmentStatModifier> _byName = {
    for (final v in values) v.name: v,
  };
}

/// Combat stats provided by equipment items.
/// Parsed from the `equipmentStats` array in Melvor JSON.
///
/// Uses a map internally for simplicity. Stats are accessed via typed getters.
@immutable
class EquipmentStats extends Equatable {
  const EquipmentStats(this._values);

  /// Parses equipment stats from JSON array.
  factory EquipmentStats.fromJson(List<dynamic>? json) {
    if (json == null || json.isEmpty) return empty;

    final values = <String, int>{};
    for (final stat in json.cast<Map<String, dynamic>>()) {
      final key = stat['key'] as String;
      final value = (stat['value'] as num).toInt();
      values[key] = value;
    }
    return EquipmentStats(values);
  }

  static const empty = EquipmentStats({});

  final Map<String, int> _values;

  /// Gets an equipment stat value by modifier.
  /// Returns null if this stat doesn't exist or is zero.
  int? getAsModifier(EquipmentStatModifier modifier) {
    final value = _values[modifier.statKey];
    if (value == null || value == 0) return null;
    return value;
  }

  @override
  List<Object?> get props => [_values];
}

/// An entry in a drop table from the Melvor JSON data.
/// Used for weighted drops within a DropTable.
@immutable
class DropTableEntry extends Equatable {
  const DropTableEntry({
    required this.itemID,
    required this.minQuantity,
    required this.maxQuantity,
    required this.weight,
  });

  /// Creates a DropTableEntry from a JSON map (standard format).
  factory DropTableEntry.fromJson(Map<String, dynamic> json) {
    return DropTableEntry(
      itemID: MelvorId.fromJson(json['itemID'] as String),
      minQuantity: json['minQuantity'] as int,
      maxQuantity: json['maxQuantity'] as int,
      weight: json['weight'] as int,
    );
  }

  /// Creates a DropTableEntry from thieving loot table JSON format.
  factory DropTableEntry.fromThievingJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    return DropTableEntry(
      itemID: MelvorId.fromJsonWithNamespace(
        json['itemID'] as String,
        defaultNamespace: namespace,
      ),
      minQuantity: json['minQuantity'] as int? ?? 1,
      maxQuantity: json['maxQuantity'] as int? ?? 1,
      weight: json['weight'] as int,
    );
  }

  /// The fully qualified item ID (e.g., "melvorD:Normal_Logs").
  final MelvorId itemID;

  /// The minimum quantity that can drop.
  final int minQuantity;

  /// The maximum quantity that can drop.
  final int maxQuantity;

  /// The expected quantity that will drop.
  double get expectedCount => (minQuantity + maxQuantity) / 2.0;

  /// The weight of this entry in the drop table.
  final int weight;

  /// Creates the ItemStack when this entry is selected/rolled.
  ItemStack roll(ItemRegistry items, Random random) {
    final count = minQuantity == maxQuantity
        ? minQuantity
        : minQuantity + random.nextInt(maxQuantity - minQuantity + 1);
    final item = items.byId(itemID);
    return ItemStack(item, count: count);
  }

  @override
  List<Object?> get props => [itemID, minQuantity, maxQuantity, weight];
}

/// Types of events that can trigger consumable consumption.
enum ConsumesOnType {
  playerAttack('PlayerAttack'),
  enemyAttack('EnemyAttack'),
  playerSummonAttack('PlayerSummonAttack'),
  fishingAction('FishingAction'),
  runeConsumption('RuneConsumption'),
  prayerPointConsumption('PrayerPointConsumption'),
  thievingAction('ThievingAction'),
  farmingPlantAction('FarmingPlantAction'),
  farmingHarvestAction('FarmingHarvestAction'),
  runecraftingAction('RunecraftingAction'),
  potionUsed('PotionUsed'),
  potionChargeUsed('PotionChargeUsed'),
  woodcuttingAction('WoodcuttingAction'),
  miningAction('MiningAction'),
  herbloreAction('HerbloreAction'),
  craftingAction('CraftingAction'),
  firemakingAction('FiremakingAction'),
  cookingAction('CookingAction'),
  smithingAction('SmithingAction'),
  fletchingAction('FletchingAction'),
  agilityAction('AgilityAction'),
  summoningAction('SummoningAction'),
  astrologyAction('AstrologyAction');

  const ConsumesOnType(this.jsonName);

  /// The JSON name used in Melvor data files.
  final String jsonName;

  /// Whether this is a combat action type.
  bool get isCombat =>
      this == playerAttack || this == enemyAttack || this == playerSummonAttack;

  /// Lookup map for efficient fromJson conversion.
  static final Map<String, ConsumesOnType> _byJsonName = {
    for (final type in values) type.jsonName: type,
  };

  /// Parses a ConsumesOnType from JSON, returns null for unknown types.
  static ConsumesOnType? fromJson(String type) => _byJsonName[type];
}

/// Defines when a consumable item is consumed.
@immutable
class ConsumesOn extends Equatable {
  const ConsumesOn({required this.type, this.attackTypes, this.successful});

  factory ConsumesOn.fromJson(Map<String, dynamic> json) {
    final typeString = json['type'] as String;
    final type = ConsumesOnType.fromJson(typeString);

    // Parse attack types if present (for PlayerAttack/EnemyAttack)
    final attackTypesJson = json['attackTypes'] as List<dynamic>?;
    final attackTypes = attackTypesJson
        ?.cast<String>()
        .map(CombatType.fromJson)
        .toList();

    // Parse successful flag if present (for ThievingAction)
    // Note: 'succesful' is a typo in Melvor data that we must match.
    final successful = json['succesful'] as bool?;

    return ConsumesOn(
      type: type,
      attackTypes: attackTypes,
      successful: successful,
    );
  }

  /// The type of event that triggers consumption.
  /// Null if the type is unknown/unsupported.
  final ConsumesOnType? type;

  /// For PlayerAttack/EnemyAttack: which attack types trigger consumption.
  /// Null means all attack types.
  final List<CombatType>? attackTypes;

  /// For ThievingAction: whether only successful actions trigger consumption.
  final bool? successful;

  @override
  List<Object?> get props => [type, attackTypes, successful];
}

/// An item loaded from the Melvor game data.
@immutable
class Item extends Equatable {
  const Item({
    required this.id,
    required this.name,
    required this.itemType,
    required this.sellsFor,
    this.category,
    this.type,
    this.description,
    this.healsFor,
    this.compostValue,
    this.harvestBonus,
    this.dropTable,
    this.media,
    this.validSlots = const <EquipmentSlot>[],
    this.modifiers = const ModifierDataSet([]),
    this.conditionalModifiers = const <ConditionalModifier>[],
    this.equipmentStats = EquipmentStats.empty,
    this.attackType,
    this.equipRequirements = const [],
    this.potionCharges,
    this.potionTier,
    this.potionAction,
    this.consumesOn = const [],
    this.masteryTokenSkillId,
  });

  /// Creates a simple test item with minimal required fields.
  /// Only for use in tests.
  @visibleForTesting
  Item.test(
    this.name, {
    required int gp,
    this.healsFor,
    this.compostValue,
    this.harvestBonus,
    this.attackType,
    this.equipRequirements = const [],
    this.potionCharges,
    this.potionTier,
    this.potionAction,
    this.consumesOn = const [],
  }) : id = MelvorId('melvorD:${name.replaceAll(' ', '_')}'),
       itemType = 'Item',
       sellsFor = gp,
       category = null,
       type = null,
       description = null,
       dropTable = null,
       media = null,
       validSlots = const <EquipmentSlot>[],
       modifiers = const ModifierDataSet([]),
       conditionalModifiers = const <ConditionalModifier>[],
       equipmentStats = EquipmentStats.empty,
       masteryTokenSkillId = null;

  /// Creates an Item from a JSON map.
  factory Item.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Melvor uses HP/10, we use actual HP values, so multiply by 10.
    final rawHealsFor = json['healsFor'] as num?;
    final healsFor = rawHealsFor != null ? (rawHealsFor * 10).toInt() : null;

    // Parse compost value if present.
    // JSON stores 2x the actual percent (e.g., 20 = 10%, 100 = 50%).
    final rawCompostValue = json['compostValue'] as int?;
    final compostValue = rawCompostValue != null ? rawCompostValue ~/ 2 : null;

    // Parse harvest bonus if present.
    // JSON stores 2x the actual percent (e.g., 20 = 10%).
    final rawHarvestBonus = json['harvestBonus'] as int?;
    final harvestBonus = rawHarvestBonus != null ? rawHarvestBonus ~/ 2 : null;

    // Parse drop table if present.
    final dropTableJson = json['dropTable'] as List<dynamic>?;
    DropTable? dropTable;
    if (dropTableJson != null && dropTableJson.isNotEmpty) {
      final entries = dropTableJson
          .map((e) => DropTableEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      dropTable = DropTable(entries);
    }

    // Parse media path, stripping query params (e.g., "?2").
    final media = (json['media'] as String?)?.split('?').first;

    // Parse valid equipment slots from JSON slot names.
    final validSlotsJson = json['validSlots'] as List<dynamic>?;
    final validSlots =
        validSlotsJson
            ?.map((s) => EquipmentSlot.fromJson(s as String))
            .toList() ??
        const <EquipmentSlot>[];

    // Normalize ID to always have namespace (items in JSON may lack it).
    final id = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    // Parse modifiers if present.
    final modifiersJson = json['modifiers'] as Map<String, dynamic>?;
    final modifiers = modifiersJson != null
        ? ModifierDataSet.fromJson(modifiersJson, namespace: namespace)
        : const ModifierDataSet([]);

    // Parse equipmentStats into EquipmentStats class.
    final equipmentStatsJson = json['equipmentStats'] as List<dynamic>?;
    final equipmentStats = EquipmentStats.fromJson(equipmentStatsJson);

    // Parse equipment requirements (same format as shop requirements).
    final equipReqsJson = json['equipRequirements'] as List<dynamic>? ?? [];
    final equipRequirements = equipReqsJson
        .map(
          (e) => ShopRequirement.fromJson(
            e as Map<String, dynamic>,
            namespace: namespace,
          ),
        )
        .whereType<ShopRequirement>()
        .toList();

    // Parse potion-specific fields (only for Potion itemType).
    final isPotion = json['itemType'] == 'Potion';
    final potionAction = isPotion && json['action'] != null
        ? MelvorId.fromJsonWithNamespace(
            json['action'] as String,
            defaultNamespace: namespace,
          )
        : null;
    final potionCharges = isPotion ? json['charges'] as int? : null;
    final potionTier = isPotion ? json['tier'] as int? : null;

    // Parse consumesOn for consumable equipment.
    final consumesOn =
        maybeList<ConsumesOn>(json['consumesOn'], ConsumesOn.fromJson) ??
        const [];

    // Parse conditionalModifiers if present.
    final conditionalModifiers =
        maybeList<ConditionalModifier>(
          json['conditionalModifiers'],
          (e) => ConditionalModifier.fromJson(e, namespace: namespace),
        ) ??
        const <ConditionalModifier>[];

    return Item(
      id: id,
      name: json['name'] as String,
      itemType: json['itemType'] as String,
      sellsFor: json['sellsFor'] as int,
      category: json['category'] as String?,
      type: json['type'] as String?,
      healsFor: healsFor,
      compostValue: compostValue,
      harvestBonus: harvestBonus,
      dropTable: dropTable,
      media: media,
      validSlots: validSlots,
      description: json['customDescription'] as String?,
      modifiers: modifiers,
      conditionalModifiers: conditionalModifiers,
      equipmentStats: equipmentStats,
      attackType: json['attackType'] != null
          ? AttackType.fromJson(json['attackType'] as String)
          : null,
      equipRequirements: equipRequirements,
      potionCharges: potionCharges,
      potionTier: potionTier,
      potionAction: potionAction,
      consumesOn: consumesOn,
      masteryTokenSkillId: json['skill'] != null
          ? MelvorId.fromJsonWithNamespace(
              json['skill'] as String,
              defaultNamespace: namespace,
            )
          : null,
    );
  }

  /// The unique identifier for this item (e.g., "melvorD:Normal_Logs").
  final MelvorId id;

  /// The display name for this item (e.g., "Normal Logs").
  final String name;

  /// The type of item (e.g., "Item", "Food", "Weapon", "Equipment").
  final String itemType;

  /// The amount of GP this item sells for.
  final int sellsFor;

  /// The category of this item (e.g., "Woodcutting", "Fishing").
  final String? category;

  /// The sub-type of this item (e.g., "Logs", "Raw Fish", "Food").
  final String? type;

  /// Custom description for this item.
  final String? description;

  /// The amount of HP this item heals when consumed. Null if not consumable.
  final int? healsFor;

  /// The skill this mastery token is for. Null if not a mastery token.
  final MelvorId? masteryTokenSkillId;

  /// The compost value for farming (0-50). Null if not compost.
  final int? compostValue;

  /// Harvest bonus percentage for farming (e.g., 10 for +10%). Null if none.
  final int? harvestBonus;

  /// The drop table for openable items. Null if not openable.
  final DropTable? dropTable;

  /// The asset path for this item's icon (e.g., "assets/media/bank/logs_normal.png").
  final String? media;

  /// The equipment slots this item can be equipped in.
  /// Empty list means the item cannot be equipped.
  final List<EquipmentSlot> validSlots;

  /// The modifiers this item provides when equipped.
  /// Empty set means no modifiers.
  final ModifierDataSet modifiers;

  /// Conditional modifiers that apply only when certain conditions are met.
  /// For example, extra defense when fighting specific enemy types.
  final List<ConditionalModifier> conditionalModifiers;

  /// Combat stats provided by this equipment item.
  /// Contains attack bonuses, strength bonuses, defence bonuses, etc.
  final EquipmentStats equipmentStats;

  /// The attack type for weapon items (melee, ranged, magic).
  /// Null for non-weapon items.
  final AttackType? attackType;

  /// Requirements that must be met to equip this item.
  /// Empty list means no requirements.
  final List<ShopRequirement> equipRequirements;

  /// Number of charges per potion. Null for non-potion items.
  /// Each charge is consumed on a skill action before the potion is depleted.
  final int? potionCharges;

  /// Potion tier (0-3 for tiers I-IV). Null for non-potion items.
  final int? potionTier;

  /// The skill/action this potion applies to (e.g., "melvorD:Woodcutting").
  /// Null for non-potion items.
  final MelvorId? potionAction;

  /// Events that trigger consumption of this item when equipped.
  /// Empty list means the item is not consumed on use.
  final List<ConsumesOn> consumesOn;

  /// Whether this item can be consumed for healing.
  bool get isConsumable => healsFor != null;

  /// Whether this item can be opened (has a drop table).
  bool get isOpenable => dropTable != null;

  /// Whether this item can be equipped (has valid slots).
  bool get isEquippable => validSlots.isNotEmpty;

  /// Whether this item is a summoning tablet (familiar).
  /// Tablets are equipped in summon slots and track charge counts.
  bool get isSummonTablet => type == 'Familiar';

  /// Whether this item is a potion.
  bool get isPotion => itemType == 'Potion';

  /// Returns true if this item can be equipped in the given slot.
  bool canEquipInSlot(EquipmentSlot slot) => validSlots.contains(slot);

  /// Opens this item once and returns the resulting drop.
  /// Throws if the item is not openable.
  ItemStack open(ItemRegistry items, Random random) {
    if (dropTable == null) {
      throw StateError('Item $name is not openable');
    }
    return dropTable!.roll(items, random);
  }

  @override
  List<Object?> get props => [
    id,
    name,
    itemType,
    sellsFor,
    category,
    type,
    healsFor,
    compostValue,
    harvestBonus,
    dropTable,
    media,
    validSlots,
    description,
    modifiers,
    conditionalModifiers,
    equipmentStats,
    attackType,
    equipRequirements,
    potionCharges,
    potionTier,
    potionAction,
    consumesOn,
    masteryTokenSkillId,
  ];
}

@immutable
class ItemRegistry {
  ItemRegistry(List<Item> items) : _all = items {
    _byName = {for (final item in _all) item.name: item};
    _byId = {for (final item in _all) item.id.toJson(): item};
  }

  final List<Item> _all;
  late final Map<String, Item> _byName;
  late final Map<String, Item> _byId;

  /// All registered items.
  List<Item> get all => _all;

  /// Returns the item by MelvorId, or throws a StateError if not found.
  Item byId(MelvorId id) {
    final item = _byId[id.toJson()];
    if (item == null) {
      throw StateError('Item not found: $id');
    }
    return item;
  }

  /// Returns the item by name, or throws a StateError if not found.
  @visibleForTesting
  Item byName(String name) {
    final item = _byName[name];
    if (item == null) {
      throw StateError('Item not found: $name');
    }
    return item;
  }

  /// Returns the index of the item in the registry, or -1 if not found.
  int indexForItem(Item item) => _all.indexOf(item);
}
