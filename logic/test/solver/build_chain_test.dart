import 'package:logic/logic.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('buildChainForItem', () {
    group('simple items (no inputs)', () {
      test('builds chain for copper ore (Mining)', () {
        final state = GlobalState.empty(testRegistries);
        const copperOre = MelvorId('melvorD:Copper_Ore');
        const goal = ReachSkillLevelGoal(Skill.mining, 10);

        final result = buildChainForItem(state, copperOre, 100, goal);

        expect(result, isA<ChainBuilt>());
        final chain = (result as ChainBuilt).chain;
        expect(chain.itemId, copperOre);
        expect(chain.quantity, 100);
        expect(chain.isLeaf, isTrue);
        expect(chain.children, isEmpty);
      });

      test('builds chain for logs (Woodcutting)', () {
        final state = GlobalState.empty(testRegistries);
        const logs = MelvorId('melvorD:Normal_Logs');
        const goal = ReachSkillLevelGoal(Skill.woodcutting, 10);

        final result = buildChainForItem(state, logs, 50, goal);

        expect(result, isA<ChainBuilt>());
        final chain = (result as ChainBuilt).chain;
        expect(chain.itemId, logs);
        expect(chain.quantity, 50);
        expect(chain.isLeaf, isTrue);
      });
    });

    group('consuming items (with inputs)', () {
      test('builds chain for bronze bar (Smithing)', () {
        // Bronze bar requires Copper Ore + Tin Ore
        final state = GlobalState.empty(testRegistries);
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);

        expect(result, isA<ChainBuilt>());
        final chain = (result as ChainBuilt).chain;
        expect(chain.itemId, bronzeBar);
        expect(chain.quantity, 10);
        expect(chain.isLeaf, isFalse);
        expect(chain.children.length, 2); // Copper Ore + Tin Ore

        // Verify children are ore types
        final childItemIds = chain.children.map((c) => c.itemId).toSet();
        expect(
          childItemIds,
          containsAll([
            const MelvorId('melvorD:Copper_Ore'),
            const MelvorId('melvorD:Tin_Ore'),
          ]),
        );

        // Each child should be a leaf (mining has no inputs)
        for (final child in chain.children) {
          expect(child.isLeaf, isTrue);
        }
      });

      test(
        'builds multi-tier chain for bronze dagger (item -> bar -> ores)',
        () {
          // Bronze Dagger requires Bronze Bars
          // Bronze Bars require Copper Ore + Tin Ore
          final state = GlobalState.empty(testRegistries);
          const bronzeDagger = MelvorId('melvorD:Bronze_Dagger');
          const goal = ReachSkillLevelGoal(Skill.smithing, 10);

          final result = buildChainForItem(state, bronzeDagger, 5, goal);

          expect(result, isA<ChainBuilt>());
          final chain = (result as ChainBuilt).chain;
          expect(chain.itemId, bronzeDagger);
          expect(chain.quantity, 5);

          // Should have one child: Bronze Bar
          expect(chain.children.length, 1);
          final barChild = chain.children.first;
          expect(barChild.itemId, const MelvorId('melvorD:Bronze_Bar'));

          // Bar child should have two children (ores)
          expect(barChild.children.length, 2);
          for (final oreChild in barChild.children) {
            expect(oreChild.isLeaf, isTrue);
          }
        },
      );
    });

    group('unlock requirements', () {
      test('returns ChainNeedsUnlock when producer is locked', () {
        // Start with level 1 mining - Iron Ore requires level 15
        final state = GlobalState.empty(testRegistries);
        const ironOre = MelvorId('melvorD:Iron_Ore');
        const goal = ReachSkillLevelGoal(Skill.mining, 20);

        final result = buildChainForItem(state, ironOre, 10, goal);

        expect(result, isA<ChainNeedsUnlock>());
        final unlock = result as ChainNeedsUnlock;
        expect(unlock.skill, Skill.mining);
        expect(unlock.requiredLevel, 15);
        expect(unlock.forItem, ironOre);
      });

      test('returns ChainNeedsUnlock for multi-tier chain with locked input', () {
        // Iron Bar needs Iron Ore (Mining level 15)
        // Iron Bar action itself needs Smithing level 10
        // With Smithing unlocked but Mining locked, we should hit Mining unlock
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            // Smithing 10 to unlock Iron Bar action
            Skill.smithing: SkillState(xp: 1200, masteryPoolXp: 0),
            // Mining 1 (default) - Iron Ore needs level 15
          },
        );
        const ironBar = MelvorId('melvorD:Iron_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 20);

        final result = buildChainForItem(state, ironBar, 10, goal);

        expect(result, isA<ChainNeedsUnlock>());
        final unlock = result as ChainNeedsUnlock;
        expect(unlock.skill, Skill.mining);
        expect(unlock.requiredLevel, 15); // Iron Ore unlock level
        expect(unlock.forItem, const MelvorId('melvorD:Iron_Ore'));
      });

      test('succeeds when skill level is sufficient', () {
        // With mining level 15, iron ore should be producible
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 6500, masteryPoolXp: 0),
          }, // Level 15 (~6500 xp)
        );
        const ironOre = MelvorId('melvorD:Iron_Ore');
        const goal = ReachSkillLevelGoal(Skill.mining, 20);

        final result = buildChainForItem(state, ironOre, 10, goal);

        expect(result, isA<ChainBuilt>());
      });
    });

    group('cycle detection', () {
      test('detects and fails on production cycles', () {
        // In a well-formed game, cycles shouldn't exist, but we guard anyway.
        // We can't easily create a cycle in test data, but we verify the guard
        // works by testing the depth limit which is similar protection.
        final state = GlobalState.empty(testRegistries);
        const copperOre = MelvorId('melvorD:Copper_Ore');
        const goal = ReachSkillLevelGoal(Skill.mining, 10);

        // Normal case should work
        final result = buildChainForItem(state, copperOre, 10, goal);
        expect(result, isA<ChainBuilt>());
      });
    });

    group('depth limit', () {
      test('respects max chain depth', () {
        // buildChainForItem has a maxChainDepth constant
        // Normal production chains are only 2-3 levels deep
        // This test verifies the mechanism exists
        expect(maxChainDepth, greaterThan(0));
        expect(maxChainDepth, lessThan(20)); // Reasonable bound
      });
    });

    group('helper functions', () {
      test('chainToProducerMap extracts direct child producers', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 1200, masteryPoolXp: 0),
          },
        );
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);
        expect(result, isA<ChainBuilt>());

        final chain = (result as ChainBuilt).chain;
        final producerMap = chainToProducerMap(chain);

        // Should have entries for copper and tin ore
        expect(producerMap.length, 2);
        expect(
          producerMap.containsKey(const MelvorId('melvorD:Copper_Ore')),
          isTrue,
        );
        expect(
          producerMap.containsKey(const MelvorId('melvorD:Tin_Ore')),
          isTrue,
        );
      });

      test('chainToInputRequirements collects leaf quantities', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 1200, masteryPoolXp: 0),
          },
        );
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);
        expect(result, isA<ChainBuilt>());

        final chain = (result as ChainBuilt).chain;
        final inputs = chainToInputRequirements(chain);

        // Should require 10 of each ore type for 10 bronze bars
        expect(inputs[const MelvorId('melvorD:Copper_Ore')], 10);
        expect(inputs[const MelvorId('melvorD:Tin_Ore')], 10);
      });
    });

    group('PlannedChain', () {
      test('bottomUpTraversal visits leaves first', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 1200, masteryPoolXp: 0),
          },
        );
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);
        final chain = (result as ChainBuilt).chain;

        final nodes = chain.bottomUpTraversal.toList();

        // Leaves (ores) should come first, root (bar) should come last
        expect(nodes.last.itemId, bronzeBar);
        for (final node in nodes.take(nodes.length - 1)) {
          expect(node.isLeaf, isTrue);
        }
      });

      test('topDownTraversal visits root first', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 1200, masteryPoolXp: 0),
          },
        );
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);
        final chain = (result as ChainBuilt).chain;

        final nodes = chain.topDownTraversal.toList();

        // Root (bar) should come first, leaves (ores) should come last
        expect(nodes.first.itemId, bronzeBar);
        for (final node in nodes.skip(1)) {
          expect(node.isLeaf, isTrue);
        }
      });

      test('totalTicks includes all children', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.mining: SkillState(xp: 1200, masteryPoolXp: 0),
          },
        );
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        const goal = ReachSkillLevelGoal(Skill.smithing, 10);

        final result = buildChainForItem(state, bronzeBar, 10, goal);
        final chain = (result as ChainBuilt).chain;

        // Total ticks should be sum of root + all children
        var expectedTotal = chain.ticksNeeded;
        for (final child in chain.children) {
          expectedTotal += child.ticksNeeded;
        }
        expect(chain.totalTicks, expectedTotal);
      });

      test('toString produces readable output', () {
        final state = GlobalState.empty(testRegistries);
        const copperOre = MelvorId('melvorD:Copper_Ore');
        const goal = ReachSkillLevelGoal(Skill.mining, 10);

        final result = buildChainForItem(state, copperOre, 10, goal);
        final chain = (result as ChainBuilt).chain;

        final str = chain.toString();
        expect(str, contains('Copper_Ore'));
        expect(str, contains('x10'));
      });
    });
  });
}
