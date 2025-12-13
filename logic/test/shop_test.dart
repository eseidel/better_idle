import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('ShopState', () {
    test('nextBankSlotCost returns correct costs for first 10 slots', () {
      void expectSlotCost(int slot, int expectedCost) {
        final shopState = ShopState(bankSlots: slot);
        final cost = shopState.nextBankSlotCost();
        expect(
          cost,
          expectedCost,
          reason: 'Bank slot $slot should cost $expectedCost, but got $cost',
        );
      }

      // Expected costs calculated from the formula:
      // C_b = floor(132728500 * (n+2) / 142015^(163/(122+n)))
      // where n is the current number of bank slots purchased
      expectSlotCost(0, 34);
      expectSlotCost(1, 59);
      expectSlotCost(2, 89);
      expectSlotCost(3, 126);
      expectSlotCost(4, 172);
      expectSlotCost(5, 226);
      expectSlotCost(6, 291);
      expectSlotCost(7, 368);
      expectSlotCost(8, 459);
      expectSlotCost(9, 566);

      // Slot costs cap at 5M GP
      expectSlotCost(200, 5000000);
    });

    test('ShopState.empty starts with 0 bank slots', () {
      const shopState = ShopState.empty();
      expect(shopState.bankSlots, 0);
      expect(shopState.nextBankSlotCost(), greaterThan(0));
    });

    test('ShopState.copyWith updates bank slots', () {
      const shopState = ShopState.empty();
      final updated = shopState.copyWith(bankSlots: 5);
      expect(updated.bankSlots, 5);
      expect(
        updated.nextBankSlotCost(),
        isNot(equals(shopState.nextBankSlotCost())),
      );
    });

    test('ShopState serialization round-trip', () {
      const original = ShopState(bankSlots: 3);
      final json = original.toJson();
      final loaded = ShopState.fromJson(json);

      expect(loaded.bankSlots, original.bankSlots);
      expect(loaded.nextBankSlotCost(), original.nextBankSlotCost());
    });
  });
}
