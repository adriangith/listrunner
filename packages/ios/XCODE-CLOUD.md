# Nightly Xcode Cloud builds

## Workflow configuration

Configured by the user in Xcode on 2 November 2026 (cloud execution still pending):

- Repository: `adriangith/listrunner`; project: `packages/ios/ListRunner.xcodeproj`.
- Shared scheme: `ListRunner`; archive configuration: Release.
- Environment: explicit Xcode **27.1 (27A9275)**; macOS Latest Release.
  The Mac has 27.2, so cloud/compiler compatibility is not yet proven.
- Start conditions: daily **02:00 Australia/Melbourne**, branch `main`, plus manual
  branch starts. Branch Changes was removed.
- One Archive/iOS action, Distribution Preparation **App Store Connect**, not
  internal-testing-only. A separate Build action is unnecessary.
- Next cloud build number set to **3**, following uploaded manual 1.0 (2).
  Recheck the highest uploaded build if another manual upload intervenes.
  On 3 November, local archive **1.0 (3)** was uploaded successfully as **1.0 (4)**
  by Xcode's automatic build-number management. Before any later cloud run, recheck
  App Store Connect and set the next cloud build to **at least 5**. The saved
  workflow is unchanged; Apple processing is not yet verified. See
  `docs/releases/revision-3.md`.
- No TestFlight group post-action: promote selected successful builds to external
  testers manually, completing beta-review/export-compliance requirements as needed.
  App Store Connect preparation does not publish the app publicly. Verify actual
  uploaded/processed status in App Store Connect; an archive is not upload proof.
- Workflow saved **disabled** while repository checks are prepared. Do not assume
  it is enabled or a cloud build has succeeded from this document.

## Automatic TestFlight tester notes

`packages/ios/TestFlight/WhatToTest.en-US.txt` supplies the English **What to Test** text for future Xcode Cloud builds. The `TestFlight` directory sits beside `ListRunner.xcodeproj`, as required by Xcode Cloud. The file does not need a target membership or a build-script generator; Xcode Cloud discovers it in the build's checked-out revision.

Edit and commit this file before starting a release build when the testing focus changes. It contains curated tester guidance, not automatically generated commit messages. The same text is reused for subsequent builds until updated and is visible to all testers who can access the build. Group assignment and notification settings remain controlled by the workflow, not this file.

Build **5**, shown running from `28baa28` on 4 November, predates this file and cannot pick up a later commit. Its notes must be added manually in App Store Connect after upload. Adding this file does not start a build, change the nightly schedule, assign testers or publish the app.

Apple reference: https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app

## Automatic offline gates

Xcode Cloud discovers `ci_scripts` beside the project, so the hooks live under
`packages/ios/ci_scripts`, **not at the repository root**. They are executable.

`ci_post_clone.sh` ensures Node.js 22+ is available, using Homebrew's `node@22`
formula if necessary, then runs `tests/run-cloud-checks.sh`. Tool installation may
use the network; the tests themselves use local fixtures and compiled programs:

- Release metadata, expansion/resource-reference contracts and resource-verifier tests.
- Cloud-hook/archived-resource failure-path tests.
- Three explicitly selected Node page-behaviour suites; no npm dependencies/install.
- Native parser, regional search, synthetic store-registry and recovery checks.

Any failed check returns a nonzero exit code and stops the build before archiving.
No XCTest action is added: the existing shared scheme includes UI and gated live
retailer tests. These standalone gates do **not** replace simulator UI coverage,
accessibility checks, physical-device testing, or live-retailer certification.
No retailer page is opened, no account accessed and no cart altered by these gates.

`ci_post_xcodebuild.sh` checks the xcodebuild exit code. On successful archive
actions it requires `CI_ARCHIVE_PATH`, checks the archived bundle identity and
resolved version/build, and byte-compares every canonical JSON resource. It rejects
missing resources and legacy `*-v2.json` duplicates. A JSON manifest in the build
log records the exact checkout commit, cloud build number and archive metadata;
it explicitly does **not** claim signing/export/upload/processing succeeded.
It does not automatically create successful-upload Git tags.

Local Mac equivalent (no Homebrew installation by this command):

```sh
bash packages/ios/tests/run-cloud-checks.sh
```

## Scheme warning investigation and first cloud run

The Xcode workflow editor warns the scheme may only exist locally. Checks so far:

- `packages/ios/ListRunner.xcodeproj/xcshareddata/xcschemes/ListRunner.xcscheme`
  is tracked and was already pushed on `main`, not under `xcuserdata`.
- Mac and GitHub `main` matched at `a0276982ea9fdc18a5e0de93464aded39f93179a`
  before these CI additions; refreshing the Mac's stale `origin/main` did not
  remove the warning, nor did reopening the editor.
- Mac `xcodebuild -list -json -project .../ListRunner.xcodeproj` recognizes the
  `ListRunner` scheme. Its ArchiveAction uses Release.
- Xcode's generated untracked `xcshareddata/xcodecloud/manifest.json` on the Mac
  is preserved, not deleted or overwritten by the Git handoff.

The warning's cause remains **unresolved**, not proven harmless. Do not recreate
the project or scheme, clear credentials, or discard local state to suppress it.
After pushing these hooks and verifying the saved workflow/project selection,
a single user-triggered cloud run is the next end-to-end diagnostic. If scheme
discovery fails, use the actual cloud checkout path/revision and error log to
investigate rather than guessing. Keep external distribution post-actions empty.
The workflow must be enabled to use it; enabling also enables its nightly schedule.
Disable it again if that diagnostic fails, until the failure is fixed.

## Local validation before first cloud run

The complete `ci_post_clone.sh` hook passed on the Mac at
`a3c2c3d0487cac1af0fef09053db0cf8faf4dbfb`, with Node 22 and local Xcode 27.2:
22 Python checks, 249 Node page-behaviour tests, 449 parser checks, 195 regional
search checks, synthetic store-registry proof, and 1,666 native recovery checks.
Hook syntax and the Python/Node checks also passed on Linux. Post-xcodebuild
failure paths and resource auditing were tested with synthetic archives; no cloud
archive or upload was produced by this validation. It does not establish Xcode
27.1 cloud compatibility or resolve the workflow editor's scheme warning.

Mac log: `~/Library/Logs/ListRunner-cloud-offline-a3c2c3d.log`.

## Apple references

https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

https://developer.apple.com/documentation/xcode/environment-variable-reference

https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud

https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
