# Melvor Data Merge Analysis

This document describes how `melvorDemo.json` and `melvorFull.json` are merged in `MelvorData`.

## Namespaces

- **Demo**: `melvorD` (base game)
- **Full**: `melvorF` (expansion content)

## Skills Distribution

| Category | Skills |
|----------|--------|
| **Both files** | Woodcutting, Fishing, Firemaking, Cooking, Mining, Smithing, Farming, Summoning, Magic |
| **Demo only** | Attack, Strength, Defence, Hitpoints (combat skills) |
| **Full only** | Thieving, Fletching, Crafting, Runecrafting, Herblore, Agility, Astrology, Township, Ranged, Prayer, Slayer |

## Merge Behavior

The `_mergeSkillData` function in `melvor_data.dart` handles merging skill data when a skill exists in both files:

### 1. List Values -> Appended

Items from Full are added after Demo's list items:

| Skill | Key | Demo | Full | Merged Total |
|-------|-----|------|------|--------------|
| Cooking | recipes | 30 | 2 | 32 |
| Farming | recipes | 20 | 4 | 24 |
| Magic | spellCategories | 10 | 1 | 11 |
| Firemaking | primaryProducts | 1 | 2 | 3 |

### 2. Non-List Values -> Overridden

Full's value completely replaces Demo's value. The `minibar` config is consistently overridden - Full adds Max_Skillcape, Cape_of_Completion, and other expansion items.

### 3. New Keys -> Added

Keys that only exist in Full get added to the merged result:

- Woodcutting: `bannedJewleryIDs`
- Magic: `altSpells`, `customMilestones`, `randomShards`

## Core Game Data Location

Most core game data is in Demo with no additions from Full:

| Skill | Data Type | Demo Count | Full Count |
|-------|-----------|------------|------------|
| Woodcutting | trees | 9 | 0 |
| Mining | rockData | 11 | 0 |
| Fishing | fish | 23 | 0 |
| Fishing | areas | 8 | 0 |

## Special Cases

### Summoning

Demo only contains `categories`. All actual content (recipes, synergies, pets, mastery bonuses, etc.) comes from Full.

### Combat Skills

Attack, Strength, Defence, and Hitpoints only exist in Demo - they have no expansion content in Full.

## Code Reference

See `_mergeSkillData` in [melvor_data.dart](../lib/src/data/melvor_data.dart) for the merge implementation.
