import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:meta/meta.dart';

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

  /// Creates a DropTableEntry from a simple name string with equal min/max.
  DropTableEntry.fromName(String name, {int count = 1, required this.weight})
    : itemID = MelvorId.fromName(name),
      minQuantity = count,
      maxQuantity = count;

  DropTableEntry.test(
    String name, {
    required int gp,
    int min = 1,
    int max = 1,
    this.weight = 1,
  }) : itemID = MelvorId.fromName(name),
       minQuantity = min,
       maxQuantity = max;

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
    this.healsFor,
    this.dropTable,
    this.media,
    this.validSlots = const [],
  });

  /// Creates a simple test item with minimal required fields.
  /// Only for use in tests.
  @visibleForTesting
  Item.test(this.name, {required int gp, this.healsFor})
    : id = MelvorId('melvorD:${name.replaceAll(' ', '_')}'),
      itemType = 'Item',
      sellsFor = gp,
      category = null,
      type = null,
      dropTable = null,
      media = null,
      validSlots = const [];

  /// Creates an Item from a JSON map.
  factory Item.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    // Melvor uses HP/10, we use actual HP values, so multiply by 10.
    final rawHealsFor = json['healsFor'] as num?;
    final healsFor = rawHealsFor != null ? (rawHealsFor * 10).toInt() : null;

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

    // Parse valid equipment slots.
    final validSlotsJson = json['validSlots'] as List<dynamic>?;
    final validSlots =
        validSlotsJson
            ?.map((s) => EquipmentSlot.fromJson(s as String))
            .toList() ??
        const [];

    // Normalize ID to always have namespace (items in JSON may lack it).
    final id = MelvorId.fromJsonWithNamespace(
      json['id'] as String,
      defaultNamespace: namespace,
    );

    return Item(
      id: id,
      name: json['name'] as String,
      itemType: json['itemType'] as String,
      sellsFor: json['sellsFor'] as int,
      category: json['category'] as String?,
      type: json['type'] as String?,
      healsFor: healsFor,
      dropTable: dropTable,
      media: media,
      validSlots: validSlots,
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

  /// The amount of HP this item heals when consumed. Null if not consumable.
  final int? healsFor;

  /// The drop table for openable items. Null if not openable.
  final DropTable? dropTable;

  /// The asset path for this item's icon (e.g., "assets/media/bank/logs_normal.png").
  final String? media;

  /// The equipment slots this item can be equipped in.
  /// Empty list means the item cannot be equipped.
  final List<EquipmentSlot> validSlots;

  /// Whether this item can be consumed for healing.
  bool get isConsumable => healsFor != null;

  /// Whether this item can be opened (has a drop table).
  bool get isOpenable => dropTable != null;

  /// Whether this item can be equipped (has valid slots).
  bool get isEquippable => validSlots.isNotEmpty;

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
    dropTable,
    media,
    validSlots,
  ];

  @override
  String toString() => 'Item($name)';
}

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
