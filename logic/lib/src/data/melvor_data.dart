import 'dart:io';

import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_unlock.dart';

import 'actions.dart';
import 'cache.dart';
import 'melvor_id.dart';
import 'shop.dart';

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
      return await loadFromCache(cache);
    } finally {
      cache.close();
    }
  }

  /// Loads MelvorData from an existing cache instance.
  static Future<MelvorData> loadFromCache(Cache cache) async {
    final demoData = await cache.ensureDemoData();
    final fullData = await cache.ensureFullData();
    return MelvorData([demoData, fullData]);
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

    final (farmingCrops, farmingCategories, farmingPlots) = parseFarming(
      skillDataById['melvorD:Farming'],
    );
    actions.addAll(farmingCrops);
    _farmingCrops = FarmingCropRegistry(farmingCrops);
    _farmingCategories = farmingCategories;
    _farmingPlots = farmingPlots;

    final (fletchingActions, fletchingCategories) = parseFletching(
      skillDataById['melvorD:Fletching'],
    );
    actions.addAll(fletchingActions);
    _fletchingCategories = fletchingCategories;

    final (craftingActions, craftingCategories) = parseCrafting(
      skillDataById['melvorD:Crafting'],
    );
    actions.addAll(craftingActions);
    _craftingCategories = craftingCategories;

    final (herbloreActions, herbloreCategories) = parseHerblore(
      skillDataById['melvorD:Herblore'],
    );
    actions.addAll(herbloreActions);
    _herbloreCategories = herbloreCategories;

    final (runecraftingActions, runecraftingCategories) = parseRunecrafting(
      skillDataById['melvorD:Runecrafting'],
    );
    actions.addAll(runecraftingActions);
    _runecraftingCategories = runecraftingCategories;

    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      actions.addAll(parseCombatActions(json, namespace: namespace));
    }

    final (thievingActions, thievingAreas) = parseThieving(
      skillDataById['melvorD:Thieving'],
    );
    actions.addAll(thievingActions);
    _thievingAreas = thievingAreas;

    final (agilityActions, agilityCourses, agilityPillars) = parseAgility(
      skillDataById['melvorD:Agility'],
    );
    actions.addAll(agilityActions);
    _agilityCourses = agilityCourses;
    _agilityPillars = agilityPillars;

    actions.addAll(parseSummoning(skillDataById['melvorD:Summoning']));
    actions.addAll(parseAstrology(skillDataById['melvorD:Astrology']));
    actions.addAll(parseAltMagic(skillDataById['melvorD:Magic']));

    _actions = ActionRegistry(actions);
    _combatAreas = CombatAreaRegistry(combatAreas);

    // Parse shop data
    _shop = parseShop(dataFiles);

    // Parse mastery bonuses for all skills
    _masteryBonuses = parseMasteryBonuses(skillDataById);

    // Parse mastery unlocks (display-only descriptions) for all skills
    _masteryUnlocks = parseMasteryUnlocks(skillDataById);
  }

  late final ItemRegistry _items;
  late final ActionRegistry _actions;
  late final ShopRegistry _shop;
  late final FishingAreaRegistry _fishingAreas;
  late final SmithingCategoryRegistry _smithingCategories;
  late final FarmingCropRegistry _farmingCrops;
  late final FarmingCategoryRegistry _farmingCategories;
  late final FarmingPlotRegistry _farmingPlots;
  late final FletchingCategoryRegistry _fletchingCategories;
  late final CraftingCategoryRegistry _craftingCategories;
  late final HerbloreCategoryRegistry _herbloreCategories;
  late final RunecraftingCategoryRegistry _runecraftingCategories;
  late final ThievingAreaRegistry _thievingAreas;
  late final CombatAreaRegistry _combatAreas;
  late final AgilityCourseRegistry _agilityCourses;
  late final AgilityPillarRegistry _agilityPillars;
  late final MasteryBonusRegistry _masteryBonuses;
  late final MasteryUnlockRegistry _masteryUnlocks;

  /// Returns the item registry.
  ItemRegistry get items => _items;

  ActionRegistry get actions => _actions;

  FishingAreaRegistry get fishingAreas => _fishingAreas;

  SmithingCategoryRegistry get smithingCategories => _smithingCategories;

  FarmingCropRegistry get farmingCrops => _farmingCrops;

  FarmingCategoryRegistry get farmingCategories => _farmingCategories;

  FarmingPlotRegistry get farmingPlots => _farmingPlots;

  FletchingCategoryRegistry get fletchingCategories => _fletchingCategories;

  CraftingCategoryRegistry get craftingCategories => _craftingCategories;

  HerbloreCategoryRegistry get herbloreCategories => _herbloreCategories;

  RunecraftingCategoryRegistry get runecraftingCategories =>
      _runecraftingCategories;

  ThievingAreaRegistry get thievingAreas => _thievingAreas;

  CombatAreaRegistry get combatAreas => _combatAreas;

  AgilityCourseRegistry get agilityCourses => _agilityCourses;

  AgilityPillarRegistry get agilityPillars => _agilityPillars;

  ShopRegistry get shop => _shop;

  MasteryBonusRegistry get masteryBonuses => _masteryBonuses;

  MasteryUnlockRegistry get masteryUnlocks => _masteryUnlocks;
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

