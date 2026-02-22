import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/widgets/context_extensions.dart';
import 'package:ui/src/widgets/item_image.dart';
import 'package:ui/src/widgets/style.dart';

/// Shows a dialog displaying the equipment stats for an item.
void showEquipmentStatsDialog(BuildContext context, Item item) {
  showDialog<void>(
    context: context,
    builder: (_) => EquipmentStatsDialog(item: item),
  );
}

/// A dialog that displays equipment stats organized into three cards:
/// item info, offensive stats, and defensive stats.
class EquipmentStatsDialog extends StatelessWidget {
  const EquipmentStatsDialog({required this.item, super.key});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final stats = item.equipmentStats;

    final offensiveStats = <(EquipmentStatModifier, int)>[];
    final defensiveStats = <(EquipmentStatModifier, int)>[];
    for (final modifier in EquipmentStatModifier.values) {
      final value = stats.getAsModifier(modifier);
      if (value == null) continue;
      if (modifier.isOffensive) {
        offensiveStats.add((modifier, value));
      } else {
        defensiveStats.add((modifier, value));
      }
    }

    return AlertDialog(
      title: Text(item.name),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ItemInfoCard(item: item),
              const SizedBox(width: 8),
              _StatsCard(title: 'Offensive Stats', stats: offensiveStats),
              const SizedBox(width: 8),
              _StatsCard(title: 'Defensive Stats', stats: defensiveStats),
            ],
          ),
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

class _ItemInfoCard extends StatelessWidget {
  const _ItemInfoCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final registry = context.state.registries.modifierMetadata;
    final modifierDescriptions = _formatModifiers(item, registry);

    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ItemImage(item: item, size: 64),
              if (modifierDescriptions.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final desc in modifierDescriptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Style.textColorSuccess,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<String> _formatModifiers(Item item, ModifierMetadataRegistry registry) {
    final descriptions = <String>[];
    for (final mod in item.modifiers.modifiers) {
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
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.stats});

  final String title;
  final List<(EquipmentStatModifier, int)> stats;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (stats.isEmpty)
                const Text(
                  'None',
                  style: TextStyle(color: Style.textColorSecondary),
                )
              else
                for (final (modifier, value) in stats)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            modifier.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Style.textColorSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '$value',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
