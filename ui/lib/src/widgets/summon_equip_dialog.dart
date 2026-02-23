import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Returns true if there are any equippable synergies or skill-relevant
/// summon tablets for the given [skill].
bool hasSummonContent(GlobalState state, Skill skill) {
  final summoning = state.registries.summoning;

  // Check for any skill-relevant tablets in inventory.
  for (final stack in state.inventory.items) {
    if (stack.item.isSummonTablet &&
        summoning.isFamiliarRelevantToSkill(stack.item.id, skill)) {
      return true;
    }
  }

  // Check for already-equipped tablets relevant to this skill.
  for (final slot in [EquipmentSlot.summon1, EquipmentSlot.summon2]) {
    final item = state.equipment.gearInSlot(slot);
    if (item != null &&
        item.isSummonTablet &&
        summoning.isFamiliarRelevantToSkill(item.id, skill)) {
      return true;
    }
  }

  return false;
}

/// Shows a dialog for equipping summon tablets relevant to a skill.
///
/// Lists equippable synergy pairs (with effects) first, then individual
/// skill-relevant tablets.
void showSummonEquipDialog(BuildContext context, Skill skill) {
  showDialog<void>(
    context: context,
    builder: (_) => SummonEquipDialog(skill: skill),
  );
}

/// A synergy pair that the player can equip.
class _EquippableSynergy {
  _EquippableSynergy({
    required this.synergy,
    required this.action1,
    required this.action2,
    required this.tablet1,
    required this.tablet2,
  });

  final SummoningSynergy synergy;
  final SummoningAction action1;
  final SummoningAction action2;
  final Item tablet1;
  final Item tablet2;
}

/// Dialog displaying equippable summon synergies and individual tablets
/// for a given skill.
class SummonEquipDialog extends StatelessWidget {
  const SummonEquipDialog({required this.skill, super.key});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final summoning = state.registries.summoning;
    final synergies = state.registries.summoningSynergies;
    final equipment = state.equipment;

    // Find equippable synergies relevant to this skill.
    final equippableSynergies = <_EquippableSynergy>[];
    for (final synergy in synergies.all) {
      if (synergy.summonIds.length != 2) continue;
      final a1 = summoning.byId(synergy.summonIds[0]);
      final a2 = summoning.byId(synergy.summonIds[1]);
      if (a1 == null || a2 == null) continue;

      // At least one familiar must be relevant to this skill.
      final relevant = a1.markSkillIds.contains(skill.id) ||
          a2.markSkillIds.contains(skill.id);
      if (!relevant) continue;

      // Both must have mark level >= 3.
      if (state.summoning.markLevel(a1.productId) < 3) continue;
      if (state.summoning.markLevel(a2.productId) < 3) continue;

      // Player must have both tablets (in inventory or equipped).
      final t1 = state.registries.items.byId(a1.productId);
      final t2 = state.registries.items.byId(a2.productId);
      final has1 = state.inventory.countOfItem(t1) > 0 ||
          equipment.gearInSlot(EquipmentSlot.summon1)?.id == t1.id ||
          equipment.gearInSlot(EquipmentSlot.summon2)?.id == t1.id;
      final has2 = state.inventory.countOfItem(t2) > 0 ||
          equipment.gearInSlot(EquipmentSlot.summon1)?.id == t2.id ||
          equipment.gearInSlot(EquipmentSlot.summon2)?.id == t2.id;
      if (!has1 || !has2) continue;

      equippableSynergies.add(
        _EquippableSynergy(
          synergy: synergy,
          action1: a1,
          action2: a2,
          tablet1: t1,
          tablet2: t2,
        ),
      );
    }

    // Find individual skill-relevant tablets in inventory.
    final individualTablets = <Item>[];
    for (final stack in state.inventory.items) {
      final item = stack.item;
      if (!item.isSummonTablet) continue;
      if (!summoning.isFamiliarRelevantToSkill(item.id, skill)) continue;
      individualTablets.add(item);
    }
    individualTablets.sort((a, b) => a.name.compareTo(b.name));

    final hasContent =
        equippableSynergies.isNotEmpty || individualTablets.isNotEmpty;

