# Paprika Reminders Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import incomplete iOS Reminders from a list named `Paprika`, parse them into ListRunner's existing review/wizard flow, and mark the exact source reminder complete when the user taps Added.

**Architecture:** A new Capacitor Swift Package plugin (`packages/reminders-plugin`) wraps Apple EventKit to read and complete reminders. The mobile app calls this plugin via a TypeScript bridge, maps imported reminders to parsed items by original text, and tracks reminder IDs so the wizard can complete the exact source reminder on Added.

**Tech Stack:** TypeScript, Capacitor 8, Swift / EventKit, Vite, Node test runner

## Global Constraints

- iOS deployment target: iOS 15 (`Package.swift` platforms: `[.iOS(.v15)]`)
- Capacitor version: `^8.0.0`
- Swift tools version: `5.9`
- Plugin registered as `Reminders` (jsName)
- Reminders list name is fixed to `Paprika`
- Only incomplete reminders are imported
- Manual paste entry must remain available and unchanged
- Plugin source-level tests use `node --test tests/*.test.mjs` (reads Swift source, no TS import)
- Mobile unit tests use `tsx --test tests/*.test.mjs` (imports TypeScript source files directly)
- `packages/core` must be built (`npm run build` in `packages/core`) before running mobile tests, since `@listrunner/core` resolves to its `dist/index.js` via the `file:../core` symlink
- Core parser must remain generic — no Reminders-specific fields in `ParsedItem`

---

## File Structure

**New files:**

| File | Responsibility |
|------|---------------|
| `packages/reminders-plugin/package.json` | Package metadata, `@listrunner/reminders` name, build/test scripts |
| `packages/reminders-plugin/tsconfig.json` | TypeScript config for plugin wrapper |
| `packages/reminders-plugin/.gitignore` | Ignore node_modules/dist |
| `packages/reminders-plugin/src/index.ts` | TypeScript interface + `registerPlugin` call |
| `packages/reminders-plugin/Package.swift` | Swift Package Manager manifest for Capacitor iOS sync |
| `packages/reminders-plugin/ios/RemindersPlugin.swift` | Native EventKit implementation |
| `packages/reminders-plugin/tests/plugin-methods.test.mjs` | Source-level Swift plugin checks |
| `packages/mobile/src/reminder-import.ts` | Pure functions: map reminders → parsed items, look up reminder IDs |
| `packages/mobile/tests/reminder-import.test.mjs` | Unit tests for import mapping and completion logic |

**Modified files:**

| File | Change |
|------|--------|
| `packages/mobile/package.json` | Add `@listrunner/reminders` dependency |
| `packages/mobile/tsconfig.json` | Add `@listrunner/reminders` path alias |
| `packages/mobile/vite.config.ts` | Add `@listrunner/reminders` Vite alias |
| `packages/mobile/index.html` | Add "Load from Paprika Reminders" button + status element |
| `packages/mobile/src/main.ts` | Import Reminders plugin, add load handler, complete on Added |
| `packages/mobile/ios/App/App/Info.plist` | Add `NSRemindersUsageDescription` key |

---

## Task 1: Scaffold reminders-plugin package

**Files:**
- Create: `packages/reminders-plugin/package.json`
- Create: `packages/reminders-plugin/tsconfig.json`
- Create: `packages/reminders-plugin/.gitignore`
- Create: `packages/reminders-plugin/src/index.ts`
- Create: `packages/reminders-plugin/Package.swift`

**Interfaces:**
- Produces: `@listrunner/reminders` npm package exporting default `Reminders` plugin object with methods `getPaprikaItems()` and `completeReminder({ id })`.

- [ ] **Step 1: Create package.json**

