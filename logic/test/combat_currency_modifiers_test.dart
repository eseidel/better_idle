import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

/// Creates a test item equipped in the ring slot with the given modifiers.
Item _testRing(List<ModifierData> modifiers) {
  return Item(
    id: const MelvorId('test:combatCurrencyRing'),
    name: 'Test Ring',
    itemType: 'Equipment',
    sellsFor: 0,
    validSlots: const [EquipmentSlot.ring],
    modifiers: ModifierDataSet(modifiers),
  );
}

/// Equips the given ring on a high-combat-skill state and starts combat
/// against [monster]. Returns the resulting state.
GlobalState _startCombatWithRing(
  Item ring,
  CombatAction monster,
  Random random, {
  SlayerTask? slayerTask,
}) {
  const highSkill = SkillState(xp: 1000000, masteryPoolXp: 0);
  return GlobalState.test(
    testRegistries,
    skillStates: const {
      Skill.hitpoints: highSkill,
      Skill.attack: highSkill,
      Skill.strength: highSkill,
      Skill.defence: highSkill,
      Skill.slayer: highSkill,
    },
    equipment: Equipment(
      foodSlots: const [null, null, null],
      selectedFoodSlot: 0,
      gearSlots: {EquipmentSlot.ring: ring},
    ),
    slayerTask: slayerTask,
  ).startAction(monster, random: random);
}

/// Runs combat for a fixed number of ticks and returns the GP earned.
int _runCombatForGp(
  GlobalState initialState,
  Random random, {
  int ticks = 50000,
}) {
  final builder = StateUpdateBuilder(initialState);
  consumeTicks(builder, ticks, random: random);
  return builder.build().currency(Currency.gp);
}

