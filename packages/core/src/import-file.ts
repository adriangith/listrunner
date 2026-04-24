/**
 * Normalizes text imported from a file into a newline-separated list suitable
 * for parseList. CSV files have their first non-empty cell per row extracted.
 */
export function normalizeImportedText(raw: string, filename: string): string {
  const isCSV = /\.csv$/i.test(filename);
  if (!isCSV) return raw;

  const lines = raw.replace(/\r\n?/g, "\n").split("\n");
  return lines
    .map((line) => {
      if (!line.trim()) return "";
      const cells = splitCSVLine(line);
      const first = cells.find((c) => c.trim().length > 0);
      return first?.trim() ?? "";
    })
    .filter((l) => l.length > 0)
    .join("\n");
}

/**
 * Minimal CSV line splitter. Handles double-quoted cells and escaped quotes.
 * Doesn't attempt multi-line cells; files with embedded newlines inside quotes
 * should go through a full CSV library, not this helper.
 */
export function splitCSVLine(line: string): string[] {
  const out: string[] = [];
  let buf = "";
  let inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuote) {
      if (ch === '"' && line[i + 1] === '"') {
        buf += '"';
        i++;
      } else if (ch === '"') {
        inQuote = false;
      } else {
        buf += ch;
      }
    } else {
      if (ch === ",") {
        out.push(buf);
        buf = "";
      } else if (ch === '"' && buf.length === 0) {
        inQuote = true;
      } else {
        buf += ch;
      }
    }
  }
  out.push(buf);
  return out;
}
