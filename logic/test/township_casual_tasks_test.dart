import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

const _deityId = MelvorId('melvorF:Test_Deity');
const _woodId = MelvorId('melvorF:Wood');
const _golbinId = MelvorId('melvorD:Golbin');

final _logs = Item.test('Normal Logs', gp: 1);
final _sword = Item.test('Bronze Sword', gp: 1);

/// A casual task donating 10 logs for 2500 Wood.
const _logsTaskId = MelvorId('melvorF:CasualTask0');

/// A casual task killing 3 Golbin with a Bronze Sword equipped.
const _swordTaskId = MelvorId('melvorF:CasualTask1');

/// A casual task killing 2 Golbin, gated on Attack 50.
const _gatedTaskId = MelvorId('melvorF:CasualTask2');

const _townshipXpReward = TaskReward(
  type: TaskRewardType.skillXP,
  id: MelvorId('melvorD:Township'),
  quantity: 400,
);
const _gpReward = TaskReward(
  type: TaskRewardType.currency,
  id: MelvorId('melvorD:GP'),
  quantity: 1,
);

final _registries = Registries.test(
  items: [_logs, _sword],
  township: TownshipRegistry(
    casualTasks: [
      TownshipTask(
        id: _logsTaskId,
        category: TaskCategory.casual,
        goals: [TaskGoal(type: TaskGoalType.items, id: _logs.id, quantity: 10)],
        rewards: const [
          _townshipXpReward,
          TaskReward(
            type: TaskRewardType.townshipResource,
            id: _woodId,
            quantity: 2500,
          ),
          _gpReward,
        ],
      ),
      TownshipTask(
        id: _swordTaskId,
        category: TaskCategory.casual,
        goals: [
          TaskGoal(
            type: TaskGoalType.monsterWithItems,
            id: _golbinId,
            quantity: 3,
            itemIds: [_sword.id],
          ),
        ],
        rewards: const [
          _townshipXpReward,
          _gpReward,
          TaskReward(
            type: TaskRewardType.currency,
            id: MelvorId('melvorD:SlayerCoins'),
            quantity: 100,
          ),
        ],
      ),
      const TownshipTask(
        id: _gatedTaskId,
        category: TaskCategory.casual,
        goals: [
          TaskGoal(type: TaskGoalType.monsters, id: _golbinId, quantity: 2),
        ],
        rewards: [_townshipXpReward, _gpReward],
        requirements: [SkillLevelRequirement(skill: Skill.attack, level: 50)],
      ),
    ],
  ),
);

GlobalState _state({
  List<MelvorId> activeCasualTasks = const [],
  Tick casualTaskTicksRemaining = 0,
  MelvorId? worshipId = _deityId,
  Map<Skill, SkillState> skillStates = const {},
  int gp = 0,
  Equipment equipment = const Equipment.empty(),
}) {
  return GlobalState.test(
    _registries,
    skillStates: skillStates,
    currencies: {Currency.gp: gp},
    equipment: equipment,
    township: TownshipState(
      registry: _registries.township,
      worshipId: worshipId,
      activeCasualTasks: activeCasualTasks,
      casualTaskTicksRemaining: casualTaskTicksRemaining,
    ),
  );
}

GlobalState _tick(GlobalState state, Tick ticks) {
  final builder = StateUpdateBuilder(state);
  consumeTicks(builder, ticks, random: Random(0));
  return builder.build();
}

