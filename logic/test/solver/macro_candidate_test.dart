import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/build_chain.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/candidates/macro_expansion_context.dart';
import 'package:logic/src/solver/core/goal.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });

  group('MacroProvenance', () {
    group('TopLevelProvenance', () {
      test('describe returns top-level candidate', () {
        const provenance = TopLevelProvenance();
        expect(provenance.describe(), 'Top-level candidate');
      });
    });

    group('SkillPrereqProvenance', () {
      test('describe includes skill, level, and action', () {
        final miningAction = testActions.mining('Iron');
        final provenance = SkillPrereqProvenance(
          requiredSkill: Skill.mining,
          requiredLevel: 15,
          unlocksAction: miningAction.id,
        );

        expect(provenance.describe(), contains('Mining'));
        expect(provenance.describe(), contains('L15'));
        expect(provenance.describe(), contains(miningAction.id.toString()));
      });

      test('stores required skill correctly', () {
        final action = testActions.woodcutting('Oak Tree');
        final provenance = SkillPrereqProvenance(
          requiredSkill: Skill.woodcutting,
          requiredLevel: 10,
          unlocksAction: action.id,
        );

        expect(provenance.requiredSkill, Skill.woodcutting);
        expect(provenance.requiredLevel, 10);
        expect(provenance.unlocksAction, action.id);
      });
    });

    group('InputPrereqProvenance', () {
      test('describe includes action, item, and quantity', () {
        final action = testActions.smithing('Bronze Dagger');
        const bronzeBar = MelvorId('melvorD:Bronze_Bar');
        final provenance = InputPrereqProvenance(
          forAction: action.id,
          inputItem: bronzeBar,
          quantityNeeded: 50,
        );

        expect(provenance.describe(), contains('50x'));
        expect(provenance.describe(), contains('Bronze_Bar'));
        expect(provenance.describe(), contains(action.id.toString()));
      });

      test('stores values correctly', () {
        final action = testActions.smithing('Iron Dagger');
        const ironBar = MelvorId('melvorD:Iron_Bar');
        final provenance = InputPrereqProvenance(
          forAction: action.id,
          inputItem: ironBar,
          quantityNeeded: 25,
        );

        expect(provenance.forAction, action.id);
        expect(provenance.inputItem, ironBar);
        expect(provenance.quantityNeeded, 25);
      });
    });

    group('BatchInputProvenance', () {
      test('describe includes item, batch size, and target level', () {
        const provenance = BatchInputProvenance(
          forItem: MelvorId('melvorD:Copper_Ore'),
          batchSize: 120,
          targetLevel: 10,
        );

        expect(provenance.describe(), contains('120x'));
        expect(provenance.describe(), contains('Copper_Ore'));
        expect(provenance.describe(), contains('L10'));
      });

      test('stores values correctly', () {
        const provenance = BatchInputProvenance(
          forItem: MelvorId('melvorD:Iron_Ore'),
          batchSize: 200,
          targetLevel: 15,
        );

        expect(provenance.forItem, const MelvorId('melvorD:Iron_Ore'));
        expect(provenance.batchSize, 200);
        expect(provenance.targetLevel, 15);
      });
    });

    group('ChainProvenance', () {
      test('describe includes parent and child items', () {
        const provenance = ChainProvenance(
          parentItem: MelvorId('melvorD:Bronze_Dagger'),
          childItem: MelvorId('melvorD:Bronze_Bar'),
        );

        expect(provenance.describe(), contains('Bronze_Bar'));
        expect(provenance.describe(), contains('Bronze_Dagger'));
      });

      test('stores values correctly', () {
        const provenance = ChainProvenance(
          parentItem: MelvorId('melvorD:Iron_Sword'),
          childItem: MelvorId('melvorD:Iron_Bar'),
        );

        expect(provenance.parentItem, const MelvorId('melvorD:Iron_Sword'));
        expect(provenance.childItem, const MelvorId('melvorD:Iron_Bar'));
      });
    });
  });

  group('MacroCandidate', () {
    group('TrainSkillUntil', () {
      test('stores skill and primary stop', () {
        const macro = TrainSkillUntil(
          Skill.woodcutting,
          StopAtNextBoundary(Skill.woodcutting),
        );

        expect(macro.skill, Skill.woodcutting);
        expect(macro.primaryStop, isA<StopAtNextBoundary>());
        expect(macro.watchedStops, isEmpty);
      });

      test('stores watched stops', () {
        const macro = TrainSkillUntil(
          Skill.woodcutting,
          StopAtNextBoundary(Skill.woodcutting),
          watchedStops: [
            StopWhenUpgradeAffordable(
              MelvorId('melvorD:Iron_Axe'),
              50,
              'Iron Axe',
            ),
          ],
        );

        expect(macro.watchedStops, hasLength(1));
        expect(macro.watchedStops.first, isA<StopWhenUpgradeAffordable>());
      });

      test('allStops includes primary and watched stops', () {
        const macro = TrainSkillUntil(
          Skill.woodcutting,
          StopAtNextBoundary(Skill.woodcutting),
          watchedStops: [
            StopWhenUpgradeAffordable(
              MelvorId('melvorD:Iron_Axe'),
              50,
              'Iron Axe',
            ),
            StopAtGoal(Skill.woodcutting, 1000),
          ],
        );

        expect(macro.allStops, hasLength(3));
      });

      test('stores provenance', () {
        const macro = TrainSkillUntil(
          Skill.mining,
          StopAtNextBoundary(Skill.mining),
          provenance: TopLevelProvenance(),
        );

        expect(macro.provenance, isA<TopLevelProvenance>());
      });

      test('stores actionId when specified', () {
        final action = testActions.woodcutting('Normal Tree');
        final macro = TrainSkillUntil(
          Skill.woodcutting,
          const StopAtNextBoundary(Skill.woodcutting),
          actionId: action.id,
        );

        expect(macro.actionId, action.id);
      });

      // NOTE: Tests using 'const' will pass because Dart canonicalizes const
      // instances (same arguments = same object = same hashCode). We need
      // non-const (separate allocations) to properly test dedupeKey behavior.
      group('dedupeKey', () {
        // Helper functions that return new instances each call
        MacroStopRule makeStopAtNextBoundary(Skill skill) =>
            StopAtNextBoundary(skill);
        MacroStopRule makeStopAtGoal(Skill skill, int xp) =>
            StopAtGoal(skill, xp);
        MacroStopRule makeStopAtLevel(Skill skill, int level) =>
            StopAtLevel(skill, level);
        MacroStopRule makeStopWhenUpgradeAffordable(
          MelvorId id,
          int cost,
          String name,
        ) => StopWhenUpgradeAffordable(id, cost, name);
        MacroStopRule makeStopWhenInputsDepleted() =>
            const StopWhenInputsDepleted();

        test('identical non-const macros with StopAtNextBoundary produce same '
            'dedupeKey', () {
          final macro1 = TrainSkillUntil(
            Skill.woodcutting,
            makeStopAtNextBoundary(Skill.woodcutting),
          );
          final macro2 = TrainSkillUntil(
            Skill.woodcutting,
            makeStopAtNextBoundary(Skill.woodcutting),
          );

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test(
          'identical non-const macros with StopAtGoal produce same dedupeKey',
          () {
            final macro1 = TrainSkillUntil(
              Skill.mining,
              makeStopAtGoal(Skill.mining, 5000),
            );
            final macro2 = TrainSkillUntil(
              Skill.mining,
              makeStopAtGoal(Skill.mining, 5000),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test(
          'identical non-const macros with StopAtLevel produce same dedupeKey',
          () {
            final macro1 = TrainSkillUntil(
              Skill.fishing,
              makeStopAtLevel(Skill.fishing, 25),
            );
            final macro2 = TrainSkillUntil(
              Skill.fishing,
              makeStopAtLevel(Skill.fishing, 25),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test(
          'identical non-const macros with StopWhenUpgradeAffordable produce '
          'same dedupeKey',
          () {
            final macro1 = TrainSkillUntil(
              Skill.woodcutting,
              makeStopWhenUpgradeAffordable(
                const MelvorId('melvorD:Iron_Axe'),
                50,
                'Iron Axe',
              ),
            );
            final macro2 = TrainSkillUntil(
              Skill.woodcutting,
              makeStopWhenUpgradeAffordable(
                const MelvorId('melvorD:Iron_Axe'),
                50,
                'Iron Axe',
              ),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test('identical non-const macros with StopWhenInputsDepleted produce '
            'same dedupeKey', () {
          final macro1 = TrainSkillUntil(
            Skill.firemaking,
            makeStopWhenInputsDepleted(),
          );
          final macro2 = TrainSkillUntil(
            Skill.firemaking,
            makeStopWhenInputsDepleted(),
          );

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test(
          'macros with different stop rules produce different dedupeKeys',
          () {
            final macro1 = TrainSkillUntil(
              Skill.woodcutting,
              makeStopAtNextBoundary(Skill.woodcutting),
            );
            final macro2 = TrainSkillUntil(
              Skill.woodcutting,
              makeStopAtLevel(Skill.woodcutting, 10),
            );

            expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
          },
        );

        test('macros with different skills produce different dedupeKeys', () {
          final macro1 = TrainSkillUntil(
            Skill.woodcutting,
            makeStopAtNextBoundary(Skill.woodcutting),
          );
          final macro2 = TrainSkillUntil(
            Skill.mining,
            makeStopAtNextBoundary(Skill.mining),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test('non-const StopAtGoal macros with different XP values produce '
            'different dedupeKeys', () {
          final macro1 = TrainSkillUntil(
            Skill.mining,
            makeStopAtGoal(Skill.mining, 5000),
          );
          final macro2 = TrainSkillUntil(
            Skill.mining,
            makeStopAtGoal(Skill.mining, 10000),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test('non-const StopAtLevel macros with different levels produce '
            'different dedupeKeys', () {
          final macro1 = TrainSkillUntil(
            Skill.fishing,
            makeStopAtLevel(Skill.fishing, 25),
          );
          final macro2 = TrainSkillUntil(
            Skill.fishing,
            makeStopAtLevel(Skill.fishing, 50),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });
      });
    });

    group('AcquireItem', () {
      test('stores item and quantity', () {
        const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);

        expect(macro.itemId, const MelvorId('melvorD:Normal_Logs'));
        expect(macro.quantity, 50);
      });

      test('stores provenance', () {
        final action = testActions.firemaking('Burn Oak Logs');
        final macro = AcquireItem(
          const MelvorId('melvorD:Oak_Logs'),
          100,
          provenance: InputPrereqProvenance(
            forAction: action.id,
            inputItem: const MelvorId('melvorD:Oak_Logs'),
            quantityNeeded: 100,
          ),
        );

        expect(macro.provenance, isA<InputPrereqProvenance>());
      });

      group('dedupeKey', () {
        test('identical macros produce same dedupeKey', () {
          const macro1 = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);
          const macro2 = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test('macros with different items produce different dedupeKeys', () {
          const macro1 = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);
          const macro2 = AcquireItem(MelvorId('melvorD:Oak_Logs'), 50);

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test(
          'macros with different quantities produce different dedupeKeys',
          () {
            const macro1 = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);
            const macro2 = AcquireItem(MelvorId('melvorD:Normal_Logs'), 100);

            expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
          },
        );
      });

      group('expand', () {
        MacroExpansionContext makeContext(
          GlobalState state, {
          Goal? goal,
          Map<Skill, SkillBoundaries>? boundaries,
        }) {
          return MacroExpansionContext(
            state: state,
            goal: goal ?? const ReachSkillLevelGoal(Skill.woodcutting, 10),
            boundaries: boundaries ?? const {},
          );
        }

        test('expands to woodcutting action for Normal Logs', () {
          final state = GlobalState.empty(testRegistries);
          final context = makeContext(state);
          const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 10);

          final result = macro.expand(context);

          expect(result, isA<MacroExpanded>());
          final expanded = result as MacroExpanded;
          expect(expanded.result.ticksElapsed, greaterThan(0));
          expect(expanded.result.waitFor, isA<WaitForInventoryDelta>());
          final waitFor = expanded.result.waitFor as WaitForInventoryDelta;
          expect(waitFor.itemId, const MelvorId('melvorD:Normal_Logs'));
          expect(waitFor.delta, 10);
        });

        test('returns MacroCannotExpand when no producer exists', () {
          final state = GlobalState.empty(testRegistries);
          final context = makeContext(state);
          // Use a non-existent item
          const macro = AcquireItem(MelvorId('melvorD:NonExistent_Item'), 10);

          final result = macro.expand(context);

          expect(result, isA<MacroCannotExpand>());
        });

        test('returns training prerequisite when producer is locked', () {
          // Start at level 1 - Oak Tree requires level 10
          final state = GlobalState.empty(testRegistries);
          final context = makeContext(state);
          const macro = AcquireItem(MelvorId('melvorD:Oak_Logs'), 10);

          final result = macro.expand(context);

          // Should return training prerequisite (not expand recursively)
          expect(result, isA<MacroNeedsPrerequisite>());
          final prereq = result as MacroNeedsPrerequisite;
          expect(prereq.prerequisite, isA<TrainSkillUntil>());
          final train = prereq.prerequisite as TrainSkillUntil;
          expect(train.skill, Skill.woodcutting);
        });

        test('uses unlocked producer when available', () {
          // Give enough woodcutting level to unlock Oak Tree (L10)
          final state = GlobalState.test(
            testRegistries,
            skillStates: const {
              Skill.woodcutting: SkillState(xp: 1200, masteryPoolXp: 0),
            },
          );
          final context = makeContext(state);
          const macro = AcquireItem(MelvorId('melvorD:Oak_Logs'), 10);

          final result = macro.expand(context);

          expect(result, isA<MacroExpanded>());
          final expanded = result as MacroExpanded;
          // Should produce oak logs directly
          expect(expanded.result.waitFor, isA<WaitForInventoryDelta>());
          final waitFor = expanded.result.waitFor as WaitForInventoryDelta;
          expect(waitFor.itemId, const MelvorId('melvorD:Oak_Logs'));
        });

        test(
          'returns input prerequisite when consuming action needs inputs',
          () {
            // Bronze Bar requires Copper Ore and Tin Ore
            // Smithing starts at L1, Bronze Bar is L1
            final state = GlobalState.test(
              testRegistries,
              skillStates: const {
                Skill.smithing: SkillState(xp: 0, masteryPoolXp: 0),
                Skill.mining: SkillState(xp: 0, masteryPoolXp: 0),
              },
            );
            final context = makeContext(
              state,
              goal: const ReachSkillLevelGoal(Skill.smithing, 10),
            );
            const macro = AcquireItem(MelvorId('melvorD:Bronze_Bar'), 5);

            final result = macro.expand(context);

            // Should return input prerequisite (not expand recursively)
            expect(result, isA<MacroNeedsPrerequisite>());
            final prereq = result as MacroNeedsPrerequisite;
            expect(prereq.prerequisite, isA<AcquireItem>());
            final acquire = prereq.prerequisite as AcquireItem;
            // Should need one of the input ores (Copper or Tin)
            expect(
              acquire.itemId,
              anyOf(
                const MelvorId('melvorD:Copper_Ore'),
                const MelvorId('melvorD:Tin_Ore'),
              ),
            );
          },
        );

        test('produces item when inputs are already available', () {
          // Give enough ores to make Bronze Bars
          final copperOre = testItems.byName('Copper Ore');
          final tinOre = testItems.byName('Tin Ore');
          final inventory = Inventory.fromItems(testItems, [
            ItemStack(copperOre, count: 20),
            ItemStack(tinOre, count: 20),
          ]);
          final state = GlobalState.test(
            testRegistries,
            inventory: inventory,
            skillStates: const {
              Skill.smithing: SkillState(xp: 0, masteryPoolXp: 0),
              Skill.mining: SkillState(xp: 0, masteryPoolXp: 0),
            },
          );
          final context = makeContext(
            state,
            goal: const ReachSkillLevelGoal(Skill.smithing, 10),
          );
          const macro = AcquireItem(MelvorId('melvorD:Bronze_Bar'), 5);

          final result = macro.expand(context);

          expect(result, isA<MacroExpanded>());
          final expanded = result as MacroExpanded;
          // Should wait for Bronze Bars since inputs are available
          expect(expanded.result.waitFor, isA<WaitForInventoryDelta>());
          final waitFor = expanded.result.waitFor as WaitForInventoryDelta;
          expect(waitFor.itemId, const MelvorId('melvorD:Bronze_Bar'));
          expect(waitFor.delta, 5);
        });

        test('calculates correct ticks for production', () {
          final state = GlobalState.empty(testRegistries);
          final context = makeContext(state);
          const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 10);

          final result = macro.expand(context);

          expect(result, isA<MacroExpanded>());
          final expanded = result as MacroExpanded;
          // Normal Tree takes 3 seconds = 30 ticks per log
          // 10 logs = 300 ticks
          expect(expanded.result.ticksElapsed, 300);
        });

        test('uses delta semantics for WaitFor', () {
          // Start with some logs already in inventory
          final normalLogs = testItems.byName('Normal Logs');
          final inventory = Inventory.fromItems(testItems, [
            ItemStack(normalLogs, count: 5),
          ]);
          final state = GlobalState.test(testRegistries, inventory: inventory);
          final context = makeContext(state);
          const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 10);

          final result = macro.expand(context);

          expect(result, isA<MacroExpanded>());
          final expanded = result as MacroExpanded;
          final waitFor = expanded.result.waitFor as WaitForInventoryDelta;
          // Should acquire 10 MORE logs (delta semantics)
          expect(waitFor.delta, 10);
          expect(waitFor.startCount, 5);
        });
      });
    });

    group('EnsureStock', () {
      test('stores item and minTotal', () {
        const macro = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);

        expect(macro.itemId, const MelvorId('melvorD:Copper_Ore'));
        expect(macro.minTotal, 200);
      });

      test('stores provenance', () {
        const macro = EnsureStock(
          MelvorId('melvorD:Iron_Ore'),
          150,
          provenance: BatchInputProvenance(
            forItem: MelvorId('melvorD:Iron_Ore'),
            batchSize: 150,
            targetLevel: 20,
          ),
        );

        expect(macro.provenance, isA<BatchInputProvenance>());
      });

      group('dedupeKey', () {
        test('identical macros produce same dedupeKey', () {
          const macro1 = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);
          const macro2 = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test('macros with different items produce different dedupeKeys', () {
          const macro1 = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);
          const macro2 = EnsureStock(MelvorId('melvorD:Iron_Ore'), 200);

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test('macros with different minTotal produce different dedupeKeys', () {
          const macro1 = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);
          const macro2 = EnsureStock(MelvorId('melvorD:Copper_Ore'), 300);

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });
      });
    });

    group('TrainConsumingSkillUntil', () {
      test('stores skill and primary stop', () {
        const macro = TrainConsumingSkillUntil(
          Skill.firemaking,
          StopAtNextBoundary(Skill.firemaking),
        );

        expect(macro.consumingSkill, Skill.firemaking);
        expect(macro.primaryStop, isA<StopAtNextBoundary>());
      });

      test('stores watched stops', () {
        const macro = TrainConsumingSkillUntil(
          Skill.cooking,
          StopAtNextBoundary(Skill.cooking),
          watchedStops: [StopAtGoal(Skill.cooking, 5000)],
        );

        expect(macro.watchedStops, hasLength(1));
      });

      test('allStops includes primary and watched stops', () {
        const macro = TrainConsumingSkillUntil(
          Skill.smithing,
          StopAtNextBoundary(Skill.smithing),
          watchedStops: [
            StopAtGoal(Skill.smithing, 10000),
            StopWhenUpgradeAffordable(
              MelvorId('melvorD:Some_Upgrade'),
              500,
              'Some Upgrade',
            ),
          ],
        );

        expect(macro.allStops, hasLength(3));
      });

      test('stores provenance', () {
        const macro = TrainConsumingSkillUntil(
          Skill.firemaking,
          StopAtNextBoundary(Skill.firemaking),
          provenance: TopLevelProvenance(),
        );

        expect(macro.provenance, isA<TopLevelProvenance>());
      });

      // NOTE: Tests use non-const instances because const instances in Dart are
      // canonicalized (same arguments = same object = same hashCode). We need
      // non-const (separate allocations) to properly test dedupeKey behavior.
      group('dedupeKey', () {
        // Helper functions that return new instances each call
        MacroStopRule makeStopAtNextBoundary(Skill skill) =>
            StopAtNextBoundary(skill);
        MacroStopRule makeStopAtGoal(Skill skill, int xp) =>
            StopAtGoal(skill, xp);
        MacroStopRule makeStopAtLevel(Skill skill, int level) =>
            StopAtLevel(skill, level);
        MacroStopRule makeStopWhenUpgradeAffordable(
          MelvorId id,
          int cost,
          String name,
        ) => StopWhenUpgradeAffordable(id, cost, name);
        MacroStopRule makeStopWhenInputsDepleted() =>
            const StopWhenInputsDepleted();

        test('identical non-const macros with StopAtNextBoundary produce same '
            'dedupeKey', () {
          final macro1 = TrainConsumingSkillUntil(
            Skill.firemaking,
            makeStopAtNextBoundary(Skill.firemaking),
          );
          final macro2 = TrainConsumingSkillUntil(
            Skill.firemaking,
            makeStopAtNextBoundary(Skill.firemaking),
          );

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test(
          'identical non-const macros with StopAtGoal produce same dedupeKey',
          () {
            final macro1 = TrainConsumingSkillUntil(
              Skill.smithing,
              makeStopAtGoal(Skill.smithing, 8000),
            );
            final macro2 = TrainConsumingSkillUntil(
              Skill.smithing,
              makeStopAtGoal(Skill.smithing, 8000),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test(
          'identical non-const macros with StopAtLevel produce same dedupeKey',
          () {
            final macro1 = TrainConsumingSkillUntil(
              Skill.cooking,
              makeStopAtLevel(Skill.cooking, 30),
            );
            final macro2 = TrainConsumingSkillUntil(
              Skill.cooking,
              makeStopAtLevel(Skill.cooking, 30),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test(
          'identical non-const macros with StopWhenUpgradeAffordable produce '
          'same dedupeKey',
          () {
            final macro1 = TrainConsumingSkillUntil(
              Skill.firemaking,
              makeStopWhenUpgradeAffordable(
                const MelvorId('melvorD:Some_Upgrade'),
                100,
                'Some Upgrade',
              ),
            );
            final macro2 = TrainConsumingSkillUntil(
              Skill.firemaking,
              makeStopWhenUpgradeAffordable(
                const MelvorId('melvorD:Some_Upgrade'),
                100,
                'Some Upgrade',
              ),
            );

            expect(macro1.dedupeKey, equals(macro2.dedupeKey));
          },
        );

        test('identical non-const macros with StopWhenInputsDepleted produce '
            'same dedupeKey', () {
          final macro1 = TrainConsumingSkillUntil(
            Skill.smithing,
            makeStopWhenInputsDepleted(),
          );
          final macro2 = TrainConsumingSkillUntil(
            Skill.smithing,
            makeStopWhenInputsDepleted(),
          );

          expect(macro1.dedupeKey, equals(macro2.dedupeKey));
        });

        test('macros with different skills produce different dedupeKeys', () {
          final macro1 = TrainConsumingSkillUntil(
            Skill.firemaking,
            makeStopAtNextBoundary(Skill.firemaking),
          );
          final macro2 = TrainConsumingSkillUntil(
            Skill.cooking,
            makeStopAtNextBoundary(Skill.cooking),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test(
          'macros with different stop rules produce different dedupeKeys',
          () {
            final macro1 = TrainConsumingSkillUntil(
              Skill.firemaking,
              makeStopAtNextBoundary(Skill.firemaking),
            );
            final macro2 = TrainConsumingSkillUntil(
              Skill.firemaking,
              makeStopAtLevel(Skill.firemaking, 15),
            );

            expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
          },
        );

        test('non-const StopAtGoal macros with different XP values produce '
            'different dedupeKeys', () {
          final macro1 = TrainConsumingSkillUntil(
            Skill.smithing,
            makeStopAtGoal(Skill.smithing, 5000),
          );
          final macro2 = TrainConsumingSkillUntil(
            Skill.smithing,
            makeStopAtGoal(Skill.smithing, 10000),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });

        test('non-const StopAtLevel macros with different levels produce '
            'different dedupeKeys', () {
          final macro1 = TrainConsumingSkillUntil(
            Skill.cooking,
            makeStopAtLevel(Skill.cooking, 20),
          );
          final macro2 = TrainConsumingSkillUntil(
            Skill.cooking,
            makeStopAtLevel(Skill.cooking, 40),
          );

          expect(macro1.dedupeKey, isNot(equals(macro2.dedupeKey)));
        });
      });
    });
  });

  group('MacroCandidate JSON serialization', () {
    test('TrainSkillUntil round-trips through JSON', () {
      final action = testActions.woodcutting('Normal Tree');
      final original = TrainSkillUntil(
        Skill.woodcutting,
        const StopAtNextBoundary(Skill.woodcutting),
        watchedStops: const [
          StopWhenUpgradeAffordable(
            MelvorId('melvorD:Iron_Axe'),
            50,
            'Iron Axe',
          ),
          StopAtGoal(Skill.woodcutting, 1000),
        ],
        actionId: action.id,
      );

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json);

      expect(restored, isA<TrainSkillUntil>());
      final restoredMacro = restored as TrainSkillUntil;
      expect(restoredMacro.skill, original.skill);
      expect(restoredMacro.actionId, original.actionId);
      expect(restoredMacro.watchedStops, hasLength(2));
      expect(restoredMacro.primaryStop, isA<StopAtNextBoundary>());
    });

    test('TrainSkillUntil without actionId round-trips through JSON', () {
      const original = TrainSkillUntil(
        Skill.mining,
        StopAtLevel(Skill.mining, 15),
      );

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json) as TrainSkillUntil;

      expect(restored.skill, Skill.mining);
      expect(restored.actionId, isNull);
      expect(restored.primaryStop, isA<StopAtLevel>());
      final stopRule = restored.primaryStop as StopAtLevel;
      expect(stopRule.level, 15);
    });

    test('AcquireItem round-trips through JSON', () {
      const original = AcquireItem(MelvorId('melvorD:Oak_Logs'), 50);

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json);

      expect(restored, isA<AcquireItem>());
      final restoredMacro = restored as AcquireItem;
      expect(restoredMacro.itemId, const MelvorId('melvorD:Oak_Logs'));
      expect(restoredMacro.quantity, 50);
    });

    test('EnsureStock round-trips through JSON', () {
      const original = EnsureStock(MelvorId('melvorD:Copper_Ore'), 200);

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json);

      expect(restored, isA<EnsureStock>());
      final restoredMacro = restored as EnsureStock;
      expect(restoredMacro.itemId, const MelvorId('melvorD:Copper_Ore'));
      expect(restoredMacro.minTotal, 200);
    });

    test('TrainConsumingSkillUntil round-trips through JSON', () {
      final consumeAction = testActions.firemaking('Burn Normal Logs');
      final producerAction = testActions.woodcutting('Normal Tree');
      const logsId = MelvorId('melvorD:Normal_Logs');

      final original = TrainConsumingSkillUntil(
        Skill.firemaking,
        const StopAtNextBoundary(Skill.firemaking),
        watchedStops: const [StopAtGoal(Skill.firemaking, 5000)],
        actionId: consumeAction.id,
        consumeActionId: consumeAction.id,
        producerByInputItem: {logsId: producerAction.id},
        bufferTarget: 20,
        sellPolicySpec: const SellAllSpec(),
        maxRecoveryAttempts: 5,
      );

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json);

      expect(restored, isA<TrainConsumingSkillUntil>());
      final restoredMacro = restored as TrainConsumingSkillUntil;
      expect(restoredMacro.consumingSkill, Skill.firemaking);
      expect(restoredMacro.actionId, consumeAction.id);
      expect(restoredMacro.consumeActionId, consumeAction.id);
      expect(restoredMacro.producerByInputItem, {logsId: producerAction.id});
      expect(restoredMacro.bufferTarget, 20);
      expect(restoredMacro.sellPolicySpec, isA<SellAllSpec>());
      expect(restoredMacro.maxRecoveryAttempts, 5);
      expect(restoredMacro.watchedStops, hasLength(1));
    });

    test(
      'TrainConsumingSkillUntil with inputChains round-trips through JSON',
      () {
        const copperOreId = MelvorId('melvorD:Copper_Ore');
        const tinOreId = MelvorId('melvorD:Tin_Ore');
        const bronzeBarId = MelvorId('melvorD:Bronze_Bar');

        final copperMining = testActions.mining('Copper');
        final tinMining = testActions.mining('Tin');
        final bronzeSmelting = testActions.smithing('Bronze Bar');
        final bronzeDagger = testActions.smithing('Bronze Dagger');

        final inputChain = PlannedChain(
          itemId: bronzeBarId,
          quantity: 10,
          actionId: bronzeSmelting.id,
          actionsNeeded: 10,
          ticksNeeded: 300,
          children: [
            PlannedChain(
              itemId: copperOreId,
              quantity: 10,
              actionId: copperMining.id,
              actionsNeeded: 10,
              ticksNeeded: 300,
              children: const [],
            ),
            PlannedChain(
              itemId: tinOreId,
              quantity: 10,
              actionId: tinMining.id,
              actionsNeeded: 10,
              ticksNeeded: 300,
              children: const [],
            ),
          ],
        );

        final original = TrainConsumingSkillUntil(
          Skill.smithing,
          const StopAtNextBoundary(Skill.smithing),
          consumeActionId: bronzeDagger.id,
          inputChains: {bronzeBarId: inputChain},
          sellPolicySpec: const ReserveConsumingInputsSpec(),
        );

        final json = original.toJson();
        final restored = MacroCandidate.fromJson(json);

        expect(restored, isA<TrainConsumingSkillUntil>());
        final restoredMacro = restored as TrainConsumingSkillUntil;
        expect(restoredMacro.inputChains, isNotNull);
        expect(restoredMacro.inputChains!.containsKey(bronzeBarId), isTrue);

        final restoredChain = restoredMacro.inputChains![bronzeBarId]!;
        expect(restoredChain.itemId, bronzeBarId);
        expect(restoredChain.quantity, 10);
        expect(restoredChain.children, hasLength(2));
        expect(restoredChain.children[0].itemId, copperOreId);
        expect(restoredChain.children[1].itemId, tinOreId);

        expect(restoredMacro.sellPolicySpec, isA<ReserveConsumingInputsSpec>());
      },
    );

    test('TrainConsumingSkillUntil with minimal fields round-trips', () {
      const original = TrainConsumingSkillUntil(
        Skill.cooking,
        StopWhenInputsDepleted(),
      );

      final json = original.toJson();
      final restored = MacroCandidate.fromJson(json);

      expect(restored, isA<TrainConsumingSkillUntil>());
      final restoredMacro = restored as TrainConsumingSkillUntil;
      expect(restoredMacro.consumingSkill, Skill.cooking);
      expect(restoredMacro.consumeActionId, isNull);
      expect(restoredMacro.producerByInputItem, isNull);
      expect(restoredMacro.bufferTarget, isNull);
      expect(restoredMacro.sellPolicySpec, isNull);
      expect(restoredMacro.inputChains, isNull);
      expect(restoredMacro.maxRecoveryAttempts, 3); // default value
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownMacro', 'foo': 'bar'};

      expect(
        () => MacroCandidate.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MacroStopRule JSON serialization', () {
    test('StopAtNextBoundary round-trips through JSON', () {
      const original = StopAtNextBoundary(Skill.fishing);

      final json = original.toJson();
      final restored = MacroStopRule.fromJson(json);

      expect(restored, isA<StopAtNextBoundary>());
      final restoredRule = restored as StopAtNextBoundary;
      expect(restoredRule.skill, Skill.fishing);
    });

    test('StopAtGoal round-trips through JSON', () {
      const original = StopAtGoal(Skill.mining, 10000);

      final json = original.toJson();
      final restored = MacroStopRule.fromJson(json);

      expect(restored, isA<StopAtGoal>());
      final restoredRule = restored as StopAtGoal;
      expect(restoredRule.skill, Skill.mining);
      expect(restoredRule.targetXp, 10000);
    });

    test('StopAtLevel round-trips through JSON', () {
      const original = StopAtLevel(Skill.smithing, 50);

      final json = original.toJson();
      final restored = MacroStopRule.fromJson(json);

      expect(restored, isA<StopAtLevel>());
      final restoredRule = restored as StopAtLevel;
      expect(restoredRule.skill, Skill.smithing);
      expect(restoredRule.level, 50);
    });

    test('StopWhenUpgradeAffordable round-trips through JSON', () {
      const original = StopWhenUpgradeAffordable(
        MelvorId('melvorD:Steel_Axe'),
        500,
        'Steel Axe',
      );

      final json = original.toJson();
      final restored = MacroStopRule.fromJson(json);

      expect(restored, isA<StopWhenUpgradeAffordable>());
      final restoredRule = restored as StopWhenUpgradeAffordable;
      expect(restoredRule.purchaseId, const MelvorId('melvorD:Steel_Axe'));
      expect(restoredRule.cost, 500);
      expect(restoredRule.upgradeName, 'Steel Axe');
    });

    test('StopWhenInputsDepleted round-trips through JSON', () {
      const original = StopWhenInputsDepleted();

      final json = original.toJson();
      final restored = MacroStopRule.fromJson(json);

      expect(restored, isA<StopWhenInputsDepleted>());
    });

    test('fromJson throws for unknown type', () {
      final json = {'type': 'UnknownStopRule'};

      expect(() => MacroStopRule.fromJson(json), throwsA(isA<ArgumentError>()));
    });
  });

  group('MacroStopRule', () {
    group('StopAtNextBoundary', () {
      test('toWaitFor returns WaitForSkillXp with next boundary level', () {
        final state = GlobalState.empty(testRegistries);
        const stopRule = StopAtNextBoundary(Skill.woodcutting);

        // Create boundaries with a level 10 unlock
        final boundaries = {
          Skill.woodcutting: const SkillBoundaries(Skill.woodcutting, [10]),
        };

        final waitFor = stopRule.toWaitFor(state, boundaries);

        expect(waitFor, isA<WaitForSkillXp>());
        final waitForXp = waitFor as WaitForSkillXp;
        expect(waitForXp.skill, Skill.woodcutting);
        expect(waitForXp.targetXp, startXpForLevel(10));
      });

      test('toWaitFor targets level 99 when no more boundaries', () {
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.woodcutting: SkillState(xp: 1000000, masteryPoolXp: 0),
          },
        );
        const stopRule = StopAtNextBoundary(Skill.woodcutting);

        // Create boundaries with a low level already passed
        final boundaries = {
          Skill.woodcutting: const SkillBoundaries(Skill.woodcutting, [5]),
        };

        final waitFor = stopRule.toWaitFor(state, boundaries);

        expect(waitFor, isA<WaitForSkillXp>());
        final waitForXp = waitFor as WaitForSkillXp;
        expect(waitForXp.targetXp, startXpForLevel(99));
      });
    });

    group('StopAtGoal', () {
      test('toWaitFor returns WaitForSkillXp with target XP', () {
        final state = GlobalState.empty(testRegistries);
        const stopRule = StopAtGoal(Skill.fishing, 5000);

        final waitFor = stopRule.toWaitFor(state, <Skill, SkillBoundaries>{});

        expect(waitFor, isA<WaitForSkillXp>());
        final waitForXp = waitFor as WaitForSkillXp;
        expect(waitForXp.skill, Skill.fishing);
        expect(waitForXp.targetXp, 5000);
      });
    });

    group('StopAtLevel', () {
      test('toWaitFor returns WaitForSkillXp for target level', () {
        final state = GlobalState.empty(testRegistries);
        const stopRule = StopAtLevel(Skill.mining, 50);

        final waitFor = stopRule.toWaitFor(state, <Skill, SkillBoundaries>{});

        expect(waitFor, isA<WaitForSkillXp>());
        final waitForXp = waitFor as WaitForSkillXp;
        expect(waitForXp.skill, Skill.mining);
        expect(waitForXp.targetXp, startXpForLevel(50));
      });

      test('stores skill and level', () {
        const stopRule = StopAtLevel(Skill.smithing, 30);

        expect(stopRule.skill, Skill.smithing);
        expect(stopRule.level, 30);
      });
    });

    group('StopWhenUpgradeAffordable', () {
      test('toWaitFor returns WaitForEffectiveCredits', () {
        final state = GlobalState.empty(testRegistries);
        const stopRule = StopWhenUpgradeAffordable(
          MelvorId('melvorD:Iron_Axe'),
          50,
          'Iron Axe',
        );

        final waitFor = stopRule.toWaitFor(state, <Skill, SkillBoundaries>{});

        expect(waitFor, isA<WaitForEffectiveCredits>());
        final waitForCredits = waitFor as WaitForEffectiveCredits;
        expect(waitForCredits.targetValue, 50);
      });

      test('stores purchase id, cost, and name', () {
        const stopRule = StopWhenUpgradeAffordable(
          MelvorId('melvorD:Steel_Axe'),
          200,
          'Steel Axe',
        );

        expect(stopRule.purchaseId, const MelvorId('melvorD:Steel_Axe'));
        expect(stopRule.cost, 200);
        expect(stopRule.upgradeName, 'Steel Axe');
      });
    });

    group('StopWhenInputsDepleted', () {
      test('toWaitFor returns WaitForInputsDepleted with active action', () {
        final logs = testItems.byName('Normal Logs');
        final inventory = Inventory.fromItems(testItems, [
          ItemStack(logs, count: 10),
        ]);
        var state = GlobalState.test(testRegistries, inventory: inventory);
        final action = testActions.firemaking('Burn Normal Logs');
        state = state.startAction(action, random: Random(0));

        const stopRule = StopWhenInputsDepleted();

        final waitFor = stopRule.toWaitFor(state, <Skill, SkillBoundaries>{});

        expect(waitFor, isA<WaitForInputsDepleted>());
        final waitForInputs = waitFor as WaitForInputsDepleted;
        expect(waitForInputs.actionId, action.id);
      });

      test('toWaitFor throws when no active action', () {
        final state = GlobalState.empty(testRegistries);
        const stopRule = StopWhenInputsDepleted();

        expect(
          () => stopRule.toWaitFor(state, <Skill, SkillBoundaries>{}),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
