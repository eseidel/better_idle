import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/cached_image.dart';
import 'package:better_idle/src/widgets/context_extensions.dart';
import 'package:better_idle/src/widgets/game_scaffold.dart';
import 'package:better_idle/src/widgets/item_image.dart';
import 'package:better_idle/src/widgets/mastery_pool.dart';
import 'package:better_idle/src/widgets/mastery_unlocks_dialog.dart';
import 'package:better_idle/src/widgets/shard_purchase_dialog.dart';
import 'package:better_idle/src/widgets/skill_action_display.dart';
import 'package:better_idle/src/widgets/skill_image.dart';
import 'package:better_idle/src/widgets/skill_milestones_dialog.dart';
import 'package:better_idle/src/widgets/skill_progress.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:logic/logic.dart';

class SummoningPage extends StatefulWidget {
  const SummoningPage({super.key});

  @override
  State<SummoningPage> createState() => _SummoningPageState();
}

class _SummoningPageState extends State<SummoningPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SummoningAction? _selectedAction;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToTabletForAction(SummoningAction action) {
    setState(() {
      _selectedAction = action;
    });
    _tabController.animateTo(1); // Switch to Tablets tab
  }

  @override
  Widget build(BuildContext context) {
    const skill = Skill.summoning;
    final state = context.state;
    final actions = state.registries.summoning.actions.toList();
    final skillState = state.skillState(skill);
    final skillLevel = skillState.skillLevel;

    // Sort by level, then by tier
    actions.sort((SummoningAction a, SummoningAction b) {
      final tierCompare = a.tier.compareTo(b.tier);
      if (tierCompare != 0) return tierCompare;
      return a.unlockLevel.compareTo(b.unlockLevel);
    });

    // Default to first unlocked action if none selected
    final unlockedActions = actions
        .where((SummoningAction a) => skillLevel >= a.unlockLevel)
        .toList();
    final selectedAction =
        _selectedAction ??
        (unlockedActions.isNotEmpty ? unlockedActions.first : actions.first);

    return GameScaffold(
      title: const Text('Summoning'),
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(
            icon: CachedImage(
              assetPath: 'assets/media/skills/summoning/mark_4_256.png',
              size: 24,
            ),
            text: 'Marks',
          ),
          Tab(
            icon: CachedImage(
              assetPath: 'assets/media/skills/summoning/summoning.png',
              size: 24,
            ),
            text: 'Tablets',
          ),
        ],
      ),
      body: Column(
        children: [
          SkillProgress(xp: skillState.xp),
          const MasteryPoolProgress(skill: skill),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MasteryUnlocksButton(skill: skill),
              SkillMilestonesButton(skill: skill),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MarksTab(
                  actions: actions,
                  skillLevel: skillLevel,
                  onCreateTablets: _navigateToTabletForAction,
                ),
                _TabletsTab(
                  actions: actions,
                  selectedAction: selectedAction,
                  skillLevel: skillLevel,
                  onSelectAction: (action) {
                    setState(() {
                      _selectedAction = action;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Marks tab showing all summoning marks and their discovery progress.
class _MarksTab extends StatelessWidget {
  const _MarksTab({
    required this.actions,
    required this.skillLevel,
    required this.onCreateTablets,
  });

  final List<SummoningAction> actions;
  final int skillLevel;
  final void Function(SummoningAction) onCreateTablets;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions.map((action) {
          return _MarkCard(
            action: action,
            skillLevel: skillLevel,
            onCreateTablets: () => onCreateTablets(action),
          );
        }).toList(),
      ),
    );
  }
}

/// A card displaying a summoning mark with its progress and discovery info.
class _MarkCard extends StatelessWidget {
  const _MarkCard({
    required this.action,
    required this.skillLevel,
    required this.onCreateTablets,
  });

  final SummoningAction action;
  final int skillLevel;
  final VoidCallback onCreateTablets;

  @override
  Widget build(BuildContext context) {
    final isUnlocked = skillLevel >= action.unlockLevel;

    if (!isUnlocked) {
      return _LockedMarkCard(action: action);
    }

    final state = context.state;
    final summoningState = state.summoning;
    final isDiscovered = summoningState.isDiscovered(action.productId);

    // Show simplified card for undiscovered marks
    if (!isDiscovered) {
      return _UndiscoveredMarkCard(action: action);
    }

    final hasCrafted = summoningState.hasCrafted(action.productId);

    // Show card prompting to create first tablet
    if (!hasCrafted) {
      return _NeedFirstCraftCard(
        action: action,
        onCreateTablets: onCreateTablets,
      );
    }

    final marks = summoningState.marksFor(action.productId);
    final markLevel = summoningState.markLevel(action.productId);
    final maxMarkLevel = markLevelThresholds.length;
    final isMaxLevel = markLevel >= maxMarkLevel;
    final familiarItem = state.registries.items.byId(action.productId);

    // Calculate progress to next mark level
    final nextThreshold = markLevel < markLevelThresholds.length
        ? markLevelThresholds[markLevel]
        : markLevelThresholds.last;
    final prevThreshold = markLevel > 0
        ? markLevelThresholds[markLevel - 1]
        : 0;
    final progressInLevel = marks - prevThreshold;
    final levelRange = nextThreshold - prevThreshold;
    final progress = isMaxLevel
        ? 1.0
        : (progressInLevel / levelRange).clamp(0.0, 1.0);

    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mark level header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isMaxLevel ? 'Max Level' : 'Mark Level $markLevel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // "Mark of the" label
              const Text(
                'Mark of the',
                style: TextStyle(fontSize: 10, color: Style.textColorSecondary),
              ),
              // Familiar name
              Text(
                familiarItem.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Mark image
              if (action.markMedia != null)
                CachedImage(assetPath: action.markMedia, size: 48)
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Style.containerBackgroundLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star, size: 32, color: Colors.amber),
                ),
              const SizedBox(height: 8),
              // Progress (only show if not max level)
              if (!isMaxLevel) ...[
                SizedBox(
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Style.progressBackgroundColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.amber,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$marks / $nextThreshold',
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(height: 8),
              ],
              // Discovery skills (just icons, no label)
              _MarkDiscoverySkillsRow(skillIds: action.markSkillIds),
              const SizedBox(height: 12),
              // Create Tablets button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCreateTablets,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Style.successColor,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Create Tablets',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A simplified card for undiscovered marks showing just the essentials.
class _UndiscoveredMarkCard extends StatelessWidget {
  const _UndiscoveredMarkCard({required this.action});

  final SummoningAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        color: Style.cellBackgroundColorLocked,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Not Discovered',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Style.textColorSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Style.containerBackgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.help_outline,
                  size: 32,
                  color: Style.textColorSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Discovered In:',
                style: TextStyle(fontSize: 10, color: Style.textColorSecondary),
              ),
              const SizedBox(height: 4),
              _MarkDiscoverySkillsRow(skillIds: action.markSkillIds),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card for familiars that have been discovered but need first tablet craft.
class _NeedFirstCraftCard extends StatelessWidget {
  const _NeedFirstCraftCard({
    required this.action,
    required this.onCreateTablets,
  });

  final SummoningAction action;
  final VoidCallback onCreateTablets;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final familiarItem = state.registries.items.byId(action.productId);

    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "Mark of the" label
              const Text(
                'Mark of the',
                style: TextStyle(fontSize: 10, color: Style.textColorSecondary),
              ),
              // Familiar name
              Text(
                familiarItem.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Mark image
              if (action.markMedia != null)
                CachedImage(assetPath: action.markMedia, size: 48)
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Style.containerBackgroundLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star, size: 32, color: Colors.amber),
                ),
              const SizedBox(height: 12),
              // Instruction text
              const Text(
                'Create 1st tablet to find more marks',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Style.textColorSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // Create Tablets button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCreateTablets,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Style.successColor,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Create Tablets',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A locked mark card showing the level requirement.
class _LockedMarkCard extends StatelessWidget {
  const _LockedMarkCard({required this.action});

  final SummoningAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        color: Style.cellBackgroundColorLocked,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Locked',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Style.textColorSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Style.containerBackgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.help_outline,
                  size: 32,
                  color: Style.textColorSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Requires ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Style.textColorSecondary,
                    ),
                  ),
                  const SkillImage(skill: Skill.summoning, size: 14),
                  Text(
                    ' Level ${action.unlockLevel}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Style.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Tablets tab for creating summoning tablets.
class _TabletsTab extends StatelessWidget {
  const _TabletsTab({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelectAction,
  });

  final List<SummoningAction> actions;
  final SummoningAction selectedAction;
  final int skillLevel;
  final void Function(SummoningAction) onSelectAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SummoningActionDisplay(
            action: selectedAction,
            skillLevel: skillLevel,
            onStart: () {
              context.dispatch(ToggleActionAction(action: selectedAction));
            },
          ),
          const SizedBox(height: 24),
          _ActionList(
            actions: actions,
            selectedAction: selectedAction,
            skillLevel: skillLevel,
            onSelect: onSelectAction,
          ),
        ],
      ),
    );
  }
}

/// Custom action display for Summoning that shows mark requirements.
class _SummoningActionDisplay extends StatelessWidget {
  const _SummoningActionDisplay({
    required this.action,
    required this.skillLevel,
    required this.onStart,
  });

  final SummoningAction action;
  final int skillLevel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final summoningState = state.summoning;
    final canCraft = summoningState.canCraftTablet(action.productId);
    final marks = summoningState.marksFor(action.productId);
    final markLevel = summoningState.markLevel(action.productId);

    // If player doesn't have marks yet, show a "discover marks" message
    if (!canCraft) {
      return _buildNeedMarksDisplay(context, action, marks, markLevel);
    }

    // Otherwise show the normal skill action display
    return SkillActionDisplay(
      action: action,
      skill: Skill.summoning,
      skillLevel: skillLevel,
      headerText: 'Create',
      buttonText: 'Create',
      onStart: onStart,
      onInputItemTap: (item) => _onShardTap(context, item),
      additionalContent: _MarkProgressRow(
        marks: marks,
        markLevel: markLevel,
        markMedia: action.markMedia,
      ),
    );
  }

  void _onShardTap(BuildContext context, Item item) {
    // Check if this item has any shop purchases available
    final purchases = context.state.registries.shop.purchasesContainingItem(
      item.id,
    );
    if (purchases.isNotEmpty) {
      showShardPurchaseDialog(context, item);
    }
  }

  Widget _buildNeedMarksDisplay(
    BuildContext context,
    SummoningAction action,
    int marks,
    int markLevel,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Style.cellBackgroundColorLocked,
        border: Border.all(color: Style.textColorSecondary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Style.containerBackgroundLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.help_outline,
              size: 32,
              color: Style.textColorSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '???',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Style.textColorSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _MarkProgressRow(
            marks: marks,
            markLevel: markLevel,
            markMedia: action.markMedia,
            isDiscovered: false,
          ),
          const SizedBox(height: 16),
          const Icon(
            Icons.help_outline,
            size: 32,
            color: Style.textColorSecondary,
          ),
          const SizedBox(height: 8),
          const Text(
            'Discover marks to unlock',
            style: TextStyle(color: Style.textColorSecondary),
          ),
          const SizedBox(height: 4),
          _MarkDiscoverySkillsRow(skillIds: action.markSkillIds),
        ],
      ),
    );
  }
}

