import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/execution/prerequisites.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('ensureExecutable', () {
    test('returns ExecReady for action with no prerequisites', () {
      // Woodcutting Normal Tree requires no inputs and level 1
      final state = GlobalState.empty(testRegistries);
      final normalTree = testActions.woodcutting('Normal Tree');
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);

      final result = ensureExecutable(state, normalTree.id, goal);

      expect(result, isA<ExecReady>());
    });

    test('returns ExecNeedsMacros when action requires higher skill level', () {
      // Oak Tree requires level 15 woodcutting
      final state = GlobalState.empty(testRegistries);
      final oakTree = testActions.woodcutting('Oak Tree');
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 20);

      final result = ensureExecutable(state, oakTree.id, goal);

      expect(result, isA<ExecNeedsMacros>());
      final needsMacros = result as ExecNeedsMacros;
      expect(needsMacros.macros, hasLength(1));

      final macro = needsMacros.macros.first;
      expect(macro, isA<TrainSkillUntil>());
      final trainMacro = macro as TrainSkillUntil;
      expect(trainMacro.skill, equals(Skill.woodcutting));
      expect(trainMacro.primaryStop, isA<StopAtLevel>());
      final stop = trainMacro.primaryStop as StopAtLevel;
      expect(stop.level, equals(oakTree.unlockLevel));
    });

    test('returns ExecNeedsMacros for locked producer of required input', () {
      // Steel Dagger requires Steel Bar, which requires Smithing level 30
      // At level 1, we can't smelt Steel Bars, so ensureExecutable should
      // return macros to train Smithing to unlock Steel Bar production.
      final state = GlobalState.empty(testRegistries);
      final steelDagger = testActions.smithing('Steel Dagger');
      const goal = ReachSkillLevelGoal(Skill.smithing, 50);

      // Verify that Steel Dagger requires Steel Bar
      final steelBarId = testItems.byName('Steel Bar').id;
      expect(steelDagger.inputs.containsKey(steelBarId), isTrue);

      // Verify that Steel Bar producer (Smelt Steel Bar) is locked at level 1
      final smeltSteelBar = testActions.smithing('Steel Bar');
      expect(smeltSteelBar.unlockLevel, greaterThan(1));

      final result = ensureExecutable(state, steelDagger.id, goal);

      expect(result, isA<ExecNeedsMacros>());
      final needsMacros = result as ExecNeedsMacros;

      // Should have macro(s) to train Smithing to unlock Steel Bar production
      // and potentially Steel Dagger itself (it requires level 35)
      expect(needsMacros.macros, isNotEmpty);

      // At least one macro should be training Smithing
      final smithingMacros = needsMacros.macros
          .whereType<TrainSkillUntil>()
          .where((m) => m.skill == Skill.smithing);
      expect(smithingMacros, isNotEmpty);
    });

    test('returns ExecReady when inputs already in inventory', () {
      // Give the player enough Bronze Bars to make a Bronze Dagger
      final bronzeBar = testItems.byName('Bronze Bar');
      final inventory = Inventory.fromItems(testItems, [
        ItemStack(bronzeBar, count: 10),
      ]);
      final state = GlobalState.test(testRegistries, inventory: inventory);
      final bronzeDagger = testActions.smithing('Bronze Dagger');
      const goal = ReachSkillLevelGoal(Skill.smithing, 10);

      final result = ensureExecutable(state, bronzeDagger.id, goal);

      // Should be ready since we have the inputs
      expect(result, isA<ExecReady>());
    });

    test('handles depth limit by returning ExecUnknown', () {
      final state = GlobalState.empty(testRegistries);
      final bronzeDagger = testActions.smithing('Bronze Dagger');
      const goal = ReachSkillLevelGoal(Skill.smithing, 10);

      // Force a very low depth limit
      final result = ensureExecutable(
        state,
        bronzeDagger.id,
        goal,
        maxDepth: 0,
      );

      expect(result, isA<ExecUnknown>());
      final unknown = result as ExecUnknown;
      expect(unknown.reason, contains('depth limit'));
    });
  });

  group('ExecNeedsMacros', () {
    group('deduplication', () {
      test('removes duplicate macros with same dedupeKey', () {
        // Create two TrainSkillUntil macros with identical dedupeKey
        // (same skill and same primaryStop)
        const stop = StopAtLevel(Skill.mining, 10);
        const macro1 = TrainSkillUntil(Skill.mining, stop);
        const macro2 = TrainSkillUntil(Skill.mining, stop);

        // Verify they have the same dedupeKey
        expect(macro1.dedupeKey, equals(macro2.dedupeKey));

        // Create ExecNeedsMacros with duplicates
        final result = ExecNeedsMacros([macro1, macro2]);

        // Should only contain one macro after dedup
        expect(result.macros, hasLength(1));
        expect(result.macros.first, equals(macro1));
      });

      test('keeps macros with different dedupeKeys', () {
        // Create macros with different dedupeKeys
        const miningStop = StopAtLevel(Skill.mining, 10);
        const woodcuttingStop = StopAtLevel(Skill.woodcutting, 15);
        const macro1 = TrainSkillUntil(Skill.mining, miningStop);
        const macro2 = TrainSkillUntil(Skill.woodcutting, woodcuttingStop);

        // Verify they have different dedupeKeys
        expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));

        // Create ExecNeedsMacros with different macros
        final result = ExecNeedsMacros([macro1, macro2]);

        // Should keep both macros
        expect(result.macros, hasLength(2));
      });

      test('preserves order and keeps first occurrence', () {
        // Create three macros where first and third are duplicates
        const stopA = StopAtLevel(Skill.mining, 10);
        const stopB = StopAtLevel(Skill.woodcutting, 15);
        const macro1 = TrainSkillUntil(Skill.mining, stopA);
        const macro2 = TrainSkillUntil(Skill.woodcutting, stopB);
        const macro3 = TrainSkillUntil(
          Skill.mining,
          stopA,
        ); // duplicate of macro1

        final result = ExecNeedsMacros([macro1, macro2, macro3]);

        // Should contain macro1 and macro2 (macro3 deduplicated)
        expect(result.macros, hasLength(2));
        expect(result.macros[0].dedupeKey, equals(macro1.dedupeKey));
        expect(result.macros[1].dedupeKey, equals(macro2.dedupeKey));
      });

      test('dedupes macros with same skill but different stop levels', () {
        // Different stop levels produce different hashCodes -> different keys
        const stop10 = StopAtLevel(Skill.mining, 10);
        const stop20 = StopAtLevel(Skill.mining, 20);
        const macro1 = TrainSkillUntil(Skill.mining, stop10);
        const macro2 = TrainSkillUntil(Skill.mining, stop20);

        // These should have different dedupeKeys due to different hashCodes
        expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));

        final result = ExecNeedsMacros([macro1, macro2]);

        // Both should be kept (different targets)
        expect(result.macros, hasLength(2));
      });

      test('handles empty list', () {
        final result = ExecNeedsMacros([]);
        expect(result.macros, isEmpty);
      });

      test('handles single macro', () {
        const stop = StopAtLevel(Skill.mining, 10);
        const macro = TrainSkillUntil(Skill.mining, stop);

        final result = ExecNeedsMacros([macro]);

        expect(result.macros, hasLength(1));
        expect(result.macros.first, equals(macro));
      });

      test('dedupes multiple occurrences of same macro', () {
        const stop = StopAtLevel(Skill.fishing, 25);
        const macro = TrainSkillUntil(Skill.fishing, stop);

        // Pass 5 copies of the same macro
        final result = ExecNeedsMacros([macro, macro, macro, macro, macro]);

        // Should dedupe to just one
        expect(result.macros, hasLength(1));
      });
    });
  });
}
