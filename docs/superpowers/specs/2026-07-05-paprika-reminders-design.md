# Paprika Reminders Import And Completion Design

## Goal

ListRunner should import grocery items from the iOS Reminders list named exactly `Paprika`, matching Paprika iOS's grocery-list export behavior. When the user marks an imported item as added in ListRunner, ListRunner should mark the corresponding iOS Reminder complete.

Manual paste-based list entry remains available and unchanged.

## Decisions

- The Reminders list name is fixed to `Paprika` for the first version.
- Import is explicit: the input screen gets a `Load from Paprika Reminders` button.
- Only incomplete reminders are imported.
- Tapping `Added` completes the exact source reminder.
- Tapping `Skip`, `Dismiss`, or `Exit Wizard` does not complete a reminder.
- Manual paste entry remains available and unchanged.

## User Flow

On the input screen, the user can either paste a list or tap `Load from Paprika Reminders`.

When the Reminders button is tapped:

1. iOS asks for Reminders permission if needed.
2. ListRunner looks for a Reminders list named exactly `Paprika`.
3. ListRunner reads incomplete reminders from that list.
4. ListRunner parses the reminder titles with the existing `parseList()` flow.
5. The user lands on the existing review screen.

During the wizard:

1. The active item may have a source reminder ID if it came from Reminders.
2. When the user taps `Added`, ListRunner completes that exact reminder in iOS Reminders.
3. If the item was manually entered or added during review, it has no reminder ID and no Reminders update is attempted.

## Architecture

Add a new package at `packages/reminders-plugin`. It will follow the existing Capacitor plugin pattern used by `packages/store-session-plugin`.

The package contains:

- `src/index.ts`: TypeScript wrapper and exported plugin types.
- `ios/RemindersPlugin.swift`: Swift implementation using EventKit.
- `Package.swift`: Swift Package Manager manifest for Capacitor iOS sync.
- `package.json`: package metadata and build/test scripts.

The plugin is registered as `Reminders` and exposes two methods:

```ts
type ReminderItem = {
  id: string;
  title: string;
};

interface RemindersPlugin {
  getPaprikaItems(): Promise<{ items: ReminderItem[] }>;
  completeReminder(options: { id: string }): Promise<void>;
}
```

The mobile package adds `@listrunner/reminders` as a local dependency and aliases it for Vite and TypeScript, matching the existing local package setup.

## iOS Requirements

The native plugin uses Apple's EventKit framework to access Reminders.

The iOS app must include a Reminders usage description in `Info.plist`:

```xml
<key>NSRemindersUsageDescription</key>
<string>ListRunner reads your Paprika grocery reminders and marks items complete when you add them.</string>
```

The Swift plugin handles these cases:

- Permission granted: continue.
- Permission not yet determined: request Reminders permission and continue if granted.
- Permission denied or restricted: reject with a clear error code/message.
- `Paprika` list missing: reject with a clear error code/message.
- No incomplete reminders: return an empty items array.
- Completion target missing: reject so the UI can warn the user.

If multiple Reminders calendars named `Paprika` exist, the first version uses the first matching calendar returned by EventKit. It does not expose list selection.

## Data Flow

Import flow:

1. User taps `Load from Paprika Reminders`.
2. JavaScript calls `Reminders.getPaprikaItems()`.
3. Swift requests or checks Reminders permission, finds the `Paprika` list, and fetches incomplete reminders.
4. JavaScript converts reminder titles into newline-separated text and calls `parseList()`.
5. JavaScript associates parsed items with source reminder IDs by original import order.
6. The review screen renders normally.

Completion flow:

1. The current wizard item resolves to an optional source reminder ID.
2. User taps `Added`.
3. ListRunner records the normal selection history entry.
4. If a reminder ID exists, JavaScript calls `Reminders.completeReminder({ id })`.
5. The wizard advances regardless of completion success so shopping is not blocked.
6. If completion fails, ListRunner shows a warning that the iOS Reminder could not be checked off.

## Parser Metadata Strategy

The core parser should remain generic. It should not know about iOS Reminders.

The mobile layer will track reminder metadata outside the parsed item model, keyed by parsed item order for imported reminders. Pantry-filtered reminders remain incomplete in iOS Reminders because ListRunner did not ask the user to buy them.

This order-based mapping works because each imported reminder title becomes one input line and the parser processes list lines in order. Manually added review items have no source reminder ID.

If future work needs richer metadata across all clients, this can be revisited with a core model change.

## UI Changes

Input screen:

- Add `Load from Paprika Reminders` below or beside `Parse List`.
- Show loading state while Reminders are being read.
- Show clear inline status/errors for permission denial, missing list, and empty list.

Wizard screen:

- Reuse existing controls.
- Show a warning if completing an iOS Reminder fails.

No visual redesign is required for the first version.

## Error Handling

- Permission denied: show that Reminders permission is needed and keep paste entry available.
- Missing `Paprika` list: show `No Paprika list found` and keep paste entry available.
- Empty list: show `No incomplete reminders found`.
- Import failure: show a generic import failure message with manual paste as fallback.
- Completion failure: keep the ListRunner flow moving and show a warning.
- Native plugin unavailable, such as web preview: disable or gracefully fail the Reminders button with a clear message.

## Testing

- Add mobile unit tests for converting imported reminders into parsed review items while preserving reminder IDs.
- Add mobile tests confirming `Added` calls `completeReminder` only for imported items.
- Add mobile tests confirming a failed reminder completion does not block wizard advancement.
- Add source-level plugin checks for Capacitor method registration and EventKit usage.
- Run `npm test` and `npm run build` for the new plugin.
- Run `npx tsc --noEmit` and `npm run build` for `packages/mobile`.
- Run `npm run cap:sync` on the Mac checkout and an unsigned Xcode iOS build to confirm Swift compiles.

## Out Of Scope

- Configurable Reminders list names.
- Importing completed reminders.
- Completing reminders on skip or dismissal.
- Bidirectional sync from ListRunner back into Reminders beyond marking imported items complete.
- Android support.
