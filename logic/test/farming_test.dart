import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  setUpAll(loadTestRegistries);

  group('Farming countdown pattern', () {
    test('PlotState uses countdown pattern like mining/stunned', () {
      // Verify that PlotState uses the countdown pattern (growthTicksRemaining)
      // instead of timestamp-based tracking (plantedAtTick).

      final cropId = ActionId.test(Skill.farming, 'Potato');

      // Create a plot with 100 ticks remaining
      final plot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 100,
        compostApplied: 0,
      );

      expect(plot.growthTicksRemaining, 100);
      expect(plot.isGrowing, true);
      expect(plot.isReadyToHarvest, false);

      // Decrement the countdown
      final updated = plot.copyWith(growthTicksRemaining: 50);
      expect(updated.growthTicksRemaining, 50);
      expect(updated.isGrowing, true);

      // Reach zero
      final ready = plot.copyWith(growthTicksRemaining: 0);
      expect(ready.growthTicksRemaining, 0);
      expect(ready.isGrowing, false);
      expect(ready.isReadyToHarvest, true);
    });

    test('PlotState handles null cropId (empty plot)', () {
      const emptyPlot = PlotState.empty();

      expect(emptyPlot.cropId, isNull);
      expect(emptyPlot.isEmpty, true);
      expect(emptyPlot.isGrowing, false);
      expect(emptyPlot.isReadyToHarvest, false);
    });

    test('PlotState serialization preserves countdown', () {
      final cropId = ActionId.test(Skill.farming, 'Potato');
      final plot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 42,
        compostApplied: 10,
      );

      final json = plot.toJson();
      final restored = PlotState.fromJson(json);

      expect(restored.cropId, cropId);
      expect(restored.growthTicksRemaining, 42);
      expect(restored.compostApplied, 10);
      expect(restored.isGrowing, true);
    });

    test('PlotState ready state (countdown at 0)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(
        cropId: cropId,
        growthTicksRemaining: 0,
        compostApplied: 0,
      );

      expect(readyPlot.isGrowing, false);
      expect(readyPlot.isReadyToHarvest, true);
    });

    test('PlotState ready state (countdown null)', () {
      final cropId = ActionId.test(Skill.farming, 'Carrot');
      final readyPlot = PlotState(
        cropId: cropId,
        growthTicksRemaining: null,
        compostApplied: 0,
      );

      expect(readyPlot.isGrowing, false);
      expect(readyPlot.isReadyToHarvest, true);
    });
  });
}
