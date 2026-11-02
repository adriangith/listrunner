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
- No TestFlight group post-action: promote selected successful builds to external
  testers manually, completing beta-review/export-compliance requirements as needed.
  App Store Connect preparation does not publish the app publicly. Verify actual
  uploaded/processed status in App Store Connect; an archive is not upload proof.
- Workflow saved **disabled** while repository checks are prepared. Do not assume
  it is enabled or a cloud build has succeeded from this document.

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

## Apple references

https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

https://developer.apple.com/documentation/xcode/environment-variable-reference

https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud

https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds
