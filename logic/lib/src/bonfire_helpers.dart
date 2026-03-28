import 'package:logic/src/data/actions.dart';
import 'package:logic/src/tick.dart';
import 'package:logic/src/types/modifier_provider.dart';

/// Extension on [ModifierProvider] for computed bonfire properties.
extension BonfireModifiers on ModifierProvider {
  /// Whether bonfires are free (no log cost) based on the freeBonfires
  /// modifier. This comes from potions (e.g., Controlled Heat Potion).
  bool get isBonfireFree =>
      getModifier('freeBonfires', skillId: Skill.firemaking.id) > 0;
}

/// Computes the bonfire duration in ticks, applying the
/// firemakingBonfireInterval modifier.
int bonfireDurationTicks(ModifierProvider modifiers, FiremakingAction action) {
  final intervalMod = modifiers
      .getModifier('firemakingBonfireInterval', skillId: Skill.firemaking.id)
      .toInt();
  final baseTicks = ticksFromDuration(action.bonfireInterval);
  return (baseTicks * (1.0 + intervalMod / 100.0)).round().clamp(
    1,
    baseTicks * 10,
  );
}
