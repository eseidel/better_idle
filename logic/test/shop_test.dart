import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('ShopCost', () {
    test('fixedCurrencyCosts returns all fixed costs', () {
      const cost = ShopCost(
        currencies: [
          CurrencyCost(
            currency: Currency.gp,
            type: CostType.fixed,
            fixedCost: 1000,
          ),
          CurrencyCost(
            currency: Currency.slayerCoins,
            type: CostType.fixed,
            fixedCost: 50,
          ),
        ],
        items: [],
      );

      final fixed = cost.fixedCurrencyCosts;
      expect(fixed.length, 2);
      expect(fixed[0], (Currency.gp, 1000));
      expect(fixed[1], (Currency.slayerCoins, 50));
    });

    test('fixedCurrencyCosts excludes bank slot pricing', () {
      const cost = ShopCost(
        currencies: [
          CurrencyCost(currency: Currency.gp, type: CostType.bankSlot),
        ],
        items: [],
      );

      expect(cost.fixedCurrencyCosts, isEmpty);
      expect(cost.usesBankSlotPricing, isTrue);
    });
  });

  group('ShopRegistry', () {
    setUpAll(() async {
      await loadTestRegistries();
    });
    test('item costs reference valid items', () {
      for (final purchase in testRegistries.shop.all) {
        for (final itemCost in purchase.cost.items) {
          // This should not throw - all item IDs should be valid
          expect(
            () => testRegistries.items.byId(itemCost.itemId),
            returnsNormally,
            reason:
                'Item ${itemCost.itemId} in purchase ${purchase.id} '
                'should exist in item registry',
          );
        }
      }
    });
  });

  group('ShopState', () {
    test('nextBankSlotCost returns correct costs for first 10 slots', () {
      void expectSlotCost(int slot, int expectedCost) {
        final bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
        var purchaseCounts = <MelvorId, int>{};
        for (var i = 0; i < slot; i++) {
          purchaseCounts = {
            ...purchaseCounts,
            bankSlotId: (purchaseCounts[bankSlotId] ?? 0) + 1,
          };
        }
        final shopState = ShopState(purchaseCounts: purchaseCounts);
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
      expect(shopState.bankSlotsPurchased, 0);
      expect(shopState.nextBankSlotCost(), greaterThan(0));
    });

    test('ShopState.withPurchase adds purchase', () {
      const shopState = ShopState.empty();
      final bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
      final updated = shopState.withPurchase(bankSlotId);
      expect(updated.purchaseCount(bankSlotId), 1);
      expect(
        updated.nextBankSlotCost(),
        isNot(equals(shopState.nextBankSlotCost())),
      );
    });

    test('ShopState serialization round-trip', () {
      final bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
      final original = ShopState(purchaseCounts: {bankSlotId: 3});
      final json = original.toJson();
      final loaded = ShopState.fromJson(json);

      expect(loaded.bankSlotsPurchased, original.bankSlotsPurchased);
      expect(loaded.nextBankSlotCost(), original.nextBankSlotCost());
    });
  });
}