```json
{
  "name": "@listrunner/reminders",
  "version": "0.1.0",
  "description": "ListRunner iOS Reminders plugin for Paprika grocery list import and completion",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch",
    "test": "node --test tests/*.test.mjs"
  },
  "keywords": ["capacitor", "plugin", "ios", "reminders"],
  "capacitor": {
    "ios": {
      "src": "ios"
    }
  },
  "devDependencies": {
    "@capacitor/cli": "^8.0.0",
    "@capacitor/ios": "^8.0.0",
    "typescript": "^5.7.0"
  },
  "dependencies": {
    "@capacitor/core": "^8.0.0"
  },
  "peerDependencies": {
    "@capacitor/core": "^8.0.0"
  },
  "files": [
    "dist/",
    "ios/",
    "Package.swift"
  ]
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "isolatedModules": true,
    "declaration": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

- [ ] **Step 3: Create .gitignore**

```
node_modules
dist
```

- [ ] **Step 4: Create src/index.ts**

```ts
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
```

- [ ] **Step 5: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ListrunnerReminders",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "ListrunnerReminders",
            targets: ["ListrunnerReminders"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "ListrunnerReminders",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios")
    ]
)
```

- [ ] **Step 6: Install dependencies and verify build**

Run:
```bash
cd packages/reminders-plugin
npm install
npm run build
```
Expected: `tsc` completes with no errors and `dist/index.js` + `dist/index.d.ts` are created.

- [ ] **Step 7: Commit**

```bash
git add packages/reminders-plugin/package.json packages/reminders-plugin/tsconfig.json packages/reminders-plugin/.gitignore packages/reminders-plugin/src/index.ts packages/reminders-plugin/Package.swift
git commit -m "Add reminders-plugin package scaffold"
```

---

## Task 2: Swift plugin implementation

**Files:**
- Create: `packages/reminders-plugin/ios/RemindersPlugin.swift`
- Create: `packages/reminders-plugin/tests/plugin-methods.test.mjs`

**Interfaces:**
- Produces: Native Capacitor plugin `RemindersPlugin` registered as `Reminders` with methods `getPaprikaItems` and `completeReminder`, using EventKit to read the `Paprika` calendar and complete reminders by identifier.

- [ ] **Step 1: Write the failing source-level test**

Create `packages/reminders-plugin/tests/plugin-methods.test.mjs`:

```js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "RemindersPlugin.swift"),
  "utf8",
);

test("plugin declares CAPBridgedPlugin with Reminders jsName", () => {
  assert.match(source, /class RemindersPlugin:\s*CAPPlugin,\s*CAPBridgedPlugin/);
  assert.match(source, /let jsName = "Reminders"/);
});

test("plugin registers getPaprikaItems and completeReminder methods", () => {
  assert.match(source, /CAPPluginMethod\(name: "getPaprikaItems"/);
  assert.match(source, /CAPPluginMethod\(name: "completeReminder"/);
});

test("plugin imports EventKit", () => {
  assert.match(source, /^import EventKit/m);
});

test("plugin fetches calendars named Paprika", () => {
  assert.match(source, /\$0\.title == "Paprika"/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd packages/reminders-plugin
npm test
```
Expected: FAIL — `RemindersPlugin.swift` does not exist, readFileSync throws.

- [ ] **Step 3: Write the Swift plugin implementation**

Create `packages/reminders-plugin/ios/RemindersPlugin.swift`:

```swift
import Foundation
import Capacitor
import EventKit

@objc(RemindersPlugin)
public class RemindersPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RemindersPlugin"
    public let jsName = "Reminders"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getPaprikaItems", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "completeReminder", returnType: CAPPluginReturnPromise)
    ]

    private let eventStore = EKEventStore()

    @objc func getPaprikaItems(_ call: CAPPluginCall) {
        requestAccess { [weak self] granted in
            guard granted else {
                call.reject("Reminders permission denied")
                return
            }
            self?.fetchPaprikaItems(call)
        }
    }

    @objc func completeReminder(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("Invalid id")
            return
        }

        requestAccess { [weak self] granted in
            guard granted else {
                call.reject("Reminders permission denied")
                return
            }
            self?.completeReminderById(id, call)
        }
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        eventStore.requestAccess(to: .reminder) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func fetchPaprikaItems(_ call: CAPPluginCall) {
        let calendars = eventStore.calendars(for: .reminder)
        guard let paprikaCalendar = calendars.first(where: { $0.title == "Paprika" }) else {
            call.reject("No Paprika list found")
            return
        }

        let predicate = eventStore.predicateForReminders(in: [paprikaCalendar])
        let reminders = eventStore.reminders(matching: predicate)

        let incomplete = reminders.filter { !$0.isCompleted }

        let items: [[String: Any]] = incomplete.map { r in
            [
                "id": r.calendarItemIdentifier,
                "title": r.title ?? "",
            ]
        }

        call.resolve(["items": items])
    }

    private func completeReminderById(_ id: String, _ call: CAPPluginCall) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            call.reject("Reminder not found")
            return
        }

        reminder.isCompleted = true
        do {
            try eventStore.save(reminder, commit: true)
            call.resolve()
        } catch {
            call.reject("Failed to complete reminder: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd packages/reminders-plugin
npm test
```
Expected: PASS — all 4 tests pass.

