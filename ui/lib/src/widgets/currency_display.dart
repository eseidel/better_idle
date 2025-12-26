import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

/// Displays a single currency amount with icon.
class CurrencyDisplay extends StatelessWidget {
  const CurrencyDisplay({
    required this.currency,
    required this.amount,
    super.key,
    this.canAfford,
    this.size = 16,
  });

  /// Creates a CurrencyDisplay from a CurrencyStack.
  factory CurrencyDisplay.fromStack(
    CurrencyStack stack, {
    Key? key,
    bool? canAfford,
    double size = 16,
  }) {
    return CurrencyDisplay(
      key: key,
      currency: stack.currency,
      amount: stack.amount,
      canAfford: canAfford,
      size: size,
    );
  }

  final Currency currency;
  final int amount;

  /// If provided, colors the text green (can afford) or red (cannot afford).
  final bool? canAfford;

  /// Icon size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final textStyle = canAfford != null
        ? TextStyle(
            color: canAfford! ? Style.successColor : Style.errorColor,
            fontWeight: FontWeight.bold,
          )
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachedImage(assetPath: currency.assetPath, size: size),
        const SizedBox(width: 4),
        Text(approximateCreditString(amount), style: textStyle),
      ],
    );
  }
}

/// Displays a list of currency costs/rewards.
class CurrencyListDisplay extends StatelessWidget {
  const CurrencyListDisplay({
    required this.stacks,
    super.key,
    this.canAfford,
    this.size = 16,
    this.spacing = 8,
    this.emptyText,
  });

  /// Creates from a CurrencyCosts object.
  factory CurrencyListDisplay.fromCosts(
    CurrencyCosts costs, {
    Key? key,
    Map<Currency, bool>? canAfford,
    double size = 16,
    double spacing = 8,
    String? emptyText,
  }) {
    return CurrencyListDisplay(
      key: key,
      stacks: costs.costs,
      canAfford: canAfford,
      size: size,
      spacing: spacing,
      emptyText: emptyText,
    );
  }

  final List<CurrencyStack> stacks;

  /// Map of currency to whether the player can afford that cost.
  final Map<Currency, bool>? canAfford;

  /// Icon size.
  final double size;

  /// Spacing between items.
  final double spacing;

  /// Text to show when there are no costs (e.g., "Free" or "-").
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (stacks.isEmpty) {
      if (emptyText != null) {
        return Text(emptyText!);
      }
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: spacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: stacks.map((stack) {
        return CurrencyDisplay.fromStack(
          stack,
          canAfford: canAfford?[stack.currency],
          size: size,
        );
      }).toList(),
    );
  }
}
