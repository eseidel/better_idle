import 'package:equatable/equatable.dart';
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
