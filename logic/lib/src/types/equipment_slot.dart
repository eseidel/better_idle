import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// Equipment slot identifiers.
///
/// Use this enum when referencing specific slots in code. The registry
/// provides metadata (emptyName, emptyMedia, etc.) loaded from JSON.
enum EquipmentSlot {
  helmet('Helmet'),
  platebody('Platebody'),
  platelegs('Platelegs'),
  boots('Boots'),
  gloves('Gloves'),
  cape('Cape'),
  amulet('Amulet'),
  ring('Ring'),
  weapon('Weapon'),
  shield('Shield'),
  quiver('Quiver'),
  summon1('Summon1'),
  summon2('Summon2'),
  consumable('Consumable'),
  passive('Passive'),
  gem('Gem'),
  enhancement1('Enhancement1'),
  enhancement2('Enhancement2'),
  enhancement3('Enhancement3');

  const EquipmentSlot(this.jsonName);

  /// The slot name as it appears in JSON (matches MelvorId localId).
  final String jsonName;

  /// Returns true if this slot tracks stack counts
  /// (summons, quiver, consumable).
  ///
  /// This mirrors the JSON `allowQuantity` field. It's kept on the enum for
  /// convenience to avoid passing the registry everywhere. The registry
  /// validates this matches the JSON at construction time.
  bool get isStackSlot => switch (this) {
    quiver || summon1 || summon2 || consumable => true,
    _ => false,
  };

  /// Returns true if this slot is for summoning tablets.
  bool get isSummonSlot => this == summon1 || this == summon2;

  /// Returns true if this slot is for the quiver (ammo).
  bool get isQuiverSlot => this == quiver;

  /// Parse from JSON slot name.
  static EquipmentSlot fromJson(String name) {
    for (final slot in values) {
      if (slot.jsonName == name) return slot;
    }
    throw ArgumentError('Unknown equipment slot: $name');
  }

  /// Parse from JSON, returning null if input is null.
  static EquipmentSlot? maybeFromJson(String? name) {
    if (name == null) return null;
    return fromJson(name);
  }

  /// Serialize to JSON.
  String toJson() => jsonName;
}

/// Definition of an equipment slot parsed from Melvor JSON.
///
/// Contains metadata about slots (emptyName, emptyMedia, grid position, etc.)
/// that is loaded from the game data. Use [EquipmentSlot] enum to reference
/// specific slots in code, and the registry to access metadata.
@immutable
class EquipmentSlotDef extends Equatable {
  const EquipmentSlotDef({
    required this.slot,
    required this.id,
    required this.allowQuantity,
    required this.emptyName,
    required this.emptyMedia,
    required this.providesEquipStats,
    required this.gridPosition,
    this.unlockDungeonId,
  });

  /// Parses an EquipmentSlotDef from Melvor JSON.
  ///
  /// The `requirements` field in the demo data uses an impossible SkillLevel
  /// (Attack 1000) to lock the Passive slot. The full data replaces this with
  /// a DungeonCompletion requirement for "Into the Mist". Since we only support
  /// the full game, we directly parse the dungeon requirement and ignore the
  /// SkillLevel requirement.
  factory EquipmentSlotDef.fromJson(
    Map<String, dynamic> json, {
    required String namespace,
  }) {
    final idString = json['id'] as String;
    // Handle both namespaced IDs (from melvorFull patches) and plain IDs.
    final id = idString.contains(':')
        ? MelvorId.fromJson(idString)
        : MelvorId.fromJsonWithNamespace(idString, defaultNamespace: namespace);

    final gridJson = json['gridPosition'] as Map<String, dynamic>;
    final gridPosition = GridPosition(
      col: gridJson['col'] as int,
      row: gridJson['row'] as int,
    );

    // Parse unlock dungeon from requirements.
    // We only support DungeonCompletion requirements (used for Passive slot).
    // SkillLevel requirements with level 1000 are ignored (demo-only lock).
    MelvorId? unlockDungeonId;
    final requirements = json['requirements'];
    if (requirements is List<dynamic>) {
      // Demo format: array of requirement objects.
      for (final req in requirements) {
        final reqMap = req as Map<String, dynamic>;
        final type = reqMap['type'] as String;
        if (type == 'DungeonCompletion') {
          unlockDungeonId = MelvorId.fromJsonWithNamespace(
            reqMap['dungeonID'] as String,
            defaultNamespace: namespace,
          );
          break;
        }
        // Ignore SkillLevel requirements (demo-only impossible requirements).
      }
    } else if (requirements is Map<String, dynamic>) {
      // Full game patch format: { "remove": [...], "add": [...] }.
      // Only process the "add" section since we're not supporting demo-only.
      final addList = requirements['add'] as List<dynamic>?;
      if (addList != null) {
        for (final req in addList) {
          final reqMap = req as Map<String, dynamic>;
          final type = reqMap['type'] as String;
          if (type == 'DungeonCompletion') {
            unlockDungeonId = MelvorId.fromJsonWithNamespace(
              reqMap['dungeonID'] as String,
              defaultNamespace: namespace,
            );
            break;
          }
        }
      }
    }

    // Parse the enum from the slot name.
    final slotName = id.localId;
    final slot = EquipmentSlot.fromJson(slotName);

    return EquipmentSlotDef(
      slot: slot,
      id: id,
      allowQuantity: json['allowQuantity'] as bool,
      emptyName: json['emptyName'] as String,
      emptyMedia: json['emptyMedia'] as String,
      providesEquipStats: json['providesEquipStats'] as bool,
      gridPosition: gridPosition,
      unlockDungeonId: unlockDungeonId,
    );
  }

