import type { SelectionRecord } from "./types.js";

/** Cap on records retained per store — keeps storage footprint bounded. */
const DEFAULT_MAX_PER_STORE = 500;

/**
 * Append-only selection history log.
 * Records which products the user picks at each store,
 * enabling future "loupe hints" features.
 */
export class SelectionHistory {
  private records: SelectionRecord[];
  private readonly maxPerStore: number;
  /** Tracks the highest timestamp handed out so rapid calls remain monotonic. */
  private lastTimestamp = 0;

  constructor(
    initial: SelectionRecord[] = [],
    options: { maxPerStore?: number } = {},
  ) {
    this.records = [...initial];
    this.maxPerStore = options.maxPerStore ?? DEFAULT_MAX_PER_STORE;
    for (const r of this.records) {
      if (r.timestamp > this.lastTimestamp) this.lastTimestamp = r.timestamp;
    }
  }

  /** Record a product selection. */
  add(record: Omit<SelectionRecord, "timestamp">): SelectionRecord {
    const now = Date.now();
    const timestamp = now > this.lastTimestamp ? now : this.lastTimestamp + 1;
    this.lastTimestamp = timestamp;
    const entry: SelectionRecord = { ...record, timestamp };
    this.records.push(entry);
    this.pruneStore(entry.store);
    return entry;
  }

  /** Remove every record. */
  clear(): void {
    this.records = [];
  }

  /** Remove every record belonging to a specific store. */
  clearStore(store: string): number {
    const before = this.records.length;
    this.records = this.records.filter((r) => r.store !== store);
    return before - this.records.length;
  }

  /** Drop oldest records for a store when it exceeds the cap. */
  private pruneStore(store: string): void {
    const storeRecords = this.records.filter((r) => r.store === store);
    if (storeRecords.length <= this.maxPerStore) return;
    storeRecords.sort((a, b) => a.timestamp - b.timestamp);
    const toRemove = storeRecords.slice(0, storeRecords.length - this.maxPerStore);
    const removeSet = new Set(toRemove);
    this.records = this.records.filter((r) => !removeSet.has(r));
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
