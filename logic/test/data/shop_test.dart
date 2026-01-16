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

    test('fromIdString throws for unknown id', () {
      expect(
        () => Currency.fromIdString('unknown:Currency'),
        throwsArgumentError,
      );
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

    test('fromJson parses contains.items correctly', () {
      final json = {
        'id': 'Test_Resupply',
        'customName': 'Test Resupply',
        'customDescription': r'+${qty1} Arrows, +${qty2} Bolts, +${qty3} Runes',
        'category': 'melvorD:General',
        'cost': {'items': <dynamic>[], 'currencies': <dynamic>[]},
        'contains': {
          'modifiers': <String, dynamic>{},
          'items': [
            {'id': 'melvorD:Adamant_Arrows', 'quantity': 200},
            {'id': 'melvorD:Sapphire_Bolts', 'quantity': 150},
            {'id': 'melvorD:Light_Rune', 'quantity': 500},
          ],
        },
        'unlockRequirements': <dynamic>[],
        'purchaseRequirements': <dynamic>[],
        'defaultBuyLimit': 1,
      };
      final purchase = ShopPurchase.fromJson(json, namespace: 'melvorD');

      expect(purchase.contains.items.length, 3);
      expect(
        purchase.contains.items[0].itemId,
        const MelvorId('melvorD:Adamant_Arrows'),
      );
      expect(purchase.contains.items[0].quantity, 200);
      expect(
        purchase.contains.items[1].itemId,
        const MelvorId('melvorD:Sapphire_Bolts'),
      );
      expect(purchase.contains.items[1].quantity, 150);
      expect(
        purchase.contains.items[2].itemId,
        const MelvorId('melvorD:Light_Rune'),
      );
      expect(purchase.contains.items[2].quantity, 500);
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

    test('purchasesContainingItem returns purchases that contain the item', () {
      // Find a purchase that contains items
      final purchaseWithItems = testRegistries.shop.all.firstWhere(
        (p) => p.contains.items.isNotEmpty,
        orElse: () => throw StateError('No purchase with items found'),
      );

      final containedItemId = purchaseWithItems.contains.items.first.itemId;
      final results = testRegistries.shop.purchasesContainingItem(
        containedItemId,
      );

      expect(results, isNotEmpty);
      expect(results, contains(purchaseWithItems));

      // Verify all results contain the item
      for (final purchase in results) {
        expect(
          purchase.contains.items.any((item) => item.itemId == containedItemId),
          isTrue,
          reason:
              'Purchase ${purchase.id} should contain item $containedItemId',
        );
      }
    });

    test(
      'purchasesContainingItem returns empty list for non-existent item',
      () {
        final results = testRegistries.shop.purchasesContainingItem(
          const MelvorId('melvorD:Non_Existent_Item'),
        );

        expect(results, isEmpty);
      },
    );

    test(
      'purchasesContainingItem returns multiple purchases for common items',
      () {
        // Build a map of itemId -> count of purchases containing it
        final itemPurchaseCounts = <MelvorId, int>{};
        for (final purchase in testRegistries.shop.all) {
          for (final item in purchase.contains.items) {
            itemPurchaseCounts[item.itemId] =
                (itemPurchaseCounts[item.itemId] ?? 0) + 1;
          }
        }

        // Find an item that appears in multiple purchases (if any)
        final multiPurchaseEntry = itemPurchaseCounts.entries
            .where((e) => e.value > 1)
            .firstOrNull;

        if (multiPurchaseEntry != null) {
          final itemId = multiPurchaseEntry.key;
          final expectedCount = multiPurchaseEntry.value;

          final results = testRegistries.shop.purchasesContainingItem(itemId);
          expect(results.length, expectedCount);
        }
      },
    );
  });

  group('ShopContents', () {
    test('fromJson parses itemCharges correctly', () {
      final json = {
        'modifiers': <String, dynamic>{},
        'items': <dynamic>[],
        'itemCharges': {'id': 'melvorF:Thieving_Gloves', 'quantity': 500},
      };
      final contents = ShopContents.fromJson(json, namespace: 'melvorD');

      expect(contents.itemCharges, isNotNull);
      expect(
        contents.itemCharges!.itemId,
        const MelvorId('melvorF:Thieving_Gloves'),
      );
      expect(contents.itemCharges!.quantity, 500);
    });

    test('fromJson handles missing itemCharges', () {
      final json = {'modifiers': <String, dynamic>{}, 'items': <dynamic>[]};
      final contents = ShopContents.fromJson(json, namespace: 'melvorD');

      expect(contents.itemCharges, isNull);
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

  group('ItemCharges purchases', () {
    setUpAll(() async {
      await loadTestRegistries();
    });

    test('purchasing gloves adds item to inventory and sets charges', () {
      // Find a gloves purchase with itemCharges from the registry
      final glovesPurchase = testRegistries.shop.all.firstWhere(
        (p) => p.contains.itemCharges != null,
        orElse: () => throw StateError('No itemCharges purchase found'),
      );

      final itemCharges = glovesPurchase.contains.itemCharges!;
      final glovesItem = testRegistries.items.byId(itemCharges.itemId);

      // Start with empty state and enough GP
      final costs = glovesPurchase.cost.currencyCosts(bankSlotsPurchased: 0);
      final gpCost = costs.firstWhere((c) => c.$1 == Currency.gp).$2;

      final state = GlobalState.test(testRegistries, gp: gpCost);

      // Verify starting conditions
      expect(state.inventory.countOfItem(glovesItem), 0);
      expect(state.itemChargeCount(itemCharges.itemId), 0);

      // Simulate purchase by applying the changes manually
      // (mimicking what PurchaseShopItemAction does)
      var newState = state.addCurrency(Currency.gp, -gpCost);

      // Add item to inventory if not present
      if (newState.inventory.countOfItem(glovesItem) == 0) {
        newState = newState.copyWith(
          inventory: newState.inventory.adding(ItemStack(glovesItem, count: 1)),
        );
      }

      // Add charges
      final newCharges = Map<MelvorId, int>.from(newState.itemCharges);
      newCharges[itemCharges.itemId] =
          (newCharges[itemCharges.itemId] ?? 0) + itemCharges.quantity;
      newState = newState.copyWith(itemCharges: newCharges);

      // Verify: should have 1 gloves and the charges
      expect(newState.inventory.countOfItem(glovesItem), 1);
      expect(
        newState.itemChargeCount(itemCharges.itemId),
        itemCharges.quantity,
      );
    });

    test('purchasing gloves again adds charges but not more items', () {
      final glovesPurchase = testRegistries.shop.all.firstWhere(
        (p) => p.contains.itemCharges != null,
        orElse: () => throw StateError('No itemCharges purchase found'),
      );

      final itemCharges = glovesPurchase.contains.itemCharges!;
      final glovesItem = testRegistries.items.byId(itemCharges.itemId);

      final costs = glovesPurchase.cost.currencyCosts(bankSlotsPurchased: 0);
      final gpCost = costs.firstWhere((c) => c.$1 == Currency.gp).$2;

      // Start with state already having gloves and some charges
      var state = GlobalState.test(testRegistries, gp: gpCost * 2);

      // First purchase - adds item and charges
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(glovesItem, count: 1)),
        itemCharges: {itemCharges.itemId: itemCharges.quantity},
      );

      expect(state.inventory.countOfItem(glovesItem), 1);
      expect(state.itemChargeCount(itemCharges.itemId), itemCharges.quantity);

      // Second purchase - should only add charges, not items
      var newState = state.addCurrency(Currency.gp, -gpCost);

      // Check if item already exists (it does)
      if (newState.inventory.countOfItem(glovesItem) == 0) {
        newState = newState.copyWith(
          inventory: newState.inventory.adding(ItemStack(glovesItem, count: 1)),
        );
      }

      // Add more charges
      final newCharges = Map<MelvorId, int>.from(newState.itemCharges);
      newCharges[itemCharges.itemId] =
          (newCharges[itemCharges.itemId] ?? 0) + itemCharges.quantity;
      newState = newState.copyWith(itemCharges: newCharges);

      // Verify: should still have only 1 gloves but double the charges
      expect(newState.inventory.countOfItem(glovesItem), 1);
      expect(
        newState.itemChargeCount(itemCharges.itemId),
        itemCharges.quantity * 2,
      );
    });

    test('selling gloves then buying again gives gloves back', () {
      final glovesPurchase = testRegistries.shop.all.firstWhere(
        (p) => p.contains.itemCharges != null,
        orElse: () => throw StateError('No itemCharges purchase found'),
      );

      final itemCharges = glovesPurchase.contains.itemCharges!;
      final glovesItem = testRegistries.items.byId(itemCharges.itemId);

      final costs = glovesPurchase.cost.currencyCosts(bankSlotsPurchased: 0);
      final gpCost = costs.firstWhere((c) => c.$1 == Currency.gp).$2;

      // Start with gloves and charges
      var state = GlobalState.test(
        testRegistries,
        gp: gpCost,
        itemCharges: {itemCharges.itemId: itemCharges.quantity},
      );
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(glovesItem, count: 1)),
      );

      expect(state.inventory.countOfItem(glovesItem), 1);
      expect(state.itemChargeCount(itemCharges.itemId), itemCharges.quantity);

      // Sell the gloves
      state = state.sellItem(ItemStack(glovesItem, count: 1));
      expect(state.inventory.countOfItem(glovesItem), 0);
      // Charges remain even after selling
      expect(state.itemChargeCount(itemCharges.itemId), itemCharges.quantity);

      // Buy again
      var newState = state.addCurrency(Currency.gp, -gpCost);

      // Add item to inventory if not present (it's not)
      if (newState.inventory.countOfItem(glovesItem) == 0) {
        newState = newState.copyWith(
          inventory: newState.inventory.adding(ItemStack(glovesItem, count: 1)),
        );
      }

      // Add more charges
      final newCharges = Map<MelvorId, int>.from(newState.itemCharges);
      newCharges[itemCharges.itemId] =
          (newCharges[itemCharges.itemId] ?? 0) + itemCharges.quantity;
      newState = newState.copyWith(itemCharges: newCharges);

      // Verify: should have gloves again with additional charges
      expect(newState.inventory.countOfItem(glovesItem), 1);
      expect(
        newState.itemChargeCount(itemCharges.itemId),
        itemCharges.quantity * 2,
      );
    });
  });

  group('ShopRegistry cooking equipment chains', () {
    setUpAll(() async {
      await loadTestRegistries();
    });

    test('cookingFireChain returns ordered list of fire upgrades', () {
      final chain = testRegistries.shop.cookingFireChain;
      expect(chain, isNotEmpty);
      // Verify it's a list of MelvorIds
      for (final id in chain) {
        expect(id, isA<MelvorId>());
      }
    });

    test('cookingFurnaceChain returns ordered list of furnace upgrades', () {
      final chain = testRegistries.shop.cookingFurnaceChain;
      expect(chain, isNotEmpty);
      for (final id in chain) {
        expect(id, isA<MelvorId>());
      }
    });

    test('cookingPotChain returns ordered list of pot upgrades', () {
      final chain = testRegistries.shop.cookingPotChain;
      expect(chain, isNotEmpty);
      for (final id in chain) {
        expect(id, isA<MelvorId>());
      }
    });

    test('cookingFireLevel returns 0 with no purchases', () {
      final level = testRegistries.shop.cookingFireLevel({});
      expect(level, 0);
    });

    test('cookingFireLevel counts owned upgrades', () {
      final chain = testRegistries.shop.cookingFireChain;
      if (chain.isEmpty) return; // Skip if no fire upgrades defined

      // With first upgrade purchased
      var level = testRegistries.shop.cookingFireLevel({chain.first: 1});
      expect(level, 1);

      // With first two upgrades purchased
      if (chain.length >= 2) {
        level = testRegistries.shop.cookingFireLevel({
          chain[0]: 1,
          chain[1]: 1,
        });
        expect(level, 2);
      }
    });

    test('cookingFurnaceLevel counts owned upgrades', () {
      final chain = testRegistries.shop.cookingFurnaceChain;
      if (chain.isEmpty) return;

      var level = testRegistries.shop.cookingFurnaceLevel({chain.first: 1});
      expect(level, 1);

      if (chain.length >= 2) {
        level = testRegistries.shop.cookingFurnaceLevel({
          chain[0]: 1,
          chain[1]: 1,
        });
        expect(level, 2);
      }
    });

    test('cookingPotLevel counts owned upgrades', () {
      final chain = testRegistries.shop.cookingPotChain;
      if (chain.isEmpty) return;

      var level = testRegistries.shop.cookingPotLevel({chain.first: 1});
      expect(level, 1);

      if (chain.length >= 2) {
        level = testRegistries.shop.cookingPotLevel({chain[0]: 1, chain[1]: 1});
        expect(level, 2);
      }
    });

    test('highestCookingFireId returns null with no purchases', () {
      final highest = testRegistries.shop.highestCookingFireId({});
      expect(highest, isNull);
    });

    test('highestCookingFireId returns highest owned upgrade', () {
      final chain = testRegistries.shop.cookingFireChain;
      if (chain.isEmpty) return;

      // With first upgrade only
      var highest = testRegistries.shop.highestCookingFireId({chain.first: 1});
      expect(highest, chain.first);

      // With first two upgrades
      if (chain.length >= 2) {
        highest = testRegistries.shop.highestCookingFireId({
          chain[0]: 1,
          chain[1]: 1,
        });
        expect(highest, chain[1]);
      }
    });

    test('highestCookingFurnaceId returns highest owned upgrade', () {
      final chain = testRegistries.shop.cookingFurnaceChain;
      if (chain.isEmpty) return;

      var highest = testRegistries.shop.highestCookingFurnaceId({
        chain.first: 1,
      });
      expect(highest, chain.first);

      if (chain.length >= 2) {
        highest = testRegistries.shop.highestCookingFurnaceId({
          chain[0]: 1,
          chain[1]: 1,
        });
        expect(highest, chain[1]);
      }
    });

    test('highestCookingPotId returns highest owned upgrade', () {
      final chain = testRegistries.shop.cookingPotChain;
      if (chain.isEmpty) return;

      var highest = testRegistries.shop.highestCookingPotId({chain.first: 1});
      expect(highest, chain.first);

      if (chain.length >= 2) {
        highest = testRegistries.shop.highestCookingPotId({
          chain[0]: 1,
          chain[1]: 1,
        });
        expect(highest, chain[1]);
      }
    });

    test('level method counts non-contiguous purchases', () {
      final chain = testRegistries.shop.cookingFireChain;
      if (chain.length < 3) return;

      // Only own the second item in the chain (skipping first)
      // Level is the count of owned items, regardless of which ones
      final level = testRegistries.shop.cookingFireLevel({chain[1]: 1});
      expect(level, 1);

      // highestCookingFireId uses level as an index, assuming purchases
      // are made in order. With level=1, it returns chain[0].
      // This tests the current behavior (which assumes sequential purchase).
      final highest = testRegistries.shop.highestCookingFireId({chain[1]: 1});
      expect(highest, chain[0]);
    });
  });

  group('GlobalState itemCharges', () {
    setUpAll(() async {
      await loadTestRegistries();
    });

    test('itemChargeCount returns 0 for items with no charges', () {
      final state = GlobalState.test(testRegistries);
      expect(
        state.itemChargeCount(const MelvorId('melvorF:Thieving_Gloves')),
        0,
      );
    });

    test('itemChargeCount returns correct value for items with charges', () {
      final state = GlobalState.test(
        testRegistries,
        itemCharges: {const MelvorId('melvorF:Thieving_Gloves'): 500},
      );
      expect(
        state.itemChargeCount(const MelvorId('melvorF:Thieving_Gloves')),
        500,
      );
    });

    test('itemCharges serialization round-trip', () {
      final original = GlobalState.test(
        testRegistries,
        itemCharges: {
          const MelvorId('melvorF:Thieving_Gloves'): 500,
          const MelvorId('melvorD:Some_Other_Item'): 100,
        },
      );
      final json = original.toJson();
      final loaded = GlobalState.fromJson(testRegistries, json);

      expect(
        loaded.itemChargeCount(const MelvorId('melvorF:Thieving_Gloves')),
        500,
      );
      expect(
        loaded.itemChargeCount(const MelvorId('melvorD:Some_Other_Item')),
        100,
      );
    });
  });
}
