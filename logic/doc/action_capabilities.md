<!-- cspell:words Runecrafting Herblore Fletching Defence masterable performable -->

# Action Capabilities

Splitting `SkillAction` into the capabilities it currently bundles. Stage 1
has landed ([#277](https://github.com/eseidel/better_idle/pull/277)); stages 2
to 4 are proposed.

## The problem

`Action` has three members - `id`, `name`, `skill`. Everything else lives on
`SkillAction`, which 15 classes extend. Two classes sit outside it and share
none of its vocabulary: `CombatAction` has `levels`, `attackSpeed`,
`lootChance`, `lootTable`, and `FarmingCrop` re-declares its own `level`,
`baseXP` and `baseInterval`.

That duplication is the tell. A crop is trainable, has a recipe and earns
mastery, but it is not performable, and `SkillAction` offers no way to take
the first three without the fourth - so `FarmingCrop` stays outside and
restates them under different names. `SkillAction` bundles four capabilities
that vary independently:

| capability | members |
|---|---|
| **trainable** | `xp`, `unlockLevel` |
| **performable** | `minDuration`, `maxDuration`, `meanDuration`, `rollDuration` |
| **recipe** | `inputs`, `outputs`, `alternativeRecipes`, `categoryId` |
| **masterable** | `masteryActionTime`, and membership in the skill's mastery list |

Which classes have which:

| | trainable | performable | recipe | masterable |
|---|:---:|:---:|:---:|:---:|
| 13 ordinary skill actions | yes | yes | yes | yes |
| Astrology, Alt. Magic | yes | yes | **empty maps** | yes |
| `FarmingCrop` (outside) | yes | **no** | yes (seed to product) | yes |
| `CombatAction` (outside) | no | yes | no | no |

Astrology and Alt. Magic never pass `outputs` or `inputs`, so they inherit
`const {}` permanently. Crops grow in the background and are harvested - they
are never the active action. Combat monsters are performed but have no
mastery. Nothing before farming forced the distinction.

Being outside `SkillAction` is why crops earn no mastery today: the mastery
pool, its cap and the XP formula are all keyed on the skill's `SkillAction`
list. [#275](https://github.com/eseidel/better_idle/pull/275) fixes that by
moving `FarmingCrop` inside and adding a `canBeActiveAction` flag to opt it
back out of being performable - which works, and is the boolean this proposal
replaces with a type.

## Durations

Four things in this codebase are measured in time, and only one of them
belongs on an action as its duration.

| | what it is | where it lives |
|---|---|---|
| bar period | how often the progress bar fills | `SkillAction.duration` |
| ranged bar period | a bar that lands somewhere in a window | `SkillAction.ranged` |
| respawn, stun | the actor pausing itself | `MiningPersistentState`, `StunnedState` |
| crop growth | a background timer with no actor | `FarmingCrop.baseInterval` |

**The bar period has one meaning.** Woodcutting, mining, thieving, cooking,
firemaking and astrology all answer "how often does the bar fill" the same
way. What differs is what happens when it fills - an item, a hit against a
rock's HP, a success roll - and that is downstream of the duration, not a
second sense of it. Mining has no miss chance; every swing lands.

**Fishing is the only ranged action.** `SkillAction.ranged` has exactly one
user, so `rollDuration` is an identity for every other action. That is a
variation within the capability rather than a separate concept, so
`Performable` owns `minDuration`, `maxDuration` and `rollDuration` as a unit.

**Respawn and stun are not durations of an action.** A depleted rock's
`respawnTicksRemaining` and thieving's three-second `StunnedState` are the
actor sitting still, and both already live in state objects rather than on
`SkillAction`. `MiningAction.respawnTime` describes the rock and is already on
`MiningAction` rather than the base class. All of that is placed correctly and
should not move.

**Only the crop is awkward.** A crop has no progress bar the player fills; it
grows over hours and is harvested. Its interval is its own field today, and
#275 maps it onto `maxDuration` to get at the mastery machinery. Extracting
`Performable` removes the dilemma rather than managing it: a crop keeps a
growth interval of its own and gains mastery without claiming a duration.

A crop could render a bar - it is the same shape, just hours long. The line
between `Performable` and a background timer is not the kind of time being
measured, it is whether the player is the one driving it.

## Constraints

- **Melvor's data is fixed input.** We parse what the CDN gives us; the shape
  of `melvorDemo.json` is not ours to change.
- **Saves must migrate.** Our own JSON is ours to change, provided there is a
  path from existing saves.
- **Dart, and its performance model.** The solver iterates every action for a
  skill inside candidate enumeration and rate estimation, so per-action
  indirection sits on a hot path.

On saves: `GlobalState` persists `actionStates` keyed by `ActionId`,
`skillStates` by skill name, `plotStates` by `MelvorId`. Nothing in the save
encodes an action's class shape, so **the capability split needs no save
migration.** Only splitting `ActionState` would, and its JSON already omits
`combat` and `selectedRecipeIndex` when null, so that shape is close already.

## Traits, and what Dart gives us instead

The model here is Rust traits: declare `Performable`, `Masterable`, `Recipe`,
implement them per type, and write functions over whatever combination they
need. Dart's mixins are the closest construct and carry most of it - default
implementations, multiple application, mixin-as-a-type. Three differences
shape the design.

**No intersection types.** Rust writes `fn f<T: Performable + Masterable>`.
Dart cannot spell that. This is the binding constraint, and the reason the
answer is not "dissolve `SkillAction` into mixins": the solver touches
`inputs`/`outputs` in 39 files and wants several capabilities at once. Dart
pushes you to name the combinations actually in use, and there are three:

```dart
abstract class SkillAction extends Action     // 13 ordinary actions
    with Trainable, Performable, Recipe, Masterable {}
class FarmingCrop  extends Action with Trainable, Recipe, Masterable {}
class CombatAction extends Action with Performable {}
```

**No retroactive implementation.** `impl Trait for Foo` has no Dart analogue;
capabilities are fixed at class declaration. Harmless here - the data is
static and we own every action class.

**Mixins with instance fields forbid const constructors.** Every action class
is const, so capability mixins declare abstract getters and each class
satisfies them with a `final` field. Const constructors survive mixin
application and const canonicalization still holds:

```dart
mixin Masterable on Action { double get masteryActionTime; }

class Crop extends Action with Masterable {
  const Crop({required super.id, required this.masteryActionTime});
  @override
  final double masteryActionTime;
}
// identical(c, const Crop(...)) is true
```

Registry queries return the narrow capability, which is where the
decomposition pays off:

```dart
List<Performable> performableActions(Skill skill);
List<Masterable>  masteryActions(Skill skill);
List<Recipe>      recipes(Skill skill);
```

`FarmingCrop` is absent from `performableActions`, so the `canBeActiveAction`
flag that [#275](https://github.com/eseidel/better_idle/pull/275) introduces
disappears - the type system enforces what the boolean asks politely.

## is-a or has-a

Most of what is wrong here is inheritance used for things that are not
subtype relationships, so the has-a shape deserves weighing:

```dart
class Action {
  final ActionId id; final String name; final Skill skill;
  final Performable? performable;
  final MasteryRules? mastery;
  final Recipe? recipe;
}
```

It sidesteps the intersection problem entirely - `action.recipe` is a field,
not a type constraint - and maps well onto parsing static JSON, where presence
is already optional. Against it: `action.inputs` becomes
`action.recipe!.inputs` across 39 files, trading compile-time guarantees for
null checks, and it adds a pointer hop plus a null test per access on the
solver's inner loop, where mixin dispatch costs the same as today's virtual
call.

The intersection problem is has-a's main advantage, and naming three
combinations defuses it. So: **is-a for capabilities, has-a within them.**
Capabilities are mixins; optional data inside a capability is a nullable field
rather than a member every action inherits. `alternativeRecipes` is the
clearest case - 2 of the 15 subclasses use it, and it belongs on a `Recipe`
object, not on everything with an id.

## Staged migration

1. ~~**`masteryActionTime` as a field each action supplies.**~~ Landed in
   [#277](https://github.com/eseidel/better_idle/pull/277): deleted a 26-case
   switch over `Skill` and moved farming's `masteryXPDivider` into the crop.
2. **Extract `Masterable`; split the registry queries.** Largely the content
   of #275, generalized beyond farming.
3. **Extract `Performable`; move `FarmingCrop` off `SkillAction`.** The real
   work - type annotations across the solver. `canBeActiveAction` dies here,
   and the crop's interval becomes a growth interval rather than a duration.
4. **Extract `Recipe`**, dropping it from Astrology and Alt. Magic, whose maps
   are permanently empty, and folding `alternativeRecipes` into it.

Stage 3 carries the risk. Stages 1 and 2 make it mechanical. None of the four
touches the save format.

## Alternatives considered

**Leave the hierarchy alone; fix it at the registry.** Add
`masteryActions`/`recipes` alongside `actionsForSkill` and stop pretending one
list serves every caller. Cheap, and what #275 does for the farming case.
Rejected as an end state because it leaves the lying fields in place -
astrology's empty `outputs`, the crop's borrowed duration - and the next odd
action re-opens the argument.

**Full composition**, with `Action` holding nullable capability objects.
Rejected for the 39-file null-check churn and the hot-path cost, not because
the modelling is wrong.

**Pure mixins with no combined type.** Rejected on the Dart constraint: the
solver would have nothing to name.

## Open questions

- Where does the crop's growth interval live - a field on `FarmingCrop`, or a
  `GrowsOverTime` capability paired with the plot state that counts it down?
- Does `ActionState` want the same treatment? It is `masteryXp` +
  `cumulativeTicks` + `combat` + `selectedRecipeIndex`, four concerns in one
  record, mirroring `SkillAction` on the state side. Unlike the action split
  this one is persisted and needs a save migration.
- Is `Trainable` worth separating at all? Only `CombatAction` lacks it, and
  combat levelling differs enough that it may never share the mixin.
