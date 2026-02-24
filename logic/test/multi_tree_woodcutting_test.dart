import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late WoodcuttingTree normalTree;
  late WoodcuttingTree oakTree;
  late Item normalLogs;
  late Item oakLogs;

  setUpAll(() async {
    await loadTestRegistries();

    normalTree =
        testRegistries.woodcuttingAction('Normal Tree') as WoodcuttingTree;
    oakTree = testRegistries.woodcuttingAction('Oak Tree') as WoodcuttingTree;

    normalLogs = testItems.byName('Normal Logs');
    oakLogs = testItems.byName('Oak Logs');
  });

  /// Creates a state with the Multi_Tree shop purchase.
  GlobalState stateWithMultiTree() {
    return GlobalState.test(
      testRegistries,
      shop: const ShopState.empty().withPurchase(
        MelvorId.fromJson('melvorD:Multi_Tree'),
      ),
    );
  }

  group('multi-tree woodcutting', () {
    test('startMultiTreeWoodcutting sets secondaryActionId', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      final activity = state.activeActivity! as SkillActivity;
      expect(activity.secondaryActionId, isNotNull);
      expect(activity.skill, Skill.woodcutting);
    });

    test('slower tree becomes primary, faster tree becomes secondary', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      final activity = state.activeActivity! as SkillActivity;
      // Oak (4s) is slower -> primary, Normal (3s) is faster -> secondary
      expect(activity.actionId, oakTree.id.localId);
      expect(activity.secondaryActionId, normalTree.id.localId);
    });

    test('totalTicks equals the slower tree duration', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      final activity = state.activeActivity! as SkillActivity;
      // Oak Tree has fixed duration, totalTicks should be Oak's duration
      // (40 ticks = 4 seconds)
      expect(activity.totalTicks, 40);
    });

    test('isActionActive returns true for both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      expect(state.isActionActive(oakTree), isTrue);
      expect(state.isActionActive(normalTree), isTrue);
    });

    test('activeProgress returns progress for both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // Both trees should share the same progress (starts at 0)
      expect(state.activeProgress(oakTree), 0);
      expect(state.activeProgress(normalTree), 0);
    });

    test('completing one cycle produces logs from both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // Complete one full cycle (40 ticks for Oak Tree)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 40, random: random);
      state = builder.build();

      // Both logs should be in inventory
      final normalLogsCount = state.inventory.countOfItem(normalLogs);
      final oakLogsCount = state.inventory.countOfItem(oakLogs);

      // Oak logs: 1 (primary, completes once)
      expect(oakLogsCount, 1);
      // Normal logs: M_Action = floor(40/30) = 1 (both fixed duration)
      // (M_Action multiplier scales the secondary tree's output)
      expect(normalLogsCount, greaterThanOrEqualTo(1));
    });

    test('XP is awarded for both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 40, random: random);
      state = builder.build();

      // Woodcutting XP should include both trees' contributions
      final wcXp = state.skillState(Skill.woodcutting).xp;
      // Primary (oak) XP + secondary (normal) XP * M_Action
      expect(wcXp, greaterThan(oakTree.xp));
    });

    test('mastery is awarded for both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 40, random: random);
      state = builder.build();

      // Both trees should gain mastery XP
      final oakMastery = state.actionState(oakTree.id).masteryXp;
      final normalMastery = state.actionState(normalTree.id).masteryXp;
      expect(oakMastery, greaterThan(0));
      expect(normalMastery, greaterThan(0));
    });

    test('without Multi_Tree purchase, second tree starts alone', () {
      final random = Random(0);
      var state = GlobalState.empty(testRegistries);

      // Start normal tree first
      state = state.startAction(normalTree, random: random);
      expect(state.isActionActive(normalTree), isTrue);

      // Start oak tree - should replace normal tree (no multi-tree)
      state = state.startAction(oakTree, random: random);
      expect(state.isActionActive(oakTree), isTrue);
      expect(state.isActionActive(normalTree), isFalse);

      final activity = state.activeActivity! as SkillActivity;
      expect(activity.secondaryActionId, isNull);
    });

    test('clicking active primary tree stops both', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // isActionActive returns true for both
      expect(state.isActionActive(oakTree), isTrue);
      expect(state.isActionActive(normalTree), isTrue);

      // Clear action (simulates clicking active tree)
      state = state.clearAction();
      expect(state.activeActivity, isNull);
      expect(state.isActionActive(oakTree), isFalse);
      expect(state.isActionActive(normalTree), isFalse);
    });

    test('JSON round-trip preserves secondaryActionId', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // Serialize and deserialize
      final json = state.toJson();
      final restored = GlobalState.fromJson(testRegistries, json);

      final activity = restored.activeActivity! as SkillActivity;
      expect(activity.secondaryActionId, isNotNull);
      expect(activity.actionId, oakTree.id.localId);
      expect(activity.secondaryActionId, normalTree.id.localId);
    });

    test('restart uses max duration of both trees', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // Complete one cycle and let it restart
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 40, random: random);
      state = builder.build();

      // After restart, should still have multi-tree active
      final activity = state.activeActivity! as SkillActivity;
      expect(activity.secondaryActionId, normalTree.id.localId);
      // totalTicks should be max of both trees' durations (40 for Oak)
      expect(activity.totalTicks, 40);
    });

    test('multiple completions accumulate correctly', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      // Complete 3 cycles (3 * 40 = 120 ticks)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 120, random: random);
      state = builder.build();

      // Oak logs should be at least 3
      final oakLogsCount = state.inventory.countOfItem(oakLogs);
      expect(oakLogsCount, greaterThanOrEqualTo(3));

      // Normal logs should be at least 3 (M_Action=1 * 3 cycles)
      final normalLogsCount = state.inventory.countOfItem(normalLogs);
      expect(normalLogsCount, greaterThanOrEqualTo(3));
    });

    test('secondaryWoodcuttingActionId returns correct ID', () {
      final random = Random(0);
      var state = stateWithMultiTree();
      state = state.startMultiTreeWoodcutting(
        normalTree,
        oakTree,
        random: random,
      );

      expect(state.secondaryWoodcuttingActionId, normalTree.id);
    });

    test('secondaryWoodcuttingActionId returns null for single tree', () {
      final random = Random(0);
      var state = GlobalState.empty(testRegistries);
      state = state.startAction(normalTree, random: random);

      expect(state.secondaryWoodcuttingActionId, isNull);
    });
  });
}