- [ ] **Step 5: Verify TypeScript build still passes**

Run:
```bash
cd packages/reminders-plugin
npm run build
```
Expected: `tsc` completes with no errors.

- [ ] **Step 6: Commit**

```bash
git add packages/reminders-plugin/ios/RemindersPlugin.swift packages/reminders-plugin/tests/plugin-methods.test.mjs
git commit -m "Add EventKit Reminders plugin implementation"
```

---

## Task 3: Mobile reminder-import mapping module (TDD)

**Files:**
- Create: `packages/mobile/src/reminder-import.ts`
- Create: `packages/mobile/tests/reminder-import.test.mjs`
- Modify: `packages/mobile/package.json` (add test script)

**Interfaces:**
- Consumes: `splitItems`, `parseList`, `ParsedList`, `ParsedItem` from `@listrunner/core`
- Produces: `ReminderItem` type, `importReminders(reminders, pantryExclusions)` → `{ parsedList, reminderIdByOriginal }`, `getReminderIdForItem(parsedItem, reminderIdByOriginal)` → `string | undefined`

- [ ] **Step 1: Add test script to mobile package.json**

Modify `packages/mobile/package.json` — add `"test": "node --test tests/*.test.mjs"` to scripts:

```json
{
  "name": "@listrunner/mobile",
  "version": "0.1.0",
  "description": "ListRunner iOS app — shopping list wizard with in-app browser and overlay",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "tsx --test tests/*.test.mjs",
    "cap:sync": "cap sync",
    "cap:open": "cap open ios"
  },
  "dependencies": {
    "@capacitor/browser": "^8.0.0",
    "@capacitor/core": "^8.0.0",
    "@capacitor/ios": "^8.0.0",
    "@capacitor/preferences": "^8.0.0",
    "@listrunner/core": "file:../core",
    "@listrunner/store-session": "file:../store-session-plugin"
  },
  "devDependencies": {
    "@capacitor/cli": "^8.0.0",
    "typescript": "^5.7.0",
    "tsx": "^4.19.0",
    "vite": "^6.0.0"
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/mobile/tests/reminder-import.test.mjs`:

