import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('EquipmentSlotDef.fromJson', () {
    group('requirements parsing', () {
      test('parses array-style requirements (demo format)', () {
        // This is how the demo data defines the Passive slot
        final json = <String, dynamic>{
          'id': 'Passive',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/passive_slot.png',
          'emptyName': 'Passive',
          'providesEquipStats': false,
          'gridPosition': {'col': 1, 'row': 0},
          'requirements': [
            {'type': 'SkillLevel', 'skillID': 'melvorD:Attack', 'level': 1000},
          ],
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.slot, EquipmentSlot.passive);
        expect(slot.id.toJson(), 'melvorD:Passive');
        // SkillLevel requirements are ignored (demo-only lock)
        expect(slot.unlockDungeonId, isNull);
      });

      test('parses object-style requirements with add (full game patch)', () {
        // This is how melvorFull.json patches the Passive slot
        final json = <String, dynamic>{
          'id': 'Passive',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/passive_slot.png',
          'emptyName': 'Passive',
          'providesEquipStats': false,
          'gridPosition': {'col': 1, 'row': 0},
          'requirements': {
            'remove': ['SkillLevel'],
            'add': [
              {
                'type': 'DungeonCompletion',
                'dungeonID': 'melvorF:Into_the_Mist',
                'count': 1,
              },
            ],
          },
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.slot, EquipmentSlot.passive);
        expect(slot.unlockDungeonId, isNotNull);
        expect(slot.unlockDungeonId!.toJson(), 'melvorF:Into_the_Mist');
        expect(slot.requiresUnlock, isTrue);
      });

      test('parses DungeonCompletion in array-style requirements', () {
        // DungeonCompletion could also appear in array format
        final json = <String, dynamic>{
          'id': 'Passive',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/passive_slot.png',
          'emptyName': 'Passive',
          'providesEquipStats': false,
          'gridPosition': {'col': 1, 'row': 0},
          'requirements': [
            {
              'type': 'DungeonCompletion',
              'dungeonID': 'melvorF:Into_the_Mist',
              'count': 1,
            },
          ],
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.unlockDungeonId, isNotNull);
        expect(slot.unlockDungeonId!.toJson(), 'melvorF:Into_the_Mist');
      });

      test('handles empty add array in patch format', () {
        final json = <String, dynamic>{
          'id': 'Helmet',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_helmet.png',
          'emptyName': 'Head',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 0},
          'requirements': {
            'remove': ['SomeRequirement'],
            'add': <Map<String, dynamic>>[],
          },
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.slot, EquipmentSlot.helmet);
        expect(slot.unlockDungeonId, isNull);
      });

      test('handles patch format with no add key', () {
        final json = <String, dynamic>{
          'id': 'Helmet',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_helmet.png',
          'emptyName': 'Head',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 0},
          'requirements': {
            'remove': ['SomeRequirement'],
          },
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.slot, EquipmentSlot.helmet);
        expect(slot.unlockDungeonId, isNull);
      });

      test('handles no requirements', () {
        final json = <String, dynamic>{
          'id': 'Helmet',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_helmet.png',
          'emptyName': 'Head',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 0},
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.slot, EquipmentSlot.helmet);
        expect(slot.unlockDungeonId, isNull);
        expect(slot.requiresUnlock, isFalse);
      });
    });

    group('id parsing', () {
      test('parses namespaced id and ignores namespace parameter', () {
        // When MelvorData merges a patch, it passes the existing slot's
        // namespaced ID (e.g., 'melvorD:Passive') in the merged JSON.
        // The fromJson should use MelvorId.fromJson for these, ignoring the
        // namespace parameter entirely.
        final json = <String, dynamic>{
          'id': 'melvorD:Passive',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/passive_slot.png',
          'emptyName': 'Passive',
          'providesEquipStats': false,
          'gridPosition': {'col': 1, 'row': 0},
        };

        // Pass a different namespace to verify it's ignored
        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorFull');

        // Should use melvorD from the ID, not melvorFull from parameter
        expect(slot.id.namespace, 'melvorD');
        expect(slot.id.localId, 'Passive');
        expect(slot.id.toJson(), 'melvorD:Passive');
        expect(slot.slot, EquipmentSlot.passive);
      });

      test('parses plain id with namespace', () {
        // Base definitions use plain IDs
        final json = <String, dynamic>{
          'id': 'Weapon',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/weapon_sword.png',
          'emptyName': 'Weapon',
          'providesEquipStats': true,
          'gridPosition': {'col': 1, 'row': 2},
        };

        final slot = EquipmentSlotDef.fromJson(json, namespace: 'melvorD');

        expect(slot.id.toJson(), 'melvorD:Weapon');
        expect(slot.slot, EquipmentSlot.weapon);
      });
    });
  });

  group('EquipmentSlot', () {
    test('fromJson parses all slot names', () {
      expect(EquipmentSlot.fromJson('Helmet'), EquipmentSlot.helmet);
      expect(EquipmentSlot.fromJson('Platebody'), EquipmentSlot.platebody);
      expect(EquipmentSlot.fromJson('Platelegs'), EquipmentSlot.platelegs);
      expect(EquipmentSlot.fromJson('Boots'), EquipmentSlot.boots);
      expect(EquipmentSlot.fromJson('Gloves'), EquipmentSlot.gloves);
      expect(EquipmentSlot.fromJson('Cape'), EquipmentSlot.cape);
      expect(EquipmentSlot.fromJson('Amulet'), EquipmentSlot.amulet);
      expect(EquipmentSlot.fromJson('Ring'), EquipmentSlot.ring);
      expect(EquipmentSlot.fromJson('Weapon'), EquipmentSlot.weapon);
      expect(EquipmentSlot.fromJson('Shield'), EquipmentSlot.shield);
      expect(EquipmentSlot.fromJson('Quiver'), EquipmentSlot.quiver);
      expect(EquipmentSlot.fromJson('Summon1'), EquipmentSlot.summon1);
      expect(EquipmentSlot.fromJson('Summon2'), EquipmentSlot.summon2);
      expect(EquipmentSlot.fromJson('Consumable'), EquipmentSlot.consumable);
      expect(EquipmentSlot.fromJson('Passive'), EquipmentSlot.passive);
      expect(EquipmentSlot.fromJson('Gem'), EquipmentSlot.gem);
      expect(
        EquipmentSlot.fromJson('Enhancement1'),
        EquipmentSlot.enhancement1,
      );
      expect(
        EquipmentSlot.fromJson('Enhancement2'),
        EquipmentSlot.enhancement2,
      );
      expect(
        EquipmentSlot.fromJson('Enhancement3'),
        EquipmentSlot.enhancement3,
      );
    });

    test('fromJson throws for unknown slot', () {
      expect(() => EquipmentSlot.fromJson('UnknownSlot'), throwsArgumentError);
    });

    test('toJson round-trips', () {
      for (final slot in EquipmentSlot.values) {
        expect(EquipmentSlot.fromJson(slot.toJson()), slot);
      }
    });

    test('maybeFromJson returns null for null input', () {
      expect(EquipmentSlot.maybeFromJson(null), isNull);
    });

    test('maybeFromJson parses valid input', () {
      expect(EquipmentSlot.maybeFromJson('Weapon'), EquipmentSlot.weapon);
    });
  });
}
