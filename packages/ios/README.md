# ListRunner iOS

Native SwiftUI app targeting iPhone on iOS 17 or later.

Open `ListRunner.xcodeproj` in Xcode, choose an iPhone simulator, and run the `ListRunner` scheme. This is a native SwiftUI/SwiftData iOS 17 app, not the removed Capacitor app.

## Current implementation

- Add one or many items from comma-, newline-, and bullet-separated text.
- Parse common counts, multipliers, and grocery units; unrecognized entries are retained as names.
- Merge typed duplicates by normalized name and compatible units; persist one active list locally with SwiftData.
- Review status totals, edit item name/quantity/unit, delete rows, and clear a list with pending-item confirmation.
- Open Coles in a persistent-data WKWebView sheet with native item cards and manual Mark Added, Skip, Next, Pause, Undo, and Finish controls.

This is the first implementation slice, not release-complete MVP. Automatic Coles search/cart detection and secure bridge, Paprika/EventKit, robust persistence/migration recovery, settings/session reset, dedicated test targets, and full selection-history/accessibility lifecycle behavior remain to be implemented. The current store overlay explicitly tells the user to search manually; it does not claim to detect cart changes or reverse Coles cart operations.

## Build and test

The source is authored on the Linux development system and synchronized to the Mac through Git. On the Mac:

```sh
cd packages/ios
xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
  -destination 'generic/platform=iOS Simulator' build
```

Then open `ListRunner.xcodeproj` in Xcode, choose an iOS 17+ iPhone simulator, and run the app. A native XCTest target has not yet been added, so this initial slice still needs parser/UI tests before it can be treated as verified. Report Xcode build errors back against the synced commit; this Linux host does not have `xcodebuild` or the iOS SDK.
