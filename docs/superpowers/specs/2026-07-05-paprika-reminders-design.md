# Paprika Reminders Import And Completion Design

## Summary

ListRunner will add an iOS-only import path for grocery lists exported by Paprika into Apple Reminders. The first version uses a fixed Reminders list name, `Paprika`, imports only incomplete reminders, and marks the exact source reminder complete when the user taps **Added** in ListRunner.

Manual paste-based list entry remains available and unchanged.

## Goals

- Add a **Load from Paprika Reminders** button on the mobile input screen.
- Read incomplete reminders from the iOS Reminders list named exactly `Paprika`.
- Reuse the existing parsing and review flow after import.
- Track each imported reminder's native ID through the wizard.
- Mark an imported reminder complete in iOS Reminders when its ListRunner item is marked **Added**.
- Keep skipped, dismissed, exited, pantry-filtered, and manually added items incomplete in Reminders.

## Non-Goals

- Configurable Reminders list names.
- Automatic import on app launch.
- Importing completed reminders.
- Creating or modifying the `Paprika` list.
- Completing reminders for manually pasted or manually added items.
- Syncing ListRunner state back to Reminders for actions other than **Added**.

## User Flow

The input screen shows the existing textarea and parse button plus a new **Load from Paprika Reminders** button.

When the user taps the new button, ListRunner asks iOS for Reminders permission if needed, looks for the `Paprika` Reminders list, and fetches incomplete reminder titles. It parses those titles with the existing parser and shows the existing review screen.

During the wizard, tapping **Added** records normal ListRunner history and completes the exact imported reminder in iOS Reminders. **Skip**, **Dismiss**, and **Exit Wizard** do not complete reminders. Items manually added on the review screen have no reminder ID, so **Added** only advances ListRunner for those items.

## Architecture

Add a new Capacitor Swift Package plugin at `packages/reminders-plugin`.

The package mirrors the existing `packages/store-session-plugin` structure:

- `src/index.ts` exposes the TypeScript API.
- `ios/RemindersPlugin.swift` implements the native iOS behavior.
- `Package.swift` lets Capacitor include the plugin through Swift Package Manager.
- `package.json` declares `@listrunner/reminders`.

The plugin name exposed to JavaScript is `Reminders`.

## Plugin API

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

`getPaprikaItems()` reads incomplete reminders from the `Paprika` list only. `completeReminder({ id })` marks one reminder complete by native reminder ID.

## iOS Details

The native plugin uses Apple EventKit.

The mobile iOS app must include a Reminders usage description in `Info.plist`:

```xml
<key>NSRemindersUsageDescription</key>
<string>ListRunner reads your Paprika grocery reminders and marks items complete when you add them.</string>
```

Permission states:

- Authorized: read and complete reminders normally.
- Not determined: request Reminders permission and continue if granted.
- Denied or restricted: reject with a permission-specific error code.

The plugin should query calendars for a Reminders calendar named exactly `Paprika`. If multiple matching calendars exist, use the first returned by EventKit. The first version does not expose list selection.

## Mobile Data Flow

Import flow:

1. User taps **Load from Paprika Reminders**.
2. Mobile JS calls `Reminders.getPaprikaItems()`.
3. JS builds raw list text with `items.map(item => item.title).join("\n")`.
4. JS calls existing `parseList(rawText, { pantryExclusions })`.
5. JS keeps source reminder metadata in the mobile layer, keyed by imported item order.
6. JS renders the existing review screen.

Completion flow:

1. The current wizard item resolves to an optional imported reminder ID.
2. User taps **Added**.
3. ListRunner records the normal history entry.
4. If a reminder ID exists, JS calls `Reminders.completeReminder({ id })`.
5. The wizard advances regardless of completion success so shopping is not blocked.
6. If completion fails, ListRunner shows a warning that the iOS reminder could not be checked off.

The core parser models should remain generic. The mobile layer owns imported reminder metadata instead of adding Reminders-specific fields to `ParsedItem`.

## Mapping Imported Reminders To Parsed Items

The first version tracks reminder IDs by original imported item order. This works because each reminder title becomes one input line and the current parser processes list lines in order.

Pantry-filtered reminders are not completed automatically. If a reminder title is filtered out, it remains incomplete in Reminders.

Manually added review items have no source reminder ID. They can be added to the ListRunner wizard, but they do not complete any iOS reminder.

## Error Handling

- Permission denied: show a clear message and leave paste entry available.
- `Paprika` list missing: show `No Paprika list found` and leave paste entry available.
- No incomplete reminders: show `No incomplete reminders found` and leave paste entry available.
- Import failure: show a generic import failure message with manual paste as fallback.
- Completion failure: keep advancing the wizard and show a warning that the iOS reminder could not be checked off.

## Testing

- Unit-test mobile import mapping: reminder titles become parsed items and retain reminder IDs by order.
- Unit-test **Added** handling: completion is attempted only for imported items with reminder IDs.
- Unit-test failure handling: a failed reminder completion does not block wizard advancement.
- Add source-level Swift/plugin checks for Capacitor method registration and EventKit usage where direct iOS XCTest is not available in the Linux workspace.
- Verify local packages with `npm test`, `npm run build`, `npx tsc --noEmit`, and mobile `npm run build`.
- Verify on the Mac with `npm run cap:sync` and an unsigned Xcode iOS build.

## Open Decisions

No open product decisions remain for the first version. Future versions may add configurable Reminders list names or automatic import, but those are outside this scope.
