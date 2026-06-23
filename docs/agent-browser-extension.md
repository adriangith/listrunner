# Agent Browser Extension Workflow

Use this workflow when testing ListRunner through `agent-browser` and the
agent-browser dashboard.

## Build

```bash
cd packages/extension
npm run build
```

The Chrome extension build is written to:

```text
packages/extension/dist/chrome
```

The build script also copies the Chrome build to this shared path when it is
writable:

```text
/mnt/listrunner-extension
```

## Agent Browser Dashboard

Start the dashboard with:

```bash
agent-browser dashboard start
```

The default dashboard URL is:

```text
http://localhost:4848
```

Always pass the browser runtime flag through `--args` when launching browser
sessions:

```bash
agent-browser --args "--no-sandbox" open "about:blank"
```

## Loading the Extension

The intended launch command is:

```bash
agent-browser --args "--no-sandbox" \
  --extension "/home/claude-svc/listrunner/packages/extension/dist/chrome" \
  open "chrome://extensions"
```

On this headless host, that currently fails because Chromium switches to an X11
launch path when the extension is loaded and exits with:

```text
Missing X server or $DISPLAY
```

That is a browser/environment limitation, not a ListRunner build failure.

## Dashboard Fallback

For wizard behavior that does not need Chrome extension APIs, use the harness:

```bash
cd packages/harness
npm run build
```

For an interactive harness server, run:

```bash
cd packages/harness
npm run dev
```

It serves the dashboard at:

```text
http://localhost:3000
```

The harness exercises parsing, wizard flow, search-term editing, pantry
exclusions, skipped-item revisit flow, and selection history. It does not test
extension service-worker behavior, Chrome messaging, or content-script
add-to-cart detection.
