import 'package:logic/logic.dart';
import 'package:test/test.dart';

/// Creates minimal data files for testing MelvorData parsing.
///
/// This mirrors the real data structure where melvorDemo defines base slots
/// and melvorFull patches them with updated requirements.
Map<String, dynamic> _createDemoData() {
  return {
    'namespace': 'melvorD',
    'data': {
      // All 19 equipment slots must be defined for the registry to validate
      'equipmentSlots': [
        {
          'id': 'Helmet',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_helmet.png',
          'emptyName': 'Head',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 0},
        },
        {
          'id': 'Platebody',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_platebody.png',
          'emptyName': 'Torso',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 2},
        },
        {
          'id': 'Platelegs',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_platelegs.png',
          'emptyName': 'Legs',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 3},
        },
        {
          'id': 'Boots',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_boots.png',
          'emptyName': 'Feet',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 4},
        },
        {
          'id': 'Gloves',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_gloves.png',
          'emptyName': 'Hands',
          'providesEquipStats': true,
          'gridPosition': {'col': 1, 'row': 4},
        },
        {
          'id': 'Cape',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_cape.png',
          'emptyName': 'Cape',
          'providesEquipStats': true,
          'gridPosition': {'col': 1, 'row': 1},
        },
        {
          'id': 'Amulet',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_amulet.png',
          'emptyName': 'Neck',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 1},
        },
        {
          'id': 'Ring',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_ring.png',
          'emptyName': 'Ring',
          'providesEquipStats': true,
          'gridPosition': {'col': 3, 'row': 4},
        },
        {
          'id': 'Weapon',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/weapon_sword.png',
          'emptyName': 'Weapon',
          'providesEquipStats': true,
          'gridPosition': {'col': 1, 'row': 2},
        },
        {
          'id': 'Shield',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/armour_shield.png',
          'emptyName': 'Offhand',
          'providesEquipStats': true,
          'gridPosition': {'col': 3, 'row': 2},
        },
        {
          'id': 'Quiver',
          'allowQuantity': true,
          'emptyMedia': 'assets/media/bank/weapon_quiver.png',
          'emptyName': 'Quiver',
          'providesEquipStats': true,
          'gridPosition': {'col': 3, 'row': 1},
        },
        {
          'id': 'Summon1',
          'allowQuantity': true,
          'emptyMedia': 'assets/media/bank/misc_summon.png',
          'emptyName': 'Summon L',
          'providesEquipStats': true,
          'gridPosition': {'col': 1, 'row': 5},
        },
        {
          'id': 'Summon2',
          'allowQuantity': true,
          'emptyMedia': 'assets/media/bank/misc_summon.png',
          'emptyName': 'Summon R',
          'providesEquipStats': true,
          'gridPosition': {'col': 3, 'row': 5},
        },
        {
          'id': 'Consumable',
          'allowQuantity': true,
          'emptyMedia': 'assets/media/bank/misc_consumable.png',
          'emptyName': 'Consumable',
          'providesEquipStats': true,
          'gridPosition': {'col': 2, 'row': 5},
        },
        // Passive slot with demo-style requirements (SkillLevel lock)
        {
          'id': 'Passive',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/passive_slot.png',
          'emptyName': 'Passive',
          'providesEquipStats': false,
          'gridPosition': {'col': 1, 'row': 0},
          'requirements': [
            {'type': 'SkillLevel', 'skillID': 'melvorD:Attack', 'level': 1000},
          ],
        },
        {
          'id': 'Gem',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_gem.png',
          'emptyName': 'Gem',
          'providesEquipStats': true,
          'gridPosition': {'col': 3, 'row': 0},
        },
        {
          'id': 'Enhancement1',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_enhancement.png',
          'emptyName': 'Enhancement 1',
          'providesEquipStats': true,
          'gridPosition': {'col': 0, 'row': 2},
        },
        {
          'id': 'Enhancement2',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_enhancement.png',
          'emptyName': 'Enhancement 2',
          'providesEquipStats': true,
          'gridPosition': {'col': 0, 'row': 3},
        },
        {
          'id': 'Enhancement3',
          'allowQuantity': false,
          'emptyMedia': 'assets/media/bank/misc_enhancement.png',
          'emptyName': 'Enhancement 3',
          'providesEquipStats': true,
          'gridPosition': {'col': 0, 'row': 4},
        },
      ],
    },
  };
}

/// Creates a patch data file that updates the Passive slot requirements.
///
/// This mirrors how melvorFull.json patches the Passive slot from demo data.
Map<String, dynamic> _createFullPatchData() {
  return {
    'namespace': 'melvorFull',
    'data': {
      // Patch for the Passive slot - uses namespaced ID to reference existing
      'equipmentSlots': [
        {
          'id': 'melvorD:Passive',
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
        },
      ],
    },
  };
}

void main() {
  group('MelvorData equipment slot patching', () {
    test('patches Passive slot requirements from demo to full format', () {
      // Load demo data first (base definitions), then full data (patches)
      final melvorData = MelvorData([
        _createDemoData(),
        _createFullPatchData(),
      ]);
      final equipmentSlots = melvorData.toRegistries().equipmentSlots;

      // Verify the Passive slot was patched correctly
      final passiveSlot = equipmentSlots[EquipmentSlot.passive];
      expect(passiveSlot, isNotNull);
      expect(passiveSlot!.slot, EquipmentSlot.passive);

      // The patch should have replaced the SkillLevel requirement with
      // a DungeonCompletion requirement
      expect(passiveSlot.unlockDungeonId, isNotNull);
      expect(passiveSlot.unlockDungeonId!.toJson(), 'melvorF:Into_the_Mist');
      expect(passiveSlot.requiresUnlock, isTrue);

      // Other properties should be preserved from the base definition
      expect(passiveSlot.id.toJson(), 'melvorD:Passive');
      expect(passiveSlot.allowQuantity, isFalse);
      expect(passiveSlot.emptyName, 'Passive');
      expect(passiveSlot.providesEquipStats, isFalse);
    });

    test('demo data without patch has no unlock requirement', () {
      // Load only demo data (no patch)
      final melvorData = MelvorData([_createDemoData()]);
      final equipmentSlots = melvorData.toRegistries().equipmentSlots;

      final passiveSlot = equipmentSlots[EquipmentSlot.passive];
      expect(passiveSlot, isNotNull);

      // SkillLevel requirements are ignored, so no unlock should be set
      expect(passiveSlot!.unlockDungeonId, isNull);
      expect(passiveSlot.requiresUnlock, isFalse);
    });

    test('patch for non-existent slot is ignored', () {
      final demoData = _createDemoData();
      final patchData = {
        'namespace': 'melvorFull',
        'data': {
          'equipmentSlots': [
            {
              // Reference a slot that doesn't exist
              'id': 'melvorD:NonExistent',
              'requirements': {
                'add': [
                  {'type': 'DungeonCompletion', 'dungeonID': 'melvorF:Test'},
                ],
              },
            },
          ],
        },
      };

      // Should not throw - patch is silently ignored
      final melvorData = MelvorData([demoData, patchData]);
      final equipmentSlots = melvorData.toRegistries().equipmentSlots;
      expect(equipmentSlots.all.length, 19);
    });
  });
}
