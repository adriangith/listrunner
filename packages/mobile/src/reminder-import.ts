import { parseList, splitItems, type ParsedList, type ParsedItem } from "@listrunner/core";

export type ReminderItem = {
  id: string;
  title: string;
};

export function importReminders(
  reminders: ReminderItem[],
  pantryExclusions: string[],
): { parsedList: ParsedList; reminderIdBySearchTerm: Map<string, string> } {
  const rawText = reminders.map((r) => r.title).join("\n");
  const parsedList = parseList(rawText, { pantryExclusions });

  const cleanedToId = new Map<string, string>();
  for (const r of reminders) {
    const cleaned = splitItems(r.title)[0]?.original ?? r.title;
    cleanedToId.set(cleaned, r.id);
  }

  const reminderIdBySearchTerm = new Map<string, string>();
  for (const item of [...parsedList.items, ...parsedList.filtered]) {
    const id = cleanedToId.get(item.original);
    if (id) {
      reminderIdBySearchTerm.set(item.searchTerm, id);
    }
  }

  return { parsedList, reminderIdBySearchTerm };
}

export function getReminderIdForItem(
  parsedItem: ParsedItem,
  reminderIdBySearchTerm: Map<string, string>,
): string | undefined {
  return reminderIdBySearchTerm.get(parsedItem.searchTerm);
}
