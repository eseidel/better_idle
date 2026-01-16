import 'package:logic/src/action_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/summoning_state.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:logic/src/types/modifier_names.dart';

/// Resolves modifier values on-demand with full context.
///
/// Created fresh for each query context - holds references to sources but
/// resolves values lazily when accessed via typed methods.
///
/// Usage:
/// ```dart
/// final provider = state.createModifierProvider();
/// final bonus = provider.randomProductChance(
///   skillId: woodcuttingId,
///   itemId: birdNestId,
/// );
/// ```
class ModifierProvider with ModifierAccessors {
  ModifierProvider({
    required this.registries,
    required this.equipment,
    required this.selectedPotions,
    required this.potionChargesUsed,
    required this.inventory,
    required this.summoning,
    required this.shopPurchases,
    required this.actionStateGetter,
    required this.activeSynergy,
    this.combatTypeSkills,
    this.currentActionId,
  });

  final Registries registries;
  final Equipment equipment;
  final Map<MelvorId, MelvorId> selectedPotions;
  final Map<MelvorId, int> potionChargesUsed;
  final Inventory inventory;
  final SummoningState summoning;
  final ShopState shopPurchases;
  final ActionState Function(ActionId) actionStateGetter;
  final SummoningSynergy? activeSynergy;

  /// For combat: the set of combat skills being used (attack, strength, etc.)
  /// Used to filter summoning familiar relevance.
  final Set<Skill>? combatTypeSkills;

  /// The current action being performed, used for mastery bonus lookups.
  /// This is separate from the actionId scope parameter because mastery
  /// lookups need the full ActionId, not just the local MelvorId.
  final ActionId? currentActionId;

  /// Internal method to get a modifier value by name and scope.
  /// Walks all modifier sources and sums matching entries.
  /// Implements the abstract method from [ModifierAccessors].
  @override
  num getModifier(
    String name, {
    MelvorId? skillId,
    MelvorId? actionId,
    MelvorId? itemId,
    MelvorId? categoryId,
  }) {
    num total = 0;

    // --- Shop modifiers ---
    for (final entry in shopPurchases.purchaseCounts.entries) {
      if (entry.value <= 0) continue;
      final purchase = registries.shop.byId(entry.key);
      if (purchase == null) continue;

      for (final mod in purchase.contains.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (_scopeMatches(
            modEntry.scope,
            skillId,
            actionId,
            itemId,
            categoryId,
          )) {
            total += modEntry.value;
          }
        }
      }
    }

    // --- Mastery modifiers ---
    // Uses currentActionId (the action being performed) for mastery lookup,
    // not the actionId scope parameter (which is for filtering).
    if (skillId != null && currentActionId != null) {
      final masteryLevel = actionStateGetter(currentActionId!).masteryLevel;
      final skillBonuses = registries.masteryBonuses.forSkill(skillId);
      if (skillBonuses != null) {
        for (final bonus in skillBonuses.bonuses) {
          final count = bonus.countAtLevel(masteryLevel);
          if (count == 0) continue;

          for (final mod in bonus.modifiers.modifiers) {
            if (mod.name != name) continue;
            for (final entry in mod.entries) {
              if (_scopeMatchesMastery(
                entry.scope,
                skillId,
                actionId,
                itemId,
                categoryId,
                autoScopeToAction: bonus.autoScopeToAction,
              )) {
                total += entry.value * count;
              }
            }
          }
        }
      }
    }

    // --- Equipment modifiers ---
    final skill = skillId != null ? Skill.fromId(skillId) : null;
    for (final entry in equipment.gearSlots.entries) {
      final slot = entry.key;
      final item = entry.value;

      // For summoning tablets, only include if familiar is relevant
      if (slot.isSummonSlot && item.isSummonTablet) {
        final isRelevant = combatTypeSkills != null
            ? registries.actions.isFamiliarRelevantToCombat(
                item.id,
                combatTypeSkills!,
              )
            : skill != null &&
                  registries.actions.isFamiliarRelevantToSkill(item.id, skill);
        if (!isRelevant) continue;
      }

      for (final mod in item.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (_scopeMatches(
            modEntry.scope,
            skillId,
            actionId,
            itemId,
            categoryId,
          )) {
            total += modEntry.value;
          }
        }
      }

      // Equipment stats (attackSpeed, meleeStrengthBonus, etc.)
      // These are converted to modifier names for uniform access.
      final statValue = item.equipmentStats.getAsModifier(name);
      if (statValue != null) {
        total += statValue;
      }
    }

    // --- Synergy modifiers ---
    if (activeSynergy != null) {
      for (final mod in activeSynergy!.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (_scopeMatches(
            modEntry.scope,
            skillId,
            actionId,
            itemId,
            categoryId,
          )) {
            total += modEntry.value;
          }
        }
      }
    }

    // --- Potion modifiers ---
    if (skillId != null) {
      final potionId = selectedPotions[skillId];
      if (potionId != null) {
        final inventoryCount = inventory.countById(potionId);
        final chargesUsed = potionChargesUsed[skillId] ?? 0;
        if (inventoryCount > 0 || chargesUsed > 0) {
          final potion = registries.items.byId(potionId);
          for (final mod in potion.modifiers.modifiers) {
            if (mod.name != name) continue;
            for (final modEntry in mod.entries) {
              if (_scopeMatches(
                modEntry.scope,
                skillId,
                actionId,
                itemId,
                categoryId,
              )) {
                total += modEntry.value;
              }
            }
          }
        }
      }
    }

    return total;
  }

  /// Check if a modifier scope matches the query context.
  bool _scopeMatches(
    ModifierScope? scope,
    MelvorId? skillId,
    MelvorId? actionId,
    MelvorId? itemId,
    MelvorId? categoryId,
  ) {
    if (scope == null) return true; // Global modifier

    // Each scope field acts as a filter - if specified, it must match
    if (scope.skillId != null && scope.skillId != skillId) return false;
    if (scope.actionId != null && scope.actionId != actionId) return false;
    if (scope.itemId != null && scope.itemId != itemId) return false;
    if (scope.categoryId != null && scope.categoryId != categoryId) {
      return false;
    }

    return true;
  }

  /// Check scope matches for mastery bonuses, which have special template
  /// behavior.
  bool _scopeMatchesMastery(
    ModifierScope? scope,
    MelvorId? skillId,
    MelvorId? actionId,
    MelvorId? itemId,
    MelvorId? categoryId, {
    required bool autoScopeToAction,
  }) {
    if (scope == null) return true;
    if (!autoScopeToAction) return true; // Global modifier, no filtering

    // For autoScopeToAction = true, the actionId in scope is a template
    // placeholder. We only check skillId and categoryId.
    if (scope.skillId != null && scope.skillId != skillId) return false;
    if (scope.categoryId != null && scope.categoryId != categoryId) {
      return false;
    }

    // itemId scope still applies (e.g., for item-specific bonuses)
    if (scope.itemId != null && scope.itemId != itemId) return false;

    return true;
  }
}
