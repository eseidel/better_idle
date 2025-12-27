# Bank Sort Order

This document describes the `bankSortOrder` data structure in Melvor's game data, which defines how items should be sorted in the bank.

## Data Location

- `melvorDemo.json`: `data.bankSortOrder` - 1 entry with 631 items
- `melvorFull.json`: `data.bankSortOrder` - 78 entries

## Entry Types

### `insertAt: "Start"`

Defines the base sort order. Only appears in `melvorDemo.json`.

```json
{
  "insertAt": "Start",
  "ids": ["melvorD:Normal_Logs", "melvorD:Oak_Logs", ...]
}
```

- **ids**: List of item IDs that form the initial sort order
- No `afterID` field
- The 631 demo items are listed in their intended sort order

### `insertAt: "After"`

Inserts items after a reference item. Only appears in `melvorFull.json`.

```json
{
  "insertAt": "After",
  "afterID": "melvorD:Redwood_Logs",
  "ids": ["melvorF:Ash"]
}
```

- **afterID**: The item ID to insert after
- **ids**: List of item IDs to insert (in order) immediately after `afterID`

## Processing Algorithm

1. Start with an empty result list
2. Process the "Start" entry - add all its `ids` to the result
3. Process each "After" entry in order:
   - Find the position of `afterID` in the current result
   - Insert all `ids` immediately after that position
   - If `afterID` is not found, append to the end (fallback)
4. Items not mentioned in `bankSortOrder` go at the end

### Example

Given:
- Start: `[..., Redwood_Logs, Generous_Fire_Spirit, ...]`
- After entry: `{afterID: "Redwood_Logs", ids: ["Ash"]}`

Result: `[..., Redwood_Logs, Ash, Generous_Fire_Spirit, ...]`

## Implementation Notes

### Performance

For sorting, use a precomputed `Map<MelvorId, int>` rather than `indexOf()`:
- Building the map: O(n) where n = number of items in sort order (~1300)
- Lookup during sort: O(1)
- Total sort: O(m log m) where m = items being sorted

Using `indexOf()` would be O(n) per comparison, making sort O(m * n * log m).

### Items Not in Sort Order

Items not in `bankSortOrder` should:
- Appear after all sorted items
- Maintain stable relative ordering (return 0 from comparator)

## Statistics

| File | Entries | Total Items |
|------|---------|-------------|
| melvorDemo | 1 | 631 |
| melvorFull | 78 | ~735 |
| **Combined** | 79 | ~1366 |

## Code Reference

Parsing should be added to [melvor_data.dart](../lib/src/data/melvor_data.dart).