```js
import assert from "node:assert/strict";
import { test } from "node:test";

const { importReminders, getReminderIdForItem } = await import(
  "../src/reminder-import.ts"
);

test("importReminders maps reminder titles to parsed items", () => {
  const reminders = [
    { id: "r1", title: "milk" },
    { id: "r2", title: "2 kg rice" },
    { id: "r3", title: "bread" },
  ];

  const { parsedList, reminderIdByOriginal } = importReminders(reminders, []);

  assert.equal(parsedList.items.length, 3);
  assert.equal(parsedList.items[0].searchTerm, "milk");
  assert.equal(parsedList.items[1].searchTerm, "rice");
  assert.equal(parsedList.items[2].searchTerm, "bread");

  assert.equal(reminderIdByOriginal.get("milk"), "r1");
  assert.equal(reminderIdByOriginal.get("rice"), "r2");
  assert.equal(reminderIdByOriginal.get("bread"), "r3");
});

test("importReminders applies pantry exclusions and keeps reminder IDs for kept items only", () => {
  const reminders = [
    { id: "r1", title: "salt" },
    { id: "r2", title: "pepper" },
  ];

  const { parsedList, reminderIdByOriginal } = importReminders(reminders, ["salt"]);

  assert.equal(parsedList.items.length, 1);
  assert.equal(parsedList.items[0].searchTerm, "pepper");
  assert.equal(parsedList.filtered.length, 1);
  assert.equal(parsedList.filtered[0].searchTerm, "salt");

  // Filtered reminder ID is still in the map but the parsed item is in filtered[],
  // not items[], so the wizard won't try to complete it.
  assert.equal(reminderIdByOriginal.get("salt"), "r1");
  assert.equal(reminderIdByOriginal.get("pepper"), "r2");
});

test("importReminders strips checkbox prefixes from Paprika exports", () => {
  const reminders = [
    { id: "r1", title: "☐ milk" },
    { id: "r2", title: "- [ ] bread" },
  ];

  const { parsedList, reminderIdByOriginal } = importReminders(reminders, []);

  assert.equal(parsedList.items.length, 2);
  assert.equal(parsedList.items[0].searchTerm, "milk");
  assert.equal(parsedList.items[1].searchTerm, "bread");

  // The map keys use the cleaned original (after stripListPrefix)
  assert.equal(reminderIdByOriginal.get("milk"), "r1");
  assert.equal(reminderIdByOriginal.get("bread"), "r2");
});

test("getReminderIdForItem returns ID for imported items and undefined for manual items", () => {
  const map = new Map([
    ["milk", "r1"],
    ["bread", "r2"],
  ]);

  const importedItem = { original: "milk", quantity: null, searchTerm: "milk", filtered: false };
  const manualItem = { original: "coffee", quantity: null, searchTerm: "coffee", filtered: false };

  assert.equal(getReminderIdForItem(importedItem, map), "r1");
  assert.equal(getReminderIdForItem(manualItem, map), undefined);
});

test("importReminders handles empty reminder list", () => {
  const { parsedList, reminderIdByOriginal } = importReminders([], []);

  assert.equal(parsedList.items.length, 0);
  assert.equal(parsedList.filtered.length, 0);
  assert.equal(reminderIdByOriginal.size, 0);
});
```

- [ ] **Step 3: Run test to verify it fails**

Prerequisite: `packages/core` must be built first:
```bash
cd packages/core && npm run build
```

Then run:
```bash
cd packages/mobile
npm install
npm test
```
Expected: FAIL — `../src/reminder-import.ts` does not exist, import throws.

- [ ] **Step 4: Write minimal implementation**

Create `packages/mobile/src/reminder-import.ts`:

```ts
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

  const reminderIdByOriginal = new Map<string, string>();
  for (const r of reminders) {
    const cleaned = splitItems(r.title)[0]?.original ?? r.title;
    reminderIdByOriginal.set(cleaned, r.id);
  }

  return { parsedList, reminderIdByOriginal };
}

export function getReminderIdForItem(
  parsedItem: ParsedItem,
  reminderIdByOriginal: Map<string, string>,
): string | undefined {
  return reminderIdByOriginal.get(parsedItem.original);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run (ensuring core is built first):
```bash
cd packages/core && npm run build
cd packages/mobile && npm test
```
Expected: PASS — all 5 tests pass.

- [ ] **Step 6: Verify type-check passes**

Run:
```bash
cd packages/mobile
npx tsc --noEmit
```
Note: The `reminder-import.ts` module uses `import ... from "@listrunner/core"` which resolves through the `file:../core` symlink to `dist/index.js`. The core package must be built (`npm run build` in `packages/core`) for type-check to find types.
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/src/reminder-import.ts packages/mobile/tests/reminder-import.test.mjs packages/mobile/package.json
git commit -m "Add reminder import mapping with TDD tests"
```

---

## Task 4: Wire reminders-plugin into mobile package

**Files:**
- Modify: `packages/mobile/package.json` (add `@listrunner/reminders` dependency)
- Modify: `packages/mobile/tsconfig.json` (add path alias)
- Modify: `packages/mobile/vite.config.ts` (add Vite alias)

**Interfaces:**
- Consumes: `@listrunner/reminders` package from Task 1
- Produces: Mobile app can `import Reminders from "@listrunner/reminders"` at build and type-check time.

- [ ] **Step 1: Add dependency to package.json**

