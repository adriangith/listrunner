# TestFlight revision 1 — approximate baseline

## Status

Date-based estimate, authorised by the user. This is **not** a verified record of
the exact source revision uploaded to App Store Connect.

- User-supplied upload date: **1 November 2026**.
- Assumed timezone: **Australia/Melbourne (UTC+11)**.
- Cutoff: end of that day, immediately before **2 November 2026 00:00:00 +11:00**.
- Selection rule: latest first-parent commit on `main` before the cutoff.
- Baseline commit: **`b01ff2835732d0940f1c8024b1cf74b1cfe7a832`**.
- Commit time: **1 November 2026 23:34:41 +11:00**.
- Commit subject: `Locate flattened retailer AX buttons without losing product scope`.
- Git tag: **`testflight/revision-1`** (annotated as an approximate baseline).

The version/build metadata and actual upload time have not been independently
confirmed. Do not describe this tag as proof of what was shipped. If revision 1
was uploaded earlier on 1 November, this end-of-day estimate may include work
that was not in that upload, and a comparison may consequently omit those changes.
Correct the baseline explicitly if archive or upload records later establish it.

## Capture changes for the next build

From the repository root:

```bash
git log --oneline testflight/revision-1..HEAD
git diff --stat testflight/revision-1..HEAD
```

Review the actual diff as well as commit messages, then summarise tester-facing
features, fixes, testing priorities and known limitations. Keep test/research-only
work separate from capabilities enabled in the shipped app.

For future uploads, record the actual version/build number and full Git commit
alongside the release notes, and create the upload's tag from that exact revision.
This baseline record does not change Xcode's version or build number.
