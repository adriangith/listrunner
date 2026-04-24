import type { ItemWithQuantity } from "./types.js";

/** Words that describe preparation and should be stripped from search terms. */
const PREP_WORDS = new Set([
  "sliced",
  "diced",
  "chopped",
  "minced",
  "grated",
  "shredded",
  "crushed",
  "ground",
  "peeled",
  "deseeded",
  "halved",
  "quartered",
  "cubed",
  "julienned",
  "torn",
  "trimmed",
  "cored",
  "seeded",
  "pitted",
  "deboned",
  "beaten",
  "whisked",
  "softened",
  "melted",
  "toasted",
  "roasted",
  "blanched",
  "soaked",
  "drained",
  "rinsed",
  "dried",
  "frozen",
  "thawed",
  "warmed",
  "chilled",
  "cooled",
]);

/** Phrases to strip entirely (matched as substrings, case-insensitive). */
const STRIP_PHRASES = [
  "finely chopped",
  "roughly chopped",
  "coarsely chopped",
  "finely diced",
  "finely sliced",
  "thinly sliced",
  "freshly ground",
  "freshly squeezed",
  "freshly grated",
  "to taste",
  "for garnish",
  "for serving",
  "as needed",
  "at room temperature",
  "room temperature",
  "lightly packed",
  "firmly packed",
  "plus extra for dusting",
  "plus extra",
  "or to taste",
  "if needed",
];

/** Leading article words we silently drop ("a onion" → "onion"). */
const LEADING_ARTICLES = new Set(["a", "an", "the", "some"]);

/**
 * Cleans a product name into a store-searchable term.
 * Strips preparation instructions, qualifiers, and container descriptions.
 */
export function cleanProductName(item: ItemWithQuantity): string {
  let text = item.remaining;

  // Remove parenthetical asides: "(about 200g)", "(optional)", "(400g)"
  text = text.replace(/\s*\([^)]*\)/g, "");

  // Strip known phrases first (multi-word, before single-word stripping)
  for (const phrase of STRIP_PHRASES) {
    text = text.replace(new RegExp(phrase, "gi"), "");
  }

  // Drop trailing "of ..." clauses only when the phrase starts with "juice",
  // "zest", "rind", "peel" etc — those are recipe-style modifiers.
  text = text.replace(
    /^(juice|zest|rind|peel|heart|hearts|leaves?)\s+of\s+.+$/i,
    "$1",
  );

  // Strip trailing "or X" alternates: "basil or parsley" → "basil"
  text = text.replace(/\s+or\s+[a-z]+$/i, "");

  // Drop leading article words.
  const tokens = text.trim().split(/\s+/);
  while (
    tokens.length > 1 &&
    LEADING_ARTICLES.has(tokens[0]!.toLowerCase())
  ) {
    tokens.shift();
  }
  text = tokens.join(" ");

  // Remove trailing comma-separated prep instructions: "mozzarella, sliced"
  // Only strip if the word after the last comma is a prep word
  const commaIdx = text.lastIndexOf(",");
  if (commaIdx !== -1) {
    const afterComma = text
      .slice(commaIdx + 1)
      .trim()
      .toLowerCase();
    const wordsAfter = afterComma.split(/\s+/);
    if (wordsAfter.length <= 3 && wordsAfter.every((w) => PREP_WORDS.has(w))) {
      text = text.slice(0, commaIdx);
    }
  }

  // Strip any remaining lone trailing prep word: "carrots diced" → "carrots"
  const tailTokens = text.trim().split(/\s+/);
  while (
    tailTokens.length > 1 &&
    PREP_WORDS.has(tailTokens[tailTokens.length - 1]!.toLowerCase())
  ) {
    tailTokens.pop();
  }
  text = tailTokens.join(" ");

  // Clean up whitespace and punctuation
  text = text.replace(/\s{2,}/g, " ").trim();
  text = text.replace(/^[,\s]+|[,\s]+$/g, "").trim();

  return text;
}
