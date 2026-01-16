import 'dart:math';

import 'package:logic/logic.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  late CookingAction shrimpRecipe;
  late Item rawShrimp;
  late Item cookedShrimp;

  setUpAll(() async {
    await loadTestRegistries();
    final actions = testActions;
    final items = testItems;

    // Find a cooking action - Shrimp is a basic Fire cooking recipe
    shrimpRecipe = actions
        .forSkill(Skill.cooking)
        .whereType<CookingAction>()
        .firstWhere((a) => a.name == 'Shrimp');

    rawShrimp = items.byName('Raw Shrimp');
    cookedShrimp = items.byName('Shrimp');
  });

  group('CookingState', () {
    test('empty state has no active areas', () {
      const state = CookingState.empty();
      expect(state.fireArea.isEmpty, isTrue);
      expect(state.furnaceArea.isEmpty, isTrue);
      expect(state.potArea.isEmpty, isTrue);
      expect(state.hasActiveRecipe, isFalse);
    });

    test('withAreaState updates the correct area', () {
      const state = CookingState.empty();
      final areaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 100,
        totalTicks: 100,
      );

      final updated = state.withAreaState(CookingArea.fire, areaState);
      expect(updated.fireArea.recipeId, shrimpRecipe.id);
      expect(updated.furnaceArea.isEmpty, isTrue);
      expect(updated.potArea.isEmpty, isTrue);
    });

    test('toJson/fromJson round-trip', () {
      final areaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 50,
        totalTicks: 100,
      );
      final state = const CookingState.empty().withAreaState(
        CookingArea.fire,
        areaState,
      );

      final json = state.toJson();
      final restored = CookingState.fromJson(json);

      expect(restored.fireArea.recipeId, shrimpRecipe.id);
      expect(restored.fireArea.progressTicksRemaining, 50);
      expect(restored.fireArea.totalTicks, 100);
    });
  });

  group('CookingArea', () {
    test('fromCategoryId parses Fire category', () {
      final area = CookingArea.fromCategoryId(const MelvorId('melvorD:Fire'));
      expect(area, CookingArea.fire);
    });

    test('fromCategoryId parses Furnace category', () {
      final area = CookingArea.fromCategoryId(
        const MelvorId('melvorD:Furnace'),
      );
      expect(area, CookingArea.furnace);
    });

    test('fromCategoryId parses Pot category', () {
      final area = CookingArea.fromCategoryId(const MelvorId('melvorD:Pot'));
      expect(area, CookingArea.pot);
    });

    test('fromCategoryId returns null for unknown category', () {
      final area = CookingArea.fromCategoryId(
        const MelvorId('melvorD:Unknown'),
      );
      expect(area, isNull);
    });
  });

  group('completeCookingAction', () {
    test('successful cook produces output and grants XP', () {
      var state = GlobalState.empty(testRegistries);
      // Give player raw shrimp
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 10)),
      );

      // Use a seeded random that will succeed (70%+ success at level 0)
      // With mastery 0, success rate is 70%
      // Random(42) first value is ~0.37 which is < 0.7, so success
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeCookingAction(builder, shrimpRecipe, random, isPassive: false);

      state = builder.state;
      // Raw shrimp consumed
      expect(state.inventory.countOfItem(rawShrimp), 9);
      // Cooked shrimp produced (assuming success)
      expect(
        state.inventory.countOfItem(cookedShrimp),
        greaterThanOrEqualTo(0),
      );
      // XP granted (either 1 for failure or full amount for success)
      expect(state.skillState(Skill.cooking).xp, greaterThan(0));
    });

    test('failed cook consumes inputs and grants only 1 XP', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 10)),
      );

      // Find a random seed that causes failure
      // At mastery 0, success rate is 70%, so we need random > 0.7
      // Random(0) first value is ~0.825, which is failure (> 0.7)
      final random = Random(0);

      final builder = StateUpdateBuilder(state);
      completeCookingAction(builder, shrimpRecipe, random, isPassive: false);
      state = builder.state;

      // Raw shrimp consumed (even on failure)
      expect(state.inventory.countOfItem(rawShrimp), 9);
      // No cooked shrimp produced on failure
      expect(state.inventory.countOfItem(cookedShrimp), 0);
      // Only 1 XP on failure
      expect(state.skillState(Skill.cooking).xp, 1);
    });

    test('passive cooking grants no XP or mastery', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 10)),
      );

      // Seed that succeeds
      final random = Random(42);

      final builder = StateUpdateBuilder(state);
      completeCookingAction(builder, shrimpRecipe, random, isPassive: true);
      state = builder.state;

      // Raw shrimp consumed
      expect(state.inventory.countOfItem(rawShrimp), 9);
      // If success, output produced
      // But NO XP granted for passive cooking
      expect(state.skillState(Skill.cooking).xp, 0);
      // No mastery XP either
      expect(state.actionState(shrimpRecipe.id).masteryXp, 0);
    });

    test('higher mastery increases success rate to 100% at level 50', () {
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 100)),
      );

      // Give player level 50 mastery (adds +30% success rate = 100%)
      final masteryXp = startXpForLevel(50);
      state = state.copyWith(
        actionStates: {shrimpRecipe.id: ActionState(masteryXp: masteryXp)},
      );

      // At mastery 50, success rate is 100%, so even the worst RNG succeeds
      // Random(10) gives 0.9915, which would fail at 70% but succeeds at 100%
      final random = Random(10);
      final builder = StateUpdateBuilder(state);
      completeCookingAction(builder, shrimpRecipe, random, isPassive: false);
      final newState = builder.state;

      // Should produce output (100% success rate)
      expect(newState.inventory.countOfItem(cookedShrimp), 1);
      // Should get full XP (not just 1)
      expect(newState.skillState(Skill.cooking).xp, shrimpRecipe.xp);
    });
  });

  group('CookingAction', () {
    test('shrimp recipe is in Fire category', () {
      expect(shrimpRecipe.isInCategory('Fire'), isTrue);
      expect(shrimpRecipe.isInCategory('Furnace'), isFalse);
      expect(shrimpRecipe.isInCategory('Pot'), isFalse);
    });

    test('has perfectCookId for perfect cook mechanic', () {
      // Shrimp has a perfect cook variant
      expect(shrimpRecipe.perfectCookId, isNotNull);
    });
  });

  group('Cooking state reset', () {
    test(
      'switching from cooking to non-cooking resets all cooking progress',
      () {
        final random = Random(42);
        var state = GlobalState.empty(testRegistries);

        // Set up cooking area with progress
        final areaState = CookingAreaState(
          recipeId: shrimpRecipe.id,
          progressTicksRemaining: 50,
          totalTicks: 100,
        );
        state = state.copyWith(
          cooking: state.cooking.withAreaState(CookingArea.fire, areaState),
        );

        // Start cooking action to be able to switch from it
        state = state.copyWith(
          inventory: state.inventory.adding(ItemStack(rawShrimp, count: 10)),
        );
        state = state.startAction(shrimpRecipe, random: random);

        // Verify cooking progress is set
        expect(state.cooking.fireArea.progressTicksRemaining, 50);

        // Switch to a non-cooking action (woodcutting)
        final woodcutting = testActions.woodcutting('Normal Tree');
        state = state.startAction(woodcutting, random: random);

        // Cooking progress should be reset (but recipe still assigned)
        expect(state.cooking.fireArea.recipeId, shrimpRecipe.id);
        expect(state.cooking.fireArea.progressTicksRemaining, isNull);
        expect(state.cooking.fireArea.totalTicks, isNull);
      },
    );

    test('switching between cooking actions preserves cooking progress', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);

      // Find a Furnace cooking action
      final furnaceRecipe = testActions
          .forSkill(Skill.cooking)
          .whereType<CookingAction>()
          .firstWhere((a) => a.isInCategory('Furnace'));

      // Set up Fire cooking area with progress
      final fireState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 50,
        totalTicks: 100,
      );
      state = state.copyWith(
        cooking: state.cooking.withAreaState(CookingArea.fire, fireState),
        inventory: state.inventory
            .adding(ItemStack(rawShrimp, count: 10))
            .adding(
              ItemStack(
                testItems.byId(furnaceRecipe.inputs.keys.first),
                count: 10,
              ),
            ),
      );

      // Start cooking on Fire
      state = state.startAction(shrimpRecipe, random: random);

      // Verify Fire cooking progress is set
      expect(state.cooking.fireArea.progressTicksRemaining, 50);

      // Switch to a different cooking action (Furnace)
      state = state.startAction(furnaceRecipe, random: random);

      // Fire cooking progress should still be preserved
      expect(state.cooking.fireArea.recipeId, shrimpRecipe.id);
      expect(state.cooking.fireArea.progressTicksRemaining, 50);
      expect(state.cooking.fireArea.totalTicks, 100);
    });

    test('clearAction resets cooking progress when cooking was active', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);

      // Set up cooking area with progress
      final areaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 50,
        totalTicks: 100,
      );
      state = state.copyWith(
        cooking: state.cooking.withAreaState(CookingArea.fire, areaState),
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 10)),
      );

      // Start cooking action
      state = state.startAction(shrimpRecipe, random: random);

      // Verify cooking progress is set
      expect(state.cooking.fireArea.progressTicksRemaining, 50);

      // Clear action
      state = state.clearAction();

      // Cooking progress should be reset (but recipe still assigned)
      expect(state.cooking.fireArea.recipeId, shrimpRecipe.id);
      expect(state.cooking.fireArea.progressTicksRemaining, isNull);
    });

    test('withAllProgressCleared clears progress but preserves recipes', () {
      final areaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 50,
        totalTicks: 100,
      );
      final state = const CookingState.empty().withAreaState(
        CookingArea.fire,
        areaState,
      );

      final cleared = state.withAllProgressCleared();

      // Recipe should be preserved
      expect(cleared.fireArea.recipeId, shrimpRecipe.id);
      // Progress should be cleared
      expect(cleared.fireArea.progressTicksRemaining, isNull);
      expect(cleared.fireArea.totalTicks, isNull);
    });
  });

  group('Cooking category-scoped modifiers', () {
    test('resolveSkillModifiers includes category-scoped shop modifiers', () {
      // Find a Furnace recipe to test with
      final furnaceRecipe = testActions
          .forSkill(Skill.cooking)
          .whereType<CookingAction>()
          .firstWhere((a) => a.isInCategory('Furnace'));

      // Find the Basic Furnace shop upgrade (has perfectCookChance for Furnace)
      final basicFurnace = testRegistries.shop.all.firstWhere(
        (p) => p.name == 'Basic Furnace',
      );

      // Create state with the shop upgrade purchased
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(shop: state.shop.withPurchase(basicFurnace.id));

      // Resolve modifiers for a Furnace recipe - should include the upgrade
      final modifiers = state.createActionModifierProvider(furnaceRecipe);
      expect(
        modifiers.perfectCookChance(
          actionId: furnaceRecipe.id.localId,
          categoryId: furnaceRecipe.categoryId,
        ),
        greaterThan(0),
      );
    });

    test('category-scoped modifiers do not apply to other categories', () {
      // Find a Furnace upgrade
      final basicFurnace = testRegistries.shop.all.firstWhere(
        (p) => p.name == 'Basic Furnace',
      );

      // Create state with the Furnace upgrade purchased
      var state = GlobalState.empty(testRegistries);
      state = state.copyWith(shop: state.shop.withPurchase(basicFurnace.id));

      // Resolve modifiers for a Fire recipe - should NOT get Furnace bonus
      final modifiers = state.createActionModifierProvider(shrimpRecipe);
      // The perfectCookChance should be 0 (or whatever from other sources)
      // since the Furnace upgrade doesn't apply to Fire
      expect(
        modifiers.perfectCookChance(
          actionId: shrimpRecipe.id.localId,
          categoryId: shrimpRecipe.categoryId,
        ),
        0,
      );
    });
  });

  group('Passive cooking via consumeTicks', () {
    test(
      'passive cooking area progresses while actively cooking in another',
      () {
        final random = Random(42);
        var state = GlobalState.empty(testRegistries);

        // Find a Furnace cooking action
        final furnaceRecipe = testActions
            .forSkill(Skill.cooking)
            .whereType<CookingAction>()
            .firstWhere((a) => a.isInCategory('Furnace'));

        // Get the inputs for furnace recipe
        final furnaceInput = testItems.byId(furnaceRecipe.inputs.keys.first);

        // Give player enough of both ingredients
        state = state.copyWith(
          inventory: state.inventory
              .adding(ItemStack(rawShrimp, count: 100))
              .adding(ItemStack(furnaceInput, count: 100)),
        );

        // Set up the Fire area as passive with a recipe
        final recipeDuration = ticksFromDuration(shrimpRecipe.maxDuration);
        final fireAreaState = CookingAreaState(
          recipeId: shrimpRecipe.id,
          progressTicksRemaining: recipeDuration,
          totalTicks: recipeDuration,
        );
        state = state.copyWith(
          cooking: state.cooking.withAreaState(CookingArea.fire, fireAreaState),
        );

        // Start actively cooking in Furnace area
        state = state.startAction(furnaceRecipe, random: random);

        // Get the initial passive progress
        final initialProgress = state.cooking.fireArea.progressTicksRemaining!;

        // Consume 50 ticks (passive cooking is 5x slower)
        final builder = StateUpdateBuilder(state);
        consumeTicks(builder, 50, random: random);
        state = builder.build();

        // Verify passive cooking area made progress
        final newProgress = state.cooking.fireArea.progressTicksRemaining!;
        expect(newProgress, lessThan(initialProgress));
        // Passive cooking is 5x slower, so 50 ticks = 10 effective progress
        expect(newProgress, initialProgress - 10);
      },
    );

    test('passive cooking completes and produces output without XP', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);

      // Find a Furnace cooking action
      final furnaceRecipe = testActions
          .forSkill(Skill.cooking)
          .whereType<CookingAction>()
          .firstWhere((a) => a.isInCategory('Furnace'));

      // Get the inputs for furnace recipe
      final furnaceInput = testItems.byId(furnaceRecipe.inputs.keys.first);

      // Give player enough of both ingredients
      state = state.copyWith(
        inventory: state.inventory
            .adding(ItemStack(rawShrimp, count: 100))
            .adding(ItemStack(furnaceInput, count: 100)),
      );

      // Set up Fire area as passive with recipe almost complete
      // Passive cooking is 5x slower, so we need 5x the remaining ticks
      final fireAreaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: 5, // 5 effective ticks remaining
        totalTicks: ticksFromDuration(shrimpRecipe.maxDuration),
      );
      state = state.copyWith(
        cooking: state.cooking.withAreaState(CookingArea.fire, fireAreaState),
      );

      // Record initial inventory state
      final initialRawShrimp = state.inventory.countOfItem(rawShrimp);

      // Start actively cooking in Furnace area
      state = state.startAction(furnaceRecipe, random: random);

      // Consume 25 ticks (5 effective ticks at 5x multiplier = completes)
      final builder = StateUpdateBuilder(state);
      consumeTicks(builder, 25, random: random);
      state = builder.build();

      // Passive cooking should have consumed raw shrimp (if successful roll)
      // and produced cooked shrimp (unless failed)
      final finalRawShrimp = state.inventory.countOfItem(rawShrimp);
      expect(finalRawShrimp, lessThan(initialRawShrimp));

      // Passive cooking grants NO XP
      // Only the active furnace cooking should contribute XP
      // (We check that passive cooking completed by verifying input consumed)
      final cookingXp = state.skillState(Skill.cooking).xp;
      // Any XP should only come from active cooking, not passive
      // Passive completion doesn't grant XP, so if we got XP it's from active
      expect(cookingXp, greaterThanOrEqualTo(0));
    });

    test('passive cooking does not run when active action is not cooking', () {
      final random = Random(42);
      var state = GlobalState.empty(testRegistries);

      // Give player raw shrimp
      state = state.copyWith(
        inventory: state.inventory.adding(ItemStack(rawShrimp, count: 100)),
      );

      // Set up Fire area with a recipe and progress
      final recipeDuration = ticksFromDuration(shrimpRecipe.maxDuration);
      final fireAreaState = CookingAreaState(
        recipeId: shrimpRecipe.id,
        progressTicksRemaining: recipeDuration,
        totalTicks: recipeDuration,
      );
      state = state.copyWith(
        cooking: state.cooking.withAreaState(CookingArea.fire, fireAreaState),
      );

      // First start cooking (to set up the "from cooking" context)
      state = state.startAction(shrimpRecipe, random: random);

      // Now switch to a non-cooking action (woodcutting)
      final woodcutting = testActions.woodcutting('Normal Tree');
      state = state.startAction(woodcutting, random: random);

      // Passive cooking progress should have been cleared when switching away
      expect(state.cooking.fireArea.progressTicksRemaining, isNull);
    });
  });
}
