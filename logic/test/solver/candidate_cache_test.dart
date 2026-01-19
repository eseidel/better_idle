import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/candidate_cache.dart';
import 'package:logic/src/solver/candidates/enumerate_candidates.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('CandidateCacheKey', () {
    group('equality', () {
      test('identical states produce equal keys', () {
        final state = GlobalState.empty(testRegistries);
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        final key1 = CandidateCacheKey.fromState(state, goal);
        final key2 = CandidateCacheKey.fromState(state, goal);

        expect(key1, equals(key2));
        expect(key1.hashCode, equals(key2.hashCode));
      });

      test('different skill levels produce different keys', () {
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        final state1 = GlobalState.empty(testRegistries);
        final state2 = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
            // Level 10 woodcutting
            Skill.woodcutting: SkillState(xp: 1154, masteryPoolXp: 0),
          },
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1, isNot(equals(key2)));
      });

      test('different inventory buckets produce different keys', () {
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        // Empty inventory (bucket 0)
        final state1 = GlobalState.empty(testRegistries);

        // Full inventory (bucket 4) - fill all 12 slots with different items
        final fillerItems = <ItemStack>[];
        var i = 0;
        for (final item in testItems.all) {
          if (i >= 12) break;
          fillerItems.add(ItemStack(item, count: 1));
          i++;
        }
        final state2 = GlobalState.test(
          testRegistries,
          inventory: Inventory.fromItems(testItems, fillerItems),
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1.inventoryBucket, equals(0));
        // Bucket 3 or 4 depending on exact capacity, just verify different
        expect(key2.inventoryBucket, greaterThan(key1.inventoryBucket));
        expect(key1, isNot(equals(key2)));
      });

      test('same state with different active action produces same key', () {
        // Capability cache does NOT include activeActionId in the key
        // It's filtered dynamically instead
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        final state1 = GlobalState.empty(testRegistries);
        final normalTree = testRegistries.woodcuttingAction('Normal Tree');
        final state2 = state1.copyWith(
          activeActivity: SkillActivity(
            skill: Skill.woodcutting,
            actionId: normalTree.id.localId,
            progressTicks: 0,
            totalTicks: 10,
          ),
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        // Keys should be equal - activeActionId is not part of the key
        expect(key1, equals(key2));
      });
    });

    group('upgrade tiers', () {
      test('tracks multiple upgrades for woodcutting goal', () {
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        // State with no upgrades
        final state1 = GlobalState.empty(testRegistries);

        // State with Iron and Steel axes purchased
        final state2 = GlobalState.test(
          testRegistries,
          shop: ShopState(
            purchaseCounts: {
              const MelvorId('melvorD:Iron_Axe'): 1,
              const MelvorId('melvorD:Steel_Axe'): 1,
            },
          ),
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1.upgradeTiers[Skill.woodcutting], equals(0));
        expect(key2.upgradeTiers[Skill.woodcutting], equals(2));
        expect(key1, isNot(equals(key2)));
      });

      test('tracks multiple upgrades across different skills', () {
        const goal = ReachGpGoal(10000);

        // State with upgrades for multiple skills
        final state = GlobalState.test(
          testRegistries,
          shop: ShopState(
            purchaseCounts: {
              // 3 woodcutting upgrades
              const MelvorId('melvorD:Iron_Axe'): 1,
              const MelvorId('melvorD:Steel_Axe'): 1,
              const MelvorId('melvorD:Mithril_Axe'): 1,
              // 2 mining upgrades
              const MelvorId('melvorD:Iron_Pickaxe'): 1,
              const MelvorId('melvorD:Steel_Pickaxe'): 1,
            },
          ),
        );

        final key = CandidateCacheKey.fromState(state, goal);

        expect(key.upgradeTiers[Skill.woodcutting], equals(3));
        expect(key.upgradeTiers[Skill.mining], equals(2));
      });

      test('different upgrade counts produce different keys', () {
        const goal = ReachSkillLevelGoal(Skill.mining, 30);

        // State with 1 pickaxe upgrade
        final state1 = GlobalState.test(
          testRegistries,
          shop: ShopState(
            purchaseCounts: {const MelvorId('melvorD:Iron_Pickaxe'): 1},
          ),
        );

        // State with 3 pickaxe upgrades
        final state2 = GlobalState.test(
          testRegistries,
          shop: ShopState(
            purchaseCounts: {
              const MelvorId('melvorD:Iron_Pickaxe'): 1,
              const MelvorId('melvorD:Steel_Pickaxe'): 1,
              const MelvorId('melvorD:Mithril_Pickaxe'): 1,
            },
          ),
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1.upgradeTiers[Skill.mining], equals(1));
        expect(key2.upgradeTiers[Skill.mining], equals(3));
        expect(key1, isNot(equals(key2)));
      });

      test('same upgrades produce equal keys', () {
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

        final shopState = ShopState(
          purchaseCounts: {
            const MelvorId('melvorD:Iron_Axe'): 1,
            const MelvorId('melvorD:Steel_Axe'): 1,
          },
        );

        final state1 = GlobalState.test(testRegistries, shop: shopState);
        final state2 = GlobalState.test(testRegistries, shop: shopState);

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1, equals(key2));
        expect(key1.hashCode, equals(key2.hashCode));
      });
    });

    group('producer skill levels', () {
      test('includes woodcutting level for firemaking goal', () {
        const goal = ReachSkillLevelGoal(Skill.firemaking, 30);

        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
            // High level woodcutting
            Skill.woodcutting: SkillState(xp: 8740, masteryPoolXp: 0),
          },
        );

        final key = CandidateCacheKey.fromState(state, goal);

        // Should include both firemaking and woodcutting levels
        expect(key.skillLevelBucket[Skill.firemaking], equals(1));
        // Woodcutting should be tracked at a high level (> 1)
        expect(key.skillLevelBucket[Skill.woodcutting], greaterThan(1));
      });

      test('different producer levels produce different keys', () {
        const goal = ReachSkillLevelGoal(Skill.firemaking, 30);

        // Level 1 woodcutting
        final state1 = GlobalState.empty(testRegistries);

        // Higher level woodcutting
        final state2 = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
            Skill.woodcutting: SkillState(xp: 8740, masteryPoolXp: 0),
          },
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1.skillLevelBucket[Skill.woodcutting], equals(1));
        expect(
          key2.skillLevelBucket[Skill.woodcutting],
          greaterThan(key1.skillLevelBucket[Skill.woodcutting]!),
        );
        expect(key1, isNot(equals(key2)));
      });
    });

    group('ReachGpGoal', () {
      test('tracks all skills in key', () {
        const goal = ReachGpGoal(10000);
        final state = GlobalState.empty(testRegistries);

        final key = CandidateCacheKey.fromState(state, goal);

        // GP goals track all skills
        expect(key.skillLevelBucket.keys, containsAll(Skill.values));
      });

      test('different skill levels produce different keys', () {
        const goal = ReachGpGoal(10000);

        final state1 = GlobalState.empty(testRegistries);
        final state2 = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
            Skill.mining: SkillState(xp: 8740, masteryPoolXp: 0),
          },
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1, isNot(equals(key2)));
        expect(key2.skillLevelBucket[Skill.mining], greaterThan(1));
      });

      test('same state produces equal keys', () {
        const goal = ReachGpGoal(5000);
        final state = GlobalState.empty(testRegistries);

        final key1 = CandidateCacheKey.fromState(state, goal);
        final key2 = CandidateCacheKey.fromState(state, goal);

        expect(key1, equals(key2));
      });
    });

    group('MultiSkillGoal', () {
      test('tracks only goal-relevant skills', () {
        final goal = MultiSkillGoal.fromMap(const {
          Skill.woodcutting: 20,
          Skill.fishing: 15,
        });
        final state = GlobalState.empty(testRegistries);

        final key = CandidateCacheKey.fromState(state, goal);

        // Should include woodcutting and fishing
        expect(key.skillLevelBucket.containsKey(Skill.woodcutting), isTrue);
        expect(key.skillLevelBucket.containsKey(Skill.fishing), isTrue);
        // Should not include unrelated skills like mining
        expect(key.skillLevelBucket.containsKey(Skill.mining), isFalse);
      });

      test('includes producer skills for consuming skills', () {
        final goal = MultiSkillGoal.fromMap(const {
          Skill.firemaking: 30,
          Skill.cooking: 20,
        });
        final state = GlobalState.empty(testRegistries);

        final key = CandidateCacheKey.fromState(state, goal);

        // Should include the consuming skills
        expect(key.skillLevelBucket.containsKey(Skill.firemaking), isTrue);
        expect(key.skillLevelBucket.containsKey(Skill.cooking), isTrue);
        // Should include producer skills (woodcutting for firemaking, fishing
        // for cooking)
        expect(key.skillLevelBucket.containsKey(Skill.woodcutting), isTrue);
        expect(key.skillLevelBucket.containsKey(Skill.fishing), isTrue);
      });

      test('different skill levels produce different keys', () {
        final goal = MultiSkillGoal.fromMap(const {
          Skill.woodcutting: 20,
          Skill.mining: 15,
        });

        final state1 = GlobalState.empty(testRegistries);
        final state2 = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
            Skill.woodcutting: SkillState(xp: 4470, masteryPoolXp: 0),
          },
        );

        final key1 = CandidateCacheKey.fromState(state1, goal);
        final key2 = CandidateCacheKey.fromState(state2, goal);

        expect(key1, isNot(equals(key2)));
      });

      test('same state produces equal keys', () {
        final goal = MultiSkillGoal.fromMap(const {
          Skill.woodcutting: 20,
          Skill.fishing: 15,
        });
        final state = GlobalState.empty(testRegistries);

        final key1 = CandidateCacheKey.fromState(state, goal);
        final key2 = CandidateCacheKey.fromState(state, goal);

        expect(key1, equals(key2));
      });
    });
  });

  group('CandidateCache', () {
    test('returns cached result for same key', () {
      final cache = CandidateCache();
      final state = GlobalState.empty(testRegistries);
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

      var computeCount = 0;
      Candidates compute(GlobalState s) {
        computeCount++;
        return const Candidates(
          switchToActivities: <ActionId>[],
          buyUpgrades: <MelvorId>[],
          sellPolicy: SellAllPolicy(),
          shouldEmitSellCandidate: false,
          watch: WatchList(),
          macros: <MacroCandidate>[],
        );
      }

      // First call should compute
      cache.getOrCompute(state, goal, compute);
      expect(computeCount, equals(1));
      expect(cache.hits, equals(0));
      expect(cache.misses, equals(1));

      // Second call with same state should hit cache
      cache.getOrCompute(state, goal, compute);
      expect(computeCount, equals(1)); // Not incremented
      expect(cache.hits, equals(1));
      expect(cache.misses, equals(1));
    });

    test('filters out active action from cached candidates', () {
      final cache = CandidateCache();
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      final oakTree = testRegistries.woodcuttingAction('Oak Tree');

      // State without active action
      final stateNoAction = GlobalState.empty(testRegistries);

      // Create candidates that include both actions
      final candidatesWithBoth = Candidates(
        switchToActivities: [normalTree.id, oakTree.id],
        buyUpgrades: const <MelvorId>[],
        sellPolicy: const SellAllPolicy(),
        shouldEmitSellCandidate: false,
        watch: const WatchList(),
        macros: const <MacroCandidate>[],
      );

      // Cache with no active action
      cache.getOrCompute(stateNoAction, goal, (_) => candidatesWithBoth);
      expect(cache.misses, equals(1));

      // Now query with active action set to normalTree
      final stateWithAction = stateNoAction.copyWith(
        activeActivity: SkillActivity(
          skill: Skill.woodcutting,
          actionId: normalTree.id.localId,
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      // Should hit cache (same capability key) but filter out active action
      final result = cache.getOrCompute(
        stateWithAction,
        goal,
        (_) => throw StateError('Should not compute'),
      );
      expect(cache.hits, equals(1));

      // Result should NOT include normalTree (the active action)
      expect(result.switchToActivities, contains(oakTree.id));
      expect(result.switchToActivities, isNot(contains(normalTree.id)));
    });

    test('same capability key with different active actions shares cache', () {
      final cache = CandidateCache();
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

      final normalTree = testRegistries.woodcuttingAction('Normal Tree');
      final oakTree = testRegistries.woodcuttingAction('Oak Tree');

      // Create candidates that include both actions
      final candidatesWithBoth = Candidates(
        switchToActivities: [normalTree.id, oakTree.id],
        buyUpgrades: const <MelvorId>[],
        sellPolicy: const SellAllPolicy(),
        shouldEmitSellCandidate: false,
        watch: const WatchList(),
        macros: const <MacroCandidate>[],
      );

      // State with normalTree active
      final state1 = GlobalState.empty(testRegistries).copyWith(
        activeActivity: SkillActivity(
          skill: Skill.woodcutting,
          actionId: normalTree.id.localId,
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      // State with oakTree active (same capability key)
      final state2 = GlobalState.empty(testRegistries).copyWith(
        activeActivity: SkillActivity(
          skill: Skill.woodcutting,
          actionId: oakTree.id.localId,
          progressTicks: 0,
          totalTicks: 10,
        ),
      );

      // First call computes and caches
      final result1 = cache.getOrCompute(
        state1,
        goal,
        (_) => candidatesWithBoth,
      );
      expect(cache.misses, equals(1));
      expect(result1.switchToActivities, isNot(contains(normalTree.id)));
      expect(result1.switchToActivities, contains(oakTree.id));

      // Second call should hit cache but filter differently
      final result2 = cache.getOrCompute(
        state2,
        goal,
        (_) => throw StateError('Should not compute'),
      );
      expect(cache.hits, equals(1));
      expect(result2.switchToActivities, contains(normalTree.id));
      expect(result2.switchToActivities, isNot(contains(oakTree.id)));
    });

    test('computes new result for different skill levels', () {
      final cache = CandidateCache();
      const goal = ReachSkillLevelGoal(Skill.woodcutting, 50);

      var computeCount = 0;
      Candidates compute(GlobalState s) {
        computeCount++;
        return const Candidates(
          switchToActivities: <ActionId>[],
          buyUpgrades: <MelvorId>[],
          sellPolicy: SellAllPolicy(),
          shouldEmitSellCandidate: false,
          watch: WatchList(),
          macros: <MacroCandidate>[],
        );
      }

      // Level 1 woodcutting
      final state1 = GlobalState.empty(testRegistries);
      cache.getOrCompute(state1, goal, compute);
      expect(computeCount, equals(1));

      // Level 10 woodcutting - different capability key
      final state2 = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0),
          Skill.woodcutting: SkillState(xp: 1154, masteryPoolXp: 0),
        },
      );
      cache.getOrCompute(state2, goal, compute);
      expect(computeCount, equals(2));
      expect(cache.misses, equals(2));
    });
  });
}
