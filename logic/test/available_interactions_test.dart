import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/available_interactions.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await ensureItemsInitialized();
  });

  group('availableInteractions', () {
    test('empty state returns only level 1 activities', () {
      final state = GlobalState.empty();
      final interactions = availableInteractions(state);

      final switches = interactions.whereType<SwitchActivity>().toList();
      final upgrades = interactions.whereType<BuyUpgrade>().toList();
      final sells = interactions.whereType<SellAll>().toList();

      // Should have level 1 activities: Normal Tree, Raw Shrimp,
      // Rune Essence, Copper, Tin, Man
      expect(switches.length, 6);
      expect(switches.map((s) => s.actionName), contains('Normal Tree'));
      expect(switches.map((s) => s.actionName), contains('Raw Shrimp'));
      expect(switches.map((s) => s.actionName), contains('Man'));

      // No upgrades affordable with 0 GP
      expect(upgrades, isEmpty);

      // No items to sell
      expect(sells, isEmpty);
    });

    test('state with GP includes affordable upgrades', () {
      final state = GlobalState.empty().copyWith(gp: 1000);
      final interactions = availableInteractions(state);

      final upgrades = interactions.whereType<BuyUpgrade>().toList();

      // Should have Iron Axe (50 GP), Iron Fishing Rod (100 GP),
      // Iron Pickaxe (250 GP)
      expect(upgrades.length, 3);
      expect(upgrades.map((u) => u.type), contains(UpgradeType.axe));
      expect(upgrades.map((u) => u.type), contains(UpgradeType.fishingRod));
      expect(upgrades.map((u) => u.type), contains(UpgradeType.pickaxe));
    });

    test('active action is excluded from switches', () {
      var state = GlobalState.empty().copyWith(gp: 500);
      final action = actionRegistry.byName('Normal Tree');
      final random = Random(0);
      state = state.startAction(action, random: random);

      final interactions = availableInteractions(state);
      final switches = interactions.whereType<SwitchActivity>().toList();

      // Normal Tree should not be in the list since it's active
      expect(switches.map((s) => s.actionName), isNot(contains('Normal Tree')));
    });

    test('higher skill levels unlock more activities', () {
      final state = GlobalState.empty().copyWith(
        gp: 100000,
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          // Level 20 = 4470 XP
          Skill.woodcutting: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.fishing: const SkillState(xp: 4470, masteryPoolXp: 0),
          Skill.mining: const SkillState(xp: 4470, masteryPoolXp: 0),
        },
      );

      final interactions = availableInteractions(state);
      final switches = interactions.whereType<SwitchActivity>().toList();

      // Should have more activities unlocked at level 20
      expect(switches.map((s) => s.actionName), contains('Oak Tree'));
      expect(switches.map((s) => s.actionName), contains('Willow Tree'));
      expect(switches.map((s) => s.actionName), contains('Raw Herring'));
      expect(switches.map((s) => s.actionName), contains('Iron'));
    });

    test('inventory with items includes SellAll', () {
      final logs = itemRegistry.byName('Normal Logs');
      final ore = itemRegistry.byName('Copper Ore');
      final state = GlobalState.empty().copyWith(
        inventory: Inventory.fromItems([
          ItemStack(logs, count: 100),
          ItemStack(ore, count: 50),
        ]),
      );

      final interactions = availableInteractions(state);
      final sells = interactions.whereType<SellAll>().toList();

      expect(sells.length, 1);
    });

    test('empty inventory does not include SellAll', () {
      final state = GlobalState.empty();
      final interactions = availableInteractions(state);
      final sells = interactions.whereType<SellAll>().toList();

      expect(sells, isEmpty);
    });
  });
}
