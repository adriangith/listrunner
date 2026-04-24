import type { Quantity, ItemWithQuantity, RawItem } from "./types.js";

/** Unicode vulgar fractions and their decimal values. */
const UNICODE_FRACTIONS: Record<string, number> = {
  "¼": 0.25,
  "½": 0.5,
  "¾": 0.75,
  "⅐": 1 / 7,
  "⅑": 1 / 9,
  "⅒": 0.1,
  "⅓": 1 / 3,
  "⅔": 2 / 3,
  "⅕": 0.2,
  "⅖": 0.4,
  "⅗": 0.6,
  "⅘": 0.8,
  "⅙": 1 / 6,
  "⅚": 5 / 6,
  "⅛": 0.125,
  "⅜": 0.375,
  "⅝": 0.625,
  "⅞": 0.875,
};

const UNITS =
  "g|kg|mg|ml|l|oz|lb|lbs|cups?|tbsp|tbsps|tsp|tsps|dozen|litres?|liters?|bunch|bunches|head|heads|cloves?|stalks?|sprigs?|slices?|pieces?|cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|punnets?|pots?|tubs?|trays?|loaves|loaf";

const CONTAINER_UNITS =
  "cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|bunches?|heads?|punnets?|pots?|tubs?|trays?";

/**
 * Normalizes leading quantity phrasing:
 *   - Strips a leading "a " / "an " before units or counts ("a dozen eggs" → "1 dozen eggs").
 *   - Replaces unicode vulgar fractions with ASCII fractions ("½ cup" → "1/2 cup").
 *   - Replaces ASCII fractions / mixed numbers ("1 1/2 kg", "1/2 cup") with decimals.
 *   - Reduces ranges ("2-3 eggs") to their lower bound.
 */
function normalizeLeading(text: string): string {
  let t = text;

  // Leading "a " or "an " → "1 " when followed by a unit or common count word.
  t = t.replace(
    /^(a|an)\s+(?=(?:dozen|bunch|can|tin|packet|pack|bag|bottle|box|jar|carton|head|clove|stalk|sprig|slice|piece|loaf|punnet|pot|tub|tray|few|couple)\b)/i,
    "1 ",
  );

  // Unicode fractions — handle both "1½" (mixed) and standalone "½".
  t = t.replace(/(\d+)\s*([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])/g, (_, whole, frac) => {
    const value = parseInt(whole, 10) + UNICODE_FRACTIONS[frac]!;
    return formatAmount(value);
  });
  t = t.replace(/([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])/g, (_, frac: string) =>
    formatAmount(UNICODE_FRACTIONS[frac]!),
  );

  // Mixed numbers: "1 1/2" → "1.5"
  t = t.replace(/(\d+)\s+(\d+)\/(\d+)/g, (_, whole, num, den) => {
    const d = parseInt(den, 10);
    if (d === 0) return `${whole}`;
    return formatAmount(parseInt(whole, 10) + parseInt(num, 10) / d);
  });

  // Simple fractions: "1/2" → "0.5"
  t = t.replace(/(\d+)\/(\d+)/g, (_, num, den) => {
    const d = parseInt(den, 10);
    if (d === 0) return num;
    return formatAmount(parseInt(num, 10) / d);
  });

  // Ranges: "2-3 eggs", "2–3 eggs", "2 to 3 eggs" → use the lower bound.
  t = t.replace(/^(\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*\d+(?:\.\d+)?/i, "$1");

  return t;
}

function formatAmount(n: number): string {
  // Use a modest precision to avoid noise like 0.6666666666
  const rounded = Math.round(n * 1000) / 1000;
  return String(rounded);
}

/**
 * Extracts quantity information from a raw item string.
 * Handles patterns like "2x chicken", "500g flour", "1 can tomatoes", "3 large eggs".
 */
export function extractQuantity(item: RawItem): ItemWithQuantity {
  const normalized = normalizeLeading(item.original);
  const text = normalized;

  // Pattern: "N unit (Xg)" — e.g., "1 can (400g) tomatoes"
  const containerMatch = text.match(
    new RegExp(
      String.raw`^(\d+\.?\d*)\s*(${CONTAINER_UNITS})\s*(?:\((\d+\.?\d*)\s*(g|kg|ml|l|oz|lb)\))\s+(.+)`,
      "i",
    ),
  );
  if (containerMatch) {
    return {
      original: item.original,
      quantity: {
        amount: parseFloat(containerMatch[1]!),
        unit: containerMatch[2]!.toLowerCase(),
      },
      remaining: containerMatch[5]!.trim(),
    };
  }

  // Pattern: "Nx item" — e.g., "2x chicken breast"
  const multiplierMatch = text.match(/^(\d+\.?\d*)\s*x\s+(.+)/i);
  if (multiplierMatch) {
    return {
      original: item.original,
      quantity: { amount: parseFloat(multiplierMatch[1]!), unit: null },
      remaining: multiplierMatch[2]!.trim(),
    };
  }

  // Pattern: "N unit item" — e.g., "500g flour", "2 kg rice", "1 dozen eggs"
  const unitMatch = text.match(
    new RegExp(String.raw`^(\d+\.?\d*)\s*(${UNITS})\s+(.+)`, "i"),
  );
  if (unitMatch) {
    return {
      original: item.original,
      quantity: {
        amount: parseFloat(unitMatch[1]!),
        unit: unitMatch[2]!.toLowerCase(),
      },
      remaining: unitMatch[3]!.trim(),
    };
  }

  // Pattern: "N item" — e.g., "3 eggs", "1 lemon"
  const countMatch = text.match(/^(\d+\.?\d*)\s+(.+)/);
  if (countMatch) {
    return {
      original: item.original,
      quantity: { amount: parseFloat(countMatch[1]!), unit: null },
      remaining: countMatch[2]!.trim(),
    };
  }

  // No quantity found
  return {
    original: item.original,
    quantity: null,
    remaining: item.original,
  };
}

/**
 * Process an array of raw items to extract quantities.
 */
export function extractQuantities(items: RawItem[]): ItemWithQuantity[] {
  return items.map(extractQuantity);
}