/// Shows which skills can discover marks for a familiar.
class _MarkDiscoverySkillsRow extends StatelessWidget {
  const _MarkDiscoverySkillsRow({required this.skillIds});

  final List<MelvorId> skillIds;

  @override
  Widget build(BuildContext context) {
    if (skillIds.isEmpty) {
      return const Text(
        'Train skills to find marks',
        style: TextStyle(color: Style.textColorSecondary, fontSize: 12),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final skill in skillIds.map(Skill.fromId))
          Tooltip(
            message: skill.name,
            child: SkillImage(skill: skill, size: 16),
          ),
      ],
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({
    required this.actions,
    required this.selectedAction,
    required this.skillLevel,
    required this.onSelect,
  });

  final List<SummoningAction> actions;
  final SkillAction selectedAction;
  final int skillLevel;
  final void Function(SummoningAction) onSelect;

  @override
  Widget build(BuildContext context) {
    // Group actions by tier
    final tier1 = actions.where((a) => a.tier == 1).toList();
    final tier2 = actions.where((a) => a.tier == 2).toList();
    final tier3 = actions.where((a) => a.tier == 3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tier1.isNotEmpty) ...[
          const _TierHeader(tier: 1),
          ..._buildActionCards(context, tier1),
        ],
        if (tier2.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _TierHeader(tier: 2),
          ..._buildActionCards(context, tier2),
        ],
        if (tier3.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _TierHeader(tier: 3),
          ..._buildActionCards(context, tier3),
        ],
      ],
    );
  }

  List<Widget> _buildActionCards(
    BuildContext context,
    List<SummoningAction> tierActions,
  ) {
    final state = context.state;
    final summoningState = state.summoning;

    return tierActions.map((action) {
      final isSelected = action.name == selectedAction.name;
      final isUnlocked = skillLevel >= action.unlockLevel;
      final canCraft = summoningState.canCraftTablet(action.productId);

      if (!isUnlocked) {
        return Card(
          color: Style.cellBackgroundColorLocked,
          child: ListTile(
            leading: const Icon(Icons.lock, color: Style.textColorSecondary),
            title: Row(
              children: [
                const Text(
                  'Unlocked at ',
                  style: TextStyle(color: Style.textColorSecondary),
                ),
                const SkillImage(skill: Skill.summoning, size: 14),
                Text(
                  ' Level ${action.unlockLevel}',
                  style: const TextStyle(color: Style.textColorSecondary),
                ),
              ],
            ),
            onTap: () => onSelect(action),
          ),
        );
      }

      final productItem = state.registries.items.byId(action.productId);
      final isDiscovered = summoningState.isDiscovered(action.productId);
      return Card(
        color: isSelected ? Style.selectedColorLight : null,
        child: ListTile(
          leading: Stack(
            children: [
              if (isDiscovered)
                ItemImage(item: productItem)
              else
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Style.containerBackgroundLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: Style.textColorSecondary,
                    size: 24,
                  ),
                ),
            ],
          ),
          title: Text(
            isDiscovered ? productItem.name : '???',
            style: TextStyle(
              color: isDiscovered ? null : Style.textColorSecondary,
            ),
          ),
          subtitle: canCraft
              ? _RecipesDisplay(
                  action: action,
                  onItemTap: (item) => _onShardTap(context, item),
                )
              : _MarkDiscoverySkillsRow(skillIds: action.markSkillIds),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Style.selectedColor)
              : null,
          onTap: () => onSelect(action),
        ),
      );
    }).toList();
  }

  void _onShardTap(BuildContext context, Item item) {
    // Check if this item has any shop purchases available
    final purchases = context.state.registries.shop.purchasesContainingItem(
      item.id,
    );
    if (purchases.isNotEmpty) {
      showShardPurchaseDialog(context, item);
    }
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({required this.tier});

  final int tier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Tier $tier Familiars',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Displays the selected recipe for a summoning familiar in the list.
class _RecipesDisplay extends StatelessWidget {
  const _RecipesDisplay({required this.action, this.onItemTap});

  final SummoningAction action;
  final void Function(Item item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    final state = context.state;
    final actionState = state.actionState(action.id);
    final selection = actionState.recipeSelection(action);

    // Get the selected recipe inputs
    final inputs = action.inputsForRecipe(selection);
    final hasMultipleRecipes = action.hasAlternativeRecipes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, entry) in inputs.entries.indexed) ...[
                if (index > 0) const SizedBox(width: 6),
                _buildItemCell(
                  context,
                  state.registries.items.byId(entry.key),
                  entry.value,
                ),
              ],
            ],
          ),
        ),
        if (hasMultipleRecipes)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '(multiple recipes)',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Style.textColorSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemCell(BuildContext context, Item item, int count) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ItemImage(item: item, size: 16),
        const SizedBox(width: 2),
        Text('$count', style: const TextStyle(fontSize: 12)),
      ],
    );

    if (onItemTap != null) {
      return GestureDetector(onTap: () => onItemTap!(item), child: content);
    }
    return content;
  }
}