void main() {
  setUpAll(loadTestRegistries);

  // Use Plant: 2 HP, guaranteed quick kills, and has GP drops (1-5).
  late CombatAction plant;

  setUp(() {
    plant = testRegistries.combatAction('Plant');
  });

  group('currencyGainFromCombat', () {
    test('increases GP from monster kills', () {
      // Run long enough to get multiple kills for a clear signal.
      final noModRing = _testRing(const []);
      final baseGp = _runCombatForGp(
        _startCombatWithRing(noModRing, plant, Random(42)),
        Random(42),
      );

      // With 100% currencyGainFromCombat.
      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromCombat',
          entries: [ModifierEntry(value: 100)],
        ),
      ]);
      final modGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );

      // With 100% bonus, GP should be roughly double the base.
      expect(modGp, greaterThan(baseGp));
    });
  });

  group('currencyGainFromMonsterDrops', () {
    test('increases GP from monster kills', () {
      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromMonsterDrops',
          entries: [ModifierEntry(value: 100)],
        ),
      ]);
      final baseGp = _runCombatForGp(
        _startCombatWithRing(_testRing(const []), plant, Random(42)),
        Random(42),
      );
      final modGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );
      expect(modGp, greaterThan(baseGp));
    });
  });

  group('currencyGainFromSlayerTaskMonsterDrops', () {
    test('applies extra GP only when fighting slayer task monster', () {
      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromSlayerTaskMonsterDrops',
          entries: [ModifierEntry(value: 200)],
        ),
      ]);

      // On slayer task for this monster.
      final task = SlayerTask(
        categoryId: const MelvorId('melvorF:SlayerEasy'),
        monsterId: plant.id.localId,
        killsRequired: 99999,
        killsCompleted: 0,
      );
      final onTaskGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42), slayerTask: task),
        Random(42),
      );

      // Off task (no slayer task set).
      final offTaskGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );

      // On-task should earn more GP from the extra modifier.
      expect(onTaskGp, greaterThan(offTaskGp));
    });

    test('does not apply when not on slayer task', () {
      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromSlayerTaskMonsterDrops',
          entries: [ModifierEntry(value: 200)],
        ),
      ]);
      // No slayer task - modifier should not apply.
      final withRingGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );
      final noRingGp = _runCombatForGp(
        _startCombatWithRing(_testRing(const []), plant, Random(42)),
        Random(42),
      );
      // Should be same GP since modifier only applies on-task.
      expect(withRingGp, noRingGp);
    });
  });

  group('flatCurrencyGainFromMonsterDrops', () {
    test('adds flat GP per monster kill', () {
      final ring = _testRing(const [
        ModifierData(
          name: 'flatCurrencyGainFromMonsterDrops',
          entries: [ModifierEntry(value: 500)],
        ),
      ]);
      final modGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );
      final baseGp = _runCombatForGp(
        _startCombatWithRing(_testRing(const []), plant, Random(42)),
        Random(42),
      );
      // Each kill adds 500 flat GP, so total should be much higher.
      expect(modGp, greaterThan(baseGp + 500));
    });
  });

  group('flatCurrencyGainOnEnemyHit', () {
    test('grants GP on each successful hit', () {
      final ring = _testRing(const [
        ModifierData(
          name: 'flatCurrencyGainOnEnemyHit',
          entries: [ModifierEntry(value: 10)],
        ),
      ]);
      final modGp = _runCombatForGp(
        _startCombatWithRing(ring, plant, Random(42)),
        Random(42),
      );
      final baseGp = _runCombatForGp(
        _startCombatWithRing(_testRing(const []), plant, Random(42)),
        Random(42),
      );
      // With the modifier, should earn more GP (from hits before kill).
      expect(modGp, greaterThan(baseGp));
    });
  });

  group('currencyGainFromLogSales', () {
    test('increases GP when selling logs', () {
      // Find a log item from woodcutting.
      final tree = testRegistries.woodcutting.actions.first;
      final logItem = testRegistries.items.byId(tree.productId);
      final logStack = ItemStack(logItem, count: 10);
      final baseSellValue = logStack.sellsFor;

      // Create state with the ring equipped and logs in inventory.
      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromLogSales',
          entries: [ModifierEntry(value: 50)],
        ),
      ]);
      const highSkill = SkillState(xp: 1000000, masteryPoolXp: 0);
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testRegistries.items, [logStack]),
        skillStates: const {
          Skill.hitpoints: highSkill,
          Skill.attack: highSkill,
          Skill.strength: highSkill,
          Skill.defence: highSkill,
        },
        equipment: Equipment(
          foodSlots: const [null, null, null],
          selectedFoodSlot: 0,
          gearSlots: {EquipmentSlot.ring: ring},
        ),
      );

      state = state.sellItem(logStack);

      // Should earn 50% more than base sell value.
      final expectedGp = (baseSellValue * 1.5).round();
      expect(state.currency(Currency.gp), expectedGp);
    });

    test('does not apply to non-log items', () {
      // Find a non-log item.
      final bronzeSword = testRegistries.items.byName('Bronze Sword');
      final stack = ItemStack(bronzeSword, count: 1);
      final baseSellValue = stack.sellsFor;

      final ring = _testRing(const [
        ModifierData(
          name: 'currencyGainFromLogSales',
          entries: [ModifierEntry(value: 50)],
        ),
      ]);
      const highSkill = SkillState(xp: 1000000, masteryPoolXp: 0);
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testRegistries.items, [stack]),
        skillStates: const {
          Skill.hitpoints: highSkill,
          Skill.attack: highSkill,
          Skill.strength: highSkill,
          Skill.defence: highSkill,
        },
        equipment: Equipment(
          foodSlots: const [null, null, null],
          selectedFoodSlot: 0,
          gearSlots: {EquipmentSlot.ring: ring},
        ),
      );

      state = state.sellItem(stack);

      // Should earn exactly base sell value (no bonus).
      expect(state.currency(Currency.gp), baseSellValue);
    });
  });

  group('WoodcuttingRegistry.isLog', () {
    test('returns true for woodcutting products', () {
      for (final tree in testRegistries.woodcutting.actions) {
        expect(testRegistries.woodcutting.isLog(tree.productId), isTrue);
      }
    });

    test('returns false for non-log items', () {
      final bronzeSword = testRegistries.items.byName('Bronze Sword');
      expect(testRegistries.woodcutting.isLog(bronzeSword.id), isFalse);
    });
  });
}
