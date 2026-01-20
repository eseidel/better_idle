import 'dart:io';

import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/cache.dart';
import 'package:logic/src/data/melvor_id.dart';
import 'package:logic/src/data/registries.dart';
import 'package:logic/src/data/shop.dart';
import 'package:logic/src/data/summoning_synergy.dart';
import 'package:logic/src/data/township.dart';
import 'package:logic/src/types/drop.dart';
import 'package:logic/src/types/equipment_slot.dart';
import 'package:logic/src/types/mastery.dart';
import 'package:logic/src/types/mastery_pool_bonus.dart';
import 'package:logic/src/types/mastery_unlock.dart';
import 'package:meta/meta.dart';

/// A skill data entry from a single data file, with its namespace preserved.
@immutable
class SkillDataEntry {
  const SkillDataEntry(this.namespace, this.data);

  final String namespace;
  final Map<String, dynamic> data;
}

/// Parsed representation of the Melvor game data.
///
/// Combines data from multiple JSON files (demo + full game).
@immutable
class MelvorData {
  /// Creates a MelvorData from multiple parsed JSON data files.
  ///
  /// Later files override items from earlier files with the same name.
  /// Skill data from later files is merged with earlier files by skillID.
  MelvorData(List<Map<String, dynamic>> dataFiles) {
    final items = <Item>[];
    final skillDataById = <String, List<SkillDataEntry>>{};
    final combatAreas = <CombatArea>[];
    final dungeons = <Dungeon>[];
    final bankSortEntries = <DisplayOrderEntry>[];
    final equipmentSlots = <EquipmentSlotDef>[];

    // Step 1: Collect items and skill data entries (preserving namespace)
    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) continue;

      // Collect items
      final itemsJson = data['items'] as List<dynamic>? ?? [];
      for (final itemJson in itemsJson) {
        items.add(
          Item.fromJson(itemJson as Map<String, dynamic>, namespace: namespace),
        );
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

      // Dungeons (not skill-based)
      dungeons.addAll(parseDungeons(json, namespace: namespace));

      // Collect bank sort order entries
      final sortOrder = data['bankSortOrder'] as List<dynamic>? ?? [];
      for (final entry in sortOrder) {
        bankSortEntries.add(
          DisplayOrderEntry.fromJson(
            entry as Map<String, dynamic>,
            namespace: namespace,
          ),
        );
      }

      // Collect equipment slots (merging demo base with full game patches).
      final slotsJson = data['equipmentSlots'] as List<dynamic>? ?? [];
      for (final slotJson in slotsJson) {
        final slotMap = slotJson as Map<String, dynamic>;
        final slotId = slotMap['id'] as String;

        // Check if this is a patch (has add/remove in requirements).
        // Patches reference existing slots by namespaced ID.
        if (slotId.contains(':')) {
          // This is a patch - find and update the existing slot.
          final existingIndex = equipmentSlots.indexWhere(
            (s) => s.id.toJson() == slotId,
          );
          if (existingIndex >= 0) {
            // Re-parse with merged data. The fromJson handles the patch format.
            final existing = equipmentSlots[existingIndex];
            // Create a merged JSON with base slot data + patch requirements.
            final mergedJson = <String, dynamic>{
              'id': existing.id.toJson(),
              'allowQuantity': existing.allowQuantity,
              'emptyMedia': existing.emptyMedia,
              'emptyName': existing.emptyName,
              'providesEquipStats': existing.providesEquipStats,
              'gridPosition': {
                'col': existing.gridPosition.col,
                'row': existing.gridPosition.row,
              },
              'requirements': slotMap['requirements'],
            };
            equipmentSlots[existingIndex] = EquipmentSlotDef.fromJson(
              mergedJson,
              namespace: namespace,
            );
          }
        } else {
          // This is a new slot definition.
          equipmentSlots.add(
            EquipmentSlotDef.fromJson(slotMap, namespace: namespace),
          );
        }
      }
    }

