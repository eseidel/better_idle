import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('Initial state', () {
    test('Free farming plots are unlocked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots with level 1 and no cost are unlocked
      final freePlots = testRegistries.farmingPlots
          .where((plot) => plot.level == 1 && plot.currencyCosts.isEmpty)
          .toList();

      expect(
        freePlots,
        isNotEmpty,
        reason: 'Test registries should have some free plots',
      );

      for (final plot in freePlots) {
        expect(
          state.unlockedPlots.contains(plot.id),
          true,
          reason:
              'Plot ${plot.id} with level ${plot.level} and no cost '
              'should be unlocked',
        );
      }
    });

    test('Paid farming plots are locked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots that cost currency are locked
      final paidPlots = testRegistries.farmingPlots
          .where((plot) => plot.currencyCosts.isNotEmpty)
          .toList();

      for (final plot in paidPlots) {
        expect(
          state.unlockedPlots.contains(plot.id),
          false,
          reason: 'Plot ${plot.id} with cost should be locked',
        );
      }
    });

    test('Higher level farming plots are locked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots requiring higher levels are locked
      final highLevelPlots = testRegistries.farmingPlots
          .where((plot) => plot.level > 1)
          .toList();

      for (final plot in highLevelPlots) {
        expect(
          state.unlockedPlots.contains(plot.id),
          false,
          reason:
              'Plot ${plot.id} requiring level ${plot.level} should be locked',
        );
      }
    });
  });
}