void main() {
  group('casual task data', () {
    setUpAll(loadTestRegistries);

    test('parses casual tasks separately from main tasks', () {
      final township = testRegistries.township;
      expect(township.casualTasks, hasLength(170));
      expect(township.casualTasks.every((t) => t.isCasual), isTrue);
      expect(township.tasks.any((t) => t.isCasual), isFalse);

      final task = township.taskById(const MelvorId('melvorF:CasualTask1'));
      expect(task.isCasual, isTrue);
      expect(task.goals.single.type, TaskGoalType.items);
      expect(
        task.requirements,
        contains(const SkillLevelRequirement(skill: Skill.town, level: 5)),
      );
      expect(
        task.rewards.where((r) => r.type == TaskRewardType.townshipResource),
        isNotEmpty,
      );
    });

    test('parses monsterWithItems goals and ItemFound requirements', () {
      final task = testRegistries.township.taskById(
        const MelvorId('melvorF:CasualTask137'),
      );
      final goal = task.goals.single;
      expect(goal.type, TaskGoalType.monsterWithItems);
      expect(goal.id, _golbinId);
      expect(goal.quantity, 10);
      expect(goal.itemIds, [const MelvorId('melvorD:Bronze_2H_Sword')]);
      expect(
        task.requirements,
        contains(
          const ItemFoundRequirement(
            itemId: MelvorId('melvorD:Bronze_2H_Sword'),
          ),
        ),
      );
    });
  });

  group('TownshipState casual tasks', () {
    test('round-trips through JSON', () {
      final township = TownshipState(
        registry: _registries.township,
        activeCasualTasks: const [_swordTaskId, _logsTaskId],
        casualTaskTicksRemaining: 1234,
      );
      final restored = TownshipState.fromJson(
        _registries.township,
        township.toJson(),
      );
      expect(restored.activeCasualTasks, [_swordTaskId, _logsTaskId]);
      expect(restored.casualTaskTicksRemaining, 1234);
    });

    test('assignCasualTask never duplicates an active task', () {
      final township = TownshipState(
        registry: _registries.township,
        activeCasualTasks: const [_logsTaskId, _swordTaskId],
      );
      final assigned = township.assignCasualTask(
        _registries.township.casualTasks,
        Random(0),
      );
      expect(assigned.activeCasualTasks, [
        _logsTaskId,
        _swordTaskId,
        _gatedTaskId,
      ]);
      // Every candidate is now active, so nothing more is assigned.
      expect(
        assigned
            .assignCasualTask(_registries.township.casualTasks, Random(0))
            .activeCasualTasks,
        hasLength(3),
      );
    });

    test('assignCasualTask stops at maxActiveCasualTasks', () {
      final township = TownshipState(
        registry: _registries.township,
        activeCasualTasks: List.generate(
          maxActiveCasualTasks,
          (i) => MelvorId('melvorF:Other$i'),
        ),
      );
      final assigned = township.assignCasualTask(
        _registries.township.casualTasks,
        Random(0),
      );
      expect(assigned.activeCasualTasks, township.activeCasualTasks);
    });

    test('removeCasualTask discards progress', () {
      final township = TownshipState(
        registry: _registries.township,
        activeCasualTasks: const [_gatedTaskId],
      ).updateTaskProgress(_gatedTaskId, TaskGoalType.monsters, _golbinId, 1);
      final removed = township.removeCasualTask(_gatedTaskId);
      expect(removed.activeCasualTasks, isEmpty);
      expect(removed.tasks, isEmpty);
    });
  });

  group('casual task assignment over time', () {
    test('a founded town gets its first casual task right away', () {
      final state = _tick(_state(), 1);
      expect(state.township.activeCasualTasks, hasLength(1));
      expect(state.township.casualTaskTicksRemaining, ticksPerCasualTask - 1);
    });

    test('no casual tasks before a deity is chosen', () {
      final state = _tick(_state(worshipId: null), ticksPerCasualTask * 2);
      expect(state.township.activeCasualTasks, isEmpty);
    });

    test('assigns another task every 5 hours', () {
      var state = _tick(_state(casualTaskTicksRemaining: 10), 9);
      expect(state.township.activeCasualTasks, isEmpty);
      state = _tick(state, 1);
      expect(state.township.activeCasualTasks, hasLength(1));
      state = _tick(state, ticksPerCasualTask);
      expect(state.township.activeCasualTasks, hasLength(2));
    });

    test('only assigns tasks whose requirements are met', () {
      var state = _tick(_state(), ticksPerCasualTask * 3);
      expect(state.township.activeCasualTasks, hasLength(2));
      expect(state.township.activeCasualTasks, isNot(contains(_gatedTaskId)));

      state = _state(
        skillStates: {
          Skill.attack: SkillState(xp: startXpForLevel(50), masteryPoolXp: 0),
        },
      );
      state = _tick(state, ticksPerCasualTask * 3);
      expect(state.township.activeCasualTasks, contains(_gatedTaskId));
    });

    test('the casual task timer wakes the game loop', () {
      final state = _state(casualTaskTicksRemaining: 500);
      expect(StateUpdateBuilder(state).calculateTicksUntilNextEvent(), 500);
    });
  });

  group('casual task rewards', () {
    test('scale with Township and Slayer levels', () {
      final state = _state(
        skillStates: {
          Skill.slayer: SkillState(xp: startXpForLevel(20), masteryPoolXp: 0),
        },
      );
      // Township level 1 spans 83 XP; 9% of that is 7.
      final rewards = state.taskRewards(
        _registries.township.taskById(_swordTaskId),
      );
      expect(rewards, hasLength(3));
      expect(rewards[0].quantity, 7);
      expect(rewards[1].quantity, 35);
      expect(rewards[2].id, Currency.slayerCoins.id);
      expect(rewards[2].quantity, 20000);
    });

    test('keep fixed Township resource rewards', () {
      final rewards = _state().taskRewards(
        _registries.township.taskById(_logsTaskId),
      );
      final wood = rewards.singleWhere(
        (r) => r.type == TaskRewardType.townshipResource,
      );
      expect(wood.quantity, 2500);
    });
  });

  group('claiming casual tasks', () {
    test('requires the task to be assigned', () {
      var state = _state();
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(_logs, count: 10)),
      );
      expect(state.isTaskComplete(_logsTaskId), isFalse);
      expect(
        () => state.claimTaskRewardWithChanges(_logsTaskId),
        throwsStateError,
      );
    });

    test('grants rewards and returns the task to the pool', () {
      var state = _state(activeCasualTasks: [_logsTaskId]);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(_logs, count: 15)),
      );
      expect(state.isTaskComplete(_logsTaskId), isTrue);

      final (claimed, changes) = state.claimTaskRewardWithChanges(_logsTaskId);
      expect(claimed.inventory.countOfItem(_logs), 5);
      expect(claimed.township.resourceAmount(_woodId), 2500);
      expect(claimed.gp, 35);
      expect(claimed.skillState(Skill.town).xp, 7);
      expect(claimed.township.activeCasualTasks, isEmpty);
      expect(claimed.township.completedMainTasks, isEmpty);
      expect(changes.currenciesGained[Currency.gp], 35);
    });
  });

  group('skipping casual tasks', () {
    test('costs the XP left to the next Township level', () {
      final state = _state(
        skillStates: {Skill.town: const SkillState(xp: 50, masteryPoolXp: 0)},
      );
      expect(state.casualTaskSkipCost, 33);
    });

    test('costs the cap at max level', () {
      final state = _state(
        skillStates: {
          Skill.town: SkillState(
            xp: startXpForLevel(maxLevel),
            masteryPoolXp: 0,
          ),
        },
      );
      expect(state.casualTaskSkipCost, GlobalState.maxCasualTaskSkipCost);
    });

    test('charges GP and removes the task', () {
      final state = _state(activeCasualTasks: [_logsTaskId], gp: 100);
      final skipped = state.skipCasualTask(_logsTaskId);
      expect(skipped.gp, 100 - 83);
      expect(skipped.township.activeCasualTasks, isEmpty);
    });

    test('throws without enough GP or when not assigned', () {
      expect(
        () => _state(
          activeCasualTasks: [_logsTaskId],
        ).skipCasualTask(_logsTaskId),
        throwsStateError,
      );
      expect(
        () => _state(gp: 100).skipCasualTask(_logsTaskId),
        throwsStateError,
      );
    });
  });

  group('casual task kill tracking', () {
    GlobalState kill(GlobalState state) =>
        (StateUpdateBuilder(state)..trackMonsterKill(_golbinId)).build();

    test('only counts kills for assigned tasks', () {
      final goal = _registries.township.taskById(_gatedTaskId).goals.single;
      var state = kill(_state());
      expect(state.township.getGoalProgress(_gatedTaskId, goal), 0);

      state = kill(_state(activeCasualTasks: [_gatedTaskId]));
      expect(state.township.getGoalProgress(_gatedTaskId, goal), 1);
    });

    test('every task wanting the monster gets the kill', () {
      final goal = _registries.township.taskById(_gatedTaskId).goals.single;
      final otherTask = TownshipTask(
        id: const MelvorId('melvorF:Easy0'),
        category: TaskCategory.easy,
        goals: [goal],
      );
      final registries = Registries.test(
        township: TownshipRegistry(
          tasks: [otherTask],
          casualTasks: _registries.township.casualTasks,
        ),
      );
      final state = kill(
        GlobalState.test(
          registries,
          township: TownshipState(
            registry: registries.township,
            activeCasualTasks: const [_gatedTaskId],
          ),
        ),
      );
      expect(state.township.getGoalProgress(otherTask.id, goal), 1);
      expect(state.township.getGoalProgress(_gatedTaskId, goal), 1);
    });

    test('monsterWithItems goals need the items equipped', () {
      final goal = _registries.township.taskById(_swordTaskId).goals.single;
      var state = kill(_state(activeCasualTasks: [_swordTaskId]));
      expect(state.township.getGoalProgress(_swordTaskId, goal), 0);

      state = kill(
        _state(
          activeCasualTasks: [_swordTaskId],
          equipment: Equipment(
            foodSlots: const [null, null, null],
            selectedFoodSlot: 0,
            gearSlots: {EquipmentSlot.weapon: _sword},
          ),
        ),
      );
      expect(state.township.getGoalProgress(_swordTaskId, goal), 1);
    });
  });

  group('ItemFoundRequirement', () {
    test('is met by an item in the bank or equipped', () {
      final requirement = ItemFoundRequirement(itemId: _sword.id);
      final state = _state();
      expect(requirement.isMet(state), isFalse);
      expect(
        requirement.isMet(
          state.copyWith(
            inventory: state.inventory.adding(ItemStack(_sword, count: 1)),
          ),
        ),
        isTrue,
      );
      expect(
        requirement.isMet(
          _state(
            equipment: Equipment(
              foodSlots: const [null, null, null],
              selectedFoodSlot: 0,
              gearSlots: {EquipmentSlot.weapon: _sword},
            ),
          ),
        ),
        isTrue,
      );
    });
  });
}
