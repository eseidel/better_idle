import 'package:logic/logic.dart';
import 'package:logic/src/types/conditional_modifier.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('ModifierCondition parsing', () {
    test('parses DamageType condition', () {
      final json = {
        'type': 'DamageType',
        'character': 'Player',
        'damageType': 'melvorD:Normal',
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<DamageTypeCondition>());
      final dt = condition as DamageTypeCondition;
      expect(dt.character, ConditionCharacter.player);
      expect(dt.damageType, const MelvorId('melvorD:Normal'));
    });

    test('parses CombatType condition', () {
      final json = {
        'type': 'CombatType',
        'character': 'Player',
        'thisAttackType': 'melee',
        'targetAttackType': 'ranged',
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<CombatTypeCondition>());
      final ct = condition as CombatTypeCondition;
      expect(ct.character, ConditionCharacter.player);
      expect(ct.thisAttackType, CombatType.melee);
      expect(ct.targetAttackType, CombatType.ranged);
    });

    test('parses ItemCharge condition', () {
      final json = {
        'type': 'ItemCharge',
        'itemID': 'melvorF:Thieving_Gloves',
        'operator': '>',
        'value': 0,
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorF');

      expect(condition, isA<ItemChargeCondition>());
      final ic = condition as ItemChargeCondition;
      expect(ic.itemId, const MelvorId('melvorF:Thieving_Gloves'));
      expect(ic.operator, ComparisonOperator.greaterThan);
      expect(ic.value, 0);
    });

    test('parses BankItem condition', () {
      final json = {
        'type': 'BankItem',
        'itemID': 'melvorD:Charge_Stone_of_Rhaelyx',
        'operator': '>',
        'value': 0,
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<BankItemCondition>());
      final bi = condition as BankItemCondition;
      expect(bi.itemId, const MelvorId('melvorD:Charge_Stone_of_Rhaelyx'));
      expect(bi.operator, ComparisonOperator.greaterThan);
      expect(bi.value, 0);
    });

    test('parses Hitpoints condition', () {
      final json = {
        'type': 'Hitpoints',
        'character': 'Player',
        'operator': '<',
        'value': 50,
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<HitpointsCondition>());
      final hp = condition as HitpointsCondition;
      expect(hp.character, ConditionCharacter.player);
      expect(hp.operator, ComparisonOperator.lessThan);
      expect(hp.value, 50);
    });

    test('parses Every (AND) condition', () {
      final json = {
        'type': 'Every',
        'conditions': [
          {
            'type': 'CombatType',
            'character': 'Player',
            'thisAttackType': 'melee',
            'targetAttackType': 'any',
          },
          {
            'type': 'DamageType',
            'character': 'Player',
            'damageType': 'melvorD:Normal',
          },
        ],
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<EveryCondition>());
      final every = condition as EveryCondition;
      expect(every.conditions.length, 2);
      expect(every.conditions[0], isA<CombatTypeCondition>());
      expect(every.conditions[1], isA<DamageTypeCondition>());
    });

    test('parses Some (OR) condition', () {
      final json = {
        'type': 'Some',
        'conditions': [
          {
            'type': 'CombatEffectGroup',
            'character': 'Player',
            'groupID': 'melvorD:Slow',
          },
          {
            'type': 'CombatEffectGroup',
            'character': 'Player',
            'groupID': 'melvorD:BurnDOT',
          },
        ],
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<SomeCondition>());
      final some = condition as SomeCondition;
      expect(some.conditions.length, 2);
      expect(some.conditions[0], isA<CombatEffectGroupCondition>());
      expect(some.conditions[1], isA<CombatEffectGroupCondition>());
    });

    test('parses FightingSlayerTask condition', () {
      final json = {'type': 'FightingSlayerTask'};

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorD');

      expect(condition, isA<FightingSlayerTaskCondition>());
    });

    test('parses PotionUsed condition', () {
      final json = {
        'type': 'PotionUsed',
        'recipeID': 'melvorF:Bird_Nest_Potion',
      };

      final condition = ModifierCondition.fromJson(json, namespace: 'melvorF');

      expect(condition, isA<PotionUsedCondition>());
      final pu = condition as PotionUsedCondition;
      expect(pu.recipeId, const MelvorId('melvorF:Bird_Nest_Potion'));
    });
  });

  group('ComparisonOperator', () {
    test('lessThan evaluates correctly', () {
      expect(ComparisonOperator.lessThan.evaluate(5, 10), isTrue);
      expect(ComparisonOperator.lessThan.evaluate(10, 10), isFalse);
      expect(ComparisonOperator.lessThan.evaluate(15, 10), isFalse);
    });

    test('greaterThan evaluates correctly', () {
      expect(ComparisonOperator.greaterThan.evaluate(15, 10), isTrue);
      expect(ComparisonOperator.greaterThan.evaluate(10, 10), isFalse);
      expect(ComparisonOperator.greaterThan.evaluate(5, 10), isFalse);
    });

    test('lessThanOrEqual evaluates correctly', () {
      expect(ComparisonOperator.lessThanOrEqual.evaluate(5, 10), isTrue);
      expect(ComparisonOperator.lessThanOrEqual.evaluate(10, 10), isTrue);
      expect(ComparisonOperator.lessThanOrEqual.evaluate(15, 10), isFalse);
    });

    test('greaterThanOrEqual evaluates correctly', () {
      expect(ComparisonOperator.greaterThanOrEqual.evaluate(15, 10), isTrue);
      expect(ComparisonOperator.greaterThanOrEqual.evaluate(10, 10), isTrue);
      expect(ComparisonOperator.greaterThanOrEqual.evaluate(5, 10), isFalse);
    });

    test('equal evaluates correctly', () {
      expect(ComparisonOperator.equal.evaluate(10, 10), isTrue);
      expect(ComparisonOperator.equal.evaluate(5, 10), isFalse);
      expect(ComparisonOperator.equal.evaluate(15, 10), isFalse);
    });
  });

  group('ConditionContext evaluation', () {
    test('DamageType condition evaluates based on player damage type', () {
      const condition = DamageTypeCondition(
        character: ConditionCharacter.player,
        damageType: MelvorId('melvorD:Normal'),
      );

      // Matching damage type
      const contextMatch = ConditionContext(
        playerDamageType: MelvorId('melvorD:Normal'),
      );
      expect(contextMatch.evaluate(condition), isTrue);

      // Non-matching damage type
      const contextNoMatch = ConditionContext(
        playerDamageType: MelvorId('melvorD:Fire'),
      );
      expect(contextNoMatch.evaluate(condition), isFalse);

      // Missing damage type
      expect(ConditionContext.empty.evaluate(condition), isFalse);
    });

    test('CombatType condition evaluates attack type match-ups', () {
      const condition = CombatTypeCondition(
        character: ConditionCharacter.player,
        thisAttackType: CombatType.melee,
        targetAttackType: CombatType.ranged,
      );

      // Exact match
      const contextMatch = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.ranged,
      );
      expect(contextMatch.evaluate(condition), isTrue);

      // Player type mismatch
      const contextWrongPlayer = ConditionContext(
        playerAttackType: CombatType.ranged,
        enemyAttackType: CombatType.ranged,
      );
      expect(contextWrongPlayer.evaluate(condition), isFalse);

      // Enemy type mismatch
      const contextWrongEnemy = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.melee,
      );
      expect(contextWrongEnemy.evaluate(condition), isFalse);
    });

    test('CombatType condition with null (any) matches any type', () {
      const condition = CombatTypeCondition(
        character: ConditionCharacter.player,
        thisAttackType: CombatType.melee,
        // targetAttackType: null means 'any'
      );

      // Player melee vs any enemy type
      const contextVsRanged = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.ranged,
      );
      expect(contextVsRanged.evaluate(condition), isTrue);

      const contextVsMelee = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.melee,
      );
      expect(contextVsMelee.evaluate(condition), isTrue);
    });

    test('ItemCharge condition evaluates equipped item charges', () {
      const itemId = MelvorId('test:ChargedItem');
      const condition = ItemChargeCondition(
        itemId: itemId,
        operator: ComparisonOperator.greaterThan,
        value: 0,
      );

      // Has charges
      final contextWithCharges = ConditionContext(itemCharges: {itemId: 10});
      expect(contextWithCharges.evaluate(condition), isTrue);

      // No charges
      final contextNoCharges = ConditionContext(itemCharges: {itemId: 0});
      expect(contextNoCharges.evaluate(condition), isFalse);

      // Item not tracked (defaults to 0)
      expect(ConditionContext.empty.evaluate(condition), isFalse);
    });

    test('BankItem condition evaluates bank item counts', () {
      const itemId = MelvorId('test:BankItem');
      const condition = BankItemCondition(
        itemId: itemId,
        operator: ComparisonOperator.greaterThan,
        value: 0,
      );

      // Item in bank
      final contextWithItem = ConditionContext(bankItemCounts: {itemId: 5});
      expect(contextWithItem.evaluate(condition), isTrue);

      // Item not in bank
      final contextNoItem = ConditionContext(bankItemCounts: {itemId: 0});
      expect(contextNoItem.evaluate(condition), isFalse);

      // Item not tracked
      expect(ConditionContext.empty.evaluate(condition), isFalse);
    });

    test('Hitpoints condition evaluates player HP percentage', () {
      const condition = HitpointsCondition(
        character: ConditionCharacter.player,
        operator: ComparisonOperator.lessThan,
        value: 50,
      );

      // HP below threshold
      const contextLowHp = ConditionContext(playerHpPercent: 30);
      expect(contextLowHp.evaluate(condition), isTrue);

      // HP at threshold
      const contextAtThreshold = ConditionContext(playerHpPercent: 50);
      expect(contextAtThreshold.evaluate(condition), isFalse);

      // HP above threshold
      const contextHighHp = ConditionContext(playerHpPercent: 80);
      expect(contextHighHp.evaluate(condition), isFalse);
    });

    test('FightingSlayerTask condition evaluates slayer state', () {
      const condition = FightingSlayerTaskCondition();

      const contextSlayer = ConditionContext(isFightingSlayerTask: true);
      expect(contextSlayer.evaluate(condition), isTrue);

      expect(ConditionContext.empty.evaluate(condition), isFalse);
    });

    test('PotionUsed condition evaluates active potions', () {
      const potionId = MelvorId('test:TestPotion');
      const condition = PotionUsedCondition(recipeId: potionId);

      final contextWithPotion = ConditionContext(
        activePotionRecipes: {potionId},
      );
      expect(contextWithPotion.evaluate(condition), isTrue);

      expect(ConditionContext.empty.evaluate(condition), isFalse);
    });

    test('Every (AND) condition requires all conditions to be true', () {
      const everyCondition = EveryCondition(
        conditions: [
          CombatTypeCondition(
            character: ConditionCharacter.player,
            thisAttackType: CombatType.melee,
            // targetAttackType: null means 'any'
          ),
          DamageTypeCondition(
            character: ConditionCharacter.player,
            damageType: MelvorId('melvorD:Normal'),
          ),
        ],
      );

      // Both conditions met
      const contextBoth = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.ranged,
        playerDamageType: MelvorId('melvorD:Normal'),
      );
      expect(contextBoth.evaluate(everyCondition), isTrue);

      // Only one condition met
      const contextOnlyMelee = ConditionContext(
        playerAttackType: CombatType.melee,
        enemyAttackType: CombatType.ranged,
        playerDamageType: MelvorId('melvorD:Fire'),
      );
      expect(contextOnlyMelee.evaluate(everyCondition), isFalse);

      // Neither condition met
      expect(ConditionContext.empty.evaluate(everyCondition), isFalse);
    });

    test('Some (OR) condition requires any condition to be true', () {
      const someCondition = SomeCondition(
        conditions: [
          HitpointsCondition(
            character: ConditionCharacter.player,
            operator: ComparisonOperator.lessThan,
            value: 30,
          ),
          FightingSlayerTaskCondition(),
        ],
      );

      // First condition met
      const contextLowHp = ConditionContext(playerHpPercent: 20);
      expect(contextLowHp.evaluate(someCondition), isTrue);

      // Second condition met
      const contextSlayer = ConditionContext(
        playerHpPercent: 100,
        isFightingSlayerTask: true,
      );
      expect(contextSlayer.evaluate(someCondition), isTrue);

      // Both conditions met
      const contextBoth = ConditionContext(
        playerHpPercent: 20,
        isFightingSlayerTask: true,
      );
      expect(contextBoth.evaluate(someCondition), isTrue);

      // Neither condition met
      const contextNeither = ConditionContext(playerHpPercent: 80);
      expect(contextNeither.evaluate(someCondition), isFalse);
    });
  });

  group('ConditionalModifier parsing', () {
    test('parses conditional modifier with player modifiers', () {
      final json = {
        'condition': {
          'type': 'CombatType',
          'character': 'Player',
          'thisAttackType': 'melee',
          'targetAttackType': 'ranged',
        },
        'modifiers': {
          'flatResistance': [
            {'damageTypeID': 'melvorD:Normal', 'value': 1},
          ],
        },
      };

      final condMod = ConditionalModifier.fromJson(json, namespace: 'melvorD');

      expect(condMod.condition, isA<CombatTypeCondition>());
      expect(condMod.modifiers.modifiers.length, 1);
      expect(condMod.modifiers.modifiers[0].name, 'flatResistance');
    });

    test('parses conditional modifier with enemy modifiers', () {
      final json = {
        'condition': {'type': 'FightingSlayerTask'},
        'enemyModifiers': {'accuracyRating': -10},
        'descriptionLang': 'MODIFIER_DATA_decreasedSlayerTaskMonsterAccuracy',
      };

      final condMod = ConditionalModifier.fromJson(json, namespace: 'melvorD');

      expect(condMod.condition, isA<FightingSlayerTaskCondition>());
      expect(condMod.enemyModifiers, isNotNull);
      expect(condMod.enemyModifiers!.modifiers.length, 1);
      expect(condMod.enemyModifiers!.modifiers[0].name, 'accuracyRating');
      expect(condMod.descriptionLang, isNotNull);
    });
  });

  group('Item conditionalModifiers', () {
    test('items with conditionalModifiers are parsed from real data', () {
      // Use real registries from test helper
      final registries = testRegistries;
      final items = registries.items.all;

      // Find items that have conditionalModifiers
      final itemsWithCondMods = items
          .where((item) => item.conditionalModifiers.isNotEmpty)
          .toList();

      // Verify we found some items with conditional modifiers
      expect(
        itemsWithCondMods,
        isNotEmpty,
        reason: 'Should find items with conditionalModifiers in game data',
      );

      // Verify the first one has valid structure
      final sampleItem = itemsWithCondMods.first;
      expect(sampleItem.conditionalModifiers.first.condition, isNotNull);
    });
  });

  group('ModifierProvider with conditional modifiers', () {
    test('conditional modifier applies when condition is met', () {
      // Create an item with a conditional modifier that gives -10 attack
      // interval when the player uses Normal damage type
      const item = Item(
        id: MelvorId('test:TestNecklace'),
        name: 'Test Necklace',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.amulet],
        conditionalModifiers: [
          ConditionalModifier(
            condition: DamageTypeCondition(
              character: ConditionCharacter.player,
              damageType: MelvorId('melvorD:Normal'),
            ),
            modifiers: ModifierDataSet([
              ModifierData(
                name: 'attackInterval',
                entries: [ModifierEntry(value: -10)],
              ),
            ]),
          ),
        ],
      );

      final registries = Registries.test(items: const [item]);

      // Equip the item
      final (equipment, _) = const Equipment.empty().equipGear(
        item,
        EquipmentSlot.amulet,
      );

      // Create action for context
      final action = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'TestAction'),
        skill: Skill.woodcutting,
        name: 'Test Action',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      // Without condition context, modifier should NOT apply
      final stateNoContext = GlobalState.test(registries, equipment: equipment);
      final modifiersNoContext = stateNoContext.createActionModifierProvider(
        action,
        conditionContext: ConditionContext.empty,
      );
      expect(modifiersNoContext.attackInterval, 0);

      // With matching condition context, modifier SHOULD apply
      final stateWithContext = GlobalState.test(
        registries,
        equipment: equipment,
      );
      final modifiersWithContext = stateWithContext
          .createActionModifierProvider(
            action,
            conditionContext: const ConditionContext(
              playerDamageType: MelvorId('melvorD:Normal'),
            ),
          );
      expect(modifiersWithContext.attackInterval, -10);
    });

    test('conditional modifier does not apply when condition is not met', () {
      // Create an item with a conditional modifier requiring melee vs ranged
      const item = Item(
        id: MelvorId('test:CombatNecklace'),
        name: 'Combat Necklace',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: [EquipmentSlot.amulet],
        conditionalModifiers: [
          ConditionalModifier(
            condition: CombatTypeCondition(
              character: ConditionCharacter.player,
              thisAttackType: CombatType.melee,
              targetAttackType: CombatType.ranged,
            ),
            modifiers: ModifierDataSet([
              ModifierData(name: 'maxHit', entries: [ModifierEntry(value: 5)]),
            ]),
          ),
        ],
      );

      final registries = Registries.test(items: const [item]);
      final (equipment, _) = const Equipment.empty().equipGear(
        item,
        EquipmentSlot.amulet,
      );

      final action = SkillAction(
        id: ActionId.test(Skill.woodcutting, 'TestAction'),
        skill: Skill.woodcutting,
        name: 'Test Action',
        duration: const Duration(seconds: 3),
        xp: 10,
        unlockLevel: 1,
      );

      final state = GlobalState.test(registries, equipment: equipment);

      // With wrong combat type (ranged vs melee instead of melee vs ranged)
      final modifiersWrongType = state.createActionModifierProvider(
        action,
        conditionContext: const ConditionContext(
          playerAttackType: CombatType.ranged,
          enemyAttackType: CombatType.melee,
        ),
      );
      expect(modifiersWrongType.maxHit, 0);

      // With correct combat type (melee vs ranged)
      final modifiersCorrectType = state.createActionModifierProvider(
        action,
        conditionContext: const ConditionContext(
          playerAttackType: CombatType.melee,
          enemyAttackType: CombatType.ranged,
        ),
      );
      expect(modifiersCorrectType.maxHit, 5);
    });
  });
}
