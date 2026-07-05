import { registerPlugin } from '@capacitor/core';

export type ReminderItem = {
  id: string;
  title: string;
};

export interface RemindersPlugin {
  getPaprikaItems(): Promise<{ items: ReminderItem[] }>;
  completeReminder(options: { id: string }): Promise<void>;
}

const Reminders = registerPlugin<RemindersPlugin>('Reminders');
export default Reminders;