  /// The enum value for this slot.
  final EquipmentSlot slot;

  /// The unique identifier for this slot (e.g., melvorD:Weapon).
  final MelvorId id;

  /// Whether items in this slot can stack (e.g., ammo, summons, consumables).
  final bool allowQuantity;

  /// Display name when the slot is empty (e.g., "Head", "Weapon", "Offhand").
  final String emptyName;

  /// Path to the image shown when the slot is empty.
  final String emptyMedia;

  /// Whether items in this slot contribute to combat stats.
  /// The Passive slot has this set to false.
  final bool providesEquipStats;

  /// Grid position for UI layout.
  final GridPosition gridPosition;

  /// If set, the dungeon that must be completed to unlock this slot.
  /// Currently only used for the Passive slot (requires "Into the Mist").
  final MelvorId? unlockDungeonId;

  /// Short name for this slot (e.g., "Weapon", "Helmet").
  String get name => id.localId;

  /// Returns true if this slot requires dungeon completion to unlock.
  bool get requiresUnlock => unlockDungeonId != null;

  @override
  List<Object?> get props => [slot];

  @override
  String toString() => 'EquipmentSlotDef($name)';
}

/// Grid position for equipment slot UI layout.
@immutable
class GridPosition extends Equatable {
  const GridPosition({required this.col, required this.row});

  final int col;
  final int row;

  @override
  List<Object?> get props => [col, row];
}

/// Registry of all equipment slots with metadata from JSON.
class EquipmentSlotRegistry {
  EquipmentSlotRegistry(List<EquipmentSlotDef> slots)
    : _all = slots,
      _bySlot = {for (final def in slots) def.slot: def} {
    // Validate that all enum values have corresponding JSON definitions.
    final missingSlots = EquipmentSlot.values
        .where((slot) => !_bySlot.containsKey(slot))
        .toList();
    if (missingSlots.isNotEmpty) {
      throw StateError(
        'Missing JSON definitions for equipment slots: '
        '${missingSlots.map((s) => s.jsonName).join(', ')}',
      );
    }

    // Validate that enum's isStackSlot matches JSON's allowQuantity.
    // isStackSlot is kept on the enum for convenience (avoids passing registry
    // everywhere) but must match the JSON data.
    for (final def in slots) {
      if (def.slot.isStackSlot != def.allowQuantity) {
        throw StateError(
          'Slot ${def.slot.jsonName} has isStackSlot=${def.slot.isStackSlot} '
          'but JSON allowQuantity=${def.allowQuantity}',
        );
      }
    }
  }

  /// Creates an empty registry for testing.
  const EquipmentSlotRegistry.empty() : _all = const [], _bySlot = const {};

  final List<EquipmentSlotDef> _all;
  final Map<EquipmentSlot, EquipmentSlotDef> _bySlot;

  /// All registered equipment slots.
  List<EquipmentSlotDef> get all => _all;

  /// Returns the slot definition for the given enum value.
  /// Returns null if the registry is empty (test mode).
  EquipmentSlotDef? operator [](EquipmentSlot slot) => _bySlot[slot];

  /// Returns the slot definition for the given enum value.
  /// Throws if not found (should only happen with empty test registry).
  EquipmentSlotDef get(EquipmentSlot slot) {
    final def = _bySlot[slot];
    if (def == null) {
      throw StateError('Equipment slot not found: ${slot.jsonName}');
    }
    return def;
  }
}
