import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late SmithingAction steelBar;
  late Item coalOre;
  late Item ironOre;
  late Item steelBarItem;

  setUpAll(() async {
    await loadTestRegistries();
    steelBar =
        testRegistries.smithingAction('Steel Bar') as SmithingAction;
    coalOre = testItems.byName('Coal Ore');
    ironOre = testItems.byName('Iron Ore');
    steelBarItem = testItems.byName('Steel Bar');
  });

  group('smithingCoalCost via effectiveInputs', () {
    test('Steel Bar requires coal ore', () {
      expect(steelBar.inputs, contains(coalOre.id));
    });

    test('base inputs without modifiers', () {
      final baseCoalCount = steelBar.inputs[coalOre.id]!;
      expect(baseCoalCount, greaterThan(0));
      final state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(coalOre, count: 100),
          ItemStack(ironOre, count: 100),
        ]),
        skillStates: {
          Skill.smithing: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );
      final inputs = state.effectiveInputs(steelBar);
      expect(inputs[coalOre.id], baseCoalCount);
    });

    test('completeAction produces steel bar', () {
      final random = Random(42);
      var state = GlobalState.test(
        testRegistries,
        inventory: Inventory.fromItems(testItems, [
          ItemStack(coalOre, count: 100),
          ItemStack(ironOre, count: 100),
        ]),
        skillStates: {
          Skill.smithing: SkillState(
            xp: startXpForLevel(99),
            masteryPoolXp: 0,
          ),
        },
      );
      state = state.startAction(steelBar, random: random);
      final builder = StateUpdateBuilder(state);
      completeAction(builder, steelBar, random: random);
      state = builder.build();
      expect(
        state.inventory.countOfItem(steelBarItem),
        greaterThanOrEqualTo(1),
      );
    });
  });
}
