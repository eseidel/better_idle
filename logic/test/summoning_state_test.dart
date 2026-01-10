import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('markLevelForCount', () {
    test('returns 0 for no marks', () {
      expect(markLevelForCount(0), 0);
    });

    test('returns 1 for 1 mark', () {
      expect(markLevelForCount(1), 1);
    });

    test('returns 1 for 5 marks', () {
      expect(markLevelForCount(5), 1);
    });

    test('returns 2 for 6 marks', () {
      expect(markLevelForCount(6), 2);
    });

    test('returns 2 for 15 marks', () {
      expect(markLevelForCount(15), 2);
    });

    test('returns 3 for 16 marks', () {
      expect(markLevelForCount(16), 3);
    });

    test('returns 4 for 31 marks', () {
      expect(markLevelForCount(31), 4);
    });

    test('returns 5 for 46 marks', () {
      expect(markLevelForCount(46), 5);
    });

    test('returns 6 for 61 marks', () {
      expect(markLevelForCount(61), 6);
    });

    test('returns 6 for marks above 61', () {
      expect(markLevelForCount(100), 6);
    });
  });

  group('SummoningState', () {
    const familiarId1 = MelvorId('melvorF:Summoning_Familiar_Ent');
    const familiarId2 = MelvorId('melvorF:Summoning_Familiar_Golbin_Thief');

    test('empty state has no marks', () {
      const state = SummoningState.empty();
      expect(state.isEmpty, true);
      expect(state.marksFor(familiarId1), 0);
      expect(state.markLevel(familiarId1), 0);
      expect(state.canCraftTablet(familiarId1), false);
    });

    test('withMarks adds marks to familiar', () {
      const state = SummoningState.empty();
      final newState = state.withMarks(familiarId1, 5);

      expect(newState.marksFor(familiarId1), 5);
      expect(newState.markLevel(familiarId1), 1);
      expect(newState.canCraftTablet(familiarId1), true);
    });

    test('withMarks accumulates marks', () {
      const state = SummoningState.empty();
      final state1 = state.withMarks(familiarId1, 5);
      final state2 = state1.withMarks(familiarId1, 10);

      expect(state2.marksFor(familiarId1), 15);
      expect(state2.markLevel(familiarId1), 2);
    });

    test('marks are tracked per familiar', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 10)
          .withMarks(familiarId2, 20);

      expect(newState.marksFor(familiarId1), 10);
      expect(newState.marksFor(familiarId2), 20);
      expect(newState.markLevel(familiarId1), 2);
      expect(newState.markLevel(familiarId2), 3);
    });

    test('withTabletCrafted marks familiar as crafted', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 1)
          .withTabletCrafted(familiarId1);

      expect(newState.hasCrafted(familiarId1), true);
      expect(newState.hasCrafted(familiarId2), false);
    });

    test('isMarkDiscoveryBlocked returns true when 1+ marks but no tablet', () {
      const state = SummoningState.empty();
      final stateWithMark = state.withMarks(familiarId1, 1);

      // Has a mark but no tablet crafted -> blocked
      expect(stateWithMark.isMarkDiscoveryBlocked(familiarId1), true);
    });

    test('isMarkDiscoveryBlocked returns false when no marks', () {
      const state = SummoningState.empty();
      expect(state.isMarkDiscoveryBlocked(familiarId1), false);
    });

    test('isMarkDiscoveryBlocked returns false after crafting tablet', () {
      const state = SummoningState.empty();
      final newState = state
          .withMarks(familiarId1, 1)
          .withTabletCrafted(familiarId1);

      expect(newState.isMarkDiscoveryBlocked(familiarId1), false);
    });

    group('JSON serialization', () {
      test('empty state round-trips correctly', () {
        const original = SummoningState.empty();
        final json = original.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.isEmpty, true);
        expect(loaded.marks, isEmpty);
        expect(loaded.hasCraftedTablet, isEmpty);
      });

      test('state with marks round-trips correctly', () {
        const original = SummoningState.empty();
        final withMarks = original
            .withMarks(familiarId1, 15)
            .withMarks(familiarId2, 6);

        final json = withMarks.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.marksFor(familiarId1), 15);
        expect(loaded.marksFor(familiarId2), 6);
        expect(loaded.markLevel(familiarId1), 2);
        expect(loaded.markLevel(familiarId2), 2);
      });

      test('state with crafted tablets round-trips correctly', () {
        const original = SummoningState.empty();
        final withCrafted = original
            .withMarks(familiarId1, 1)
            .withTabletCrafted(familiarId1);

        final json = withCrafted.toJson();
        final loaded = SummoningState.fromJson(json);

        expect(loaded.hasCrafted(familiarId1), true);
        expect(loaded.hasCrafted(familiarId2), false);
      });

      test('maybeFromJson returns null for null input', () {
        expect(SummoningState.maybeFromJson(null), isNull);
      });

      test('maybeFromJson parses valid input', () {
        const original = SummoningState.empty();
        final withMarks = original.withMarks(familiarId1, 10);
        final json = withMarks.toJson();

        final loaded = SummoningState.maybeFromJson(json);
        expect(loaded, isNotNull);
        expect(loaded!.marksFor(familiarId1), 10);
      });
    });

    group('copyWith', () {
      test('creates a copy with new marks', () {
        const state = SummoningState.empty();
        final stateWithMarks = state.withMarks(familiarId1, 5);

        final copied = stateWithMarks.copyWith(marks: {familiarId2: 10});

        expect(copied.marksFor(familiarId1), 0);
        expect(copied.marksFor(familiarId2), 10);
      });

      test('preserves values when not overridden', () {
        const state = SummoningState.empty();
        final stateWithData = state
            .withMarks(familiarId1, 5)
            .withTabletCrafted(familiarId1);

        final copied = stateWithData.copyWith();

        expect(copied.marksFor(familiarId1), 5);
        expect(copied.hasCrafted(familiarId1), true);
      });
    });
  });
}