In `packages/mobile/package.json`, add `"@listrunner/reminders": "file:../reminders-plugin"` to dependencies:

```json
  "dependencies": {
    "@capacitor/browser": "^8.0.0",
    "@capacitor/core": "^8.0.0",
    "@capacitor/ios": "^8.0.0",
    "@capacitor/preferences": "^8.0.0",
    "@listrunner/core": "file:../core",
    "@listrunner/reminders": "file:../reminders-plugin",
    "@listrunner/store-session": "file:../store-session-plugin"
  },
```

- [ ] **Step 2: Add TypeScript path alias**

In `packages/mobile/tsconfig.json`, add the `@listrunner/reminders` path:

```json
    "paths": {
      "@capacitor/core": ["node_modules/@capacitor/core"],
      "@listrunner/core": ["../core/src/index.ts"],
      "@listrunner/reminders": ["../reminders-plugin/src/index.ts"],
      "@listrunner/store-session": ["../store-session-plugin/src/index.ts"]
    }
```

- [ ] **Step 3: Add Vite alias**

In `packages/mobile/vite.config.ts`, add the `@listrunner/reminders` alias:

```ts
  resolve: {
    alias: {
      '@capacitor/core': resolve(__dirname, 'node_modules/@capacitor/core'),
      '@listrunner/core': resolve(__dirname, '../core/src/index.ts'),
      '@listrunner/reminders': resolve(__dirname, '../reminders-plugin/src/index.ts'),
      '@listrunner/store-session': resolve(__dirname, '../store-session-plugin/src/index.ts'),
    },
  },
```

- [ ] **Step 4: Install and verify type-check**

Run:
```bash
cd packages/mobile
npm install
npx tsc --noEmit
```
Expected: No type errors.

- [ ] **Step 5: Verify build passes**

Run:
```bash
cd packages/mobile
npm run build
```
Expected: Vite build succeeds.

- [ ] **Step 6: Run tests**

Run:
```bash
cd packages/mobile
npm test
```
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/package.json packages/mobile/tsconfig.json packages/mobile/vite.config.ts
git commit -m "Wire @listrunner/reminders into mobile package"
```

---

## Task 5: Add NSRemindersUsageDescription to Info.plist

**Files:**
- Modify: `packages/mobile/ios/App/App/Info.plist`

- [ ] **Step 1: Add the Reminders usage description key**

Add the following key-value pair inside the top-level `<dict>` in `Info.plist`, before the closing `</dict>`:

```xml
	<key>NSRemindersUsageDescription</key>
	<string>ListRunner reads your Paprika grocery reminders and marks items complete when you add them.</string>
```

- [ ] **Step 2: Commit**

```bash
git add packages/mobile/ios/App/App/Info.plist
git commit -m "Add NSRemindersUsageDescription to Info.plist"
```

---

## Task 6: Mobile import UI — Load from Paprika Reminders button

**Files:**
- Modify: `packages/mobile/index.html`
- Modify: `packages/mobile/src/main.ts`

**Interfaces:**
- Consumes: `importReminders` and `getReminderIdForItem` from `src/reminder-import.ts`, `Reminders` plugin from `@listrunner/reminders`
- Produces: A "Load from Paprika Reminders" button on the input screen that reads iOS Reminders, parses them, and navigates to the review screen.

- [ ] **Step 1: Add button and status element to index.html**

In `packages/mobile/index.html`, inside `#view-input > .content`, add the button and a status paragraph after the existing `btn-pantry` button:

```html
      <button id="btn-pantry" class="btn btn-secondary">Pantry Settings</button>
      <button id="btn-paprika-reminders" class="btn btn-secondary">Load from Paprika Reminders</button>
      <p id="paprika-status" class="feedback hidden"></p>
```

- [ ] **Step 2: Add import and state in main.ts**

At the top of `packages/mobile/src/main.ts`, add the Reminders import:

```ts
import Reminders from "@listrunner/reminders";
import { importReminders, getReminderIdForItem } from "./reminder-import.js";
```

Add state variables near the existing state declarations (after `let pendingInitialStoreSearch = false;`):

```ts
let reminderIdByOriginal: Map<string, string> = new Map();
```

