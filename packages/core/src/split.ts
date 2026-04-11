import type { RawItem } from "./types.js";

/**
 * Splits raw input text into individual item strings.
 * Handles newlines, numbered lists, bullet points, and comma-separated lists.
 */
export function splitItems(input: string): RawItem[] {
  if (!input.trim()) return [];

  // Normalize line endings
  const text = input.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  let lines: string[];

  // If there are newlines, split on them (handles bulleted/numbered lists)
  if (text.includes("\n")) {
    lines = text.split("\n");
  } else {
    // Single line — split on commas
    lines = text.split(",");
  }

  return lines
    .map((line) => stripListPrefix(line.trim()))
    .filter((line) => line.length > 0)
    .map((line) => ({ original: line }));
}

/** Strips common list prefixes: bullets, dashes, numbers, checkboxes. */
function stripListPrefix(line: string): string {
  return (
    line
      // Checkbox: "- [ ] item" or "- [x] item"
      .replace(/^[-*]\s*\[[ x]?\]\s*/i, "")
      // Numbered: "1. item", "1) item", "1 - item"
      .replace(/^\d+[.)]\s+/, "")
      .replace(/^\d+\s*[-–—]\s*/, "")
      // Bullet: "- item", "* item", "• item", "· item"
      .replace(/^[-*•·]\s+/, "")
      .trim()
  );
}
