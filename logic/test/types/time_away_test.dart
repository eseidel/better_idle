import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  group('LevelChange', () {
    test('fromJson and toJson round-trip', () {
      const original = LevelChange(startLevel: 10, endLevel: 20);
      final json = original.toJson();
      final restored = LevelChange.fromJson(json);
      expect(restored.startLevel, 10);
      expect(restored.endLevel, 20);
      expect(restored.levelsGained, 10);
    });

    test('merge is order-independent', () {
      // Earlier change: level 54 -> 55
      const earlier = LevelChange(startLevel: 54, endLevel: 55);
      // Later change: level 55 -> 56
      const later = LevelChange(startLevel: 55, endLevel: 56);

      // Both orders should produce the same result: 54 -> 56
      final mergeEarlierFirst = earlier.merge(later);
      final mergeLaterFirst = later.merge(earlier);

      expect(mergeEarlierFirst.startLevel, 54);
      expect(mergeEarlierFirst.endLevel, 56);
      expect(mergeLaterFirst.startLevel, 54);
      expect(mergeLaterFirst.endLevel, 56);
    });

    test('merge handles non-contiguous level ranges', () {
      // Player leveled 10 -> 15, then 20 -> 25 (skipped some in between)
      const first = LevelChange(startLevel: 10, endLevel: 15);
      const second = LevelChange(startLevel: 20, endLevel: 25);

      // Merge should take min start (10) and max end (25)
      final merged = first.merge(second);
      expect(merged.startLevel, 10);
      expect(merged.endLevel, 25);
    });

    test('merge with identical ranges returns same range', () {
      const change = LevelChange(startLevel: 50, endLevel: 55);

      final merged = change.merge(change);
      expect(merged.startLevel, 50);
      expect(merged.endLevel, 55);
    });
  });

  group('Changes', () {
    group('merge', () {
      test('merges empty changes', () {
        const c1 = Changes.empty();
        const c2 = Changes.empty();
        final merged = c1.merge(c2);
        expect(merged.isEmpty, isTrue);
      });

      test('merges inventory changes', () {
        const itemId = MelvorId('melvorD:Normal_Logs');
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
        const c1 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts(counts: {Skill.woodcutting: 100}),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
        );
        const c2 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts(counts: {Skill.woodcutting: 50}),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
        );
        final merged = c1.merge(c2);
        expect(merged.skillXpChanges.counts[Skill.woodcutting], 150);
      });

      test('merges currencies gained', () {
        const c1 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {Currency.gp: 1000},
        );
        const c2 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {Currency.gp: 500},
        );
        final merged = c1.merge(c2);
        expect(merged.currenciesGained[Currency.gp], 1500);
      });

      test('merges multiple currency types', () {
        const c1 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {Currency.gp: 1000, Currency.slayerCoins: 50},
        );
        const c2 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {Currency.gp: 500, Currency.raidCoins: 100},
        );
        final merged = c1.merge(c2);
        expect(merged.currenciesGained[Currency.gp], 1500);
        expect(merged.currenciesGained[Currency.slayerCoins], 50);
        expect(merged.currenciesGained[Currency.raidCoins], 100);
      });

      test('merges currencies with empty', () {
        const c1 = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {Currency.gp: 1000},
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
        const original = Changes(
          inventoryChanges: Counts.empty(),
          skillXpChanges: Counts.empty(),
          droppedItems: Counts.empty(),
          skillLevelChanges: LevelChanges.empty(),
          currenciesGained: {
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
    normalTree = testRegistries.woodcuttingAction('Normal Tree');
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
          counts: {const MelvorId('melvorD:Normal_Logs'): 100},
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
        loaded.changes.inventoryChanges.counts[const MelvorId(
          'melvorD:Normal_Logs',
        )],
        100,
      );
      expect(loaded.changes.skillXpChanges.counts[Skill.woodcutting], 500);
    });
  });

  group('TimeAway.empty', () {
    test('creates empty time away', () {
      final empty = TimeAway.empty(testRegistries);
      expect(empty.activeSkill, isNull);
      expect(empty.activeAction, isNull);
      expect(empty.changes.isEmpty, isTrue);
      expect(empty.masteryLevels, isEmpty);
      expect(empty.startTime.millisecondsSinceEpoch, 0);
      expect(empty.endTime.millisecondsSinceEpoch, 0);
    });
  });

  group('predictedXpPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.predictedXpPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = testRegistries.combatAction('Plant');
      final timeAway = TimeAway.test(testRegistries, activeAction: plantAction);
      expect(timeAway.predictedXpPerHour, isEmpty);
    });

    test('returns correct xp per hour for skill action', () {
      // Normal Tree: 3 seconds per action, 10 xp per action
      // XP per hour = 10 * (3600 / 3) = 12000
      final timeAway = TimeAway.test(testRegistries, activeAction: normalTree);
      final xpPerHour = timeAway.predictedXpPerHour;
      expect(xpPerHour[Skill.woodcutting], isNotNull);
      expect(xpPerHour[Skill.woodcutting]!, greaterThan(0));
    });
  });

  group('levelForMastery', () {
    test('returns 0 for unknown action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(
        timeAway.levelForMastery(
          const ActionId(
            MelvorId('melvorD:Woodcutting'),
            MelvorId('melvorD:Unknown'),
          ),
        ),
        0,
      );
    });
  });

  group('TimeAway.maybeMergeInto', () {
    test('returns self when other is null', () {
      final t = TimeAway.test(testRegistries);
      expect(t.maybeMergeInto(null), same(t));
    });

    test('merges mastery levels taking higher values', () {
      final actionId = normalTree.id;
      final t1 = TimeAway.test(testRegistries, masteryLevels: {actionId: 5});
      final t2 = TimeAway.test(testRegistries, masteryLevels: {actionId: 10});
      final merged = t1.maybeMergeInto(t2);
      expect(merged.masteryLevels[actionId], 10);
    });

    test('merges stop reason preferring non-stillRunning', () {
      final t1 = TimeAway.test(
        testRegistries,
        stopReason: ActionStopReason.outOfInputs,
      );
      final t2 = TimeAway.test(testRegistries);
      final merged = t1.maybeMergeInto(t2);
      expect(merged.stopReason, ActionStopReason.outOfInputs);
    });

    test('merges stoppedAfter preferring non-null', () {
      final t1 = TimeAway.test(
        testRegistries,
        stoppedAfter: const Duration(seconds: 30),
      );
      final t2 = TimeAway.test(testRegistries);
      final merged = t1.maybeMergeInto(t2);
      expect(merged.stoppedAfter, const Duration(seconds: 30));
    });

    test('merges doubling chance taking higher', () {
      final t1 = TimeAway.test(testRegistries, doublingChance: 0.3);
      final t2 = TimeAway.test(testRegistries, doublingChance: 0.5);
      final merged = t1.maybeMergeInto(t2);
      expect(merged.doublingChance, 0.5);
    });

    test('merges recipe selection preferring SelectedRecipe', () {
      final t1 = TimeAway.test(
        testRegistries,
        recipeSelection: const SelectedRecipe(index: 2),
      );
      final t2 = TimeAway.test(testRegistries);
      final merged = t1.maybeMergeInto(t2);
      expect(merged.recipeSelection, isA<SelectedRecipe>());
    });

    test('merges pending loot preferring non-empty', () {
      final item = testRegistries.items.byName('Normal Logs');
      final stack = ItemStack(item, count: 5);
      final (loot, _) = const LootState.empty().addItem(stack, isBones: false);
      final t1 = TimeAway.test(testRegistries, pendingLoot: loot);
      final t2 = TimeAway.test(testRegistries);
      final merged = t1.maybeMergeInto(t2);
      expect(merged.pendingLoot.isNotEmpty, isTrue);
    });
  });

  group('TimeAway toJson with stop/recipe fields', () {
    test('serializes stopReason and stoppedAfter', () {
      final t = TimeAway.test(
        testRegistries,
        activeAction: normalTree,
        activeSkill: Skill.woodcutting,
        stopReason: ActionStopReason.outOfInputs,
        stoppedAfter: const Duration(seconds: 45),
        recipeSelection: const SelectedRecipe(index: 1),
      );
      final json = t.toJson();
      expect(json['stopReason'], 'outOfInputs');
      expect(json['stoppedAfterMs'], 45000);
      expect(json['recipeIndex'], 1);

      // Round-trip
      final restored = TimeAway.fromJson(testRegistries, json);
      expect(restored.stopReason, ActionStopReason.outOfInputs);
      expect(restored.stoppedAfter, const Duration(seconds: 45));
      expect(restored.recipeSelection, isA<SelectedRecipe>());
    });

    test('fromJson handles unknown stopReason gracefully', () {
      final json = TimeAway.test(testRegistries).toJson();
      json['stopReason'] = 'unknownFutureReason';
      final restored = TimeAway.fromJson(testRegistries, json);
      expect(restored.stopReason, ActionStopReason.stillRunning);
    });
  });

  group('Counts', () {
    test('entries returns map entries', () {
      const counts = Counts<Skill>(counts: {Skill.woodcutting: 10});
      expect(counts.entries.length, 1);
      expect(counts.isNotEmpty, isTrue);
    });

    test('toJson and fromJson with MelvorId keys', () {
      final counts = Counts<MelvorId>(
        counts: {const MelvorId('melvorD:Normal_Logs'): 5},
      );
      final json = counts.toJson();
      final restored = Counts<MelvorId>.fromJson(json);
      expect(restored.counts[const MelvorId('melvorD:Normal_Logs')], 5);
    });
  });

  group('LevelChanges', () {
    test('fromJson round-trips', () {
      final original = LevelChanges(
        changes: {
          Skill.woodcutting: const LevelChange(startLevel: 1, endLevel: 5),
        },
      );
      final json = original.toJson();
      final restored = LevelChanges.fromJson(json);
      expect(restored.changes[Skill.woodcutting]!.startLevel, 1);
      expect(restored.changes[Skill.woodcutting]!.endLevel, 5);
    });

    test('add merges overlapping skills', () {
      final a = LevelChanges(
        changes: {
          Skill.woodcutting: const LevelChange(startLevel: 1, endLevel: 5),
        },
      );
      final b = LevelChanges(
        changes: {
          Skill.woodcutting: const LevelChange(startLevel: 3, endLevel: 8),
        },
      );
      final merged = a.add(b);
      expect(merged.changes[Skill.woodcutting]!.startLevel, 1);
      expect(merged.changes[Skill.woodcutting]!.endLevel, 8);
    });

    test('add merges disjoint skills', () {
      final a = LevelChanges(
        changes: {
          Skill.woodcutting: const LevelChange(startLevel: 1, endLevel: 5),
        },
      );
      final b = LevelChanges(
        changes: {
          Skill.mining: const LevelChange(startLevel: 10, endLevel: 15),
        },
      );
      final merged = a.add(b);
      expect(merged.changes[Skill.woodcutting]!.endLevel, 5);
      expect(merged.changes[Skill.mining]!.startLevel, 10);
    });

    test('entries and isNotEmpty', () {
      final lc = LevelChanges(
        changes: {
          Skill.woodcutting: const LevelChange(startLevel: 1, endLevel: 2),
        },
      );
      expect(lc.entries.length, 1);
      expect(lc.isNotEmpty, isTrue);
    });
  });

  group('Changes tracking methods', () {
    test('losingOnDeath tracks lost items', () {
      final item = testRegistries.items.byName('Normal Logs');
      final changes = const Changes.empty().losingOnDeath(
        ItemStack(item, count: 3),
      );
      expect(changes.lostOnDeath.counts[item.id], 3);
    });
  });

  group('itemsConsumedPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = testRegistries.combatAction('Plant');
      final timeAway = TimeAway.test(testRegistries, activeAction: plantAction);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns empty map for action with no inputs', () {
      // Woodcutting has no inputs
      final timeAway = TimeAway.test(testRegistries, activeAction: normalTree);
      expect(timeAway.itemsConsumedPerHour, isEmpty);
    });

    test('returns correct items per hour for action with inputs', () {
      // "Burn Normal Logs" takes 2 seconds and consumes 1 Normal Logs
      // Actions per hour = 3600 / 2 = 1800
      // Items consumed per hour = 1 * 1800 = 1800
      final burnNormalLogs = testRegistries.firemakingAction(
        'Burn Normal Logs',
      );
      final timeAway = TimeAway.test(
        testRegistries,
        activeAction: burnNormalLogs,
      );

      final itemsPerHour = timeAway.itemsConsumedPerHour;
      expect(
        itemsPerHour[const MelvorId('melvorD:Normal_Logs')],
        closeTo(1800, 1),
      );
    });
  });

  group('itemsGainedPerHour', () {
    test('returns empty map when no active action', () {
      final timeAway = TimeAway.test(testRegistries);
      expect(timeAway.itemsGainedPerHour, isEmpty);
    });

    test('returns empty map for combat action', () {
      final plantAction = testRegistries.combatAction('Plant');
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
      expect(
        itemsPerHour[const MelvorId('melvorD:Normal_Logs')],
        closeTo(1200, 1),
      );
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
      expect(
        itemsPerHour[const MelvorId('melvorD:Bird_Nest')],
        closeTo(6, 0.1),
      );
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
      expect(itemsPerHour[const MelvorId('melvorD:Normal_Logs')], 1680);
    });
  });
}
