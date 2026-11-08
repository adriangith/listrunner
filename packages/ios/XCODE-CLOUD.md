# Nightly Xcode Cloud builds

## Change-gated nightly beta automation (4 November 2026)

The current release policy is **beta prereleases, app-related changes only**. GitHub Actions owns the nightly decision; the Apple workflow must remain enabled but **manual-only**, with no Apple schedule/branch/tag/PR automatic starts. Retain its external TestFlight group post-action. This supersedes the original workflow snapshot below.

- `.github/workflows/nightly-beta.yml` checks at about **02:07 Australia/Melbourne**. Two UTC cron slots cover summer/winter; a local-hour guard runs only one. GitHub scheduling can be delayed. On the spring-forward night when 02:00 does not exist, it skips rather than starting twice.
- It compares the checked-out `main` snapshot against the last successfully published `beta/ios-*` prerelease. Net app changes under `packages/ios/` and the nightly workflow count; Markdown, the website and `TestFlight` notes alone do not. Native tests and archive tooling do count because they are build gates. Reverted changes with no remaining app diff do not build.
- Bootstrap baseline is source `28baa28621fe568a9fcd57feed50f923069b3d81`, verified as uploaded/processed TestFlight **1.0 (5)**. Its external post-action initially failed for missing encryption compliance; do not confuse that failed workflow with a new successful automated prerelease.
- An immutable annotated `nightly/request-YYYY-MM-DD` tag pins the exact source SHA, baseline and notes. At most one request starts per Melbourne date. It is an internal build request, **not** a GitHub release and not a marker of success. Never move/retag it or use it as the baseline.
- Xcode Cloud starts via the App Store Connect API against that tag, not a moving branch. Commit subjects affecting app-related paths generate Features/Fixes/Improvements notes; routine test/build subjects become one reliability entry. Merge/docs-only chatter is excluded. Keep feature/fix commit subjects clear; no AI service or GitHub token is sent to Apple’s build environment.
- `ci_post_clone.sh` reads the request annotation, verifies the pinned source, and generates `TestFlight/WhatToTest.en-US.txt` in the temporary cloud checkout. Manual branch builds retain the curated file. The reconciler also verifies/updates the uploaded build’s English notes before publication.
- A GitHub **prerelease**, named `beta/ios-VERSION-BUILD`, is published only for the matching source reference/commit after the complete Cloud run succeeds and its single iOS upload has `processingState=VALID`. An archive alone, failed post-action, invalid/expired upload or mismatched app does not qualify. Apple external beta review can still be required; a GitHub prerelease is not an App Store public release.
- Release notes contain the TestFlight version/build, full source/baseline comparison and machine-readable provenance. Existing releases/tags are never overwritten. The successful release tag is the baseline—there is no commit pushed back to `main`, so no release-note commit loop.
- Failed changes remain eligible next night. A pending request survives runner cancellation/timeouts and is reconciled before considering newer changes. The CI job waits at most 140 minutes; if Apple takes longer, the next scheduled/manual run resumes it. Ambiguous start responses are not blindly POSTed again. Concurrent GitHub runs are serialized without cancellation.

### Credentials and operation

Repository Actions secret: **ASC_PRIVATE_KEY** (dedicated App Store Connect team `.p8` key, App Manager access). Repository variables: **ASC_ISSUER_ID**, **ASC_KEY_ID**. IDs for the app/workflow/repository and the bootstrap source are non-secret configuration in `packages/ios/nightly-beta.json`. The built-in `GITHUB_TOKEN` has contents-write permission only for immutable request tags and prereleases; no separate GitHub PAT is stored. Private keys/JWTs are never committed or logged. Rotate/revoke the dedicated Apple key in App Store Connect when needed and replace the GitHub secret.

Use **Actions → Nightly TestFlight beta → Run workflow → plan** for a read-only change/notes preview. **run** is an explicit manual start/reconciliation for diagnosis; ordinary automation happens only at night. Neither pushing a commit nor creating a release starts this GitHub workflow. The workflow only accepts `main`, and Actions dependencies are pinned to reviewed commit SHAs.

### Read-only inspection and stage diagnostics

Use workflow mode **inspect** to query Apple once for each unpublished request,
regardless of the nightly time window. It performs only GET requests: no build
start, tag change, tester-note update or release publication. Local equivalent,
with the existing `ASC_*` credentials supplied securely:

```sh
git fetch origin --tags
node packages/ios/tools/nightly-beta.mjs inspect
```

`Nightly status:` JSON records identify the request tag, pinned source SHA,
stage, elapsed seconds and, when available, reference/run/upload IDs, Cloud
build number, execution/completion status and TestFlight processing state.
Transitions and five-minute waiting heartbeats appear in logs and the GitHub
step summary. A failure reports the last operation (including an API lookup);
a timeout includes the exact retained request and last waiting stage. Raw Apple
responses, authentication headers and tokens are not diagnostic output.

- `source-reference-not-indexed`: Apple does not list the immutable Git tag yet;
  this is before a Cloud build can be started.
- `cloud-run-not-visible` / `cloud-start-accepted`: the tag is indexed but no
  matching run is visible, or the start has been accepted in this process.
- `cloud-source-metadata` / `cloud-execution`: waiting for source metadata or
  Cloud execution. `cloud-failed` includes its completion status.
- `upload-not-visible` / `testflight-processing`: Cloud succeeded, but its
  upload is not visible yet or has not finished processing.
- `ready-to-publish`: read-only inspection verified a publishable upload;
  it has **not** published it. Normal runs continue through `tester-notes`,
  `github-release`, and `released`.

Read-only investigation on 9 November 2026: GitHub contains the annotated tag
`nightly/request-2026-11-06` (tag object
`10cee4aa6be32978f04a5de8deb633b587241cac`, source
`18347796fef55944e6e7708f89217c5fba3240be`), but Apple's paginated repository
reference list does not contain it. Apple's workflow run list ends at successful
build **6**, for `nightly/request-2026-11-05`; there is no run for the pending
6 November request. This confirms a source-reference indexing/discovery block,
not an observed compiler failure. The underlying reason Apple has not indexed
the tag is not established. No tags, Cloud settings, builds or releases were
modified during inspection. Do not delete/recreate the request to mask it.

Do not re-enable the Apple schedule alongside GitHub’s schedule. Keep manual tag starts enabled for `nightly/request-` tags. To pause nightly automation, disable the GitHub Actions workflow; already-running Apple builds must be handled separately. Do not delete pending request tags to force a retry, advance the baseline after a failure, or use the next build counter as evidence of upload success.

The user approved the declaration that the app uses no non-exempt encryption after a source check found no custom cryptography/library. `ITSAppUsesNonExemptEncryption=false` is now canonical app metadata. This means exempt system HTTPS/WebKit encryption, not disabled encryption. Reassess this declaration when adding cryptography or dependencies.

Offline verification: `node --test packages/ios/tests/nightly-beta.test.mjs` (also in the cloud offline gate). It uses temporary local Git repositories and mock Apple/GitHub services, never real releases, reminders, stores or credentials. Live workflow acceptance and TestFlight processing remain separate checks.

## Historical original setup (superseded where noted above)

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
