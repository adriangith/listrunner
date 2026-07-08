import type { ParsedItem } from "@listrunner/core";

export function formatQuantity(item: ParsedItem): string {
  if (!item.quantity) return "";
  const { amount, unit } = item.quantity;
  return unit ? `${amount} ${unit}` : String(amount);
}

export function formatItemDisplayName(
  item: ParsedItem,
  searchTerm = item.searchTerm,
): string {
  return `${formatQuantity(item)} ${searchTerm}`.trim();
}
