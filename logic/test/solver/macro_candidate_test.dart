import 'dart:math';

import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/unlock_boundaries.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
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
