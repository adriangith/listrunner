import type { Quantity, ItemWithQuantity, RawItem } from "./types.js";

/**
 * Extracts quantity information from a raw item string.
 * Handles patterns like "2x chicken", "500g flour", "1 can tomatoes", "3 large eggs".
 */
export function extractQuantity(item: RawItem): ItemWithQuantity {
  const text = item.original;

  // Try patterns in order of specificity

  // Pattern: "N unit (Xg)" — e.g., "1 can (400g) tomatoes"
  const containerMatch = text.match(
    /^(\d+\.?\d*)\s*(cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|bunche?s?|heads?)\s*(?:\((\d+\.?\d*)\s*(g|kg|ml|l|oz|lb)\))\s+(.+)/i,
  );
  if (containerMatch) {
    return {
      original: text,
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
      original: text,
      quantity: { amount: parseFloat(multiplierMatch[1]!), unit: null },
      remaining: multiplierMatch[2]!.trim(),
    };
  }

  // Pattern: "N unit item" — e.g., "500g flour", "2 kg rice", "1 dozen eggs"
  const unitMatch = text.match(
    /^(\d+\.?\d*)\s*(g|kg|ml|l|oz|lb|lbs|cups?|tbsp|tsp|dozen|litre|liter|litres|liters|bunch|head|cloves?|stalks?|sprigs?|slices?|pieces?|cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|bunche?s?|heads?)\s+(.+)/i,
  );
  if (unitMatch) {
    return {
      original: text,
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
      original: text,
      quantity: { amount: parseFloat(countMatch[1]!), unit: null },
      remaining: countMatch[2]!.trim(),
    };
  }

  // No quantity found
  return {
    original: text,
    quantity: null,
    remaining: text,
  };
}

/**
 * Process an array of raw items to extract quantities.
 */
export function extractQuantities(items: RawItem[]): ItemWithQuantity[] {
  return items.map(extractQuantity);
}
