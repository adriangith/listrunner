import type { ParsedList, ParseOptions, ParsedItem } from "./types.js";
import { splitItems } from "./split.js";
import { extractQuantities } from "./quantity.js";
import { cleanProductName } from "./product-name.js";
import { applyPantryFilter } from "./pantry-filter.js";

/**
 * Parses raw shopping list text into structured items ready for the wizard.
 *
 * Pipeline: split → extract quantities → clean product names → pantry filter
 */
export function parseList(
  input: string,
  options: ParseOptions = {},
): ParsedList {
  const rawItems = splitItems(input);
  const withQuantities = extractQuantities(rawItems);

  const parsedItems: ParsedItem[] = withQuantities.map((item) => ({
    original: item.original,
    quantity: item.quantity,
    searchTerm: cleanProductName(item),
    filtered: false,
  }));

  const { keep, filtered } = applyPantryFilter(
    parsedItems,
    options.pantryExclusions ?? [],
  );

  return { items: keep, filtered };
}
