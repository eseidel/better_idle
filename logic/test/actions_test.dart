import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/types/resolved_modifiers.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late SkillAction normalTree;
  late SkillAction copperMining;

  setUpAll(() async {
    await loadTestRegistries();
    normalTree = testActions.woodcutting('Normal Tree');
    copperMining = testActions.mining('Copper');
  });

  group('SkillAction', () {
    test(
      'woodcutting base rewards return 1 item (doubling applied via modifiers)',
      () {
        // Woodcutting now uses defaultRewards (1 item per action).
        // The doubling mechanic is applied via skillItemDoublingChance modifier
        // at roll time in rollAndCollectDrops(), not in the rewards themselves.
        final normalLogsId = MelvorId.fromName('Normal Logs');

        // Base rewards are always 1 item regardless of mastery level
        final rewardsAt0 = normalTree.rewardsForMasteryLevel(0);
        expect(rewardsAt0.length, 1);
        final expectedAt0 = rewardsAt0.first.expectedItems[normalLogsId]!;
        expect(expectedAt0, closeTo(1.0, 0.001));

        // Even at high mastery, base rewards are still 1 item
        final rewardsAt50 = normalTree.rewardsForMasteryLevel(50);
        expect(rewardsAt50.length, 1);
        final expectedAt50 = rewardsAt50.first.expectedItems[normalLogsId]!;
        expect(expectedAt50, closeTo(1.0, 0.001));
      },
    );

    test('expectedItemsForDrops applies doubling chance multiplier', () {
      final normalLogsId = MelvorId.fromName('Normal Logs');
      final drops = testDrops.allDropsForAction(normalTree, masteryLevel: 0);

      // With 0% doubling chance, expected items = 1.0
      final expected0 = expectedItemsForDrops(drops, doublingChance: 0.0);
      expect(expected0[normalLogsId], closeTo(1.0, 0.001));

      // With 5% doubling chance, expected items = 1.05
      final expected5 = expectedItemsForDrops(drops, doublingChance: 0.05);
      expect(expected5[normalLogsId], closeTo(1.05, 0.001));

      // With 10% doubling chance, expected items = 1.10
      final expected10 = expectedItemsForDrops(drops, doublingChance: 0.10);
      expect(expected10[normalLogsId], closeTo(1.10, 0.001));

      // With 25% doubling chance, expected items = 1.25
      final expected25 = expectedItemsForDrops(drops, doublingChance: 0.25);
      expect(expected25[normalLogsId], closeTo(1.25, 0.001));
    });
  });

  group('allDropsForAction', () {
    test('mining actions include gem drops from miningGemTable', () {
      final drops = testDrops.allDropsForAction(copperMining, masteryLevel: 1);

      // Check that miningGemTable (a DropChance wrapping DropTable) is included
      final hasGemTable = drops.any(
        (d) => d is DropChance && d.child is DropTable,
      );
      expect(
        hasGemTable,
        isTrue,
        reason: 'Mining actions should include gem drop table',
      );

      // Verify gems appear in expectedItems
      final allExpectedItems = expectedItemsForDrops(drops);

      // At least one gem should be present (keys are now MelvorId)
      final gemIds = [
        MelvorId('melvorD:Topaz'),
        MelvorId('melvorD:Sapphire'),
        MelvorId('melvorD:Ruby'),
        MelvorId('melvorD:Emerald'),
        MelvorId('melvorD:Diamond'),
      ];
      final hasAnyGem = gemIds.any(allExpectedItems.containsKey);
      expect(
        hasAnyGem,
        isTrue,
        reason: 'Mining drops should include gems from miningGemTable',
      );
    });
  });

  group('rollAndCollectDrops', () {
    test('doubles items when random triggers doubling chance', () {
      final normalLogsId = MelvorId.fromName('Normal Logs');
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);

      // Create modifiers with 100% doubling chance to guarantee doubling
      const modifiers = ResolvedModifiers({'skillItemDoublingChance': 100});

      // Use a fixed seed random - the doubling check uses random.nextDouble()
      // With 100% chance, any random value will trigger doubling
      final random = Random(42);

      rollAndCollectDrops(builder, normalTree, modifiers, random);

      // With 100% doubling chance, we should get 2 logs instead of 1
      final inventory = builder.state.inventory;
      final logsCount = inventory.countById(normalLogsId);
      expect(logsCount, 2, reason: 'Should have doubled the logs drop');
    });

    test('does not double items when doubling chance is 0', () {
      final normalLogsId = MelvorId.fromName('Normal Logs');
      final state = GlobalState.test(testRegistries);
      final builder = StateUpdateBuilder(state);

      // No doubling chance
      const modifiers = ResolvedModifiers.empty;

      final random = Random(42);

      rollAndCollectDrops(builder, normalTree, modifiers, random);

      // With 0% doubling chance, we should get exactly 1 log
      final inventory = builder.state.inventory;
      final logsCount = inventory.countById(normalLogsId);
      expect(
        logsCount,
        1,
        reason: 'Should have exactly 1 log without doubling',
      );
    });
  });
}
