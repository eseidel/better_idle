import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

/// A mock Random that returns predictable values.
class MockRandom implements Random {
  MockRandom({this.nextDoubleValue = 0.0, this.nextIntValue = 0});

  final double nextDoubleValue;
  final int nextIntValue;

  @override
  double nextDouble() => nextDoubleValue;

  @override
  int nextInt(int max) => nextIntValue.clamp(0, max - 1);

  @override
  bool nextBool() => nextDoubleValue < 0.5;
}

void main() {
  late ThievingAction manAction;

  setUpAll(() async {
    await loadTestRegistries();
    manAction = testRegistries.thievingAction('Man');
  });

  group('Thieving drops', () {
    test("allDropsForAction contains Bobby's Pocket for thieving", () {
      final drops = testDrops.allDropsForAction(
        manAction,
        const NoSelectedRecipe(),
      );
      final itemIds = drops.map((d) {
        if (d is Drop) return d.itemId;
        return null;
      }).whereType<MelvorId>();
      expect(itemIds, contains(const MelvorId('melvorF:Bobbys_Pocket')));
    });
  });

  group('Area drops', () {
    const crateId = MelvorId('melvorF:Crate_Of_Basic_Supplies');
    test('Golbin Village area drops include Crate of Basic Supplies', () {
      final golbin = testRegistries.thievingAction('Golbin');
      final golbinChief = testRegistries.thievingAction('Golbin Chief');

      // Both actions should be in Golbin Village
      // ThievingActions store their area directly
      expect(golbin.area.name, 'Golbin Village');
      expect(golbinChief.area.name, 'Golbin Village');

      // Get all drops for both actions
      final golbinDrops = testDrops.allDropsForAction(
        golbin,
        const NoSelectedRecipe(),
      );
      final chiefDrops = testDrops.allDropsForAction(
        golbinChief,
        const NoSelectedRecipe(),
      );

      // Extract drop names from Drop objects (area drops are rate-based Drops)
      List<MelvorId> getDropIds(List<Droppable> drops) {
        return drops.whereType<Drop>().map((d) => d.itemId).toList();
      }

      // Both should include Crate Of Basic Supplies from area drops

      expect(getDropIds(golbinDrops), contains(crateId));
      expect(getDropIds(chiefDrops), contains(crateId));
    });

    test('Crate Of Basic Supplies has correct rate (1/500)', () {
      final golbinAction = testRegistries.thievingAction('Golbin');
      final drops = testDrops.allDropsForAction(
        golbinAction,
        const NoSelectedRecipe(),
      );
      final crateDrop = drops.whereType<Drop>().firstWhere(
        (d) => d.itemId == crateId,
      );

      expect(crateDrop.rate, closeTo(1 / 500, 0.0001));
    });

    test('Low Town has Jeweled Necklace area drop', () {
      final drops = testDrops.allDropsForAction(
        manAction,
        const NoSelectedRecipe(),
      );
      final dropIds = drops.whereType<Drop>().map((d) => d.itemId).toList();

      expect(dropIds, contains(const MelvorId('melvorF:Jeweled_Necklace')));
      expect(dropIds, isNot(contains(crateId)));
    });
  });

  group('NPC unique drops', () {
    test('Lumberjack has NPC-specific unique drop', () {
      final lumberjack = testRegistries.thievingAction('Lumberjack');
      expect(lumberjack.uniqueDrop, isNotNull);
      expect(
        lumberjack.uniqueDrop!.itemId,
        const MelvorId('melvorF:Lumberjacks_Top'),
      );
      expect(lumberjack.uniqueDrop!.rate, closeTo(1 / 500, 0.0001));
    });

    test('Woman has NPC-specific unique drop', () {
      final woman = testRegistries.thievingAction('Woman');
      expect(woman.uniqueDrop, isNotNull);
      expect(
        woman.uniqueDrop!.itemId,
        const MelvorId('melvorF:Fine_Coinpurse'),
      );
    });

    test('Man does not have NPC-specific unique drop', () {
      expect(manAction.uniqueDrop, isNull);
    });

    test('NPC unique drop appears in allDropsForAction', () {
      final lumberjack = testRegistries.thievingAction('Lumberjack');
      final drops = testDrops.allDropsForAction(
        lumberjack,
        const NoSelectedRecipe(),
      );
      final dropIds = drops.whereType<Drop>().map((d) => d.itemId).toList();
      expect(dropIds, contains(const MelvorId('melvorF:Lumberjacks_Top')));
    });

    test('all three drop tiers present for Golbin Chief', () {
      // Golbin Chief has: loot table, area drops, and NPC unique drop.
      final chief = testRegistries.thievingAction('Golbin Chief');

      // Tier 1: NPC loot table
      expect(chief.dropTable, isNotNull);

      // Tier 2: Area unique drops (Golbin Village → Crate of Basic Supplies)
      expect(chief.area.uniqueDrops, isNotEmpty);

      // Tier 3: NPC unique drop (Golbin Mask)
      expect(chief.uniqueDrop, isNotNull);
      expect(chief.uniqueDrop!.itemId, const MelvorId('melvorF:Golbin_Mask'));

      // All should appear in allDropsForAction
      final drops = testDrops.allDropsForAction(
        chief,
        const NoSelectedRecipe(),
      );
      // loot table (DropChance) + area drop + NPC unique drop +
      // 3 generalRareItems + 3 rareDrops = 9
      expect(drops.length, 9);
    });
  });

  group('Golbin drops', () {
    late ThievingAction golbinAction;
    late DropChance golbinDropChance;
    late DropTable golbinDropTable;

    setUp(() {
      golbinAction = testRegistries.thievingAction('Golbin');
      golbinDropChance = golbinAction.dropTable! as DropChance;
      golbinDropTable = golbinDropChance.child as DropTable;
    });

    test('Golbin has NPC-specific drop table', () {
      final drops = testDrops.allDropsForAction(
        golbinAction,
        const NoSelectedRecipe(),
      );
      // Should have 8 drops: Golbin drop table (action-level) +
      // area drop (Crate of Basic Supplies) + 3 generalRareItems (skill-level)
      // (Bobby's Pocket, Chapeau Noir, Boots of Stealth) + 3 rareDrops
      // (Gold Topaz Ring, Circlet of Rhaelyx, Mysterious Stone)
      expect(drops.length, 8);
      // Only the Golbin drop table is wrapped in DropChance
      final dropChances = drops.whereType<DropChance>().toList();
      expect(dropChances, hasLength(1));
      const copperOreId = MelvorId('melvorD:Copper_Ore');
      expect(dropChances.first.expectedItems[copperOreId], greaterThan(0));
    });

    test('golbinDropTable has correct structure', () {
      // The drop table should have ~75% chance to drop something
      expect(golbinDropChance.rate, closeTo(0.75, 0.01));
      expect(golbinDropTable.entries, hasLength(9));
    });

    test('golbinDropTable has correct items', () {
      // Use the DropChance's expectedItems which includes the rate
      // Keys are MelvorId objects
      final expected = golbinDropChance.expectedItems;

      // Verify all expected items are present
      expect(expected, contains(const MelvorId('melvorD:Copper_Ore')));
      expect(expected, contains(const MelvorId('melvorD:Bronze_Bar')));
      expect(expected, contains(const MelvorId('melvorD:Normal_Logs')));
      expect(expected, contains(const MelvorId('melvorD:Tin_Ore')));
      expect(expected, contains(const MelvorId('melvorD:Oak_Logs')));
      expect(expected, contains(const MelvorId('melvorD:Iron_Bar')));
      expect(expected, contains(const MelvorId('melvorD:Iron_Ore')));
      expect(expected, contains(const MelvorId('melvorD:Steel_Bar')));
      expect(expected, contains(const MelvorId('melvorD:Willow_Logs')));

      // Copper and Tin should have higher rates than Iron and Steel
      expect(
        expected[const MelvorId('melvorD:Copper_Ore')],
        greaterThan(expected[const MelvorId('melvorD:Iron_Ore')]!),
      );
      expect(
        expected[const MelvorId('melvorD:Tin_Ore')],
        greaterThan(expected[const MelvorId('melvorD:Steel_Bar')]!),
      );
    });

    test('golbinDropTable total rate is approximately 75%', () {
      // Use the DropChance's expectedItems which includes the rate
      final expected = golbinDropChance.expectedItems;
      final totalRate = expected.values.fold<double>(
        0,
        (sum, rate) => sum + rate,
      );
      // Total should be approximately 75%
      expect(totalRate, closeTo(0.75, 0.01));
    });

    test('Golbin thieving success can grant drops', () {
      // Set up state with Golbin action active
      final random = Random(42);
      var state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.thieving: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
        },
      ).startAction(golbinAction, random: random);

      // Run many thieving attempts to get drops
      final random2 = Random(123);
      var gotDrop = false;

      for (var i = 0; i < 100 && !gotDrop; i++) {
        final builder = StateUpdateBuilder(state);
        // Use random that succeeds thieving
        final rng = MockRandom(nextIntValue: 50);
        completeThievingAction(builder, golbinAction, rng);
        state = builder.build();

        // Process with real random for drops
        final dropBuilder = StateUpdateBuilder(state);
        consumeTicks(dropBuilder, 30, random: random2);
        state = dropBuilder.build();

        // Check if we got any of the Golbin-specific drops
        final golbinItems = [
          const MelvorId('melvorD:Copper_Ore'),
          const MelvorId('melvorD:Bronze_Bar'),
          const MelvorId('melvorD:Normal_Logs'),
          const MelvorId('melvorD:Tin_Ore'),
          const MelvorId('melvorD:Oak_Logs'),
          const MelvorId('melvorD:Iron_Bar'),
          const MelvorId('melvorD:Iron_Ore'),
          const MelvorId('melvorD:Steel_Bar'),
          const MelvorId('melvorD:Willow_Logs'),
        ];
        for (final item in golbinItems) {
          if (state.inventory.countById(item) > 0) {
            gotDrop = true;
            break;
          }
        }
      }

      expect(gotDrop, isTrue, reason: 'Should get Golbin drops eventually');
    });
  });

  group('ThievingAction', () {
    test('Man action has correct properties', () {
      expect(manAction.name, 'Man');
      expect(manAction.skill, Skill.thieving);
      expect(manAction.unlockLevel, 1);
      expect(manAction.xp, 5);
      expect(manAction.perception, 110);
      expect(manAction.maxHit, 22);
      expect(manAction.maxGold, 100);
      expect(manAction.minDuration, const Duration(seconds: 3));
    });

    test('rollDamage returns value between 1 and maxHit', () {
      // With nextInt returning 0, damage = 1 + 0 = 1
      final minRng = MockRandom();
      expect(manAction.rollDamage(minRng), 1);

      // With nextInt returning maxHit-1, damage = 1 + (maxHit-1) = maxHit
      final maxRng = MockRandom(nextIntValue: manAction.maxHit - 1);
      expect(manAction.rollDamage(maxRng), manAction.maxHit);
    });

    test('rollGold returns value between 1 and maxGold', () {
      // With nextInt returning 0, gold = 1 + 0 = 1
      final minRng = MockRandom();
      expect(manAction.rollGold(minRng), 1);

      // With nextInt returning maxGold-1, gold = 1 + (maxGold-1) = maxGold
      final maxRng = MockRandom(nextIntValue: manAction.maxGold - 1);
      expect(manAction.rollGold(maxRng), manAction.maxGold);
    });

    test('rollSuccess fails at level 1, mastery 1 vs perception 110', () {
      // Stealth = 40 + 1 (level) + 1 (mastery) = 42
      // Success chance = (100 + 42) / (100 + 110) = 142/210 = ~67.6%
      // Roll of 0.70 (70%) should fail
      final rng = MockRandom(nextDoubleValue: 0.70);
      expect(manAction.rollSuccess(rng, 1, 1, 0), isFalse);
    });

    test('rollSuccess succeeds at level 1, mastery 1 vs perception 110', () {
      // Stealth = 40 + 1 (level) + 1 (mastery) = 42
      // Success chance = (100 + 42) / (100 + 110) = 142/210 = ~67.6%
      // Roll of 0.60 (60%) should succeed
      final rng = MockRandom(nextDoubleValue: 0.60);
      expect(manAction.rollSuccess(rng, 1, 1, 0), isTrue);
    });

    test('rollSuccess applies thievingStealth modifier', () {
      // Without modifier: Stealth = 40 + 1 + 1 = 42
      // Success chance = (100 + 42) / (100 + 110) = 142/210 = ~67.6%
      // Roll of 0.70 should fail without modifier
      final rng = MockRandom(nextDoubleValue: 0.70);
      expect(manAction.rollSuccess(rng, 1, 1, 0), isFalse);

      // With +20 thievingStealth: Stealth = 40 + 1 + 1 + 20 = 62
      // Success chance = (100 + 62) / (100 + 110) = 162/210 = ~77.1%
      // Roll of 0.70 should now succeed
      expect(manAction.rollSuccess(rng, 1, 1, 20), isTrue);
    });
  });

  group('Thieving success', () {
    test('thieving success grants gold and XP', () {
      // Set up state with thieving action active
      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds and grants specific gold
      final rng = MockRandom(
        nextIntValue: 49, // Gold = 1 + 49 = 50
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Base gold = 1 + 49 = 50
      // Thieving mastery level 1 gives +1% currencyGain:
      // 50 * 1.01 = 50.5 → 51
      expect(newState.gp, 51);
      // Should have gained XP
      expect(newState.skillState(Skill.thieving).xp, manAction.xp);
      // Should NOT be stunned
      expect(newState.isStunned, isFalse);
    });

    test('thieving gold is boosted by currencyGain modifier', () {
      // Create a gloves item with +50% currencyGain for thieving
      final gloves = Item(
        id: const MelvorId('test:ThievingGloves'),
        name: 'Thieving Gloves',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: const [EquipmentSlot.gloves],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'currencyGain',
            entries: [
              ModifierEntry(
                value: 50, // +50%
                scope: ModifierScope(skillId: Skill.thieving.id),
              ),
            ],
          ),
        ]),
      );

      // Equip the gloves
      final (equipment, _) = const Equipment.empty().equipGear(
        gloves,
        EquipmentSlot.gloves,
      );

      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds and grants specific gold
      final rng = MockRandom(
        nextIntValue: 49, // Base gold = 1 + 49 = 50
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Base gold = 50, +50% from gloves, +1% from mastery level 1
      // 50 * (1.0 + 0.50 + 0.01) = 50 * 1.51 = 75.5 → 76
      expect(newState.gp, 76);
    });

    test('thieving XP is affected by skillXP modifier', () {
      // Create a cape with -20% skillXP for thieving (penalty)
      final cape = Item(
        id: const MelvorId('test:ThievingCape'),
        name: 'Thieving Cape',
        itemType: 'Equipment',
        sellsFor: 1000,
        validSlots: const [EquipmentSlot.cape],
        modifiers: ModifierDataSet([
          ModifierData(
            name: 'skillXP',
            entries: [
              ModifierEntry(
                value: -20, // -20%
                scope: ModifierScope(skillId: Skill.thieving.id),
              ),
            ],
          ),
        ]),
      );

      // Equip the cape
      final (equipment, _) = const Equipment.empty().equipGear(
        cape,
        EquipmentSlot.cape,
      );

      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
        equipment: equipment,
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds
      final rng = MockRandom(nextIntValue: 49);

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Man action gives 5 XP, with -20% modifier: 5 * 0.8 = 4
      expect(newState.skillState(Skill.thieving).xp, 4);
    });

    test('thieving success through tick processing', () {
      // Start thieving action
      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
      ).startAction(manAction, random: random);
      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds
      final rng = MockRandom(
        nextIntValue: 99, // Gold = 1 + 99 = 100 (max)
      );

      // Process enough ticks to complete the action (3 seconds = 30 ticks)
      consumeTicks(builder, 30, random: rng);

      final newState = builder.build();
      // Base gold = 1 + 99 = 100, +1% from mastery level 1
      // 100 * 1.01 = 101
      expect(newState.gp, 101);
      // Should have gained XP
      expect(newState.skillState(Skill.thieving).xp, manAction.xp);
      // Should NOT be stunned
      expect(newState.isStunned, isFalse);
      // Action should still be active (restarted)
      expect(newState.activeActivity, isNotNull);
      expect(newState.currentActionId, manAction.id);
    });
  });

  group('Thieving failure', () {
    test('thieving failure deals damage and stuns player', () {
      // Set up state with enough HP to survive (level 10 hitpoints = 100 HP)
      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(xp: 1154, masteryPoolXp: 0), // Level 10
        },
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails and deals specific damage
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail (roll > success rate)
        nextIntValue: 10, // Damage = 1 + 10 = 11
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isTrue);

      final newState = builder.build();
      // Should have taken damage
      expect(newState.health.lostHp, 11);
      // Should be stunned
      expect(newState.isStunned, isTrue);
      expect(newState.stunned.ticksRemaining, stunnedDurationTicks);
      // Should NOT have gained XP
      expect(newState.skillState(Skill.thieving).xp, 0);
      // Should NOT have gained gold
      expect(newState.gp, 0);
    });

    test('thieving failure that kills player stops action', () {
      // Set up state with low HP (less than max damage)
      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(
            xp: 1154,
            masteryPoolXp: 0,
          ), // Level 10 = 100 HP
        },
        health: const HealthState(lostHp: 95), // Only 5 HP left (100 max)
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails and deals max damage
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail
        nextIntValue: 21, // Damage = 1 + 21 = 22 (max)
      );

      final playerAlive = completeThievingAction(builder, manAction, rng);

      expect(playerAlive, isFalse);

      final newState = builder.build();
      // Health should be reset (player respawned)
      expect(newState.health.lostHp, 0);
      // Should NOT be stunned (death clears it)
      expect(newState.isStunned, isFalse);
    });

    test(
      'thieving failure killing player through tick processing stops action',
      () {
        // Start with low HP
        final random = Random(0);
        final state = GlobalState.test(
          testRegistries,
          skillStates: const {
            Skill.hitpoints: SkillState(
              xp: 1154,
              masteryPoolXp: 0,
            ), // Level 10 = 100 HP
          },
          health: const HealthState(lostHp: 95), // Only 5 HP left
        ).startAction(manAction, random: random);

        final builder = StateUpdateBuilder(state);

        // Use a mock random that always fails and deals max damage
        final rng = MockRandom(
          nextDoubleValue: 0.99, // Always fail
          nextIntValue: 21, // Damage = 22
        );

        // Process enough ticks to complete the action (30 ticks)
        consumeTicks(builder, 30, random: rng);

        final newState = builder.build();
        // Health should be reset
        expect(newState.health.lostHp, 0);
        // Action should be stopped (player died)
        expect(newState.activeActivity, isNull);
      },
    );
  });

  group('Thieving stun recovery', () {
    test('thieving action pauses while stunned from failed attempt', () {
      // Start thieving action
      final random = Random(0);
      final state = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(
            xp: 1154,
            masteryPoolXp: 0,
          ), // Level 10 = 100 HP
        },
      ).startAction(manAction, random: random);

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always fails (to trigger stun)
      final rng = MockRandom(
        nextDoubleValue: 0.99, // Always fail
        nextIntValue: 10, // Damage = 11
      );

      // Complete the action (30 ticks) - this should fail and stun
      consumeTicks(builder, 30, random: rng);

      var newState = builder.build();
      // Should be stunned
      expect(newState.isStunned, isTrue);
      // Action should still be active (not stopped)
      expect(newState.activeActivity, isNotNull);
      expect(newState.currentActionId, manAction.id);
      // Action timer stays at 0 (completed but waiting for stun to clear)
      expect(newState.activeActivity!.remainingTicks, 0);

      // Process 15 ticks (half the stun duration)
      final builder2 = StateUpdateBuilder(newState);
      consumeTicks(builder2, 15, random: rng);

      newState = builder2.build();
      // Still stunned (15 of 30 ticks remaining)
      expect(newState.isStunned, isTrue);
      expect(newState.stunned.ticksRemaining, 15);
      // Action timer still at 0 (waiting for stun)
      expect(newState.activeActivity!.remainingTicks, 0);
    });

    test('thieving continues after stun wears off', () {
      // Set up a state where we're stunned but have an active action
      // (simulating what happens after a failed thieving attempt)
      final baseState = GlobalState.test(
        testRegistries,
        skillStates: const {
          Skill.hitpoints: SkillState(
            xp: 1154,
            masteryPoolXp: 0,
          ), // Level 10 = 100 HP
        },
        stunned: const StunnedState.fresh().stun(), // 30 ticks of stun
      );
      // Manually set up the action since startAction throws when stunned
      final state = GlobalState(
        registries: testRegistries,
        inventory: baseState.inventory,
        activeActivity: SkillActivity(
          skill: Skill.thieving,
          actionId: manAction.id.localId,
          progressTicks: 0,
          totalTicks: 30,
        ),
        skillStates: baseState.skillStates,
        actionStates: baseState.actionStates,
        updatedAt: baseState.updatedAt,
        currencies: baseState.currencies,
        shop: baseState.shop,
        health: baseState.health,
        equipment: baseState.equipment,
        stunned: baseState.stunned,
      );

      final builder = StateUpdateBuilder(state);

      // Use a mock random that always succeeds when we finally try
      final rng = MockRandom(
        nextIntValue: 49, // Gold = 50
      );

      // Process just enough to clear stun (30 ticks)
      consumeTicks(builder, 30, random: rng);

      var newState = builder.build();
      // Stun should be cleared
      expect(newState.isStunned, isFalse);
      // Action should still be active (restarted after stun)
      expect(newState.activeActivity, isNotNull);

      // Now process more ticks to complete the action
      final builder2 = StateUpdateBuilder(newState);
      consumeTicks(builder2, 30, random: rng);

      newState = builder2.build();
      // Base gold = 1 + 49 = 50, +1% from mastery level 1
      // 50 * 1.01 = 50.5 → 51
      expect(newState.gp, 51);
    });
  });
}
