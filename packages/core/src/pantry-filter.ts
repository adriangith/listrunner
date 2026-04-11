import type { ParsedItem } from "./types.js";

/**
 * Filters parsed items against a pantry exclusion list.
 * Returns items split into keep and filtered arrays.
 * Matching is case-insensitive substring: if the exclusion term appears
 * anywhere in the search term, the item is filtered.
 */
export function applyPantryFilter(
  items: ParsedItem[],
  exclusions: string[],
): { keep: ParsedItem[]; filtered: ParsedItem[] } {
  if (exclusions.length === 0) {
    return { keep: items, filtered: [] };
  }

  const normalizedExclusions = exclusions.map((e) => e.toLowerCase().trim());
  const keep: ParsedItem[] = [];
  const filtered: ParsedItem[] = [];

  for (const item of items) {
    const term = item.searchTerm.toLowerCase();
    const isExcluded = normalizedExclusions.some(
      (excl) => term === excl || term.includes(excl),
    );

    if (isExcluded) {
      filtered.push({ ...item, filtered: true });
    } else {
      keep.push(item);
    }
  }

  return { keep, filtered };
}
