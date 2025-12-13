import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  SkillAction skillAction(String name) =>
      actionRegistry.skillActionByName(name);

  final normalTree = skillAction('Normal Tree');

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

        // At mastery level 1: 5% double chance, expectedItems = 1.05
        final rewardsAt1 = normalTree.rewardsForMasteryLevel(1);
        expect(rewardsAt1.length, 1);
        final expectedAt1 = rewardsAt1.first.expectedItems['Normal Logs']!;
        expect(expectedAt1, closeTo(1.05, 0.001));

        // At mastery level 5: 25% double chance, expectedItems = 1.25
        final rewardsAt5 = normalTree.rewardsForMasteryLevel(5);
        expect(rewardsAt5.length, 1);
        final expectedAt5 = rewardsAt5.first.expectedItems['Normal Logs']!;
        expect(expectedAt5, closeTo(1.25, 0.001));

        // At mastery level 9: 45% double chance, expectedItems = 1.45
        final rewardsAt9 = normalTree.rewardsForMasteryLevel(9);
        expect(rewardsAt9.length, 1);
        final expectedAt9 = rewardsAt9.first.expectedItems['Normal Logs']!;
        expect(expectedAt9, closeTo(1.45, 0.001));
      },
    );
  });
}
