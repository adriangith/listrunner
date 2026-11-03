# TestFlight revision 3 — 1.0 (3)

## Release record

- Status: **prepared; archive signing blocked; not uploaded**.
- The user confirmed 1.0 (2) is the newest App Store Connect build and authorised preparing the next TestFlight build, without a public App Store submission or automatic tester-group distribution.
- Version/build: **1.0 (3)**; unchanged app identifier `com.adrianzafir.listrunner`.
- Version preparation commit: `97974109c8b2cb7da036dc1bda0a194e218ea4c9`, on `main`, pushed to GitHub and shared by Linux/Mac.
- Changes since revision 2 include Tesco UK support, automatic post-login add acknowledgement, Your list scroll-work reductions and the first-use **Import items...** label.
- Command-line archive attempt: Mac `~/Library/Developer/Xcode/Archives/2026-11-03/ListRunner-1.0-3-9797410.xcarchive`.
- Archive log: `~/Library/Logs/ListRunner-TestFlight-1.0-3-9797410-archive.log`.
- Compilation completed, but CodeSign failed with **`errSecInternalComponent`**. This is **not** a completed signed archive. The staged app independently reports the expected identifier, version 1.0 and build 3; all 34 staged JSON resources match canonical sources.
- The Mac screen was confirmed locked. Xcode's GUI exposes no usable project window/Archive action in that state. The next step is normal GUI archiving from an unlocked signed-in Mac session; do not change keychain ACLs, passwords or signing identity to work around the failure.
- After successful archiving, verify the actual archive, code signature, identity/build and resources, then record its exact checkout SHA and manifest. After export/upload, verify App Store Connect processing independently. Do not create a successful-upload source tag or claim availability before upload is confirmed.
- Xcode Cloud's saved next-build number was previously 3. If this manual build is uploaded, advance that workflow's next number to at least 4 before any cloud run. The workflow is not enabled or edited by this preparation.

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