Add DOM refs near the existing DOM ref section (after the `pantryBtn` ref):

```ts
const paprikaBtn = document.getElementById("btn-paprika-reminders") as HTMLButtonElement;
const paprikaStatus = document.getElementById("paprika-status") as HTMLElement;
```

- [ ] **Step 3: Add event listener in init()**

In the `init()` function, after the `pantryBtn.addEventListener` line, add:

```ts
  paprikaBtn.addEventListener("click", handleLoadPaprika);
```

- [ ] **Step 4: Implement handleLoadPaprika**

Add this function after the existing `handleParse` function:

```ts
async function handleLoadPaprika(): Promise<void> {
  paprikaStatus.classList.remove("hidden");
  paprikaStatus.textContent = "Loading Paprika reminders...";

  try {
    const result = await Reminders.getPaprikaItems();
    if (result.items.length === 0) {
      paprikaStatus.textContent = "No incomplete reminders found.";
      return;
    }

    const { parsedList: imported, reminderIdByOriginal: idMap } = importReminders(
      result.items,
      pantry.getNames(),
    );

    if (imported.items.length === 0 && imported.filtered.length > 0) {
      paprikaStatus.textContent = "All reminders were excluded by your pantry.";
      return;
    }

    parsedList = imported;
    reminderIdByOriginal = idMap;
    paprikaStatus.classList.add("hidden");
    renderReviewList();
    showView("review");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    paprikaStatus.textContent = `Could not load reminders: ${msg}`;
  }
}
```

- [ ] **Step 5: Clear reminder state on new list**

In the `handleNewList` function, add `reminderIdByOriginal = new Map();` after the existing `parsedList = null;` line:

```ts
function handleNewList(): void {
  wizardState = null;
  parsedList = null;
  reminderIdByOriginal = new Map();
  listTextarea.value = "";
  showView("input");
}
```

- [ ] **Step 6: Verify type-check and build**

Run:
```bash
cd packages/mobile
npx tsc --noEmit
npm run build
```
Expected: No type errors, Vite build succeeds.

- [ ] **Step 7: Run tests**

Run:
```bash
cd packages/core && npm run build
cd packages/mobile && npm test
```
Expected: All tests pass (import mapping tests still green).

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/index.html packages/mobile/src/main.ts
git commit -m "Add Load from Paprika Reminders button and import flow"
```

---

## Task 7: Complete iOS Reminder on Added

**Files:**
- Modify: `packages/mobile/src/main.ts`

**Interfaces:**
- Consumes: `getReminderIdForItem` from `src/reminder-import.ts`, `Reminders` plugin from `@listrunner/reminders`, `currentItem` from `@listrunner/core`
- Produces: Tapping "Added" completes the source iOS Reminder for imported items, shows a warning on failure, and always advances the wizard.

- [ ] **Step 1: Add completion failure warning element to index.html**

In `packages/mobile/index.html`, inside the wizard view `#view-wizard > .wizard-content`, add a warning paragraph after the existing `automation-warning` div:

```html
      <div id="automation-warning" class="warning hidden">
        Automation unavailable. Use manual controls below.
      </div>
      <div id="reminder-warning" class="warning hidden">
        Could not mark iOS Reminder as complete.
      </div>
```

- [ ] **Step 2: Add DOM ref in main.ts**

Near the existing DOM refs (after `const automationWarning = ...`):

```ts
const reminderWarning = document.getElementById("reminder-warning") as HTMLElement;
```

- [ ] **Step 3: Modify handleAdded to call completeReminder**

Find the existing `handleAdded` function in `packages/mobile/src/main.ts` and replace it with:

```ts
async function handleAdded(product?: {
  productName?: string;
  productImageUrl?: string | null;
}): Promise<void> {
  if (!wizardState) return;
  const item = currentItem(wizardState);
  if (!item) return;

  const searchTerm = item.searchTermOverride ?? item.parsedItem.searchTerm;

  history.add({
    store: STORE_ID,
    searchTerm,
    productName: product?.productName || searchTerm,
    productImageUrl: product?.productImageUrl || null,
  });
  persistData();

  // Complete the source iOS Reminder if this item was imported
  const reminderId = getReminderIdForItem(item.parsedItem, reminderIdByOriginal);
  if (reminderId) {
    try {
      await Reminders.completeReminder({ id: reminderId });
      reminderWarning.classList.add("hidden");
    } catch {
      reminderWarning.classList.remove("hidden");
    }
  }

  sendAction("ADVANCE");
}
```

