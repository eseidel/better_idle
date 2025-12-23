import 'dart:io';

import 'actions.dart';
import 'cache.dart';
import 'melvor_id.dart';

/// A skill data entry from a single data file, with its namespace preserved.
class SkillDataEntry {
  const SkillDataEntry(this.namespace, this.data);

  final String namespace;
  final Map<String, dynamic> data;
}

/// Parsed representation of the Melvor game data.
///
/// Combines data from multiple JSON files (demo + full game).
class MelvorData {
  /// Loads MelvorData from the cache, fetching from CDN if needed.
  static Future<MelvorData> load({Directory? cacheDir}) async {
    final cache = Cache(cacheDir: cacheDir ?? defaultCacheDir);
    try {
      final demoData = await cache.ensureDemoData();
      final fullData = await cache.ensureFullData();
      return MelvorData([demoData, fullData]);
    } finally {
      cache.close();
    }
  }

  /// Creates a MelvorData from multiple parsed JSON data files.
  ///
  /// Items from later files override items from earlier files with the same name.
  /// Skill data from later files is merged with earlier files by skillID.
  MelvorData(List<Map<String, dynamic>> dataFiles) {
    final items = <Item>[];
    final skillDataById = <String, List<SkillDataEntry>>{};
    final combatAreas = <CombatArea>[];

    // Step 1: Collect items and skill data entries (preserving namespace)
    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) continue;

      // Collect items
      final itemsJson = data['items'] as List<dynamic>? ?? [];
      for (final itemJson in itemsJson) {
        items.add(Item.fromJson(itemJson, namespace: namespace));
      }

      // Collect skill data entries
      final skillData = data['skillData'] as List<dynamic>? ?? [];
      for (final skill in skillData) {
        if (skill is! Map<String, dynamic>) continue;
        final skillId = skill['skillID'] as String?;
        final skillContent = skill['data'] as Map<String, dynamic>?;
        if (skillId == null || skillContent == null) continue;

        skillDataById
            .putIfAbsent(skillId, () => [])
            .add(SkillDataEntry(namespace, skillContent));
      }

      // Combat areas (not skill-based)
      combatAreas.addAll(parseCombatAreas(json, namespace: namespace));
    }

    _items = ItemRegistry(items);

    // Step 2: Parse each skill (null-safe, returns empty on missing)
    final actions = <Action>[];

    actions.addAll(parseWoodcutting(skillDataById['melvorD:Woodcutting']));
    actions.addAll(parseMining(skillDataById['melvorD:Mining']));
    actions.addAll(parseCooking(skillDataById['melvorD:Cooking']));
    actions.addAll(parseFiremaking(skillDataById['melvorD:Firemaking']));

    final (fishingActions, fishingAreas) = parseFishing(
      skillDataById['melvorD:Fishing'],
    );
    actions.addAll(fishingActions);
    _fishingAreas = fishingAreas;

    final (smithingActions, smithingCategories) = parseSmithing(
      skillDataById['melvorD:Smithing'],
    );
    actions.addAll(smithingActions);
    _smithingCategories = smithingCategories;

    // Parse combat before thieving so thieving wins name collisions
    // (e.g., "Golbin" exists as both monster and thieving NPC).
    // TODO(eseidel): Having a single ActionRegistry for both skill actions
    // and combat actions is problematic due to name collisions. Consider
    // separating into SkillActionRegistry and CombatActionRegistry.
    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      actions.addAll(parseCombatActions(json, namespace: namespace));
    }

    final (thievingActions, thievingAreas) = parseThieving(
      skillDataById['melvorD:Thieving'],
    );
    actions.addAll(thievingActions);
    _thievingAreas = thievingAreas;

    _actions = ActionRegistry(actions);
    _combatAreas = CombatAreaRegistry(combatAreas);
  }

  late final ItemRegistry _items;
  late final ActionRegistry _actions;
  late final FishingAreaRegistry _fishingAreas;
  late final SmithingCategoryRegistry _smithingCategories;
  late final ThievingAreaRegistry _thievingAreas;
  late final CombatAreaRegistry _combatAreas;

  /// Returns the item registry.
  ItemRegistry get items => _items;

  ActionRegistry get actions => _actions;

  FishingAreaRegistry get fishingAreas => _fishingAreas;

  SmithingCategoryRegistry get smithingCategories => _smithingCategories;

  ThievingAreaRegistry get thievingAreas => _thievingAreas;

  CombatAreaRegistry get combatAreas => _combatAreas;
}

