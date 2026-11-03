# TestFlight revision 3 — uploaded 1.0 (4)

## Release record

- Status: **uploaded successfully; Apple processing and tester availability unverified**.
- The user confirmed 1.0 (2) is the newest App Store Connect build and authorised preparing the next TestFlight build, without a public App Store submission or automatic tester-group distribution.
- Uploaded version/build: **1.0 (4)**; local archive/project version/build: **1.0 (3)**. Xcode's recommended distribution automatically managed the uploaded build number. Unchanged app identifier `com.adrianzafir.listrunner`. Do not look for uploaded build 3 or infer a separate build-3 upload from the local archive.
- Version preparation commit: `97974109c8b2cb7da036dc1bda0a194e218ea4c9`, on `main`, pushed to GitHub and shared by Linux/Mac.
- Changes since revision 2 include Tesco UK support, automatic post-login add acknowledgement, Your list scroll-work reductions and the first-use **Import items...** label.
- Command-line archive attempt: Mac `~/Library/Developer/Xcode/Archives/2026-11-03/ListRunner-1.0-3-9797410.xcarchive`.
- Archive log: `~/Library/Logs/ListRunner-TestFlight-1.0-3-9797410-archive.log`.
- Compilation completed, but CodeSign failed with **`errSecInternalComponent`**. This is **not** a completed signed archive. The staged app independently reports the expected identifier, version 1.0 and build 3; all 34 staged JSON resources match canonical sources.
- After the user unlocked the Mac, normal GUI **Product → Archive** succeeded without keychain/security changes. Completed archive: `~/Library/Developer/Xcode/Archives/2026-11-03/ListRunner 3-11-2026, 11.25 pm.xcarchive` (U+202F before `pm`), created **2026-11-03 12:25:42 UTC**. Do not confuse this with the failed CLI attempt above.
- The actual archived app passed strict/deep code-signature verification and all **34 canonical JSON resource** comparisons, and reports `com.adrianzafir.listrunner`, **1.0 (3)**. Source checkout observed before and after GUI archiving: `c8bb5e36576448bf71d7765a2bc62a71df2634fb`; the archive does not independently embed that Git SHA.
- Archived executable SHA-256: `d5867b80dec7622d069e25ba2f6e1036bce439c1f8f656229d66f08992179d40`. Verification manifest: Mac `~/Library/Logs/ListRunner-TestFlight-1.0-3-archive-manifest.json`.
- Organizer confirmed **App upload complete / ListRunner 1.0 (4) uploaded**. The archive's `Distributions` record independently reports upload success, uploaded build **4**, completed **2026-11-03T12:29:56Z**, distribution ID `de165034-8735-4c1c-969a-52b026feb657`, App Store Connect app ID `6829116336`. No public submission or tester-group action was performed. Apple processing remains unverified: the local browser was not signed in, and the Mac's opened App Store Connect page did not expose readable page content. Upload is not a claim that testers can install it yet.
- Successful-upload source tag: `testflight/revision-3`, targeting archived source `c8bb5e36576448bf71d7765a2bc62a71df2634fb`, not later release notes. Here revision 3 is the release sequence, not Apple's automatically assigned build 4.
- Verification manifest above now records both local build 3 and uploaded build 4. Distribution logs: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ListRunner_2026-11-03_23-28-22.437.xcdistributionlogs`.
- Xcode Cloud's saved next-build number was previously 3. Advance that workflow's next number to **at least 5** before any cloud run, and recheck the latest App Store Connect build. The workflow is not enabled or edited by this release.

## What to Test

Tesco UK is now available in Manage Stores. Please test searching, adding products and automatic Added status, including an Add interrupted by Tesco sign-in. ListRunner should detect Tesco's confirmed post-login addition without a repeated Add or confirmation prompt.

For normal signed-in, quantity-confirmed Tesco additions, Undo attempts to remove only the confirmed quantity added. For the first addition carried through login, the previous account-cart quantity is unknown: Undo restores the ListRunner item only and warns you to check Tesco's cart. It must not remove pre-existing groceries.

Your list now avoids repeated configuration validation, unnecessary row-position tracking, repeated drag cancellation and unchanged text-editor sizing work. Please check vertical dragging with the same list, first-item and repeated additions, a growing multiline draft, and keyboard dismissal. The first-use import button now says **Import items...**; configured Paprika imports are unchanged.

Known limits:
- Seven focused list UI scenarios passed across simulator runs, **not a clean 9/9**. Two fine-positioning assertions remain open: 3.33 points of input movement against a 2-point tolerance, and a 15-point keyboard reveal where the initial card may actually require that correction.
- No physical-device FPS/hitch-rate profile was captured; the performance work has a measured microbenchmark and functional checks, not a quantified on-phone frame-rate guarantee.
- Tesco proof covers the tested milk grid/sign-in flow, not every product, variant, detail, fulfilment or security flow.
- Other unfinished retailer integrations and broader accessibility/iOS 17 runtime checks remain unchanged. No checkout or purchase is automated.

## Preparation checks

At `9797410`, the complete offline cloud gate passed after adding the already-installed Homebrew Node 22 directory to the SSH command's PATH. It included the Python release/resource/cloud contracts, 265 selected DOM/page tests, 449 parser checks, 195 regional search checks, synthetic registry proof and 1,701 native checks. A separate full DOM run passed **313 tests**, including the Tesco suites omitted from the gate's three selected files. These checks do not imply a clean UI suite or successful signing/upload.
