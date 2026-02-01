import 'package:logic/src/action_state.dart';
import 'package:logic/src/agility_state.dart';
import 'package:logic/src/astrology_state.dart';
import 'package:logic/src/data/action_id.dart';
import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/state.dart';
import 'package:logic/src/summoning_state.dart';
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:logic/src/types/equipment.dart';
import 'package:logic/src/types/inventory.dart';
import 'package:logic/src/types/modifier.dart';
import 'package:logic/src/types/modifier_names.dart';

/// Context for scope matching within a single getModifier call.
///
/// Holds the query parameters and provides scope matching methods.
class _ScopeContext {
  _ScopeContext({this.skillId, this.actionId, this.itemId, this.categoryId});

  final MelvorId? skillId;
  final MelvorId? actionId;
  final MelvorId? itemId;
  final MelvorId? categoryId;

  /// Check if a modifier scope matches the query context.
  bool matches(ModifierScope? scope) {
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
  bool matchesMastery(ModifierScope? scope, {required bool autoScopeToAction}) {
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

/// Context for evaluating conditional modifier conditions.
///
/// This holds the combat/game state needed to evaluate whether a conditional
/// modifier's condition is met. Fields are optional - if a condition requires
/// state that isn't provided, the condition evaluates to false.
class ConditionContext {
  const ConditionContext({
    this.playerAttackType,
    this.enemyAttackType,
    this.playerDamageType,
    this.playerHpPercent,
    this.enemyHpPercent,
    this.itemCharges = const {},
    this.bankItemCounts = const {},
    this.activePotionRecipes = const {},
    this.activeEffectGroups = const {},
    this.isFightingSlayerTask = false,
  });

  /// Empty context - all conditions will fail except those that don't need
  /// any state.
  static const empty = ConditionContext();

  /// The player's current attack type.
  final CombatType? playerAttackType;

  /// The enemy's current attack type.
  final CombatType? enemyAttackType;

  /// The player's current damage type (e.g., "melvorD:Normal").
  final MelvorId? playerDamageType;

  /// The player's current HP as a percentage (0-100).
  final int? playerHpPercent;

  /// The enemy's current HP as a percentage (0-100).
  final int? enemyHpPercent;

  /// Map of item ID to current charge count for equipped items.
  final Map<MelvorId, int> itemCharges;

  /// Map of item ID to count in the bank.
  final Map<MelvorId, int> bankItemCounts;

  /// Set of active potion recipe IDs.
  final Set<MelvorId> activePotionRecipes;

  /// Set of active combat effect group IDs on player/enemy.
  /// Keys are like "Player:melvorD:PoisonDOT" or "Enemy:melvorD:BurnDOT".
  final Set<String> activeEffectGroups;

  /// Whether the player is currently fighting their slayer task monster.
  final bool isFightingSlayerTask;

  /// Evaluates whether a condition is met given this context.
  bool evaluate(ModifierCondition condition) {
    return switch (condition) {
      final DamageTypeCondition c => _evaluateDamageType(c),
      final CombatTypeCondition c => _evaluateCombatType(c),
      final ItemChargeCondition c => _evaluateItemCharge(c),
      final BankItemCondition c => _evaluateBankItem(c),
      final HitpointsCondition c => _evaluateHitpoints(c),
      final CombatEffectGroupCondition c => _evaluateEffectGroup(c),
      FightingSlayerTaskCondition() => isFightingSlayerTask,
      final PotionUsedCondition c => activePotionRecipes.contains(c.recipeId),
      final EveryCondition c => c.conditions.every(evaluate),
      final SomeCondition c => c.conditions.any(evaluate),
    };
  }

  bool _evaluateDamageType(DamageTypeCondition c) {
    if (c.character == ConditionCharacter.player) {
      return playerDamageType == c.damageType;
    }
    // Enemy damage type not yet tracked
    return false;
  }

  bool _evaluateCombatType(CombatTypeCondition c) {
    final thisType = c.character == ConditionCharacter.player
        ? playerAttackType
        : enemyAttackType;
    final targetType = c.character == ConditionCharacter.player
        ? enemyAttackType
        : playerAttackType;

    if (thisType == null || targetType == null) return false;

    // null in condition means 'any' - matches all types
    final thisMatches =
        c.thisAttackType == null || c.thisAttackType == thisType;
    final targetMatches =
        c.targetAttackType == null || c.targetAttackType == targetType;

    return thisMatches && targetMatches;
  }

  bool _evaluateItemCharge(ItemChargeCondition c) {
    final charges = itemCharges[c.itemId] ?? 0;
    return c.operator.evaluate(charges, c.value);
  }

  bool _evaluateBankItem(BankItemCondition c) {
    final count = bankItemCounts[c.itemId] ?? 0;
    return c.operator.evaluate(count, c.value);
  }

  bool _evaluateHitpoints(HitpointsCondition c) {
    final hp = c.character == ConditionCharacter.player
        ? playerHpPercent
        : enemyHpPercent;
    if (hp == null) return false;
    return c.operator.evaluate(hp, c.value);
  }

  bool _evaluateEffectGroup(CombatEffectGroupCondition c) {
    final key = '${c.character.name}:${c.groupId.toJson()}';
    return activeEffectGroups.contains(key);
  }
}

/// Resolves modifier values on-demand with full context.
///
/// Created fresh for each query context - holds references to sources but
/// resolves values lazily when accessed via typed methods.
///
/// Usage:
/// ```dart
/// final provider = state.createActionModifierProvider(action);
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
    required this.skillStateGetter,
    required this.agility,
    required this.astrology,
    this.combatTypeSkills,
    this.currentActionId,
    this.conditionContext = ConditionContext.empty,
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

  /// Agility course state - obstacles built provide passive modifiers.
  final AgilityState agility;

  /// Astrology state - purchased constellation modifiers.
  final AstrologyState astrology;

  /// Returns the SkillState for a given skill.
  /// Used to look up mastery pool XP for mastery pool checkpoint bonuses.
  final SkillState Function(Skill) skillStateGetter;

  /// For combat: the set of combat skills being used (attack, strength, etc.)
  /// Used to filter summoning familiar relevance.
  final Set<Skill>? combatTypeSkills;

  /// The current action being performed, used for mastery bonus lookups.
  /// This is separate from the actionId scope parameter because mastery
  /// lookups need the full ActionId, not just the local MelvorId.
  final ActionId? currentActionId;

  /// Context for evaluating conditional modifiers (combat state, HP, etc.).
  /// Defaults to empty context where all conditions evaluate to false.
  final ConditionContext conditionContext;

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
    final scope = _ScopeContext(
      skillId: skillId,
      actionId: actionId,
      itemId: itemId,
      categoryId: categoryId,
    );
    num total = 0;

    // --- Shop modifiers ---
    for (final entry in shopPurchases.purchaseCounts.entries) {
      if (entry.value <= 0) continue;
      final purchase = registries.shop.byId(entry.key);
      if (purchase == null) continue;

      for (final mod in purchase.contains.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (scope.matches(modEntry.scope)) {
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
              if (scope.matchesMastery(
                entry.scope,
                autoScopeToAction: bonus.autoScopeToAction,
              )) {
                total += entry.value * count;
              }
            }
          }
        }
      }
    }