/// Parses all farming data. Returns (crops, categoriesRegistry, plotsRegistry).
(List<FarmingCrop>, FarmingCategoryRegistry, FarmingPlotRegistry) parseFarming(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], FarmingCategoryRegistry([]), FarmingPlotRegistry([]));
  }

  final crops = <FarmingCrop>[];
  final categories = <FarmingCategory>[];
  final plots = <FarmingPlot>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      crops.addAll(
        recipes.map(
          (json) => FarmingCrop.fromJson(
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
          (json) => FarmingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    final plotsJson = entry.data['plots'] as List<dynamic>?;
    if (plotsJson != null) {
      plots.addAll(
        plotsJson.map(
          (json) => FarmingPlot.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (
    crops,
    FarmingCategoryRegistry(categories),
    FarmingPlotRegistry(plots),
  );
}

/// Parses all fletching data. Returns (actions, categoriesRegistry).
(List<FletchingAction>, FletchingCategoryRegistry) parseFletching(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], FletchingCategoryRegistry([]));
  }

  final actions = <FletchingAction>[];
  final categories = <FletchingCategory>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => FletchingAction.fromJson(
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
          (json) => FletchingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, FletchingCategoryRegistry(categories));
}

/// Parses all crafting data. Returns (actions, categoriesRegistry).
(List<CraftingAction>, CraftingCategoryRegistry) parseCrafting(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], CraftingCategoryRegistry([]));
  }

  final actions = <CraftingAction>[];
  final categories = <CraftingCategory>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => CraftingAction.fromJson(
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
          (json) => CraftingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, CraftingCategoryRegistry(categories));
}

/// Parses all herblore data. Returns (actions, categoriesRegistry).
(List<HerbloreAction>, HerbloreCategoryRegistry) parseHerblore(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], HerbloreCategoryRegistry([]));
  }

  final actions = <HerbloreAction>[];
  final categories = <HerbloreCategory>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => HerbloreAction.fromJson(
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
          (json) => HerbloreCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, HerbloreCategoryRegistry(categories));
}

