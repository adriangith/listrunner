import type { SelectionRecord } from "./types.js";

/**
 * Append-only selection history log.
 * Records which products the user picks at each store,
 * enabling future "loupe hints" features.
 */
export class SelectionHistory {
  private records: SelectionRecord[];

  constructor(initial: SelectionRecord[] = []) {
    this.records = [...initial];
  }

  /** Record a product selection. */
  add(record: Omit<SelectionRecord, "timestamp">): SelectionRecord {
    const entry: SelectionRecord = { ...record, timestamp: Date.now() };
    this.records.push(entry);
    return entry;
  }

  /** Get all records, optionally filtered by store. */
  getAll(store?: string): SelectionRecord[] {
    if (store) {
      return this.records.filter((r) => r.store === store);
    }
    return [...this.records];
  }

  /** Find past selections for a given search term at a store. */
  lookup(store: string, searchTerm: string): SelectionRecord[] {
    const term = searchTerm.toLowerCase();
    return this.records
      .filter((r) => r.store === store && r.searchTerm.toLowerCase() === term)
      .sort((a, b) => b.timestamp - a.timestamp);
  }

  /** Get records added after a given timestamp (for incremental sync). */
  since(timestamp: number): SelectionRecord[] {
    return this.records.filter((r) => r.timestamp > timestamp);
  }

  /** Export for serialization/sync. */
  toJSON(): SelectionRecord[] {
    return [...this.records];
  }
}
