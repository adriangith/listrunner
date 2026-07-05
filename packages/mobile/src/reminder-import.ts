import { parseList, splitItems, type ParsedList, type ParsedItem } from "@listrunner/core";

export type ReminderItem = {
  id: string;
  title: string;
};

export function importReminders(
  reminders: ReminderItem[],
  pantryExclusions: string[],
): { parsedList: ParsedList; reminderIdByOriginal: Map<string, string> } {
  const rawText = reminders.map((r) => r.title).join("\n");
  const parsedList = parseList(rawText, { pantryExclusions });

  const cleanedToId = new Map<string, string>();
  for (const r of reminders) {
    const cleaned = splitItems(r.title)[0]?.original ?? r.title;
    cleanedToId.set(cleaned, r.id);
  }

  const reminderIdByOriginal = new Map<string, string>();
  for (const item of [...parsedList.items, ...parsedList.filtered]) {
    const id = cleanedToId.get(item.original);
    if (id) {
      reminderIdByOriginal.set(item.original, id);
    }
  }

  return { parsedList, reminderIdByOriginal };
}

export function getReminderIdForItem(
  parsedItem: ParsedItem,
  reminderIdByOriginal: Map<string, string>,
): string | undefined {
  return reminderIdByOriginal.get(parsedItem.original);
}

export async function tryCompleteReminder(
  item: ParsedItem,
  reminderIdByOriginal: Map<string, string>,
  completeFn: (opts: { id: string }) => Promise<void>,
): Promise<boolean | null> {
  const id = getReminderIdForItem(item, reminderIdByOriginal);
  if (!id) return null;
  try {
    await completeFn({ id });
    return true;
  } catch {
    return false;
  }
}