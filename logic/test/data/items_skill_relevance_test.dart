import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('Item.hasModifiersForSkill', () {
    const woodcuttingId = MelvorId('melvorD:Woodcutting');
    const fishingId = MelvorId('melvorD:Fishing');

    test('returns true for item with matching skill modifier', () {
      const item = Item(
        id: MelvorId('melvorD:Test_Item'),
        name: 'Test Item',
        itemType: 'Equipment',
        sellsFor: 10,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillXP',
            entries: [
              ModifierEntry(
                value: 5,
                scope: ModifierScope(skillId: woodcuttingId),
              ),
            ],
          ),
        ]),
      );

      expect(item.hasModifiersForSkill(woodcuttingId), isTrue);
    });

    test('returns false for item with non-matching skill modifier', () {
      const item = Item(
        id: MelvorId('melvorD:Test_Item'),
        name: 'Test Item',
        itemType: 'Equipment',
        sellsFor: 10,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillXP',
            entries: [
              ModifierEntry(
                value: 5,
                scope: ModifierScope(skillId: woodcuttingId),
              ),
            ],
          ),
        ]),
      );

      expect(item.hasModifiersForSkill(fishingId), isFalse);
    });

    test('returns true for item with global modifier', () {
      const item = Item(
        id: MelvorId('melvorD:Test_Item'),
        name: 'Test Item',
        itemType: 'Equipment',
        sellsFor: 10,
        validSlots: [EquipmentSlot.ring],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'doubleItemsSkill',
            entries: [ModifierEntry(value: 5)],
          ),
        ]),
      );

      expect(item.hasModifiersForSkill(woodcuttingId), isTrue);
      expect(item.hasModifiersForSkill(fishingId), isTrue);
    });

    test('returns false for item with no modifiers', () {
      const item = Item(
        id: MelvorId('melvorD:Test_Item'),
        name: 'Test Item',
        itemType: 'Equipment',
        sellsFor: 10,
        validSlots: [EquipmentSlot.ring],
      );

      expect(item.hasModifiersForSkill(woodcuttingId), isFalse);
    });
  });
}
