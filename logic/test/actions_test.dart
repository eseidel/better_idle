import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late SkillAction normalTree;
  late SkillAction copperMining;

  setUpAll(() async {
    await ensureItemsInitialized();
    normalTree = actionRegistry.skillActionByName('Normal Tree');
    copperMining = actionRegistry.skillActionByName('Copper');
  });

  group('SkillAction', () {
    test(
      'woodcutting mastery increases expected items via 5% doubling chance',
      () {
        // Woodcutting has a doubling mechanic: every mastery level adds 5%
        // chance to double drops (capped at 50% at mastery level 10, then wraps).
        // Formula: doublePercent = (masteryLevel % 10) * 0.05
        // Expected items = singlePercent * 1 + doublePercent * 2
        //                = (1 - doublePercent) + doublePercent * 2
        //                = 1 + doublePercent

        // At mastery level 0: 0% double chance, expectedItems = 1.0
        final rewardsAt0 = normalTree.rewardsForMasteryLevel(0);
        expect(rewardsAt0.length, 1);
        final expectedAt0 = rewardsAt0.first.expectedItems['Normal Logs']!;
        expect(expectedAt0, closeTo(1.0, 0.001));

        // At mastery level 10: 5% double chance, expectedItems = 1.05
        final rewardsAt1 = normalTree.rewardsForMasteryLevel(10);
        expect(rewardsAt1.length, 1);
        final expectedAt1 = rewardsAt1.first.expectedItems['Normal Logs']!;
        expect(expectedAt1, closeTo(1.05, 0.001));

        // At mastery level 20: 10% double chance, expectedItems = 1.10
        final rewardsAt5 = normalTree.rewardsForMasteryLevel(20);
        expect(rewardsAt5.length, 1);
        final expectedAt5 = rewardsAt5.first.expectedItems['Normal Logs']!;
        expect(expectedAt5, closeTo(1.10, 0.001));

        // At mastery level 30: 15% double chance, expectedItems = 1.15
        final rewardsAt9 = normalTree.rewardsForMasteryLevel(30);
        expect(rewardsAt9.length, 1);
        final expectedAt9 = rewardsAt9.first.expectedItems['Normal Logs']!;
        expect(expectedAt9, closeTo(1.15, 0.001));
      },
    );
  });

  group('allDropsForAction', () {
    test('mining actions include gem drops from miningGemTable', () {
      final drops = dropsRegistry.allDropsForAction(
        copperMining,
        masteryLevel: 1,
      );

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

      // At least one gem should be present
      final gemNames = ['Topaz', 'Sapphire', 'Ruby', 'Emerald', 'Diamond'];
      final hasAnyGem = gemNames.any(
        (gem) => allExpectedItems.containsKey(gem),
      );
      expect(
        hasAnyGem,
        isTrue,
        reason: 'Mining drops should include gems from miningGemTable',
      );
    });
  });
}