    _items = ItemRegistry(items);
    _equipmentSlots = EquipmentSlotRegistry(equipmentSlots);

    // Compute bank sort order
    final bankSortOrder = computeDisplayOrder(bankSortEntries);
    _bankSortIndex = buildDisplayOrderIndex(bankSortOrder);

    // Step 2: Parse each skill into specialized registries
    _woodcutting = parseWoodcutting(skillDataById['melvorD:Woodcutting']);
    _mining = parseMining(skillDataById['melvorD:Mining']);
    _firemaking = parseFiremaking(skillDataById['melvorD:Firemaking']);
    _cooking = parseCooking(skillDataById['melvorD:Cooking']);
    _fishing = parseFishing(skillDataById['melvorD:Fishing']);
    _smithing = parseSmithing(skillDataById['melvorD:Smithing']);
    _farming = parseFarming(skillDataById['melvorD:Farming']);
    _fletching = parseFletching(skillDataById['melvorD:Fletching']);
    _crafting = parseCrafting(skillDataById['melvorD:Crafting']);
    _herblore = parseHerblore(skillDataById['melvorD:Herblore']);
    _runecrafting = parseRunecrafting(skillDataById['melvorD:Runecrafting']);
    _thieving = parseThieving(skillDataById['melvorD:Thieving']);
    _agility = parseAgility(skillDataById['melvorD:Agility']);
    _summoning = parseSummoning(skillDataById['melvorD:Summoning']);
    _astrology = parseAstrology(skillDataById['melvorD:Astrology']);
    _altMagic = parseAltMagic(skillDataById['melvorD:Magic']);

    // Parse combat (monsters, areas, dungeons)
    final monsters = <CombatAction>[];
    for (final json in dataFiles) {
      final namespace = json['namespace'] as String;
      monsters.addAll(parseCombatActions(json, namespace: namespace));
    }
    _combatAreas = CombatAreaRegistry(combatAreas);
    _dungeons = DungeonRegistry(dungeons);
    _combat = CombatRegistry(
      monsters: monsters,
      areas: _combatAreas,
      dungeons: _dungeons,
    );

    // Parse summoning synergies
    _summoningSynergies = parseSummoningSynergies(
      skillDataById['melvorD:Summoning'],
    );

    // Parse shop data (pass cooking categories for upgrade chain building)
    _shop = parseShop(dataFiles, cookingCategories: _cooking.categories);

    // Parse mastery bonuses for all skills
    _masteryBonuses = parseMasteryBonuses(skillDataById);

    // Parse mastery unlocks (display-only descriptions) for all skills
    _masteryUnlocks = parseMasteryUnlocks(skillDataById);

    // Parse mastery pool bonuses (checkpoints) for all skills
    _masteryPoolBonuses = parseAllMasteryPoolBonuses(skillDataById);

    // Parse township data
    _township = parseTownship(skillDataById['melvorD:Township']);

