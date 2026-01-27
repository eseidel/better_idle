import 'package:async_redux/local_persist.dart';
import 'package:flutter/material.dart';
import 'package:ui/src/services/logger.dart';

/// Metadata about all save slots.
class SaveSlotMeta {
  SaveSlotMeta({required this.activeSlot, required this.slots});

  factory SaveSlotMeta.fromJson(Map<String, dynamic> json) {
    final slotsJson = json['slots'] as Map<String, dynamic>? ?? {};
    final slots = <int, SlotInfo>{};
    for (final entry in slotsJson.entries) {
      final index = int.tryParse(entry.key);
      if (index != null && entry.value is Map<String, dynamic>) {
        slots[index] = SlotInfo.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return SaveSlotMeta(
      activeSlot: json['activeSlot'] as int? ?? 0,
      slots: slots,
    );
  }

  factory SaveSlotMeta.empty() => SaveSlotMeta(activeSlot: 0, slots: {});

  final int activeSlot;
  final Map<int, SlotInfo> slots;

  Map<String, dynamic> toJson() => {
    'activeSlot': activeSlot,
    'slots': {
      for (final e in slots.entries) e.key.toString(): e.value.toJson(),
    },
  };

  SaveSlotMeta copyWith({int? activeSlot, Map<int, SlotInfo>? slots}) {
    return SaveSlotMeta(
      activeSlot: activeSlot ?? this.activeSlot,
      slots: slots ?? this.slots,
    );
  }
}

/// Information about a single save slot.
class SlotInfo {
  SlotInfo({required this.isEmpty, this.lastPlayed});

  factory SlotInfo.fromJson(Map<String, dynamic> json) {
    final lastPlayedStr = json['lastPlayed'] as String?;
    return SlotInfo(
      isEmpty: json['isEmpty'] as bool? ?? true,
      lastPlayed: lastPlayedStr != null ? DateTime.parse(lastPlayedStr) : null,
    );
  }

  final bool isEmpty;
  final DateTime? lastPlayed;

  Map<String, dynamic> toJson() => {
    'isEmpty': isEmpty,
    if (lastPlayed != null) 'lastPlayed': lastPlayed!.toIso8601String(),
  };
}

/// Number of available save slots.
const int saveSlotCount = 3;

/// Service for managing save slot metadata.
class SaveSlotService {
  SaveSlotService._();

  static final LocalPersist _metaPersist = LocalPersist('melvor_meta');

  /// Load save slot metadata.
  static Future<SaveSlotMeta> loadMeta() async {
    try {
      final json = await _metaPersist.loadJson() as Map<String, dynamic>?;
      if (json == null) {
        return SaveSlotMeta.empty();
      }
      return SaveSlotMeta.fromJson(json);
    } on Object catch (e, stackTrace) {
      logger.err('Failed to load meta: $e, stackTrace: $stackTrace');
      return SaveSlotMeta.empty();
    }
  }

  /// Save slot metadata.
  static Future<void> saveMeta(SaveSlotMeta meta) async {
    await _metaPersist.saveJson(meta.toJson());
  }

  /// Migrate old single-save format to slot 0 if needed.
  static Future<void> migrateIfNeeded() async {
    // Check if meta already exists (already migrated)
    final metaJson = await _metaPersist.loadJson();
    if (metaJson != null) {
      return; // Already migrated
    }

    // Check for old-style save
    final oldPersist = LocalPersist('better_idle');
    final oldData = await oldPersist.loadJson();

    if (oldData != null) {
      // Migrate to slot 0
      final slot0Persist = LocalPersist('melvor_slot_0');
      await slot0Persist.saveJson(oldData);

      // Create meta with slot 0 active
      final meta = SaveSlotMeta(
        activeSlot: 0,
        slots: {0: SlotInfo(isEmpty: false, lastPlayed: DateTime.timestamp())},
      );
      await saveMeta(meta);

      // Delete old storage
      await oldPersist.delete();
      logger.info('Migrated existing save to slot 0');
    } else {
      // No existing save - create empty meta
      await saveMeta(SaveSlotMeta.empty());
    }
  }

  /// Delete a specific slot's data.
  static Future<void> deleteSlot(int slot) async {
    final slotPersist = LocalPersist('melvor_slot_$slot');
    await slotPersist.delete();

    // Update meta
    final meta = await loadMeta();
    final newSlots = Map<int, SlotInfo>.from(meta.slots);
    newSlots[slot] = SlotInfo(isEmpty: true);
    await saveMeta(meta.copyWith(slots: newSlots));
  }
}

/// Provides access to save slot management functions.
class SaveSlotManager extends InheritedWidget {
  const SaveSlotManager({
    required this.activeSlot,
    required this.switchSlot,
    required this.deleteSlot,
    required super.child,
    super.key,
  });

  final int activeSlot;
  final Future<void> Function(int slot) switchSlot;
  final Future<void> Function(int slot) deleteSlot;

  static SaveSlotManager? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SaveSlotManager>();
  }

  static SaveSlotManager of(BuildContext context) {
    final manager = maybeOf(context);
    assert(manager != null, 'No SaveSlotManager found in context');
    return manager!;
  }

  @override
  bool updateShouldNotify(SaveSlotManager oldWidget) {
    return activeSlot != oldWidget.activeSlot;
  }
}
