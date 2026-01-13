import 'package:equatable/equatable.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:meta/meta.dart';

/// A currency type in the game.
enum Currency {
  /// Gold Pieces - primary currency
  gp('melvorD:GP', 'GP', 'assets/media/main/coins.png'),

  /// Slayer Coins - earned from slayer tasks
  slayerCoins(
    'melvorD:SlayerCoins',
    'SC',
    'assets/media/main/slayer_coins.png',
  ),

  /// Raid Coins - earned from Golbin Raid
  raidCoins('melvorD:RaidCoins', 'RC', 'assets/media/main/raid_coins.png');

  const Currency(this.id, this.abbreviation, this.assetPath);

  /// The Melvor ID for this currency (e.g., "melvorD:GP")
  final String id;

  /// Short display abbreviation (e.g., "GP", "SC")
  final String abbreviation;

  /// Asset path for the currency icon
  final String assetPath;

  /// Returns true if this currency matches the given [MelvorId].
  bool matches(MelvorId melvorId) => melvorId.fullId == id;

  /// Look up a currency by its Melvor ID.
  /// Throws if not found.
  static Currency fromId(String id) {
    for (final currency in Currency.values) {
      if (currency.id == id) {
        return currency;
      }
    }
    throw ArgumentError('Unknown currency ID: $id');
  }
}

/// A stack of currency with an amount.
@immutable
class CurrencyStack extends Equatable {
  const CurrencyStack(this.currency, this.amount);

  /// The type of currency.
  final Currency currency;

  /// The amount of this currency.
  final int amount;

  @override
  List<Object?> get props => [currency, amount];

  @override
  String toString() => 'CurrencyStack($currency, $amount)';
}

/// The type of cost calculation for a shop purchase.
enum CostType {
  /// Fixed cost defined in JSON.
  fixed,

  /// Dynamic cost based on bank slot formula.
  bankSlot,
}

/// A currency cost for a shop purchase.
@immutable
class CurrencyCost extends Equatable {
  const CurrencyCost({
    required this.currency,
    required this.type,
    this.fixedCost,
  });

  factory CurrencyCost.fromJson(Map<String, dynamic> json) {
    final currencyId = json['currency'] as String;
    final currency = Currency.fromId(currencyId);
    final typeStr = json['type'] as String;
    final type = typeStr == 'BankSlot' ? CostType.bankSlot : CostType.fixed;
    final fixedCost = json['cost'] as int?;
    return CurrencyCost(currency: currency, type: type, fixedCost: fixedCost);
  }

  final Currency currency;
  final CostType type;
  final int? fixedCost;

  @override
  List<Object?> get props => [currency, type, fixedCost];
}

/// A collection of currency costs parsed from Melvor JSON.
///
/// Used for simple fixed currency costs in skills like farming and agility.
@immutable
class CurrencyCosts extends Equatable {
  const CurrencyCosts(this.costs);

  /// Parses a Melvor currencyCosts array.
  ///
  /// The JSON format is: `[{"id": "melvorD:GP", "quantity": 80000}, ...]`
  factory CurrencyCosts.fromJson(List<dynamic>? json) {
    if (json == null || json.isEmpty) return empty;
    final costs = <CurrencyStack>[];
    for (final cost in json) {
      final costMap = cost as Map<String, dynamic>;
      final currencyId = costMap['id'] as String;
      final currency = Currency.fromId(currencyId);
      final quantity = costMap['quantity'] as int;
      costs.add(CurrencyStack(currency, quantity));
    }
    return CurrencyCosts(costs);
  }

  /// An empty currency costs collection.
  static const empty = CurrencyCosts([]);

  final List<CurrencyStack> costs;

  /// Returns the GP cost, or 0 if not present.
  int get gpCost {
    for (final cost in costs) {
      if (cost.currency == Currency.gp) {
        return cost.amount;
      }
    }
    return 0;
  }

  /// Returns the cost for a specific currency, or 0 if not present.
  int costFor(Currency currency) {
    for (final cost in costs) {
      if (cost.currency == currency) {
        return cost.amount;
      }
    }
    return 0;
  }

  /// Whether there are no costs.
  bool get isEmpty => costs.isEmpty;

  /// Whether there are any costs.
  bool get isNotEmpty => costs.isNotEmpty;

  @override
  List<Object?> get props => [costs];
}

/// Parses a Melvor currency stacks array (used for rewards, etc.).
///
/// The JSON format is: `[{"id": "melvorD:GP", "quantity": 100}, ...]`
List<CurrencyStack> parseCurrencyStacks(List<dynamic>? json) {
  if (json == null || json.isEmpty) return const [];
  final stacks = <CurrencyStack>[];
  for (final item in json) {
    final itemMap = item as Map<String, dynamic>;
    final currencyId = itemMap['id'] as String;
    final currency = Currency.fromId(currencyId);
    final quantity = itemMap['quantity'] as int;
    stacks.add(CurrencyStack(currency, quantity));
  }
  return stacks;
}