- [ ] **Step 4: Hide reminder warning on wizard exit**

In the `handleExitWizard` function, add `reminderWarning.classList.add("hidden");` after `wizardState = null;`:

```ts
function handleExitWizard(): void {
  if (!confirm("Exit the wizard? You'll return to the review screen.")) {
    return;
  }
  wizardState = null;
  reminderWarning.classList.add("hidden");

  StoreSession.closeSession();

  if (parsedList) {
    showView("review");
  } else {
    showView("input");
  }
}
```

- [ ] **Step 5: Verify type-check and build**

Run:
```bash
cd packages/mobile
npx tsc --noEmit
npm run build
```
Expected: No type errors, Vite build succeeds.

- [ ] **Step 6: Run tests**

Run:
```bash
cd packages/core && npm run build
cd packages/mobile && npm test
```
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add packages/mobile/index.html packages/mobile/src/main.ts
git commit -m "Complete iOS Reminder on Added and show warning on failure"
```

---

## Task 8: Build and sync verification on Mac

This task verifies the complete integration builds and syncs correctly on the Mac checkout. It does not create new source files — it only verifies.

**Files:**
- No new files. Runs verification commands on the Mac via SSH.

- [ ] **Step 1: Sync changed files to Mac**

Use `scp` to copy all changed/new files to `~/Projects/listrunner-ios-test` on the Mac (`adrianzafir@192.168.4.182`):

```bash
# New plugin package
scp -r packages/reminders-plugin adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/

# Modified mobile files
scp packages/mobile/package.json packages/mobile/tsconfig.json packages/mobile/vite.config.ts packages/mobile/index.html packages/mobile/src/main.ts packages/mobile/src/reminder-import.ts adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/<corresponding-subpaths>

# Tests
scp packages/mobile/tests/reminder-import.test.mjs adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/tests/

# Info.plist
scp packages/mobile/ios/App/App/Info.plist adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/ios/App/App/Info.plist
```

Note: Create the `tests` and `src` directories on the Mac first if they don't exist:
```bash
ssh adrianzafir@192.168.4.182 'mkdir -p ~/Projects/listrunner-ios-test/packages/mobile/tests ~/Projects/listrunner-ios-test/packages/mobile/src'
```

- [ ] **Step 2: Run plugin tests on Mac**

Run via SSH:
```bash
ssh adrianzafir@192.168.4.182 'PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/reminders-plugin && npm install && npm test && npm run build'
```
Expected: Plugin tests pass, build succeeds.

- [ ] **Step 3: Run mobile tests and build on Mac**

Run via SSH:
```bash
ssh adrianzafir@192.168.4.182 'PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/mobile && npm install && npm test && npx tsc --noEmit && npm run build'
```
Expected: Mobile tests pass, type-check clean, build succeeds.

- [ ] **Step 4: Run cap sync on Mac**

Run via SSH:
```bash
ssh adrianzafir@192.168.4.182 'PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/mobile && npm run cap:sync'
```
Expected: `cap sync` output includes `@listrunner/reminders@0.1.0` in the "Found N Capacitor plugins for ios" list, and "All plugins have a Package.swift file".

- [ ] **Step 5: Run unsigned Xcode build on Mac**

Run via SSH:
```bash
ssh adrianzafir@192.168.4.182 'PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/mobile/ios/App && xcodebuild -project App.xcodeproj -scheme App -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_ALLOWED=NO'
```
Expected: `** BUILD SUCCEEDED **` with `ListrunnerReminders` target compiled.

- [ ] **Step 6: Verify no commit needed**

Confirm `git status` is clean — this task is verification only, no source changes expected unless something needs fixing:
```bash
git status --short
```
Expected: Clean working tree (or only Mac-sync artifacts that are gitignored).