/// Displays mark progress for a summoning familiar.
class _MarkProgressRow extends StatelessWidget {
  const _MarkProgressRow({
    required this.marks,
    required this.markLevel,
    this.markMedia,
    this.isDiscovered = true,
  });

  final int marks;
  final int markLevel;
  final String? markMedia;
  final bool isDiscovered;

  @override
  Widget build(BuildContext context) {
    // Calculate progress to next mark level
    final nextThreshold = markLevel < markLevelThresholds.length
        ? markLevelThresholds[markLevel]
        : markLevelThresholds.last;
    final prevThreshold = markLevel > 0
        ? markLevelThresholds[markLevel - 1]
        : 0;
    final progressInLevel = marks - prevThreshold;
    final levelRange = nextThreshold - prevThreshold;
    final progress = markLevel >= markLevelThresholds.length
        ? 1.0
        : (progressInLevel / levelRange).clamp(0.0, 1.0);

    return Row(
      children: [
        if (!isDiscovered)
          const Icon(
            Icons.help_outline,
            size: 16,
            color: Style.textColorSecondary,
          )
        else if (markMedia != null)
          CachedImage(assetPath: markMedia, size: 16)
        else
          const Icon(Icons.star, size: 16, color: Colors.amber),
        const SizedBox(width: 4),
        Text('Lv $markLevel', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Style.progressBackgroundColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDiscovered ? Colors.amber : Style.textColorSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$marks / $nextThreshold', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
