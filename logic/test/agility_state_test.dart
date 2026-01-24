import 'package:logic/logic.dart';
import 'package:test/test.dart';

void main() {
  final testObstacle1 = ActionId.test(Skill.agility, 'Rope_Swing');
  final testObstacle2 = ActionId.test(Skill.agility, 'Balance_Log');
  final testObstacle3 = ActionId.test(Skill.agility, 'Climb_Wall');

  group('AgilitySlotState', () {
    test('empty state has expected defaults', () {
      const state = AgilitySlotState.empty();
      expect(state.obstacleId, isNull);
      expect(state.purchaseCount, 0);
      expect(state.isEmpty, true);
      expect(state.hasObstacle, false);
      expect(state.costDiscount, 0.0);
    });

    test('state with obstacle has hasObstacle true', () {
      final state = AgilitySlotState(obstacleId: testObstacle1);
      expect(state.isEmpty, false);
      expect(state.hasObstacle, true);
    });

    group('costDiscount', () {
      test('returns 0 for 0 purchases', () {
        const state = AgilitySlotState();
        expect(state.costDiscount, 0.0);
      });

      test('returns 4% per purchase', () {
        const state1 = AgilitySlotState(purchaseCount: 1);
        expect(state1.costDiscount, 0.04);

        const state5 = AgilitySlotState(purchaseCount: 5);
        expect(state5.costDiscount, 0.20);
      });

      test('caps at 40% for 10+ purchases', () {
        const state10 = AgilitySlotState(purchaseCount: 10);
        expect(state10.costDiscount, 0.40);

        const state15 = AgilitySlotState(purchaseCount: 15);
        expect(state15.costDiscount, 0.40);
      });
    });

    test('withObstacle creates state with incremented purchaseCount', () {
      const state = AgilitySlotState(purchaseCount: 3);
      final newState = state.withObstacle(testObstacle1);

      expect(newState.obstacleId, testObstacle1);
      expect(newState.purchaseCount, 4);
    });

    test('destroyed removes obstacle but keeps purchaseCount', () {
      final state = AgilitySlotState(
        obstacleId: testObstacle1,
        purchaseCount: 5,
      );
      final newState = state.destroyed();

      expect(newState.obstacleId, isNull);
      expect(newState.isEmpty, true);
      expect(newState.purchaseCount, 5);
    });

    group('JSON serialization', () {
      test('empty state round-trips correctly', () {
        const original = AgilitySlotState.empty();
        final json = original.toJson();
        final loaded = AgilitySlotState.fromJson(json);

        expect(loaded.isEmpty, true);
        expect(loaded.obstacleId, isNull);
        expect(loaded.purchaseCount, 0);
      });

      test('state with obstacle round-trips correctly', () {
        final original = AgilitySlotState(
          obstacleId: testObstacle1,
          purchaseCount: 3,
        );
        final json = original.toJson();
        final loaded = AgilitySlotState.fromJson(json);

        expect(loaded.obstacleId, testObstacle1);
        expect(loaded.purchaseCount, 3);
      });

      test('state with only purchaseCount round-trips correctly', () {
        const original = AgilitySlotState(purchaseCount: 7);
        final json = original.toJson();
        final loaded = AgilitySlotState.fromJson(json);

        expect(loaded.obstacleId, isNull);
        expect(loaded.purchaseCount, 7);
      });

      test('toJson omits default values', () {
        const state = AgilitySlotState.empty();
        final json = state.toJson();
        expect(json, isEmpty);
      });

      test('toJson includes non-default values', () {
        final state = AgilitySlotState(
          obstacleId: testObstacle1,
          purchaseCount: 2,
        );
        final json = state.toJson();
        expect(json.containsKey('obstacleId'), true);
        expect(json.containsKey('purchaseCount'), true);
      });

      test('fromJson handles missing optional fields with defaults', () {
        final json = <String, dynamic>{};
        final loaded = AgilitySlotState.fromJson(json);

        expect(loaded.obstacleId, isNull);
        expect(loaded.purchaseCount, 0);
      });
    });
  });

  group('AgilityState', () {
    test('empty state has expected defaults', () {
      const state = AgilityState.empty();
      expect(state.slots, isEmpty);
      expect(state.currentObstacleIndex, 0);
      expect(state.isEmpty, true);
      expect(state.hasAnyObstacle, false);
      expect(state.builtObstacleCount, 0);
      expect(state.builtObstacles, isEmpty);
    });

    test('slotState returns empty state for missing slot', () {
      const state = AgilityState.empty();
      final slotState = state.slotState(5);

      expect(slotState.isEmpty, true);
      expect(slotState.purchaseCount, 0);
    });

    test('slotState returns correct state for existing slot', () {
      final state = AgilityState(
        slots: {
          0: AgilitySlotState(obstacleId: testObstacle1, purchaseCount: 2),
        },
      );
      final slotState = state.slotState(0);

      expect(slotState.obstacleId, testObstacle1);
      expect(slotState.purchaseCount, 2);
    });

    test('hasObstacle returns correct values', () {
      final state = AgilityState(
        slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
      );

      expect(state.hasObstacle(0), true);
      expect(state.hasObstacle(1), false);
    });

    test('obstacleInSlot returns correct values', () {
      final state = AgilityState(
        slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
      );

      expect(state.obstacleInSlot(0), testObstacle1);
      expect(state.obstacleInSlot(1), isNull);
    });

    test('builtObstacles returns obstacles in slot order', () {
      final state = AgilityState(
        slots: {
          2: AgilitySlotState(obstacleId: testObstacle3),
          0: AgilitySlotState(obstacleId: testObstacle1),
          1: AgilitySlotState(obstacleId: testObstacle2),
        },
      );

      expect(state.builtObstacles, [
        testObstacle1,
        testObstacle2,
        testObstacle3,
      ]);
    });

    test('builtObstacles skips empty slots', () {
      final state = AgilityState(
        slots: {
          0: AgilitySlotState(obstacleId: testObstacle1),
          1: const AgilitySlotState(purchaseCount: 2), // Empty but has history
          2: AgilitySlotState(obstacleId: testObstacle2),
        },
      );

      expect(state.builtObstacles, [testObstacle1, testObstacle2]);
    });

    test('builtObstacleCount counts correctly', () {
      final state = AgilityState(
        slots: {
          0: AgilitySlotState(obstacleId: testObstacle1),
          1: const AgilitySlotState(purchaseCount: 2), // Empty
          2: AgilitySlotState(obstacleId: testObstacle2),
        },
      );

      expect(state.builtObstacleCount, 2);
    });

    test('withObstacle adds obstacle and increments purchaseCount', () {
      const state = AgilityState.empty();
      final newState = state.withObstacle(0, testObstacle1);

      expect(newState.hasObstacle(0), true);
      expect(newState.obstacleInSlot(0), testObstacle1);
      expect(newState.slotState(0).purchaseCount, 1);
    });

    test('withObstacle on existing slot increments purchaseCount', () {
      var state = const AgilityState.empty();
      state = state.withObstacle(0, testObstacle1);
      state = state.withObstacleDestroyed(0);
      state = state.withObstacle(0, testObstacle2);

      expect(state.slotState(0).purchaseCount, 2);
      expect(state.obstacleInSlot(0), testObstacle2);
    });

    test('withObstacleDestroyed removes obstacle but keeps purchaseCount', () {
      var state = const AgilityState.empty();
      state = state.withObstacle(0, testObstacle1);
      expect(state.slotState(0).purchaseCount, 1);

      state = state.withObstacleDestroyed(0);
      expect(state.hasObstacle(0), false);
      expect(state.slotState(0).purchaseCount, 1);
    });

    test('withObstacleDestroyed on empty slot returns same state', () {
      const state = AgilityState.empty();
      final newState = state.withObstacleDestroyed(0);

      expect(identical(state, newState), true);
    });

    test('withProgressReset resets currentObstacleIndex', () {
      final state = AgilityState(
        slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
        currentObstacleIndex: 5,
      );
      final newState = state.withProgressReset();

      expect(newState.currentObstacleIndex, 0);
    });

    test('withNextObstacle advances and wraps', () {
      final state = AgilityState(
        slots: {
          0: AgilitySlotState(obstacleId: testObstacle1),
          1: AgilitySlotState(obstacleId: testObstacle2),
          2: AgilitySlotState(obstacleId: testObstacle3),
        },
      );

      final state1 = state.withNextObstacle();
      expect(state1.currentObstacleIndex, 1);

      final state2 = state1.withNextObstacle();
      expect(state2.currentObstacleIndex, 2);

      // Wraps back to 0
      final state3 = state2.withNextObstacle();
      expect(state3.currentObstacleIndex, 0);
    });

    test('withNextObstacle returns same state when no obstacles', () {
      const state = AgilityState.empty();
      final newState = state.withNextObstacle();

      expect(identical(state, newState), true);
    });

    group('JSON serialization', () {
      test('empty state round-trips correctly', () {
        const original = AgilityState.empty();
        final json = original.toJson();
        final loaded = AgilityState.fromJson(json);

        expect(loaded.isEmpty, true);
        expect(loaded.slots, isEmpty);
        expect(loaded.currentObstacleIndex, 0);
      });

      test('state with slots round-trips correctly', () {
        final original = AgilityState(
          slots: {
            0: AgilitySlotState(obstacleId: testObstacle1, purchaseCount: 2),
            2: AgilitySlotState(obstacleId: testObstacle2, purchaseCount: 5),
          },
          currentObstacleIndex: 1,
        );
        final json = original.toJson();
        final loaded = AgilityState.fromJson(json);

        expect(loaded.slots.length, 2);
        expect(loaded.slotState(0).obstacleId, testObstacle1);
        expect(loaded.slotState(0).purchaseCount, 2);
        expect(loaded.slotState(2).obstacleId, testObstacle2);
        expect(loaded.slotState(2).purchaseCount, 5);
        expect(loaded.currentObstacleIndex, 1);
      });

      test('state with empty slots (purchaseCount only) round-trips', () {
        final original = AgilityState(
          slots: {
            0: const AgilitySlotState(purchaseCount: 3), // No obstacle
            1: AgilitySlotState(obstacleId: testObstacle1),
          },
        );
        final json = original.toJson();
        final loaded = AgilityState.fromJson(json);

        expect(loaded.slotState(0).obstacleId, isNull);
        expect(loaded.slotState(0).purchaseCount, 3);
        expect(loaded.slotState(1).obstacleId, testObstacle1);
      });

      test('toJson omits default values', () {
        const state = AgilityState.empty();
        final json = state.toJson();
        expect(json, isEmpty);
      });

      test('toJson omits currentObstacleIndex when 0', () {
        final state = AgilityState(
          slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
        );
        final json = state.toJson();
        expect(json.containsKey('currentObstacleIndex'), false);
      });

      test('toJson includes currentObstacleIndex when non-zero', () {
        final state = AgilityState(
          slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
          currentObstacleIndex: 2,
        );
        final json = state.toJson();
        expect(json['currentObstacleIndex'], 2);
      });

      test('toJson omits slots with empty state', () {
        const state = AgilityState(
          slots: {
            0: AgilitySlotState.empty(), // Should be omitted
          },
        );
        final json = state.toJson();
        expect(json.containsKey('slots'), false);
      });

      test('maybeFromJson returns null for null input', () {
        expect(AgilityState.maybeFromJson(null), isNull);
      });

      test('maybeFromJson parses valid input', () {
        final original = AgilityState(
          slots: {0: AgilitySlotState(obstacleId: testObstacle1)},
        );
        final json = original.toJson();

        final loaded = AgilityState.maybeFromJson(json);
        expect(loaded, isNotNull);
        expect(loaded!.hasObstacle(0), true);
      });

      test('fromJson handles missing optional fields with defaults', () {
        final json = <String, dynamic>{};
        final loaded = AgilityState.fromJson(json);

        expect(loaded.slots, isEmpty);
        expect(loaded.currentObstacleIndex, 0);
      });

      test('fromJson handles slots with string keys', () {
        // JSON maps always have string keys
        final json = <String, dynamic>{
          'slots': {
            '0': {'obstacleId': testObstacle1.toJson(), 'purchaseCount': 1},
            '3': {'obstacleId': testObstacle2.toJson(), 'purchaseCount': 4},
          },
          'currentObstacleIndex': 1,
        };
        final loaded = AgilityState.fromJson(json);

        expect(loaded.slots.length, 2);
        expect(loaded.slots[0]?.obstacleId, testObstacle1);
        expect(loaded.slots[3]?.obstacleId, testObstacle2);
        expect(loaded.currentObstacleIndex, 1);
      });
    });
  });
}
