import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('Changes', () {
    group('merge', () {
      test('merges empty changes', () {
        const c1 = Changes.empty();
        const c2 = Changes.empty();
        final merged = c1.merge(c2);
        expect(merged.isEmpty, isTrue);
      });

      test('merges inventory changes', () {
        final itemId = MelvorId('melvorD:Normal_Logs');
        final c1 = const Changes.empty().merge(
          Changes(
            inventoryChanges: Counts(counts: {itemId: 10}),
            skillXpChanges: const Counts.empty(),
            droppedItems: const Counts.empty(),
            skillLevelChanges: const LevelChanges.empty(),
          ),
        );
        final c2 = Changes(
          inventoryChanges: Counts(counts: {itemId: 5}),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
        );
        final merged = c1.merge(c2);
        expect(merged.inventoryChanges.counts[itemId], 15);
      });

      test('merges skill xp changes', () {
        final c1 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts(counts: {Skill.woodcutting: 100}),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
        );
        final c2 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts(counts: {Skill.woodcutting: 50}),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
        );
        final merged = c1.merge(c2);
        expect(merged.skillXpChanges.counts[Skill.woodcutting], 150);
      });

      test('merges currencies gained', () {
        final c1 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {Currency.gp: 1000},
        );
        final c2 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {Currency.gp: 500},
        );
        final merged = c1.merge(c2);
        expect(merged.currenciesGained[Currency.gp], 1500);
      });

      test('merges multiple currency types', () {
        final c1 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {Currency.gp: 1000, Currency.slayerCoins: 50},
        );
        final c2 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {Currency.gp: 500, Currency.raidCoins: 100},
        );
        final merged = c1.merge(c2);
        expect(merged.currenciesGained[Currency.gp], 1500);
        expect(merged.currenciesGained[Currency.slayerCoins], 50);
        expect(merged.currenciesGained[Currency.raidCoins], 100);
      });

      test('merges currencies with empty', () {
        final c1 = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {Currency.gp: 1000},
        );
        const c2 = Changes.empty();
        final merged = c1.merge(c2);
        expect(merged.currenciesGained[Currency.gp], 1000);
      });

      test('addingCurrency adds to currencies gained', () {
        const c1 = Changes.empty();
        final c2 = c1.addingCurrency(Currency.gp, 100);
        expect(c2.currenciesGained[Currency.gp], 100);

        final c3 = c2.addingCurrency(Currency.gp, 50);
        expect(c3.currenciesGained[Currency.gp], 150);
      });
    });

    group('serialization', () {
      test('currencies round-trip through JSON', () {
        final original = Changes(
          inventoryChanges: const Counts.empty(),
          skillXpChanges: const Counts.empty(),
          droppedItems: const Counts.empty(),
          skillLevelChanges: const LevelChanges.empty(),
          currenciesGained: const {
            Currency.gp: 1000,
            Currency.slayerCoins: 50,
            Currency.raidCoins: 25,
          },
        );
        final json = original.toJson();
        final loaded = Changes.fromJson(json);

        expect(loaded.currenciesGained[Currency.gp], 1000);
        expect(loaded.currenciesGained[Currency.slayerCoins], 50);
        expect(loaded.currenciesGained[Currency.raidCoins], 25);
      });
    });
  });

  late SkillAction normalTree;

  setUpAll(() async {
    await loadTestRegistries();
    normalTree = testActions.byName('Normal Tree') as SkillAction;
  });

  test('TimeAway duration does not update on mergeChanges', () {
    final startTime = DateTime(2024, 1, 1, 12);
    final endTime = startTime.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime,
      endTime: endTime,
    );
    final t2 = t1.mergeChanges(const Changes.empty());

    expect(t2.duration, const Duration(seconds: 10));
  });

  test('TimeAway merge updates endTime to the latest endTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime1,
      endTime: endTime1,
    );

    final startTime2 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime2 = startTime2.add(const Duration(seconds: 15));
    final t2 = TimeAway.test(
      testRegistries,
      startTime: startTime2,
      endTime: endTime2,
    );

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime1);
    expect(merged.endTime, endTime2);
    expect(merged.duration, const Duration(seconds: 20));
  });

  test('TimeAway merge updates startTime to the earliest startTime', () {
    final startTime1 = DateTime(2024, 1, 1, 12, 0, 5);
    final endTime1 = startTime1.add(const Duration(seconds: 10));
    final t1 = TimeAway.test(
      testRegistries,
      startTime: startTime1,
      endTime: endTime1,
    );

    final startTime2 = DateTime(2024, 1, 1, 12);
    final endTime2 = startTime2.add(const Duration(seconds: 8));
    final t2 = TimeAway.test(
      testRegistries,
      startTime: startTime2,
      endTime: endTime2,
    );

    final merged = t1.maybeMergeInto(t2);

    // Merged should have the earliest startTime and latest endTime
    expect(merged.startTime, startTime2);
    expect(merged.endTime, endTime1);
    expect(merged.duration, const Duration(seconds: 15));
  });

  group('TimeAway serialization', () {
    test('round-trips with currencies in changes', () {
      final startTime = DateTime(2024, 1, 1, 12);
      final endTime = startTime.add(const Duration(hours: 1));
      final changes = Changes(
        inventoryChanges: Counts(
          counts: {MelvorId('melvorD:Normal_Logs'): 100},
        ),
        skillXpChanges: const Counts(counts: {Skill.woodcutting: 500}),
        droppedItems: const Counts.empty(),
        skillLevelChanges: const LevelChanges.empty(),
        currenciesGained: const {
          Currency.gp: 5000,
          Currency.slayerCoins: 100,
          Currency.raidCoins: 50,
        },
      );
      final original = TimeAway.test(
        testRegistries,
        startTime: startTime,
        endTime: endTime,
        activeSkill: Skill.woodcutting,
        activeAction: normalTree,
        changes: changes,
      );

      final json = original.toJson();
      final loaded = TimeAway.fromJson(testRegistries, json);

      expect(loaded.startTime, startTime);
      expect(loaded.endTime, endTime);
      expect(loaded.activeSkill, Skill.woodcutting);
      expect(loaded.changes.currenciesGained[Currency.gp], 5000);
      expect(loaded.changes.currenciesGained[Currency.slayerCoins], 100);
      expect(loaded.changes.currenciesGained[Currency.raidCoins], 50);
      expect(
        loaded.changes.inventoryChanges.counts[MelvorId('melvorD:Normal_Logs')],
        100,
      );
      expect(loaded.changes.skillXpChanges.counts[Skill.woodcutting], 500);
    });
  });

  group('itemsConsumedPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = testActions.byName('Plant') as CombatAction;
      final timeAway = TimeAway.test(testRegistries, activeAction: plantAction);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns empty map for action with no inputs', () {
      // Woodcutting has no inputs
      final timeAway = TimeAway.test(testRegistries, activeAction: normalTree);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns correct items per hour for action with inputs', () {
      // Firemaking: "Burn Normal Logs" takes 2 seconds and consumes 1 Normal Logs
      // Actions per hour = 3600 / 2 = 1800
      // Items consumed per hour = 1 * 1800 = 1800
      final burnNormalLogs =
          testActions.byName('Burn Normal Logs') as SkillAction;
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: burnNormalLogs,
      );

      final itemsPerHour = timeAway.itemsConsumedPerHour;
      expect(itemsPerHour[MelvorId('melvorD:Normal_Logs')], closeTo(1800, 1));
    });
  });

  group('itemsGainedPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.itemsGainedPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = testActions.byName('Plant') as CombatAction;
      final timeAway = TimeAway.test(testRegistries, activeAction: plantAction);
      expect(timeAway.itemsGainedPerHour, isEmpty);
    });

    test('returns correct items per hour for skill action', () {
      // Normal Tree takes 3 seconds per action and outputs 1 Normal Logs
      // Actions per hour = 3600 / 3 = 1200
      // Items per hour = 1 * 1200 = 1200
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {normalTree.id: 0},
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour[MelvorId('melvorD:Normal_Logs')], closeTo(1200, 1));
    });

    test('includes skill-level drops in calculation', () {
      // Woodcutting has a Bird Nest drop at 0.5% rate
      // Normal Tree: 1200 actions per hour
      // Bird Nest expected per hour = 1200 * 0.005 = 6
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {normalTree.id: 0},
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour[MelvorId('melvorD:Bird_Nest')], closeTo(6, 0.1));
    });

    test('accounts for doubling chance', () {
      // With 40% doubling chance:
      // Expected logs = 1 * (1 + 0.40) = 1.40 per action
      // Items per hour = 1.40 * 1200 = 1680
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        masteryLevels: {normalTree.id: 80},
        doublingChance: 0.40,
      );

      final itemsPerHour = timeAway.itemsGainedPerHour;
      expect(itemsPerHour[MelvorId('melvorD:Normal_Logs')], 1680);
    });
  });
}
