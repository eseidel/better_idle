import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/available_interactions.dart';
import 'package:logic/src/solver/interaction.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('availableInteractions', () {
    test('empty state returns only level 1 activities', () {
      final state = GlobalState.empty(testRegistries);
      final interactions = availableInteractions(state);

      final switches = interactions.whereType<SwitchActivity>().toList();
      final upgrades = interactions.whereType<BuyUpgrade>().toList();
      final sells = interactions.whereType<SellAll>().toList();

      // Helper to get action name from actionId
      String actionName(SwitchActivity s) => testActions.byId(s.actionId).name;

      // Should have level 1 activities: Normal Tree, Raw Shrimp,
      // Rune Essence, Copper, Tin, Man, Arrow Shafts
      expect(switches.length, 7);
      expect(switches.map(actionName), contains('Normal Tree'));
      expect(switches.map(actionName), contains('Raw Shrimp'));
      expect(switches.map(actionName), contains('Man'));

      // No upgrades affordable with 0 GP
      expect(upgrades, isEmpty);

      // No items to sell
      expect(sells, isEmpty);
    });

    test('state with GP includes affordable upgrades', () {
      final state = GlobalState.empty(testRegistries).copyWith(gp: 1000);
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
      var state = GlobalState.empty(testRegistries).copyWith(gp: 500);
      final action = testActions.byName('Normal Tree');
      final random = Random(0);
      state = state.startAction(action, random: random);

      final interactions = availableInteractions(state);
      final switches = interactions.whereType<SwitchActivity>().toList();

      // Helper to get action name from actionId
      String actionName(SwitchActivity s) => testActions.byId(s.actionId).name;

      // Normal Tree should not be in the list since it's active
      expect(switches.map(actionName), isNot(contains('Normal Tree')));
    });

    test('higher skill levels unlock more activities', () {
      final state = GlobalState.empty(testRegistries).copyWith(
        gp: 100000,
        skillStates: {
          Skill.hitpoints: const SkillState(xp: 1154, masteryPoolXp: 0),
          // Level 25 = 8740 XP (Willow Tree requires level 25)
          Skill.woodcutting: const SkillState(xp: 8740, masteryPoolXp: 0),
          Skill.fishing: const SkillState(xp: 8740, masteryPoolXp: 0),
          Skill.mining: const SkillState(xp: 8740, masteryPoolXp: 0),
        },
      );

      final interactions = availableInteractions(state);
      final switches = interactions.whereType<SwitchActivity>().toList();

      // Helper to get action name from actionId
      String actionName(SwitchActivity s) => testActions.byId(s.actionId).name;

      // Should have more activities unlocked at level 25
      expect(switches.map(actionName), contains('Oak Tree'));
      expect(switches.map(actionName), contains('Willow Tree'));
      expect(switches.map(actionName), contains('Raw Herring'));
      expect(switches.map(actionName), contains('Iron'));
    });

    test('inventory with items includes SellAll', () {
      final logs = testItems.byName('Normal Logs');
      final ore = testItems.byName('Copper Ore');
      final state = GlobalState.empty(testRegistries).copyWith(
        inventory: Inventory.fromItems(testItems, [
          ItemStack(logs, count: 100),
          ItemStack(ore, count: 50),
        ]),
      );

      final interactions = availableInteractions(state);
      final sells = interactions.whereType<SellAll>().toList();

      expect(sells.length, 1);
    });

    test('empty inventory does not include SellAll', () {
      final state = GlobalState.empty(testRegistries);
      final interactions = availableInteractions(state);
      final sells = interactions.whereType<SellAll>().toList();

      expect(sells, isEmpty);
    });
  });
}
