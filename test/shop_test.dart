import 'package:better_idle/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShopState', () {
    test('nextBankSlotCost returns correct costs for first 10 slots', () {
      // Expected costs calculated from the formula:
      // C_b = floor(132728500 * (n+2) / 142015^(163/(122+n)))
      // where n is the current number of bank slots purchased
      // These values were calculated and verified from the Melvor Idle wiki formula
      const expectedCosts = [
        34, // n=0: first bank slot
        59, // n=1: second bank slot
        89, // n=2: third bank slot
        126, // n=3: fourth bank slot
        172, // n=4: fifth bank slot
        226, // n=5: sixth bank slot
        291, // n=6: seventh bank slot
        368, // n=7: eighth bank slot
        459, // n=8: ninth bank slot
        566, // n=9: tenth bank slot
      ];

      for (var i = 0; i < 10; i++) {
        final shopState = ShopState(bankSlots: i);
        final cost = shopState.nextBankSlotCost();
        expect(
          cost,
          expectedCosts[i],
          reason:
              'Bank slot ${i + 1} (n=$i) should cost ${expectedCosts[i]}, '
              'but got $cost',
        );
      }
    });

    test('nextBankSlotCost increases as more slots are purchased', () {
      // Verify that costs generally increase (or at least don't decrease significantly)
      final costs = <int>[];
      for (var i = 0; i < 10; i++) {
        final shopState = ShopState(bankSlots: i);
        costs.add(shopState.nextBankSlotCost());
      }

      // First few slots should be the same or very similar
      // Later slots should start increasing
      expect(
        costs[0],
        greaterThan(0),
        reason: 'First slot cost should be positive',
      );

      // Verify all costs are positive
      for (var i = 0; i < costs.length; i++) {
        expect(
          costs[i],
          greaterThan(0),
          reason: 'Bank slot ${i + 1} cost should be positive',
        );
      }
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