/// Parses all runecrafting data. Returns (actions, categoriesRegistry).
(List<RunecraftingAction>, RunecraftingCategoryRegistry) parseRunecrafting(
  List<SkillDataEntry>? entries,
) {
  if (entries == null) {
    return ([], RunecraftingCategoryRegistry([]));
  }

  final actions = <RunecraftingAction>[];
  final categories = <RunecraftingCategory>[];

  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => RunecraftingAction.fromJson(
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
          (json) => RunecraftingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (actions, RunecraftingCategoryRegistry(categories));
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

/// Parses all shop data from multiple data files.
ShopRegistry parseShop(List<Map<String, dynamic>> dataFiles) {
  final purchases = <ShopPurchase>[];
  final categories = <ShopCategory>[];

  for (final json in dataFiles) {
    final namespace = json['namespace'] as String;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) continue;

    // Parse shop purchases
    final purchasesJson = data['shopPurchases'] as List<dynamic>? ?? [];
    for (final purchaseJson in purchasesJson) {
      try {
        purchases.add(
          ShopPurchase.fromJson(
            purchaseJson as Map<String, dynamic>,
            namespace: namespace,
          ),
        );
      } on ArgumentError {
        // Skip purchases with unknown currencies or skills
        continue;
      }
    }

    // Parse shop categories
    final categoriesJson = data['shopCategories'] as List<dynamic>? ?? [];
    for (final categoryJson in categoriesJson) {
      categories.add(
        ShopCategory.fromJson(
          categoryJson as Map<String, dynamic>,
          namespace: namespace,
        ),
      );
    }
  }

  return ShopRegistry(purchases, categories);
}

/// Parses mastery level bonuses for all skills.
MasteryBonusRegistry parseMasteryBonuses(
  Map<String, List<SkillDataEntry>> skillDataById,
) {
  final skillBonuses = <SkillMasteryBonuses>[];

  for (final entry in skillDataById.entries) {
    final skillId = MelvorId.fromJson(entry.key);
    final bonuses = <MasteryLevelBonus>[];

    // Collect bonuses from all data entries for this skill
    for (final dataEntry in entry.value) {
      bonuses.addAll(
        parseMasteryLevelBonuses(
          dataEntry.data,
          namespace: dataEntry.namespace,
        ),
      );
    }

    if (bonuses.isNotEmpty) {
      skillBonuses.add(SkillMasteryBonuses(skillId: skillId, bonuses: bonuses));
    }
  }

  return MasteryBonusRegistry(skillBonuses);
}

/// Parses mastery level unlocks (display-only descriptions) for all skills.
MasteryUnlockRegistry parseMasteryUnlocks(
  Map<String, List<SkillDataEntry>> skillDataById,
) {
  final skillUnlocks = <SkillMasteryUnlocks>[];

  for (final entry in skillDataById.entries) {
    final skillId = MelvorId.fromJson(entry.key);
    final unlocks = <MasteryLevelUnlock>[];

    // Collect unlocks from all data entries for this skill
    for (final dataEntry in entry.value) {
      unlocks.addAll(parseMasteryLevelUnlocks(dataEntry.data));
    }

    if (unlocks.isNotEmpty) {
      // Sort by level and remove duplicates
      unlocks.sort((a, b) => a.level.compareTo(b.level));
      skillUnlocks.add(SkillMasteryUnlocks(skillId: skillId, unlocks: unlocks));
    }
  }

  return MasteryUnlockRegistry(skillUnlocks);
}

/// Parses all agility data. Returns (obstacles, coursesRegistry, pillarsRegistry).
(List<AgilityObstacle>, AgilityCourseRegistry, AgilityPillarRegistry)
parseAgility(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return ([], AgilityCourseRegistry([]), AgilityPillarRegistry([]));
  }

  final obstacles = <AgilityObstacle>[];
  final courses = <AgilityCourse>[];
  final pillars = <AgilityPillar>[];

  for (final entry in entries) {
    // Parse obstacles
    final obstaclesJson = entry.data['obstacles'] as List<dynamic>?;
    if (obstaclesJson != null) {
      obstacles.addAll(
        obstaclesJson.map(
          (json) => AgilityObstacle.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse courses
    final coursesJson = entry.data['courses'] as List<dynamic>?;
    if (coursesJson != null) {
      courses.addAll(
        coursesJson.map(
          (json) => AgilityCourse.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse pillars
    final pillarsJson = entry.data['pillars'] as List<dynamic>?;
    if (pillarsJson != null) {
      pillars.addAll(
        pillarsJson.map(
          (json) => AgilityPillar.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  return (
    obstacles,
    AgilityCourseRegistry(courses),
    AgilityPillarRegistry(pillars),
  );
}

/// Parses all summoning data. Returns actions list.
List<SummoningAction> parseSummoning(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <SummoningAction>[];
  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => SummoningAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all astrology data. Returns actions list.
List<AstrologyAction> parseAstrology(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <AstrologyAction>[];
  for (final entry in entries) {
    final recipes = entry.data['recipes'] as List<dynamic>?;
    if (recipes != null) {
      actions.addAll(
        recipes.map(
          (json) => AstrologyAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}

/// Parses all alt magic data. Returns actions list.
List<AltMagicAction> parseAltMagic(List<SkillDataEntry>? entries) {
  if (entries == null) return [];

  final actions = <AltMagicAction>[];
  for (final entry in entries) {
    final altSpells = entry.data['altSpells'] as List<dynamic>?;
    if (altSpells != null) {
      actions.addAll(
        altSpells.map(
          (json) => AltMagicAction.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return actions;
}