    // --- Mastery pool checkpoint bonuses ---
    // These are skill-wide bonuses that activate when the mastery pool
    // reaches certain percentage thresholds (10%, 25%, 50%, 95%).
    if (skillId != null) {
      final skill = Skill.fromId(skillId);
      final poolBonuses = registries.masteryPoolBonuses.forSkill(skillId);
      if (poolBonuses != null) {
        final skillState = skillStateGetter(skill);
        final poolPercent = skillState.masteryPoolPercent(registries, skill);

        for (final bonus in poolBonuses.bonuses) {
          if (!bonus.isActiveAt(poolPercent)) continue;

          for (final mod in bonus.modifiers.modifiers) {
            if (mod.name != name) continue;
            for (final entry in mod.entries) {
              if (scope.matches(entry.scope)) {
                total += entry.value;
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
            ? registries.summoning.isFamiliarRelevantToCombat(
                item.id,
                combatTypeSkills!,
              )
            : skill != null &&
                  registries.summoning.isFamiliarRelevantToSkill(
                    item.id,
                    skill,
                  );
        if (!isRelevant) continue;
      }

      for (final mod in item.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (scope.matches(modEntry.scope)) {
            total += modEntry.value;
          }
        }
      }

      // Equipment stats (attackSpeed, meleeStrengthBonus, etc.)
      // These are converted to modifier names for uniform access.
      // Skip for slots that don't provide equipment stats (e.g., Passive slot).
      final slotDef = registries.equipmentSlots[slot];
      final providesStats = slotDef?.providesEquipStats ?? true;
      if (providesStats) {
        final statModifier = EquipmentStatModifier.tryFromName(name);
        if (statModifier != null) {
          final statValue = item.equipmentStats.getAsModifier(statModifier);
          if (statValue != null) {
            total += statValue;
          }
        }
      }

      // Conditional modifiers - only apply if condition is met
      for (final condMod in item.conditionalModifiers) {
        if (!conditionContext.evaluate(condMod.condition)) continue;

        for (final mod in condMod.modifiers.modifiers) {
          if (mod.name != name) continue;
          for (final modEntry in mod.entries) {
            if (scope.matches(modEntry.scope)) {
              total += modEntry.value;
            }
          }
        }
      }
    }

    // --- Synergy modifiers ---
    if (activeSynergy != null) {
      for (final mod in activeSynergy!.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (scope.matches(modEntry.scope)) {
            total += modEntry.value;
          }
        }
      }

      // Synergy conditional modifiers
      for (final condMod in activeSynergy!.conditionalModifiers) {
        if (!conditionContext.evaluate(condMod.condition)) continue;

        for (final mod in condMod.modifiers.modifiers) {
          if (mod.name != name) continue;
          for (final modEntry in mod.entries) {
            if (scope.matches(modEntry.scope)) {
              total += modEntry.value;
            }
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
              if (scope.matches(modEntry.scope)) {
                total += modEntry.value;
              }
            }
          }
        }
      }
    }

    // --- Agility obstacle modifiers ---
    // Built obstacles provide passive modifiers while in the course.
    for (final slotState in agility.slots.values) {
      final obstacleId = slotState.obstacleId;
      if (obstacleId == null) continue;

      final obstacle = registries.agility.byId(obstacleId.localId);
      if (obstacle == null) continue;

      for (final mod in obstacle.modifiers.modifiers) {
        if (mod.name != name) continue;
        for (final modEntry in mod.entries) {
          if (scope.matches(modEntry.scope)) {
            total += modEntry.value;
          }
        }
      }
    }

    // --- Astrology modifiers ---
    // Purchased constellation modifiers provide skill-specific bonuses.
    for (final entry in astrology.constellationStates.entries) {
      final constellationId = entry.key;
      final modState = entry.value;

      final constellation = registries.astrology.byId(constellationId);
      if (constellation == null) continue;

      for (final mod in modState.activeModifiers(constellation)) {
        if (mod.name != name) continue;
        for (final entry in mod.entries) {
          if (scope.matches(entry.scope)) {
            total += entry.value;
          }
        }
      }
    }

    return total;
  }
}
