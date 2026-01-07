import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  group('Currency', () {
    test('equality works correctly', () {
      expect(Currency.gp, equals(Currency.gp));
      expect(Currency.gp, isNot(equals(Currency.slayerCoins)));
      expect(Currency.slayerCoins, isNot(equals(Currency.raidCoins)));
    });

    test('fromId throws for unknown id', () {
      expect(() => Currency.fromId('unknown:Currency'), throwsArgumentError);
    });
  });

  group('CurrencyCost', () {
    test('equality works correctly', () {
      const cost1 = CurrencyCost(
        currency: Currency.gp,
        type: CostType.fixed,
        fixedCost: 1000,
      );
      const cost2 = CurrencyCost(
        currency: Currency.gp,
        type: CostType.fixed,
        fixedCost: 1000,
      );
      const cost3 = CurrencyCost(
        currency: Currency.gp,
        type: CostType.fixed,
        fixedCost: 2000,
      );

      expect(cost1, equals(cost2));
      expect(cost1, isNot(equals(cost3)));
    });

    test('fromJson parses fixed cost correctly', () {
      final json = {'currency': 'melvorD:GP', 'type': 'Fixed', 'cost': 5000};
      final cost = CurrencyCost.fromJson(json);

      expect(cost.currency, Currency.gp);
      expect(cost.type, CostType.fixed);
      expect(cost.fixedCost, 5000);
    });

    test('fromJson parses bank slot pricing correctly', () {
      final json = {'currency': 'melvorD:GP', 'type': 'BankSlot'};
      final cost = CurrencyCost.fromJson(json);

      expect(cost.currency, Currency.gp);
      expect(cost.type, CostType.bankSlot);
      expect(cost.fixedCost, isNull);
    });
  });

  group('ItemCost', () {
    test('equality works correctly', () {
      const cost1 = ItemCost(
        itemId: MelvorId('melvorD:Normal_Logs'),
        quantity: 10,
      );
      const cost2 = ItemCost(
        itemId: MelvorId('melvorD:Normal_Logs'),
        quantity: 10,
      );
      const cost3 = ItemCost(
        itemId: MelvorId('melvorD:Oak_Logs'),
        quantity: 10,
      );

      expect(cost1, equals(cost2));
      expect(cost1, isNot(equals(cost3)));
    });
  });

  group('ShopCost', () {
    test('currencyCosts returns all fixed costs', () {
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

      final costs = cost.currencyCosts(bankSlotsPurchased: 0);
      expect(costs.length, 2);
      expect(costs[0], (Currency.gp, 1000));
      expect(costs[1], (Currency.slayerCoins, 50));
    });

    test('currencyCosts calculates bank slot pricing dynamically', () {
      const cost = ShopCost(
        currencies: [
          CurrencyCost(currency: Currency.gp, type: CostType.bankSlot),
        ],
        items: [],
      );

      // First bank slot cost
      final costs0 = cost.currencyCosts(bankSlotsPurchased: 0);
      expect(costs0.length, 1);
      expect(costs0[0].$1, Currency.gp);
      expect(costs0[0].$2, calculateBankSlotCost(0));

      // After purchasing some slots, the cost increases
      final costs5 = cost.currencyCosts(bankSlotsPurchased: 5);
      expect(costs5.length, 1);
      expect(costs5[0].$1, Currency.gp);
      expect(costs5[0].$2, calculateBankSlotCost(5));
      expect(costs5[0].$2, greaterThan(costs0[0].$2));
    });

    test('gpCost returns GP cost for fixed pricing', () {
      const cost = ShopCost(
        currencies: [
          CurrencyCost(
            currency: Currency.gp,
            type: CostType.fixed,
            fixedCost: 5000,
          ),
        ],
        items: [],
      );

      expect(cost.gpCost, 5000);
    });

    test('gpCost returns null for bank slot pricing', () {
      const cost = ShopCost(
        currencies: [
          CurrencyCost(currency: Currency.gp, type: CostType.bankSlot),
        ],
        items: [],
      );

      expect(cost.gpCost, isNull);
    });

    test('equality works correctly', () {
      const cost1 = ShopCost(
        currencies: [
          CurrencyCost(
            currency: Currency.gp,
            type: CostType.fixed,
            fixedCost: 1000,
          ),
        ],
        items: [],
      );
      const cost2 = ShopCost(
        currencies: [
          CurrencyCost(
            currency: Currency.gp,
            type: CostType.fixed,
            fixedCost: 1000,
          ),
        ],
        items: [],
      );

      expect(cost1, equals(cost2));
    });
  });

  group('ShopPurchase', () {
    test('fromJson parses customName and customDescription', () {
      final json = {
        'id': 'Test_Item',
        'customName': 'Custom Name',
        'customDescription': 'This is a custom description',
        'category': 'melvorD:General',
        'cost': {'items': <dynamic>[], 'currencies': <dynamic>[]},
        'contains': {'modifiers': <String, dynamic>{}},
        'unlockRequirements': <dynamic>[],
        'purchaseRequirements': <dynamic>[],
        'defaultBuyLimit': 1,
      };
      final purchase = ShopPurchase.fromJson(json, namespace: 'melvorD');

      expect(purchase.name, 'Custom Name');
      expect(purchase.description, 'This is a custom description');
    });

    test('fromJson uses ID name when customName is missing', () {
      final json = {
        'id': 'Test_Item',
        'category': 'melvorD:General',
        'cost': {'items': <dynamic>[], 'currencies': <dynamic>[]},
        'contains': {'modifiers': <String, dynamic>{}},
        'unlockRequirements': <dynamic>[],
        'purchaseRequirements': <dynamic>[],
        'defaultBuyLimit': 1,
      };
      final purchase = ShopPurchase.fromJson(json, namespace: 'melvorD');

      expect(purchase.name, 'Test Item'); // ID converted to name format
      expect(purchase.description, isNull);
    });
  });

  group('ShopCategory', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'TestCategory',
        'name': 'Test Category',
        'media': 'assets/media/test.png',
      };
      final category = ShopCategory.fromJson(json, namespace: 'melvorD');

      expect(category.id, const MelvorId('melvorD:TestCategory'));
      expect(category.name, 'Test Category');
      expect(category.media, 'assets/media/test.png');
    });

    test('fromJson handles missing media', () {
      final json = {'id': 'TestCategory', 'name': 'Test Category'};
      final category = ShopCategory.fromJson(json, namespace: 'melvorD');

      expect(category.media, isNull);
    });

    test('equality works correctly', () {
      const cat1 = ShopCategory(id: MelvorId('melvorD:Test'), name: 'Test');
      const cat2 = ShopCategory(id: MelvorId('melvorD:Test'), name: 'Test');
      const cat3 = ShopCategory(id: MelvorId('melvorD:Other'), name: 'Other');

      expect(cat1, equals(cat2));
      expect(cat1, isNot(equals(cat3)));
    });
  });

  group('SkillLevelRequirement', () {
    test('fromJson parses correctly', () {
      final json = {
        'type': 'SkillLevel',
        'skillID': 'melvorD:Woodcutting',
        'level': 50,
      };
      final req = SkillLevelRequirement.fromJson(json);

      expect(req, isNotNull);
      expect(req!.skill, Skill.woodcutting);
      expect(req.level, 50);
    });

    test('fromJson throws for unsupported skill', () {
      final json = {
        'type': 'SkillLevel',
        'skillID': 'melvorD:UnsupportedSkill',
        'level': 50,
      };
      expect(() => SkillLevelRequirement.fromJson(json), throwsArgumentError);
    });

    test('equality works correctly', () {
      const req1 = SkillLevelRequirement(skill: Skill.woodcutting, level: 50);
      const req2 = SkillLevelRequirement(skill: Skill.woodcutting, level: 50);
      const req3 = SkillLevelRequirement(skill: Skill.fishing, level: 50);

      expect(req1, equals(req2));
      expect(req1, isNot(equals(req3)));
    });
  });

  group('ShopPurchaseRequirement', () {
    test('fromJson parses correctly', () {
      final json = {
        'type': 'ShopPurchase',
        'purchaseID': 'melvorD:Bronze_Axe',
        'count': 1,
      };
      final req = ShopPurchaseRequirement.fromJson(json, namespace: 'melvorD');

      expect(req.purchaseId, const MelvorId('melvorD:Bronze_Axe'));
      expect(req.count, 1);
    });

    test('equality works correctly', () {
      const req1 = ShopPurchaseRequirement(
        purchaseId: MelvorId('melvorD:Bronze_Axe'),
        count: 1,
      );
      const req2 = ShopPurchaseRequirement(
        purchaseId: MelvorId('melvorD:Bronze_Axe'),
        count: 1,
      );
      const req3 = ShopPurchaseRequirement(
        purchaseId: MelvorId('melvorD:Iron_Axe'),
        count: 1,
      );

      expect(req1, equals(req2));
      expect(req1, isNot(equals(req3)));
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
        const bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
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
      const bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
      final updated = shopState.withPurchase(bankSlotId);
      expect(updated.purchaseCount(bankSlotId), 1);
      expect(
        updated.nextBankSlotCost(),
        isNot(equals(shopState.nextBankSlotCost())),
      );
    });

    test('ShopState serialization round-trip', () {
      const bankSlotId = MelvorId('melvorD:Extra_Bank_Slot');
      final original = ShopState(purchaseCounts: {bankSlotId: 3});
      final json = original.toJson();
      final loaded = ShopState.fromJson(json);

      expect(loaded.bankSlotsPurchased, original.bankSlotsPurchased);
      expect(loaded.nextBankSlotCost(), original.nextBankSlotCost());
    });
  });
}
