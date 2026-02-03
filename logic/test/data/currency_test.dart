import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('Currency', () {
    test('gp has correct id and abbreviation', () {
      expect(Currency.gp.id, const MelvorId('melvorD:GP'));
      expect(Currency.gp.abbreviation, 'GP');
    });

    test('slayerCoins has correct id and abbreviation', () {
      expect(Currency.slayerCoins.id, const MelvorId('melvorD:SlayerCoins'));
      expect(Currency.slayerCoins.abbreviation, 'SC');
    });

    test('raidCoins has correct id and abbreviation', () {
      expect(Currency.raidCoins.id, const MelvorId('melvorD:RaidCoins'));
      expect(Currency.raidCoins.abbreviation, 'RC');
    });

    test('isGpId returns true for GP id', () {
      expect(Currency.isGpId(const MelvorId('melvorD:GP')), isTrue);
    });

    test('isGpId returns true for alternate GP id', () {
      expect(Currency.isGpId(const MelvorId('melvorF:GP')), isTrue);
    });

    test('isGpId returns false for non-GP id', () {
      expect(Currency.isGpId(const MelvorId('melvorD:SlayerCoins')), isFalse);
    });

    test('fromIdString returns correct currency', () {
      expect(Currency.fromIdString('melvorD:GP'), Currency.gp);
      expect(
        Currency.fromIdString('melvorD:SlayerCoins'),
        Currency.slayerCoins,
      );
      expect(Currency.fromIdString('melvorD:RaidCoins'), Currency.raidCoins);
    });

    test('fromIdString throws for unknown currency', () {
      expect(
        () => Currency.fromIdString('unknown:Currency'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromId returns correct currency', () {
      expect(Currency.fromId(const MelvorId('melvorD:GP')), Currency.gp);
      expect(
        Currency.fromId(const MelvorId('melvorD:SlayerCoins')),
        Currency.slayerCoins,
      );
    });

    test('fromId throws for unknown currency', () {
      expect(
        () => Currency.fromId(const MelvorId('unknown:Currency')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CurrencyStack', () {
    test('has correct properties', () {
      const stack = CurrencyStack(Currency.gp, 1000);
      expect(stack.currency, Currency.gp);
      expect(stack.amount, 1000);
    });

    test('toString returns readable string', () {
      const stack = CurrencyStack(Currency.gp, 1000);
      expect(stack.toString(), contains('gp'));
      expect(stack.toString(), contains('1000'));
    });

    test('equality works correctly', () {
      const stack1 = CurrencyStack(Currency.gp, 1000);
      const stack2 = CurrencyStack(Currency.gp, 1000);
      const stack3 = CurrencyStack(Currency.gp, 2000);
      expect(stack1, equals(stack2));
      expect(stack1, isNot(equals(stack3)));
    });
  });

  group('CurrencyCost', () {
    test('fromJson parses fixed cost', () {
      final json = {'currency': 'melvorD:GP', 'type': 'Fixed', 'cost': 1000};
      final cost = CurrencyCost.fromJson(json);
      expect(cost.currency, Currency.gp);
      expect(cost.type, CostType.fixed);
      expect(cost.fixedCost, 1000);
    });

    test('fromJson parses bank slot cost', () {
      final json = {'currency': 'melvorD:GP', 'type': 'BankSlot'};
      final cost = CurrencyCost.fromJson(json);
      expect(cost.currency, Currency.gp);
      expect(cost.type, CostType.bankSlot);
      expect(cost.fixedCost, isNull);
    });
  });

  group('CurrencyCosts', () {
    test('fromJson parses empty list', () {
      final costs = CurrencyCosts.fromJson([]);
      expect(costs.isEmpty, isTrue);
    });

    test('fromJson parses null', () {
      final costs = CurrencyCosts.fromJson(null);
      expect(costs.isEmpty, isTrue);
    });

    test('fromJson parses cost list', () {
      final json = [
        {'id': 'melvorD:GP', 'quantity': 1000},
        {'id': 'melvorD:SlayerCoins', 'quantity': 50},
      ];
      final costs = CurrencyCosts.fromJson(json);
      expect(costs.isNotEmpty, isTrue);
      expect(costs.gpCost, 1000);
      expect(costs.costFor(Currency.slayerCoins), 50);
    });

    test('gpCost returns 0 when no GP cost', () {
      final json = [
        {'id': 'melvorD:SlayerCoins', 'quantity': 50},
      ];
      final costs = CurrencyCosts.fromJson(json);
      expect(costs.gpCost, 0);
    });

    test('costFor returns 0 when currency not present', () {
      const json = [
        {'id': 'melvorD:GP', 'quantity': 1000},
      ];
      final costs = CurrencyCosts.fromJson(json);
      expect(costs.costFor(Currency.slayerCoins), 0);
    });
  });

  group('parseCurrencyStacks', () {
    test('returns empty list for null', () {
      expect(parseCurrencyStacks(null), isEmpty);
    });

    test('returns empty list for empty list', () {
      expect(parseCurrencyStacks([]), isEmpty);
    });

    test('parses currency stacks', () {
      final json = [
        {'id': 'melvorD:GP', 'quantity': 500},
        {'id': 'melvorD:RaidCoins', 'quantity': 10},
      ];
      final stacks = parseCurrencyStacks(json);
      expect(stacks, hasLength(2));
      expect(stacks[0].currency, Currency.gp);
      expect(stacks[0].amount, 500);
      expect(stacks[1].currency, Currency.raidCoins);
      expect(stacks[1].amount, 10);
    });
  });
}