    // Parse skill drops from all sources
    _drops = buildDropsRegistry(skillDataById, dataFiles);
  }

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

  late final ItemRegistry _items;
  late final EquipmentSlotRegistry _equipmentSlots;
  late final Map<MelvorId, int> _bankSortIndex;

  // Specialized skill registries (primary storage)
  late final WoodcuttingRegistry _woodcutting;
  late final MiningRegistry _mining;
  late final FiremakingRegistry _firemaking;
  late final CookingRegistry _cooking;
  late final FishingRegistry _fishing;
  late final SmithingRegistry _smithing;
  late final FarmingRegistry _farming;
  late final FletchingRegistry _fletching;
  late final CraftingRegistry _crafting;
  late final HerbloreRegistry _herblore;
  late final RunecraftingRegistry _runecrafting;
  late final ThievingRegistry _thieving;
  late final AgilityRegistry _agility;
  late final SummoningRegistry _summoning;
  late final AstrologyRegistry _astrology;
  late final AltMagicRegistry _altMagic;
  late final CombatRegistry _combat;

  // Other registries
  late final CombatAreaRegistry _combatAreas;
  late final DungeonRegistry _dungeons;
  late final ShopRegistry _shop;
  late final MasteryBonusRegistry _masteryBonuses;
  late final MasteryUnlockRegistry _masteryUnlocks;
  late final MasteryPoolBonusRegistry _masteryPoolBonuses;
  late final SummoningSynergyRegistry _summoningSynergies;
  late final TownshipRegistry _township;
  late final DropsRegistry _drops;

  /// Creates a Registries instance from this MelvorData.
  Registries toRegistries() {
    return Registries(
      items: _items,
      drops: _drops,
      equipmentSlots: _equipmentSlots,
      woodcutting: _woodcutting,
      mining: _mining,
      firemaking: _firemaking,
      fishing: _fishing,
      cooking: _cooking,
      smithing: _smithing,
      fletching: _fletching,
      crafting: _crafting,
      herblore: _herblore,
      runecrafting: _runecrafting,
      thieving: _thieving,
      agility: _agility,
      farming: _farming,
      summoning: _summoning,
      astrology: _astrology,
      altMagic: _altMagic,
      combat: _combat,
      shop: _shop,
      masteryBonuses: _masteryBonuses,
      masteryUnlocks: _masteryUnlocks,
      masteryPoolBonuses: _masteryPoolBonuses,
      summoningSynergies: _summoningSynergies,
      township: _township,
      bankSortIndex: _bankSortIndex,
    );
  }
}

/// Parses all woodcutting data. Returns WoodcuttingRegistry.
WoodcuttingRegistry parseWoodcutting(List<SkillDataEntry>? entries) {
  if (entries == null) return const WoodcuttingRegistry([]);

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
  return WoodcuttingRegistry(actions).withCache();
}

/// Parses all mining data. Returns MiningRegistry.
MiningRegistry parseMining(List<SkillDataEntry>? entries) {
  if (entries == null) return const MiningRegistry([]);

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
  return MiningRegistry(actions).withCache();
}

/// Parses all fishing data. Returns FishingRegistry.
FishingRegistry parseFishing(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return FishingRegistry(actions: const [], areas: const []);
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

  return FishingRegistry(actions: actions, areas: areas);
}

/// Parses all cooking data. Returns CookingRegistry.
CookingRegistry parseCooking(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return CookingRegistry(actions: const [], categories: const []);
  }

  final actions = <CookingAction>[];
  final categories = <CookingCategory>[];

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

    final cats = entry.data['categories'] as List<dynamic>?;
    if (cats != null) {
      categories.addAll(
        cats.map(
          (json) => CookingCategory.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }
  return CookingRegistry(actions: actions, categories: categories);
}

/// Parses all firemaking data. Returns FiremakingRegistry.
FiremakingRegistry parseFiremaking(List<SkillDataEntry>? entries) {
  if (entries == null) return const FiremakingRegistry([]);

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
  return FiremakingRegistry(actions).withCache();
}

/// Parses all smithing data. Returns SmithingRegistry.
SmithingRegistry parseSmithing(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return SmithingRegistry(actions: const [], categories: const []);
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

  return SmithingRegistry(actions: actions, categories: categories);
}

/// Parses all farming data. Returns FarmingRegistry.
FarmingRegistry parseFarming(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return FarmingRegistry(
      crops: const [],
      categories: const [],
      plots: const [],
    );
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

  return FarmingRegistry(crops: crops, categories: categories, plots: plots);
}

/// Parses all fletching data. Returns FletchingRegistry.
FletchingRegistry parseFletching(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return FletchingRegistry(actions: const [], categories: const []);
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

  return FletchingRegistry(actions: actions, categories: categories);
}

/// Parses all crafting data. Returns CraftingRegistry.
CraftingRegistry parseCrafting(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return CraftingRegistry(actions: const [], categories: const []);
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

  return CraftingRegistry(actions: actions, categories: categories);
}

/// Parses all herblore data. Returns HerbloreRegistry.
HerbloreRegistry parseHerblore(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return HerbloreRegistry(actions: const [], categories: const []);
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

  return HerbloreRegistry(actions: actions, categories: categories);
}

/// Parses all runecrafting data. Returns RunecraftingRegistry.
RunecraftingRegistry parseRunecrafting(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return RunecraftingRegistry(actions: const [], categories: const []);
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

  return RunecraftingRegistry(actions: actions, categories: categories);
}

/// Parses all thieving data. Returns ThievingRegistry.
ThievingRegistry parseThieving(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return ThievingRegistry(actions: const [], areas: const []);
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

  // Helper to find area for NPC
  ThievingArea areaForNpc(MelvorId npcId) {
    for (final area in areas) {
      if (area.npcIds.contains(npcId)) {
        return area;
      }
    }
    throw StateError('Thieving NPC $npcId has no area');
  }

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
            area: areaForNpc(npcId),
          );
        }),
      );
    }
  }

  return ThievingRegistry(actions: actions, areas: areas);
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

