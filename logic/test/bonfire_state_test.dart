import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  group('BonfireState', () {
    final testActionId = ActionId.test(Skill.firemaking, 'Burn Normal Logs');

    test('empty state has expected defaults', () {
      const state = BonfireState.empty();
      expect(state.actionId, isNull);
      expect(state.ticksRemaining, 0);
      expect(state.totalTicks, 0);
      expect(state.xpBonus, 0);
      expect(state.isActive, false);
      expect(state.isEmpty, true);
    });

    test('active state has isActive true and isEmpty false', () {
      final state = BonfireState(
        actionId: testActionId,
        ticksRemaining: 100,
        totalTicks: 200,
        xpBonus: 5,
      );
      expect(state.isActive, true);
      expect(state.isEmpty, false);
    });

    test('state with zero ticksRemaining is not active', () {
      final state = BonfireState(
        actionId: testActionId,
        ticksRemaining: 0,
        totalTicks: 200,
        xpBonus: 5,
      );
      expect(state.isActive, false);
      expect(state.isEmpty, true);
    });

    test('state with null actionId is not active', () {
      const state = BonfireState(
        actionId: null,
        ticksRemaining: 100,
        totalTicks: 200,
        xpBonus: 5,
      );
      expect(state.isActive, false);
      expect(state.isEmpty, true);
    });

    test('remainingDuration converts ticks to Duration', () {
      final state = BonfireState(
        actionId: testActionId,
        ticksRemaining: 100, // 100 ticks * 100ms = 10 seconds
        totalTicks: 200,
        xpBonus: 5,
      );
      expect(state.remainingDuration, const Duration(seconds: 10));
    });

    group('consumeTicks', () {
      test('decrements ticksRemaining', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final newState = state.consumeTicks(30);
        expect(newState.ticksRemaining, 70);
        expect(newState.actionId, testActionId);
        expect(newState.totalTicks, 200);
        expect(newState.xpBonus, 5);
      });

      test('returns empty state when all ticks consumed', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final newState = state.consumeTicks(100);
        expect(newState.isEmpty, true);
        expect(newState.isActive, false);
      });

      test('returns empty state when over-consuming ticks', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 50,
          totalTicks: 200,
          xpBonus: 5,
        );
        final newState = state.consumeTicks(100);
        expect(newState.isEmpty, true);
        expect(newState.isActive, false);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final newState = state.copyWith(ticksRemaining: 50, xpBonus: 10);
        expect(newState.actionId, testActionId);
        expect(newState.ticksRemaining, 50);
        expect(newState.totalTicks, 200);
        expect(newState.xpBonus, 10);
      });

      test('preserves values when not overridden', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final newState = state.copyWith();
        expect(newState.actionId, testActionId);
        expect(newState.ticksRemaining, 100);
        expect(newState.totalTicks, 200);
        expect(newState.xpBonus, 5);
      });
    });

    group('JSON serialization', () {
      test('empty state round-trips correctly', () {
        const original = BonfireState.empty();
        final json = original.toJson();
        final loaded = BonfireState.fromJson(json);

        expect(loaded.isEmpty, true);
        expect(loaded.actionId, isNull);
        expect(loaded.ticksRemaining, 0);
        expect(loaded.totalTicks, 0);
        expect(loaded.xpBonus, 0);
      });

      test('active state round-trips correctly', () {
        final original = BonfireState(
          actionId: testActionId,
          ticksRemaining: 150,
          totalTicks: 300,
          xpBonus: 10,
        );
        final json = original.toJson();
        final loaded = BonfireState.fromJson(json);

        expect(loaded.actionId, testActionId);
        expect(loaded.ticksRemaining, 150);
        expect(loaded.totalTicks, 300);
        expect(loaded.xpBonus, 10);
        expect(loaded.isActive, true);
      });

      test('toJson omits empty state fields', () {
        const state = BonfireState.empty();
        final json = state.toJson();
        expect(json, isEmpty);
      });

      test('toJson includes all fields for active state', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final json = state.toJson();
        expect(json.containsKey('actionId'), true);
        expect(json.containsKey('ticksRemaining'), true);
        expect(json.containsKey('totalTicks'), true);
        expect(json.containsKey('xpBonus'), true);
      });

      test('maybeFromJson returns null for null input', () {
        expect(BonfireState.maybeFromJson(null), isNull);
      });

      test('maybeFromJson parses valid input', () {
        final original = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 200,
          xpBonus: 5,
        );
        final json = original.toJson();

        final loaded = BonfireState.maybeFromJson(json);
        expect(loaded, isNotNull);
        expect(loaded!.actionId, testActionId);
        expect(loaded.ticksRemaining, 100);
      });

      test('fromJson handles missing optional fields with defaults', () {
        final json = <String, dynamic>{};
        final loaded = BonfireState.fromJson(json);

        expect(loaded.actionId, isNull);
        expect(loaded.ticksRemaining, 0);
        expect(loaded.totalTicks, 0);
        expect(loaded.xpBonus, 0);
      });
    });

    group('toProgressAt', () {
      test('returns ProgressAt with correct values for active bonfire', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 50,
          totalTicks: 200,
          xpBonus: 5,
        );
        final now = DateTime(2024, 1, 1, 12);

        final progressAt = state.toProgressAt(now);

        expect(progressAt.lastUpdateTime, now);
        // progressTicks = totalTicks - ticksRemaining = 200 - 50 = 150
        expect(progressAt.progressTicks, 150);
        expect(progressAt.totalTicks, 200);
        expect(progressAt.isAdvancing, true);
      });

      test(
        'returns ProgressAt with isAdvancing false for inactive bonfire',
        () {
          const state = BonfireState.empty();
          final now = DateTime(2024, 1, 1, 12);

          final progressAt = state.toProgressAt(now);

          expect(progressAt.lastUpdateTime, now);
          expect(progressAt.isAdvancing, false);
        },
      );

      test('progress fraction is correct for partially consumed bonfire', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 75,
          totalTicks: 100,
          xpBonus: 5,
        );
        final now = DateTime(2024, 1, 1, 12);

        final progressAt = state.toProgressAt(now);

        // progressTicks = 100 - 75 = 25, so progress = 25/100 = 0.25
        expect(progressAt.progress, 0.25);
      });

      test('progress fraction is 0 for fresh bonfire', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 100,
          totalTicks: 100,
          xpBonus: 5,
        );
        final now = DateTime(2024, 1, 1, 12);

        final progressAt = state.toProgressAt(now);

        // progressTicks = 100 - 100 = 0, so progress = 0/100 = 0
        expect(progressAt.progress, 0.0);
      });

      test('progress fraction is 1 for fully consumed bonfire', () {
        final state = BonfireState(
          actionId: testActionId,
          ticksRemaining: 0,
          totalTicks: 100,
          xpBonus: 5,
        );
        final now = DateTime(2024, 1, 1, 12);

        final progressAt = state.toProgressAt(now);

        // progressTicks = 100 - 0 = 100, so progress = 100/100 = 1
        expect(progressAt.progress, 1.0);
      });
    });
  });
}
