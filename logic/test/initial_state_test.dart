import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('Initial state', () {
    test('Free farming plots are unlocked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots with level 1 and gpCost 0 are unlocked
      final freePlots = testRegistries.farmingPlots.all
          .where((plot) => plot.level == 1 && plot.gpCost == 0)
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
              'Plot ${plot.id} with level ${plot.level} and cost '
              '${plot.gpCost} should be unlocked',
        );
      }
    });

    test('Paid farming plots are locked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots that cost GP are locked
      final paidPlots = testRegistries.farmingPlots.all
          .where((plot) => plot.gpCost > 0)
          .toList();

      for (final plot in paidPlots) {
        expect(
          state.unlockedPlots.contains(plot.id),
          false,
          reason:
              'Plot ${plot.id} with cost ${plot.gpCost} GP should be locked',
        );
      }
    });

    test('Higher level farming plots are locked at game start', () {
      final state = GlobalState.empty(testRegistries);

      // Check that plots requiring higher levels are locked
      final highLevelPlots = testRegistries.farmingPlots.all
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
