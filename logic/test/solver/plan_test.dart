import 'package:logic/logic.dart';
import 'package:logic/src/solver/analysis/wait_for.dart';
import 'package:logic/src/solver/candidates/macro_candidate.dart';
import 'package:logic/src/solver/execution/plan.dart';
import 'package:logic/src/solver/interactions/interaction.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await loadTestRegistries();
  });
  group('GoalReachedBoundary', () {
    test('describe returns human-readable string', () {
      const boundary = GoalReachedBoundary();
      expect(boundary.describe(), 'Goal reached');
    });
  });

  group('UpgradeAffordableBoundary', () {
    test('describe includes upgrade name', () {
      const boundary = UpgradeAffordableBoundary(
        MelvorId('melvorD:Auto_Eat_Tier_I'),
        'Auto Eat Tier I',
      );
      expect(boundary.describe(), 'Upgrade Auto Eat Tier I affordable');
    });

    test('stores purchaseId correctly', () {
      const purchaseId = MelvorId('melvorD:Bank_Slot');
      const boundary = UpgradeAffordableBoundary(purchaseId, 'Bank Slot');
      expect(boundary.purchaseId, purchaseId);
    });
  });

  group('UnlockBoundary', () {
    test('describe includes skill, level, and unlocks', () {
      const boundary = UnlockBoundary(Skill.woodcutting, 15, 'Oak Trees');
      expect(boundary.describe(), 'Woodcutting L15 unlocks Oak Trees');
    });

    test('stores skill, level, and unlocks correctly', () {
      const boundary = UnlockBoundary(Skill.fishing, 20, 'Trout');
      expect(boundary.skill, Skill.fishing);
      expect(boundary.level, 20);
      expect(boundary.unlocks, 'Trout');
    });
  });

  group('InputsDepletedBoundary', () {
    test('describe includes action name', () {
      final actionId = ActionId.test(Skill.firemaking, 'Burn Oak Logs');
      final boundary = InputsDepletedBoundary(
        actionId,
        const MelvorId('melvorD:Oak_Logs'),
      );
      expect(boundary.describe(), contains('Burn Oak Logs'));
    });

    test('stores actionId correctly', () {
      final actionId = ActionId.test(Skill.cooking, 'Cook Shrimp');
      final boundary = InputsDepletedBoundary(
        actionId,
        const MelvorId('melvorD:Shrimp'),
      );
      expect(boundary.actionId, actionId);
    });
  });

  group('HorizonCapBoundary', () {
    test('describe includes ticks elapsed', () {
      const boundary = HorizonCapBoundary(86400);
      expect(boundary.describe(), 'Horizon cap reached (86400 ticks)');
    });

    test('stores ticksElapsed correctly', () {
      const boundary = HorizonCapBoundary(50000);
      expect(boundary.ticksElapsed, 50000);
    });
  });

  group('InventoryPressureBoundary', () {
    test('describe includes used and total slots', () {
      const boundary = InventoryPressureBoundary(45, 50);
      expect(boundary.describe(), 'Inventory pressure (45/50 slots)');
    });

    test('stores usedSlots and totalSlots correctly', () {
      const boundary = InventoryPressureBoundary(30, 40);
      expect(boundary.usedSlots, 30);
      expect(boundary.totalSlots, 40);
    });
  });

  group('Plan.prettyPrint', () {
    test('prints header with plan stats', () {
      const plan = Plan(
        steps: [],
        totalTicks: 1000,
        interactionCount: 5,
        expandedNodes: 100,
        enqueuedNodes: 200,
      );

      final output = plan.prettyPrint();

      expect(output, contains('=== Plan ==='));
      expect(output, contains('Total ticks: 1000'));
      expect(output, contains('Interactions: 5'));
      expect(output, contains('Expanded nodes: 100'));
      expect(output, contains('Enqueued nodes: 200'));
      expect(output, contains('Steps (0 total)'));
    });

    test('formats SwitchActivity step with action registry', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [InteractionStep(SwitchActivity(action.id))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint(actions: testActions);

      expect(output, contains('Switch to Normal Tree (woodcutting)'));
    });

    test('formats SwitchActivity step without action registry', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [InteractionStep(SwitchActivity(action.id))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Switch to'));
      expect(output, contains(action.id.toString()));
    });

    test('formats BuyShopItem step', () {
      const purchaseId = MelvorId('melvorD:Iron_Axe');
      const plan = Plan(
        steps: [InteractionStep(BuyShopItem(purchaseId))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Buy Iron Axe'));
    });

    test('formats SellItems with SellAllPolicy', () {
      const plan = Plan(
        steps: [InteractionStep(SellItems(SellAllPolicy()))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Sell all'));
    });

    test('formats SellItems with SellExceptPolicy', () {
      final plan = Plan(
        steps: [
          InteractionStep(
            SellItems(
              SellExceptPolicy({
                const MelvorId('melvorD:Normal_Logs'),
                const MelvorId('melvorD:Oak_Logs'),
              }),
            ),
          ),
        ],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Sell all except'));
    });

    test('formats WaitStep with duration', () {
      // 6000 ticks = 600 seconds = 10 minutes
      const plan = Plan(
        steps: [WaitStep(6000, WaitForSkillXp(Skill.woodcutting, 1000))],
        totalTicks: 6000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('10m 0s'));
      expect(output, contains('Skill +1'));
    });

    test('formats WaitStep with expected action', () {
      final action = testActions.woodcutting('Oak Tree');
      final plan = Plan(
        steps: [
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 500),
            expectedAction: action.id,
          ),
        ],
        totalTicks: 3000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint(actions: testActions);

      expect(output, contains('Oak Tree'));
    });

    test('formats MacroStep for TrainSkillUntil', () {
      const macro = TrainSkillUntil(
        Skill.mining,
        StopAtNextBoundary(Skill.mining),
      );
      const plan = Plan(
        steps: [
          MacroStep(
            macro,
            36000, // 1 hour
            WaitForSkillXp(Skill.mining, 10000),
          ),
        ],
        totalTicks: 36000,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Macro: Mining'));
      expect(output, contains('1h 0m'));
    });

    test('formats MacroStep for AcquireItem', () {
      const macro = AcquireItem(MelvorId('melvorD:Normal_Logs'), 50);
      const plan = Plan(
        steps: [
          MacroStep(
            macro,
            1200,
            WaitForInventoryAtLeast(MelvorId('melvorD:Normal_Logs'), 50),
          ),
        ],
        totalTicks: 1200,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('Macro: Acquire 50x Normal Logs'));
    });

    test('formats duration in hours and minutes', () {
      const plan = Plan(
        steps: [
          WaitStep(
            39600, // 3960 seconds = 1h 6m
            WaitForSkillXp(Skill.fishing, 50000),
          ),
        ],
        totalTicks: 39600,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('1h 6m'));
    });

    test('formats duration in minutes and seconds', () {
      const plan = Plan(
        steps: [
          WaitStep(
            1230, // 123 seconds = 2m 3s
            WaitForSkillXp(Skill.fishing, 500),
          ),
        ],
        totalTicks: 1230,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('2m 3s'));
    });

    test('formats duration in seconds only', () {
      const plan = Plan(
        steps: [
          WaitStep(
            450, // 45 seconds
            WaitForSkillXp(Skill.fishing, 100),
          ),
        ],
        totalTicks: 450,
        interactionCount: 0,
      );

      final output = plan.prettyPrint();

      expect(output, contains('45s'));
    });

    test('respects maxSteps parameter', () {
      final steps = List.generate(
        50,
        (i) => InteractionStep(BuyShopItem(MelvorId('melvorD:Item_$i'))),
      );
      final plan = Plan(steps: steps, totalTicks: 0, interactionCount: 50);

      final output = plan.prettyPrint(maxSteps: 10);

      expect(output, contains('Steps (50 total)'));
      expect(output, contains('... and 40 more steps'));
    });

    test('numbers steps starting from 1', () {
      const plan = Plan(
        steps: [
          InteractionStep(SellItems(SellAllPolicy())),
          InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe'))),
        ],
        totalTicks: 0,
        interactionCount: 2,
      );

      final output = plan.prettyPrint();

      expect(output, contains('1. Sell all'));
      expect(output, contains('2. Buy Iron Axe'));
    });

    test('empty plan shows zero steps', () {
      const plan = Plan.empty();

      final output = plan.prettyPrint();

      expect(output, contains('Steps (0 total)'));
      expect(output, contains('Total ticks: 0'));
    });
  });

  group('Plan.toJson/fromJson', () {
    test('round trips empty plan', () {
      const plan = Plan.empty();

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps, isEmpty);
      expect(restored.totalTicks, plan.totalTicks);
      expect(restored.interactionCount, plan.interactionCount);
      expect(restored.expandedNodes, plan.expandedNodes);
      expect(restored.enqueuedNodes, plan.enqueuedNodes);
      expect(restored.expectedDeaths, plan.expectedDeaths);
      expect(restored.segmentMarkers, isEmpty);
    });

    test('round trips plan with InteractionSteps', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(action.id)),
          const InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe'))),
          const InteractionStep(SellItems(SellAllPolicy())),
          InteractionStep(
            SellItems(
              SellExceptPolicy({
                const MelvorId('melvorD:Normal_Logs'),
                const MelvorId('melvorD:Oak_Logs'),
              }),
            ),
          ),
        ],
        totalTicks: 1000,
        interactionCount: 4,
        expandedNodes: 50,
        enqueuedNodes: 100,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 4);
      expect(restored.totalTicks, 1000);
      expect(restored.interactionCount, 4);
      expect(restored.expandedNodes, 50);
      expect(restored.enqueuedNodes, 100);

      // Verify each step type
      expect(restored.steps[0], isA<InteractionStep>());
      final step0 = restored.steps[0] as InteractionStep;
      expect(step0.interaction, isA<SwitchActivity>());
      expect((step0.interaction as SwitchActivity).actionId, action.id);

      expect(restored.steps[1], isA<InteractionStep>());
      final step1 = restored.steps[1] as InteractionStep;
      expect(step1.interaction, isA<BuyShopItem>());
      expect(
        (step1.interaction as BuyShopItem).purchaseId,
        const MelvorId('melvorD:Iron_Axe'),
      );

      expect(restored.steps[2], isA<InteractionStep>());
      final step2 = restored.steps[2] as InteractionStep;
      expect(step2.interaction, isA<SellItems>());
      expect((step2.interaction as SellItems).policy, isA<SellAllPolicy>());

      expect(restored.steps[3], isA<InteractionStep>());
      final step3 = restored.steps[3] as InteractionStep;
      expect(step3.interaction, isA<SellItems>());
      final policy3 =
          (step3.interaction as SellItems).policy as SellExceptPolicy;
      expect(
        policy3.keepItems,
        contains(const MelvorId('melvorD:Normal_Logs')),
      );
      expect(policy3.keepItems, contains(const MelvorId('melvorD:Oak_Logs')));
    });

    test('round trips plan with WaitSteps', () {
      final action = testActions.woodcutting('Oak Tree');
      final plan = Plan(
        steps: [
          const WaitStep(6000, WaitForSkillXp(Skill.woodcutting, 1000)),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.fishing, 500, reason: 'Level 10'),
            expectedAction: action.id,
          ),
          WaitStep(1000, WaitForMasteryXp(action.id, 200)),
          const WaitStep(500, WaitForInventoryThreshold(0.9)),
          const WaitStep(200, WaitForInventoryFull()),
        ],
        totalTicks: 10700,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 5);
      expect(restored.totalTicks, 10700);

      // WaitForSkillXp without reason
      final step0 = restored.steps[0] as WaitStep;
      expect(step0.deltaTicks, 6000);
      expect(step0.waitFor, isA<WaitForSkillXp>());
      final wait0 = step0.waitFor as WaitForSkillXp;
      expect(wait0.skill, Skill.woodcutting);
      expect(wait0.targetXp, 1000);
      expect(step0.expectedAction, isNull);

      // WaitForSkillXp with reason and expectedAction
      final step1 = restored.steps[1] as WaitStep;
      expect(step1.deltaTicks, 3000);
      expect(step1.expectedAction, action.id);
      final wait1 = step1.waitFor as WaitForSkillXp;
      expect(wait1.reason, 'Level 10');

      // WaitForMasteryXp
      final step2 = restored.steps[2] as WaitStep;
      expect(step2.waitFor, isA<WaitForMasteryXp>());
      final wait2 = step2.waitFor as WaitForMasteryXp;
      expect(wait2.actionId, action.id);
      expect(wait2.targetMasteryXp, 200);

      // WaitForInventoryThreshold
      final step3 = restored.steps[3] as WaitStep;
      expect(step3.waitFor, isA<WaitForInventoryThreshold>());
      expect((step3.waitFor as WaitForInventoryThreshold).threshold, 0.9);

      // WaitForInventoryFull
      final step4 = restored.steps[4] as WaitStep;
      expect(step4.waitFor, isA<WaitForInventoryFull>());
    });

    test('round trips plan with WaitForEffectiveCredits', () {
      final plan = Plan(
        steps: [
          const WaitStep(
            1000,
            WaitForEffectiveCredits(
              5000,
              sellPolicy: SellAllPolicy(),
              reason: 'Steel Axe',
            ),
          ),
          WaitStep(
            2000,
            WaitForEffectiveCredits(
              10000,
              sellPolicy: SellExceptPolicy({
                const MelvorId('melvorD:Oak_Logs'),
              }),
            ),
          ),
        ],
        totalTicks: 3000,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 2);

      final step0 = restored.steps[0] as WaitStep;
      expect(step0.waitFor, isA<WaitForEffectiveCredits>());
      final wait0 = step0.waitFor as WaitForEffectiveCredits;
      expect(wait0.targetValue, 5000);
      expect(wait0.reason, 'Steel Axe');
      expect(wait0.sellPolicy, isA<SellAllPolicy>());

      final step1 = restored.steps[1] as WaitStep;
      final wait1 = step1.waitFor as WaitForEffectiveCredits;
      expect(wait1.sellPolicy, isA<SellExceptPolicy>());
    });

    test(
      'round trips plan with WaitForInputsDepleted and WaitForInputsAvailable',
      () {
        final action = testActions.firemaking('Burn Normal Logs');
        final plan = Plan(
          steps: [
            WaitStep(1000, WaitForInputsDepleted(action.id)),
            WaitStep(2000, WaitForInputsAvailable(action.id)),
          ],
          totalTicks: 3000,
          interactionCount: 0,
        );

        final json = plan.toJson();
        final restored = Plan.fromJson(json);

        expect(restored.steps.length, 2);

        final step0 = restored.steps[0] as WaitStep;
        expect(step0.waitFor, isA<WaitForInputsDepleted>());
        expect((step0.waitFor as WaitForInputsDepleted).actionId, action.id);

        final step1 = restored.steps[1] as WaitStep;
        expect(step1.waitFor, isA<WaitForInputsAvailable>());
        expect((step1.waitFor as WaitForInputsAvailable).actionId, action.id);
      },
    );

    test(
      'round trips plan with WaitForInventoryAtLeast and WaitForInventoryDelta',
      () {
        const plan = Plan(
          steps: [
            WaitStep(
              1000,
              WaitForInventoryAtLeast(MelvorId('melvorD:Normal_Logs'), 50),
            ),
            WaitStep(
              2000,
              WaitForInventoryDelta(
                MelvorId('melvorD:Oak_Logs'),
                25,
                startCount: 10,
              ),
            ),
          ],
          totalTicks: 3000,
          interactionCount: 0,
        );

        final json = plan.toJson();
        final restored = Plan.fromJson(json);

        final step0 = restored.steps[0] as WaitStep;
        expect(step0.waitFor, isA<WaitForInventoryAtLeast>());
        final wait0 = step0.waitFor as WaitForInventoryAtLeast;
        expect(wait0.itemId, const MelvorId('melvorD:Normal_Logs'));
        expect(wait0.minCount, 50);

        final step1 = restored.steps[1] as WaitStep;
        expect(step1.waitFor, isA<WaitForInventoryDelta>());
        final wait1 = step1.waitFor as WaitForInventoryDelta;
        expect(wait1.itemId, const MelvorId('melvorD:Oak_Logs'));
        expect(wait1.delta, 25);
        expect(wait1.startCount, 10);
      },
    );

    test('round trips plan with WaitForSufficientInputs', () {
      final action = testActions.firemaking('Burn Normal Logs');
      final plan = Plan(
        steps: [WaitStep(1000, WaitForSufficientInputs(action.id, 100))],
        totalTicks: 1000,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      final step0 = restored.steps[0] as WaitStep;
      expect(step0.waitFor, isA<WaitForSufficientInputs>());
      final wait0 = step0.waitFor as WaitForSufficientInputs;
      expect(wait0.actionId, action.id);
      expect(wait0.targetCount, 100);
    });

    test('round trips plan with WaitForAnyOf', () {
      const plan = Plan(
        steps: [
          WaitStep(
            5000,
            WaitForAnyOf([
              WaitForSkillXp(Skill.woodcutting, 1000),
              WaitForInventoryFull(),
              WaitForEffectiveCredits(500, sellPolicy: SellAllPolicy()),
            ]),
          ),
        ],
        totalTicks: 5000,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      final step0 = restored.steps[0] as WaitStep;
      expect(step0.waitFor, isA<WaitForAnyOf>());
      final anyOf = step0.waitFor as WaitForAnyOf;
      expect(anyOf.conditions.length, 3);
      expect(anyOf.conditions[0], isA<WaitForSkillXp>());
      expect(anyOf.conditions[1], isA<WaitForInventoryFull>());
      expect(anyOf.conditions[2], isA<WaitForEffectiveCredits>());
    });

    test('round trips plan with MacroSteps', () {
      const plan = Plan(
        steps: [
          MacroStep(
            TrainSkillUntil(
              Skill.mining,
              StopAtNextBoundary(Skill.mining),
              watchedStops: [
                StopWhenUpgradeAffordable(
                  MelvorId('melvorD:Iron_Pickaxe'),
                  1000,
                  'Iron Pickaxe',
                ),
              ],
            ),
            36000,
            WaitForSkillXp(Skill.mining, 10000),
          ),
          MacroStep(
            TrainSkillUntil(
              Skill.woodcutting,
              StopAtGoal(Skill.woodcutting, 50000),
            ),
            72000,
            WaitForSkillXp(Skill.woodcutting, 50000),
          ),
          MacroStep(
            TrainSkillUntil(Skill.fishing, StopAtLevel(Skill.fishing, 20)),
            18000,
            WaitForSkillXp(Skill.fishing, 4470),
          ),
        ],
        totalTicks: 126000,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 3);

      // TrainSkillUntil with StopAtNextBoundary and watchedStops
      final step0 = restored.steps[0] as MacroStep;
      expect(step0.macro, isA<TrainSkillUntil>());
      final macro0 = step0.macro as TrainSkillUntil;
      expect(macro0.skill, Skill.mining);
      expect(macro0.primaryStop, isA<StopAtNextBoundary>());
      expect(macro0.watchedStops.length, 1);
      expect(macro0.watchedStops[0], isA<StopWhenUpgradeAffordable>());
      expect(step0.deltaTicks, 36000);

      // TrainSkillUntil with StopAtGoal
      final step1 = restored.steps[1] as MacroStep;
      final macro1 = step1.macro as TrainSkillUntil;
      expect(macro1.primaryStop, isA<StopAtGoal>());
      final stop1 = macro1.primaryStop as StopAtGoal;
      expect(stop1.skill, Skill.woodcutting);
      expect(stop1.targetXp, 50000);

      // TrainSkillUntil with StopAtLevel
      final step2 = restored.steps[2] as MacroStep;
      final macro2 = step2.macro as TrainSkillUntil;
      expect(macro2.primaryStop, isA<StopAtLevel>());
      final stop2 = macro2.primaryStop as StopAtLevel;
      expect(stop2.skill, Skill.fishing);
      expect(stop2.level, 20);
    });

    test('round trips plan with AcquireItem and EnsureStock macros', () {
      const plan = Plan(
        steps: [
          MacroStep(
            AcquireItem(MelvorId('melvorD:Normal_Logs'), 50),
            1200,
            WaitForInventoryAtLeast(MelvorId('melvorD:Normal_Logs'), 50),
          ),
          MacroStep(
            EnsureStock(MelvorId('melvorD:Oak_Logs'), 100),
            2400,
            WaitForInventoryAtLeast(MelvorId('melvorD:Oak_Logs'), 100),
          ),
        ],
        totalTicks: 3600,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 2);

      final step0 = restored.steps[0] as MacroStep;
      expect(step0.macro, isA<AcquireItem>());
      final macro0 = step0.macro as AcquireItem;
      expect(macro0.itemId, const MelvorId('melvorD:Normal_Logs'));
      expect(macro0.quantity, 50);

      final step1 = restored.steps[1] as MacroStep;
      expect(step1.macro, isA<EnsureStock>());
      final macro1 = step1.macro as EnsureStock;
      expect(macro1.itemId, const MelvorId('melvorD:Oak_Logs'));
      expect(macro1.minTotal, 100);
    });

    test('round trips plan with TrainConsumingSkillUntil macro', () {
      final plan = Plan(
        steps: [
          MacroStep(
            TrainConsumingSkillUntil(
              Skill.firemaking,
              const StopAtNextBoundary(Skill.firemaking),
              watchedStops: const [StopWhenInputsDepleted()],
              consumeActionId: testActions.firemaking('Burn Normal Logs').id,
              producerByInputItem: {
                const MelvorId('melvorD:Normal_Logs'): testActions
                    .woodcutting('Normal Tree')
                    .id,
              },
              bufferTarget: 20,
              sellPolicySpec: const ReserveConsumingInputsSpec(),
              maxRecoveryAttempts: 5,
            ),
            50000,
            const WaitForSkillXp(Skill.firemaking, 5000),
          ),
        ],
        totalTicks: 50000,
        interactionCount: 0,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 1);

      final step0 = restored.steps[0] as MacroStep;
      expect(step0.macro, isA<TrainConsumingSkillUntil>());
      final macro = step0.macro as TrainConsumingSkillUntil;
      expect(macro.consumingSkill, Skill.firemaking);
      expect(macro.primaryStop, isA<StopAtNextBoundary>());
      expect(macro.watchedStops.length, 1);
      expect(macro.watchedStops[0], isA<StopWhenInputsDepleted>());
      expect(
        macro.consumeActionId,
        testActions.firemaking('Burn Normal Logs').id,
      );
      expect(macro.producerByInputItem, isNotNull);
      expect(
        macro.producerByInputItem![const MelvorId('melvorD:Normal_Logs')],
        testActions.woodcutting('Normal Tree').id,
      );
      expect(macro.bufferTarget, 20);
      expect(macro.sellPolicySpec, isA<ReserveConsumingInputsSpec>());
      expect(macro.maxRecoveryAttempts, 5);
    });

    test('round trips plan with segment markers', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(action.id)),
          const WaitStep(5000, WaitForSkillXp(Skill.woodcutting, 1000)),
          const InteractionStep(SellItems(SellAllPolicy())),
          const WaitStep(3000, WaitForSkillXp(Skill.woodcutting, 2000)),
        ],
        totalTicks: 8000,
        interactionCount: 2,
        segmentMarkers: const [
          SegmentMarker(
            stepIndex: 0,
            boundary: UnlockBoundary(Skill.woodcutting, 15, 'Oak Trees'),
            sellPolicy: SellAllPolicy(),
            description: 'Train WC to 15',
          ),
          SegmentMarker(stepIndex: 2, boundary: GoalReachedBoundary()),
        ],
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.segmentMarkers.length, 2);

      final marker0 = restored.segmentMarkers[0];
      expect(marker0.stepIndex, 0);
      expect(marker0.boundary, isA<UnlockBoundary>());
      final boundary0 = marker0.boundary as UnlockBoundary;
      expect(boundary0.skill, Skill.woodcutting);
      expect(boundary0.level, 15);
      expect(boundary0.unlocks, 'Oak Trees');
      expect(marker0.sellPolicy, isA<SellAllPolicy>());
      expect(marker0.description, 'Train WC to 15');

      final marker1 = restored.segmentMarkers[1];
      expect(marker1.stepIndex, 2);
      expect(marker1.boundary, isA<GoalReachedBoundary>());
      expect(marker1.sellPolicy, isNull);
      expect(marker1.description, isNull);
    });

    test('round trips plan with all segment boundary types', () {
      final action = testActions.firemaking('Burn Normal Logs');
      // Build plan with all boundary types in order
      final plan = Plan(
        steps: const [],
        totalTicks: 0,
        interactionCount: 0,
        segmentMarkers: [
          const SegmentMarker(stepIndex: 0, boundary: GoalReachedBoundary()),
          const SegmentMarker(
            stepIndex: 1,
            boundary: UpgradeAffordableBoundary(
              MelvorId('melvorD:Steel_Axe'),
              'Steel Axe',
            ),
          ),
          const SegmentMarker(
            stepIndex: 2,
            boundary: UnlockBoundary(Skill.mining, 30, 'Mithril Rocks'),
          ),
          SegmentMarker(
            stepIndex: 3,
            boundary: InputsDepletedBoundary(
              action.id,
              const MelvorId('melvorD:Normal_Logs'),
            ),
          ),
          const SegmentMarker(
            stepIndex: 4,
            boundary: HorizonCapBoundary(100000),
          ),
          const SegmentMarker(
            stepIndex: 5,
            boundary: InventoryPressureBoundary(45, 50),
          ),
        ],
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.segmentMarkers.length, 6);

      // GoalReachedBoundary
      expect(restored.segmentMarkers[0].boundary, isA<GoalReachedBoundary>());

      // UpgradeAffordableBoundary
      expect(
        restored.segmentMarkers[1].boundary,
        isA<UpgradeAffordableBoundary>(),
      );
      final boundary1 =
          restored.segmentMarkers[1].boundary as UpgradeAffordableBoundary;
      expect(boundary1.purchaseId, const MelvorId('melvorD:Steel_Axe'));
      expect(boundary1.upgradeName, 'Steel Axe');

      // UnlockBoundary
      expect(restored.segmentMarkers[2].boundary, isA<UnlockBoundary>());

      // InputsDepletedBoundary
      expect(
        restored.segmentMarkers[3].boundary,
        isA<InputsDepletedBoundary>(),
      );
      final boundary3 =
          restored.segmentMarkers[3].boundary as InputsDepletedBoundary;
      expect(boundary3.actionId, action.id);

      // HorizonCapBoundary
      expect(restored.segmentMarkers[4].boundary, isA<HorizonCapBoundary>());
      final boundary4 =
          restored.segmentMarkers[4].boundary as HorizonCapBoundary;
      expect(boundary4.ticksElapsed, 100000);

      // InventoryPressureBoundary
      expect(
        restored.segmentMarkers[5].boundary,
        isA<InventoryPressureBoundary>(),
      );
      final boundary5 =
          restored.segmentMarkers[5].boundary as InventoryPressureBoundary;
      expect(boundary5.usedSlots, 45);
      expect(boundary5.totalSlots, 50);
    });

    test('round trips plan with expectedDeaths', () {
      const plan = Plan(
        steps: [],
        totalTicks: 10000,
        interactionCount: 5,
        expectedDeaths: 3,
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.expectedDeaths, 3);
    });

    test('round trips complex plan with mixed step types', () {
      final wcAction = testActions.woodcutting('Normal Tree');
      final fmAction = testActions.firemaking('Burn Normal Logs');

      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(wcAction.id)),
          WaitStep(
            5000,
            const WaitForAnyOf([
              WaitForSkillXp(Skill.woodcutting, 1000),
              WaitForInventoryThreshold(0.9),
            ]),
            expectedAction: wcAction.id,
          ),
          const InteractionStep(SellItems(SellAllPolicy())),
          const MacroStep(
            TrainSkillUntil(
              Skill.woodcutting,
              StopAtNextBoundary(Skill.woodcutting),
            ),
            20000,
            WaitForSkillXp(Skill.woodcutting, 5000),
          ),
          InteractionStep(SwitchActivity(fmAction.id)),
          WaitStep(3000, WaitForInputsDepleted(fmAction.id)),
        ],
        totalTicks: 28000,
        interactionCount: 3,
        expandedNodes: 150,
        enqueuedNodes: 300,
        expectedDeaths: 1,
        segmentMarkers: [
          SegmentMarker(
            stepIndex: 0,
            boundary: const UnlockBoundary(Skill.woodcutting, 15, 'Oak Trees'),
            sellPolicy: SellExceptPolicy({
              const MelvorId('melvorD:Normal_Logs'),
            }),
          ),
          const SegmentMarker(stepIndex: 4, boundary: GoalReachedBoundary()),
        ],
      );

      final json = plan.toJson();
      final restored = Plan.fromJson(json);

      expect(restored.steps.length, 6);
      expect(restored.totalTicks, 28000);
      expect(restored.interactionCount, 3);
      expect(restored.expandedNodes, 150);
      expect(restored.enqueuedNodes, 300);
      expect(restored.expectedDeaths, 1);
      expect(restored.segmentMarkers.length, 2);

      // Verify step types
      expect(restored.steps[0], isA<InteractionStep>());
      expect(restored.steps[1], isA<WaitStep>());
      expect(restored.steps[2], isA<InteractionStep>());
      expect(restored.steps[3], isA<MacroStep>());
      expect(restored.steps[4], isA<InteractionStep>());
      expect(restored.steps[5], isA<WaitStep>());

      // Verify nested WaitForAnyOf
      final step1 = restored.steps[1] as WaitStep;
      expect(step1.waitFor, isA<WaitForAnyOf>());
      final anyOf = step1.waitFor as WaitForAnyOf;
      expect(anyOf.conditions.length, 2);

      // Verify segment marker sell policy
      final marker0 = restored.segmentMarkers[0];
      expect(marker0.sellPolicy, isA<SellExceptPolicy>());
    });
  });

  group('Plan.prettyPrintCompact', () {
    test('prints header with summary stats', () {
      const plan = Plan(
        steps: [],
        totalTicks: 36000,
        interactionCount: 10,
        expandedNodes: 100,
        enqueuedNodes: 200,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('=== Plan ==='));
      expect(output, contains('36000 ticks'));
      expect(output, contains('1h 0m'));
      expect(output, contains('10 interactions'));
      expect(output, contains('0 steps'));
    });

    test('shows empty plan message', () {
      const plan = Plan.empty();

      final output = plan.prettyPrintCompact();

      expect(output, contains('(empty plan)'));
    });

    test('formats SwitchActivity step', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [InteractionStep(SwitchActivity(action.id))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrintCompact(actions: testActions);

      expect(output, contains('Switch to Normal Tree'));
    });

    test('formats WaitStep with duration', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(action.id)),
          WaitStep(
            6000, // 10 minutes
            const WaitForSkillXp(Skill.woodcutting, 1000),
            expectedAction: action.id,
          ),
        ],
        totalTicks: 6000,
        interactionCount: 1,
      );

      final output = plan.prettyPrintCompact(actions: testActions);

      expect(output, contains('10m 0s'));
    });

    test('merges consecutive WaitSteps with same skill', () {
      final action = testActions.woodcutting('Normal Tree');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(action.id)),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 500),
            expectedAction: action.id,
          ),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 1000),
            expectedAction: action.id,
          ),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 1500),
            expectedAction: action.id,
          ),
        ],
        totalTicks: 9000,
        interactionCount: 1,
      );

      final output = plan.prettyPrintCompact(actions: testActions);

      // Should show merged duration and count (switch + 3 waits = 4 merged)
      expect(output, contains('15m 0s'));
      expect(output, contains('waits merged'));
    });

    test('groups steps by skill separately', () {
      final wcAction = testActions.woodcutting('Normal Tree');
      final fishAction = testActions.fishing('Raw Shrimp');
      final plan = Plan(
        steps: [
          InteractionStep(SwitchActivity(wcAction.id)),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.woodcutting, 500),
            expectedAction: wcAction.id,
          ),
          InteractionStep(SwitchActivity(fishAction.id)),
          WaitStep(
            3000,
            const WaitForSkillXp(Skill.fishing, 500),
            expectedAction: fishAction.id,
          ),
        ],
        totalTicks: 6000,
        interactionCount: 2,
      );

      final output = plan.prettyPrintCompact(actions: testActions);

      // Should have two separate groups (one for each skill)
      expect(output, contains('Normal Tree'));
      expect(output, contains('Raw Shrimp'));
    });

    test('formats MacroStep for TrainSkillUntil', () {
      const plan = Plan(
        steps: [
          MacroStep(
            TrainSkillUntil(Skill.mining, StopAtNextBoundary(Skill.mining)),
            36000,
            WaitForSkillXp(Skill.mining, 10000),
          ),
        ],
        totalTicks: 36000,
        interactionCount: 0,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('Mining'));
      expect(output, contains('1h 0m'));
    });

    test('formats BuyShopItem step', () {
      const plan = Plan(
        steps: [InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe')))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('Buy Iron Axe'));
    });

    test('formats SellItems step', () {
      const plan = Plan(
        steps: [InteractionStep(SellItems(SellAllPolicy()))],
        totalTicks: 0,
        interactionCount: 1,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('Sell all'));
    });

    test('respects firstSteps and lastSteps parameters', () {
      // Create a plan with 50 steps
      final steps = <PlanStep>[];
      for (var i = 0; i < 50; i++) {
        steps.add(InteractionStep(BuyShopItem(MelvorId('melvorD:Item_$i'))));
      }
      final plan = Plan(steps: steps, totalTicks: 0, interactionCount: 50);

      final output = plan.prettyPrintCompact(firstSteps: 5, lastSteps: 3);

      // Should show ellipsis for skipped middle section
      expect(output, contains('... '));
      expect(output, contains(' more steps'));
    });

    test('shows all steps when within threshold', () {
      final steps = <PlanStep>[];
      for (var i = 0; i < 10; i++) {
        steps.add(InteractionStep(BuyShopItem(MelvorId('melvorD:Item_$i'))));
      }
      final plan = Plan(steps: steps, totalTicks: 0, interactionCount: 10);

      // With firstSteps=25 + lastSteps=10 + threshold=5 = 40, 10 steps should all show
      final output = plan.prettyPrintCompact();

      // Should not have ellipsis
      expect(output, isNot(contains('... ')));
    });

    test('numbers steps starting from 1', () {
      const plan = Plan(
        steps: [
          InteractionStep(SellItems(SellAllPolicy())),
          InteractionStep(BuyShopItem(MelvorId('melvorD:Iron_Axe'))),
        ],
        totalTicks: 0,
        interactionCount: 2,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('1. '));
      expect(output, contains('2. '));
    });

    test('formats AcquireItem macro', () {
      const plan = Plan(
        steps: [
          MacroStep(
            AcquireItem(MelvorId('melvorD:Normal_Logs'), 50),
            1200,
            WaitForInventoryAtLeast(MelvorId('melvorD:Normal_Logs'), 50),
          ),
        ],
        totalTicks: 1200,
        interactionCount: 0,
      );

      final output = plan.prettyPrintCompact();

      expect(output, contains('Acquire 50x Normal Logs'));
    });

    test('includes segment count in middle summary when segments exist', () {
      // Create plan with many steps and segment markers in the middle
      final steps = <PlanStep>[];
      for (var i = 0; i < 100; i++) {
        steps.add(InteractionStep(BuyShopItem(MelvorId('melvorD:Item_$i'))));
      }
      final plan = Plan(
        steps: steps,
        totalTicks: 0,
        interactionCount: 100,
        segmentMarkers: const [
          SegmentMarker(stepIndex: 30, boundary: GoalReachedBoundary()),
          SegmentMarker(stepIndex: 50, boundary: GoalReachedBoundary()),
          SegmentMarker(stepIndex: 70, boundary: GoalReachedBoundary()),
        ],
      );

      final output = plan.prettyPrintCompact(firstSteps: 10);

      // Should mention segments in the skipped section
      expect(output, contains('segments'));
    });
  });
}