List<Dungeon> parseDungeons(
  Map<String, dynamic> json, {
  required String namespace,
}) {
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) {
    return [];
  }

  final dungeons = data['dungeons'] as List<dynamic>? ?? [];
  return dungeons
      .map((dungeonJson) => dungeonJson as Map<String, dynamic>)
      .map((dungeonJson) => Dungeon.fromJson(dungeonJson, namespace: namespace))
      .toList();
}

/// Parses all shop data from multiple data files.
ShopRegistry parseShop(
  List<Map<String, dynamic>> dataFiles, {
  List<CookingCategory>? cookingCategories,
}) {
  final purchases = <ShopPurchase>[];
  final categories = <ShopCategory>[];

  for (final json in dataFiles) {
    final namespace = json['namespace'] as String;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) continue;

    // Parse shop purchases
    final purchasesJson = data['shopPurchases'] as List<dynamic>? ?? [];
    for (final purchaseJson in purchasesJson) {
      purchases.add(
        ShopPurchase.fromJson(
          purchaseJson as Map<String, dynamic>,
          namespace: namespace,
        ),
      );
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

  return ShopRegistry(
    purchases,
    categories,
    cookingCategories: cookingCategories,
  );
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

/// Parses mastery pool bonuses (checkpoints) for all skills.
MasteryPoolBonusRegistry parseAllMasteryPoolBonuses(
  Map<String, List<SkillDataEntry>> skillDataById,
) {
  final skillBonuses = <SkillMasteryPoolBonuses>[];

  for (final entry in skillDataById.entries) {
    final skillId = MelvorId.fromJson(entry.key);
    final bonuses = <MasteryPoolBonus>[];

    // Collect bonuses from all data entries for this skill
    for (final dataEntry in entry.value) {
      bonuses.addAll(
        parseMasteryPoolBonuses(dataEntry.data, namespace: dataEntry.namespace),
      );
    }

    if (bonuses.isNotEmpty) {
      // Sort by percent ascending
      bonuses.sort((a, b) => a.percent.compareTo(b.percent));
      skillBonuses.add(
        SkillMasteryPoolBonuses(skillId: skillId, bonuses: bonuses),
      );
    }
  }

  return MasteryPoolBonusRegistry(skillBonuses);
}

/// Parses all agility data. Returns AgilityRegistry.
AgilityRegistry parseAgility(List<SkillDataEntry>? entries) {
  if (entries == null) {
    return AgilityRegistry(
      obstacles: const [],
      courses: const [],
      pillars: const [],
    );
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

  return AgilityRegistry(
    obstacles: obstacles,
    courses: courses,
    pillars: pillars,
  );
}

/// Parses all summoning data. Returns SummoningRegistry.
SummoningRegistry parseSummoning(List<SkillDataEntry>? entries) {
  if (entries == null) return SummoningRegistry(const []);

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
  return SummoningRegistry(actions);
}

/// Parses all astrology data. Returns AstrologyRegistry.
AstrologyRegistry parseAstrology(List<SkillDataEntry>? entries) {
  if (entries == null) return const AstrologyRegistry([]);

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
  return AstrologyRegistry(actions).withCache();
}

/// Parses all alt magic data. Returns AltMagicRegistry.
AltMagicRegistry parseAltMagic(List<SkillDataEntry>? entries) {
  if (entries == null) return const AltMagicRegistry([]);

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
  return AltMagicRegistry(actions).withCache();
}

/// Parses all township data. Returns TownshipRegistry.
TownshipRegistry parseTownship(List<SkillDataEntry>? entries) {
  if (entries == null) return const TownshipRegistry.empty();

  final buildings = <TownshipBuilding>[];
  final biomes = <TownshipBiome>[];
  final resources = <TownshipResource>[];
  final deities = <TownshipDeity>[];
  final trades = <TownshipTrade>[];
  final seasons = <TownshipSeason>[];
  final tasks = <TownshipTask>[];
  final buildingDisplayOrderEntries = <DisplayOrderEntry>[];

  for (final entry in entries) {
    // Parse buildings
    final buildingsJson = entry.data['buildings'] as List<dynamic>?;
    if (buildingsJson != null) {
      buildings.addAll(
        buildingsJson.map(
          (json) => TownshipBuilding.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse building display order
    final displayOrderJson =
        entry.data['buildingDisplayOrder'] as List<dynamic>?;
    if (displayOrderJson != null) {
      buildingDisplayOrderEntries.addAll(
        displayOrderJson.map(
          (json) => DisplayOrderEntry.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse biomes
    final biomesJson = entry.data['biomes'] as List<dynamic>?;
    if (biomesJson != null) {
      biomes.addAll(
        biomesJson.map(
          (json) => TownshipBiome.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse resources
    final resourcesJson = entry.data['resources'] as List<dynamic>?;
    if (resourcesJson != null) {
      resources.addAll(
        resourcesJson.map(
          (json) => TownshipResource.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse deities (worships)
    final worshipsJson = entry.data['worships'] as List<dynamic>?;
    if (worshipsJson != null) {
      deities.addAll(
        worshipsJson.map(
          (json) => TownshipDeity.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse seasons
    final seasonsJson = entry.data['seasons'] as List<dynamic>?;
    if (seasonsJson != null) {
      seasons.addAll(
        seasonsJson.map(
          (json) => TownshipSeason.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }

    // Parse trades (itemConversions.fromTownship)
    final itemConversions =
        entry.data['itemConversions'] as Map<String, dynamic>?;
    if (itemConversions != null) {
      final fromTownship = itemConversions['fromTownship'] as List<dynamic>?;
      if (fromTownship != null) {
        for (final conversion in fromTownship) {
          final conversionMap = conversion as Map<String, dynamic>;
          final resourceId = MelvorId.fromJsonWithNamespace(
            conversionMap['resourceID'] as String,
            defaultNamespace: entry.namespace,
          );
          final items = conversionMap['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final itemMap = item as Map<String, dynamic>;
            final itemId = MelvorId.fromJsonWithNamespace(
              itemMap['itemID'] as String,
              defaultNamespace: entry.namespace,
            );
            // Use item ID as trade ID since trades don't have explicit IDs
            trades.add(
              TownshipTrade(id: itemId, resourceId: resourceId, itemId: itemId),
            );
          }
        }
      }
    }

    // Parse tasks
    final tasksJson = entry.data['tasks'] as List<dynamic>?;
    if (tasksJson != null) {
      tasks.addAll(
        tasksJson.map(
          (json) => TownshipTask.fromJson(
            json as Map<String, dynamic>,
            namespace: entry.namespace,
          ),
        ),
      );
    }
  }

  // Compute building display order
  final buildingDisplayOrder = computeDisplayOrder(buildingDisplayOrderEntries);
  final buildingSortIndex = buildDisplayOrderIndex(buildingDisplayOrder);

  return TownshipRegistry(
    buildings: buildings,
    biomes: biomes,
    resources: resources,
    deities: deities,
    trades: trades,
    seasons: seasons,
    tasks: tasks,
    buildingSortIndex: buildingSortIndex,
  );
}

/// Parses the global randomGems drop table from data files.
/// Returns a DropTable if found, or null if not present.
DropTable? parseRandomGems(List<Map<String, dynamic>> dataFiles) {
  for (final json in dataFiles) {
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) continue;

    final randomGems = data['randomGems'] as List<dynamic>?;
    if (randomGems == null || randomGems.isEmpty) continue;

    final entries = randomGems
        .map((gem) => DropTableEntry.fromJson(gem as Map<String, dynamic>))
        .toList();
    return DropTable(entries);
  }
  return null;
}

/// Parses all skill-level drops from multiple JSON sources.
/// Returns a map from Skill to list of Droppable items.
Map<Skill, List<Droppable>> parseSkillDrops(
  Map<String, List<SkillDataEntry>> skillDataById,
) {
  final result = <Skill, List<Droppable>>{};

  for (final entry in skillDataById.entries) {
    final skillIdString = entry.key;
    final dataEntries = entry.value;

    // Determine the Skill enum from the skill ID
    final skillId = MelvorId.fromJson(skillIdString);
    final skill = Skill.values.where((e) => e.id == skillId).firstOrNull;
    if (skill == null) {
      // Skip unknown skills (e.g., combat sub-skills without actions)
      continue;
    }

    final drops = <Droppable>[];

    for (final dataEntry in dataEntries) {
      final namespace = dataEntry.namespace;
      final data = dataEntry.data;

      // Parse randomProducts (e.g., Woodcutting's Bird Nest)
      // Chance is in %, e.g., 0.5 means 0.5% = 0.005
      final randomProducts = data['randomProducts'] as List<dynamic>?;
      if (randomProducts != null) {
        for (final product in randomProducts) {
          final productMap = product as Map<String, dynamic>;
          final itemId = MelvorId.fromJsonWithNamespace(
            productMap['itemID'] as String,
            defaultNamespace: namespace,
          );
          final chancePercent = (productMap['chance'] as num).toDouble();
          final quantity = productMap['quantity'] as int? ?? 1;
          drops.add(Drop(itemId, rate: chancePercent / 100, count: quantity));
        }
      }

      // Parse primaryProducts (e.g., Firemaking's Coal/Ash)
      // Chance is in %, e.g., 40 means 40% = 0.40
      final primaryProducts = data['primaryProducts'] as List<dynamic>?;
      if (primaryProducts != null) {
        for (final product in primaryProducts) {
          // Can be either a simple string ID or an object with chance
          if (product is String) {
            // Simple string means 100% chance (e.g., per-log overrides)
            continue; // Skip these, they're per-action not per-skill
          }
          final productMap = product as Map<String, dynamic>;
          final itemId = MelvorId.fromJsonWithNamespace(
            productMap['itemID'] as String,
            defaultNamespace: namespace,
          );
          final chancePercent = (productMap['chance'] as num).toDouble();
          final quantity = productMap['quantity'] as int? ?? 1;
          drops.add(Drop(itemId, rate: chancePercent / 100, count: quantity));
        }
      }

      // Parse generalRareItems (e.g., Thieving's Bobby's Pocket)
      // Chance is already in 0-1 range (approximately), but represents %
      // e.g., 0.833... means ~0.833% = 0.00833
      final generalRareItems = data['generalRareItems'] as List<dynamic>?;
      if (generalRareItems != null) {
        for (final item in generalRareItems) {
          final itemMap = item as Map<String, dynamic>;
          final itemId = MelvorId.fromJsonWithNamespace(
            itemMap['itemID'] as String,
            defaultNamespace: namespace,
          );
          // Chance is percentage, divide by 100
          final chancePercent = (itemMap['chance'] as num).toDouble();
          drops.add(Drop(itemId, rate: chancePercent / 100));
        }
      }

      // Parse rareDrops (e.g., Gold Topaz Ring, Circlet of Rhaelyx)
      // These have complex chance calculations based on level or mastery.
      final rareDropsJson = data['rareDrops'] as List<dynamic>?;
      if (rareDropsJson != null) {
        for (final rareDrop in rareDropsJson) {
          final rareDropMap = rareDrop as Map<String, dynamic>;
          final itemId = MelvorId.fromJsonWithNamespace(
            rareDropMap['itemID'] as String,
            defaultNamespace: namespace,
          );
          final quantity = rareDropMap['quantity'] as int? ?? 1;

          // Parse chance object
          final chanceJson = rareDropMap['chance'] as Map<String, dynamic>;
          final chanceType = chanceJson['type'] as String;

          // Parse requirements (optional)
          MelvorId? requiredItemId;
          final requirements = rareDropMap['requirements'] as List<dynamic>?;
          if (requirements != null && requirements.isNotEmpty) {
            for (final req in requirements) {
              final reqMap = req as Map<String, dynamic>;
              if (reqMap['type'] == 'ItemFound') {
                requiredItemId = MelvorId.fromJsonWithNamespace(
                  reqMap['itemID'] as String,
                  defaultNamespace: namespace,
                );
                break;
              }
            }
          }

          // Create DropChanceCalculator based on chance type
          // Note: Melvor stores these chances as percentages (0.001 = 0.1%),
          // so divide by 100 to get actual probabilities.
          double chance(String key) =>
              (chanceJson[key] as num).toDouble() / 100;
          final calculator = switch (chanceType) {
            'Fixed' => FixedChance(chance('chance')),
            'LevelScaling' => LevelScalingChance(
              baseChance: chance('baseChance'),
              maxChance: chance('maxChance'),
              scalingFactor: chance('scalingFactor'),
            ),
            'TotalMasteryScaling' => MasteryScalingChance(
              baseChance: chance('baseChance'),
              maxChance: chance('maxChance'),
              scalingFactor: chance('scalingFactor'),
            ),
            _ => throw ArgumentError('Unknown chance type: $chanceType'),
          };

          drops.add(
            RareDrop(
              itemId: itemId,
              chance: calculator,
              count: quantity,
              requiredItemId: requiredItemId,
            ),
          );
        }
      }
    }

    if (drops.isNotEmpty) {
      result[skill] = drops;
    }
  }

  // Note: Mining gems are NOT added here as a skill-level drop.
  // They are handled separately in DropsRegistry and only applied to
  // rocks with giveGems: true (ores give gems, essence does not).

  return result;
}

/// Builds a DropsRegistry from parsed skill drops data.
DropsRegistry buildDropsRegistry(
  Map<String, List<SkillDataEntry>> skillDataById,
  List<Map<String, dynamic>> dataFiles,
) {
  final randomGems = parseRandomGems(dataFiles);
  if (randomGems == null) {
    throw StateError('randomGems data missing from game data');
  }
  final skillDrops = parseSkillDrops(skillDataById);

  // Mining gems: 1% chance to roll the gem table, only for rocks with
  // giveGems: true (ores give gems, essence does not).
  final miningGems = DropChance(randomGems, rate: 0.01);

  return DropsRegistry(skillDrops, miningGems: miningGems);
}