/// Parses all woodcutting data. Returns actions list.
List<WoodcuttingTree> parseWoodcutting(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <WoodcuttingTree>[];
  for (final entry in entries) {
    final trees = entry.data['trees'] as List<dynamic>?;
    if (trees != null) {
      actions.addAll(
        trees.map(
          (json) => WoodcuttingTree.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all mining data. Returns actions list.
List<MiningAction> parseMining(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <MiningAction>[];
  for (final entry in entries) {
    final rocks = entry.data['rockData'] as List<dynamic>?;
    if (rocks != null) {
      actions.addAll(
        rocks.map(
          (json) => MiningAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all fishing data. Returns (actions, areasRegistry).
(List<FishingAction>, FishingAreaRegistry) parseFishing(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], FishingAreaRegistry([]));
  }

  final actions = <FishingAction>[];
  final areas = <FishingArea>[];

  for (final entry in entries) {
    final fish = entry.data['fish'] as List<dynamic>?;
    if (fish != null) {
      actions.addAll(
        fish.map(
          (json) => FishingAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    final areasJson = entry.data['areas'] as List<dynamic>?;
    if (areasJson != null) {
      areas.addAll(
        areasJson.map(
          (json) => FishingArea.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, FishingAreaRegistry(areas));
}

/// Parses all cooking data. Returns actions list.
List<CookingAction> parseCooking(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <CookingAction>[];
  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => CookingAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all firemaking data. Returns actions list.
List<FiremakingAction> parseFiremaking(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <FiremakingAction>[];
  for (final entry in entries) {
    final logs = entry.data['logs'] as List<dynamic>?;
    if (logs != null) {
      actions.addAll(
        logs.map(
          (json) => FiremakingAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all smithing data. Returns (actions, categoriesRegistry).
(List<SmithingAction>, SmithingCategoryRegistry) parseSmithing(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], SmithingCategoryRegistry([]));
  }

  final actions = <SmithingAction>[];
  final categories = <SmithingCategory>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => SmithingAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    final cats = entry.data['categories'] as List<dynamic>?;
    if (cats != null) {
      categories.addAll(
        cats.map(
          (json) => SmithingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, SmithingCategoryRegistry(categories));
}

/// Parses all thieving data. Builds areas registry internally.
/// Returns (actions, areasRegistry).
(List<ThievingAction>, ThievingAreaRegistry) parseThieving(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], ThievingAreaRegistry([]));
  }

  // First pass: collect areas
  final areas = <ThievingArea>[];
  for (final entry in entries) {
    final areasJson = entry.data['areas'] as List<dynamic>?;
    if (areasJson != null) {
      areas.addAll(
        areasJson.map(
          (json) => ThievingArea.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  // Build registry so we can look up areas for NPCs
  final areasRegistry = ThievingAreaRegistry(areas);

  // Second pass: parse NPCs (need area lookup)
  final actions = <ThievingAction>[];
  for (final entry in entries) {
    final npcs = entry.data['npcs'] as List<dynamic>?;
    if (npcs != null) {
      actions.addAll(
        npcs.map((npcJson) {
          final npcMap = npcJson as Map<String, dynamic>;
          final npcId = MelvorId.fromJsonWithNamespace(
            npcMap['id'] as String,
            defaultNamespace: entry.namespace,
          );
          return ThievingAction.fromJson(
            npcMap,
            namespace: entry.namespace,
            area: areasRegistry.areaForNpc(npcId),
          );
        }),
      );
    }
  }

  return (actions, areasRegistry);
}

List<CombatAction> parseCombatActions(
  Map<String, dynamic> json, {
  required String namespace,
}) {
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) {
    return [];
  }

  final monsters = data['monsters'] as List<dynamic>? ?? [];
  return monsters
      .map((monsterJson) => monsterJson as Map<String, dynamic>)
      // Filter out monsters with empty names (like RandomITM).
      .where((m) => (m['name'] as String?)?.isNotEmpty ?? false)
      .map(
        (monsterJson) =>
            CombatAction.fromJson(monsterJson, namespace: namespace),
      )
      .toList();
}

List<CombatArea> parseCombatAreas(
  Map<String, dynamic> json, {
  required String namespace,
}) {
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) {
    return [];
  }

  final areas = data['combatAreas'] as List<dynamic>? ?? [];
  return areas
      .map((areaJson) => areaJson as Map<String, dynamic>)
      .map((areaJson) => CombatArea.fromJson(areaJson, namespace: namespace))
      .toList();
}
