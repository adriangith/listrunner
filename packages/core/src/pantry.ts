import type { PantryItem } from "./types.js";

/**
 * Manages a pantry exclusion list.
 * Items on this list are automatically filtered from shopping lists.
 * Designed for local-first with a sync-ready interface (last-write-wins).
 */
export class PantryList {
  private items: Map<string, PantryItem>;

  constructor(initial: PantryItem[] = []) {
    this.items = new Map(initial.map((i) => [this.normalize(i.name), i]));
  }

  /** Add an item to the exclusion list. */
  add(name: string): PantryItem {
    const key = this.normalize(name);
    const existing = this.items.get(key);
    if (existing) return existing;

    const item: PantryItem = { name: name.trim(), addedAt: Date.now() };
    this.items.set(key, item);
    return item;
  }

  /** Remove an item from the exclusion list. Returns true if it existed. */
  remove(name: string): boolean {
    return this.items.delete(this.normalize(name));
  }

  /** Check if an item is on the exclusion list. */
  has(name: string): boolean {
    return this.items.has(this.normalize(name));
  }

  /** Get all exclusion list items. */
  getAll(): PantryItem[] {
    return Array.from(this.items.values());
  }

  /** Get just the names, suitable for passing to parseList as pantryExclusions. */
  getNames(): string[] {
    return this.getAll().map((i) => i.name);
  }

  /** Merge remote items using last-write-wins semantics. */
  merge(remoteItems: PantryItem[]): void {
    for (const remote of remoteItems) {
      const key = this.normalize(remote.name);
      const local = this.items.get(key);
      if (!local || remote.addedAt > local.addedAt) {
        this.items.set(key, remote);
      }
    }
  }

  /** Export for serialization/sync. */
  toJSON(): PantryItem[] {
    return this.getAll();
  }

  private normalize(name: string): string {
    return name.toLowerCase().trim();
  }
}