    return AlertDialog(
      title: Text('Summons — ${skill.name}'),
      content: SizedBox(
        width: 350,
        child: !hasContent
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No equippable tablets or synergies for this skill.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Style.textColorSecondary),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  if (equippableSynergies.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Synergies',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (final es in equippableSynergies)
                      _SynergyCard(
                        equippableSynergy: es,
                        skill: skill,
                      ),
                  ],
                  if (individualTablets.isNotEmpty)
                    _IndividualTabletSection(
                      tablets: individualTablets,
                      skill: skill,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Card displaying a synergy pair with effects and an equip button.
class _SynergyCard extends StatelessWidget {
  const _SynergyCard({
    required this.equippableSynergy,
    required this.skill,
  });

  final _EquippableSynergy equippableSynergy;
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final es = equippableSynergy;
    final descriptions = _formatModifiers(
      es.synergy.modifiers,
      state.registries.modifierMetadata,
    );

    // Check if this synergy is already active.
    final activeSynergy = state.getActiveSynergy();
    final isActive = activeSynergy != null &&
        activeSynergy.matches(es.action1.summonId, es.action2.summonId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Familiar icons and names.
            Row(
              children: [
                ItemImage(item: es.tablet1, size: 28),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    es.tablet1.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                ItemImage(item: es.tablet2, size: 28),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    es.tablet2.name,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Effects.
            if (descriptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final desc in descriptions)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      color: Style.textColorSuccess,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            // Equip button.
            Align(
              alignment: Alignment.centerRight,
              child: isActive
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 18),
                        SizedBox(width: 4),
                        Text('Equipped', style: TextStyle(fontSize: 13)),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: () {
                        context
                          ..dispatch(
                            EquipGearAction(
                              item: es.tablet1,
                              slot: EquipmentSlot.summon1,
                            ),
                          )
                          ..dispatch(
                            EquipGearAction(
                              item: es.tablet2,
                              slot: EquipmentSlot.summon2,
                            ),
                          );
                        Navigator.of(context).pop();
                      },
                      child: const Text('Equip'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section listing individual skill-relevant tablets.
class _IndividualTabletSection extends StatelessWidget {
  const _IndividualTabletSection({
    required this.tablets,
    required this.skill,
  });

  final List<Item> tablets;
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Individual Tablets'),
      children: [
        for (final tablet in tablets)
          _IndividualTabletTile(item: tablet, skill: skill),
      ],
    );
  }
}

/// Tile for an individual tablet with an equip button.
///
/// Equips to the first available summon slot (prefers empty, then slot 1).
class _IndividualTabletTile extends StatelessWidget {
  const _IndividualTabletTile({
    required this.item,
    required this.skill,
  });

  final Item item;
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final equipment = state.equipment;
    final unmetReqs = state.unmetEquipRequirements(item);
    final count = state.inventory.countOfItem(item);

    final isEquipped =
        equipment.gearInSlot(EquipmentSlot.summon1)?.id == item.id ||
        equipment.gearInSlot(EquipmentSlot.summon2)?.id == item.id;

    // Pick the best slot: prefer empty, fall back to slot 1.
    final slot1Empty = equipment.gearInSlot(EquipmentSlot.summon1) == null;
    final targetSlot =
        slot1Empty ? EquipmentSlot.summon1 : EquipmentSlot.summon2;

    return ListTile(
      dense: true,
      leading: ItemImage(item: item, size: 28),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: unmetReqs.isNotEmpty
          ? Text(
              'Requirements not met',
              style: TextStyle(
                fontSize: 12,
                color: Style.unmetRequirementColor,
              ),
            )
          : Text('x$count', style: const TextStyle(fontSize: 12)),
      trailing: isEquipped
          ? const Icon(Icons.check, size: 20)
          : unmetReqs.isEmpty
              ? OutlinedButton(
                  onPressed: () {
                    context.dispatch(
                      EquipGearAction(item: item, slot: targetSlot),
                    );
                  },
                  child: const Text('Equip'),
                )
              : null,
    );
  }
}

/// Formats a [ModifierDataSet] into a list of human-readable descriptions.
List<String> _formatModifiers(
  ModifierDataSet modifierSet,
  ModifierMetadataRegistry registry,
) {
  final descriptions = <String>[];
  for (final mod in modifierSet.modifiers) {
    for (final entry in mod.entries) {
      String? skillName;
      String? currencyName;
      final scope = entry.scope;
      if (scope != null) {
        if (scope.skillId != null) {
          skillName = Skill.fromId(scope.skillId!).name;
        }
        if (scope.currencyId != null) {
          currencyName = Currency.fromId(scope.currencyId!).name;
        }
      }
      descriptions.add(
        registry.formatDescription(
          name: mod.name,
          value: entry.value,
          skillName: skillName,
          currencyName: currencyName,
        ),
      );
    }
  }
  return descriptions;
}
