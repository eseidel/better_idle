import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/execution/prerequisites.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
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
