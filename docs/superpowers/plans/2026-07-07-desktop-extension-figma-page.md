# Desktop Extension Figma Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a polished `Desktop Extension` page in Figma with eight browser side-panel frames based on the mobile UI visual language.

**Architecture:** Use Figma Desktop Bridge scripting to create one page, lay out eight `380 x 720` side-panel frames, and draw the extension states as native Figma layers. Keep all drawing helpers in the Figma execution script for the task that uses them; no application code changes are required.

**Tech Stack:** Figma Desktop Bridge `figma_execute`, Figma frames/text/rectangles, screenshot verification through `figma_capture_screenshot`, project documentation in Markdown.

## Global Constraints

- Create one new page named `Desktop Extension`.
- Include exactly eight frames: `01 Input`, `02 Review`, `03 Wizard`, `04 Wizard Cooldown`, `05 Wizard Warning`, `06 Done`, `07 Pantry`, and `08 Shortcuts Overlay`.
- Each frame should represent a browser extension side panel, approximately `380 x 720` pixels.
- Do not use phone chrome or mobile safe-area treatments.
- Use compact browser-extension density.
- Use soft off-white page background, white cards, rounded controls, Apple-blue primary buttons, green success states, amber warning states, and blue loupe/quantity accents.
- Show desktop-specific affordances: keyboard shortcuts, editable fields, compact item rows, a store selector, and a small settings/pantry action in the header.
- Do not change extension code.
- Do not create dark-mode variants.
- Do not build a full reusable Figma component library.

---

## File Structure

- Existing spec: `docs/superpowers/specs/2026-07-07-desktop-extension-figma-page-design.md`
- Plan file: `docs/superpowers/plans/2026-07-07-desktop-extension-figma-page.md`
- Figma artifact: page `Desktop Extension` in the currently connected Figma file
- No production source files are modified.

---

### Task 1: Create the Figma Page and Frame Shells

**Files:**
- Read: `docs/superpowers/specs/2026-07-07-desktop-extension-figma-page-design.md`
- Modify: Figma page `Desktop Extension`

**Interfaces:**
- Consumes: Current Figma file through Desktop Bridge.
- Produces: A Figma page named `Desktop Extension` containing eight empty side-panel frames at stable coordinates.

- [ ] **Step 1: Confirm the Desktop Bridge is connected**

Run this Figma tool call:

```json
{
  "tool": "figma_get_file_data",
  "arguments": {
    "depth": 1,
    "verbosity": "summary"
  }
}
```

Expected: The tool returns file/page data. If it times out, continue with the next step only if `figma_execute` is available through the Desktop Bridge; otherwise pair the plugin first.

- [ ] **Step 2: Create or reset the target page and add eight side-panel frames**

Run this Figma tool call:

```json
{
  "tool": "figma_execute",
  "arguments": {
    "timeout": 30000,
    "code": "const PAGE_NAME = 'Desktop Extension';\nconst FRAME_W = 380;\nconst FRAME_H = 720;\nconst GAP_X = 80;\nconst GAP_Y = 96;\nconst frames = ['01 Input','02 Review','03 Wizard','04 Wizard Cooldown','05 Wizard Warning','06 Done','07 Pantry','08 Shortcuts Overlay'];\nlet page = figma.root.children.find((p) => p.name === PAGE_NAME);\nif (!page) {\n  page = figma.createPage();\n  page.name = PAGE_NAME;\n}\nawait figma.setCurrentPageAsync(page);\nfor (const child of [...page.children]) child.remove();\nfor (let i = 0; i < frames.length; i++) {\n  const frame = figma.createFrame();\n  frame.name = frames[i];\n  frame.resize(FRAME_W, FRAME_H);\n  frame.x = (i % 4) * (FRAME_W + GAP_X);\n  frame.y = Math.floor(i / 4) * (FRAME_H + GAP_Y);\n  frame.fills = [{ type: 'SOLID', color: { r: 0.972, g: 0.968, b: 0.956 } }];\n  frame.clipsContent = true;\n  page.appendChild(frame);\n}\nfigma.viewport.scrollAndZoomIntoView(page.children);\nreturn { pageId: page.id, frames: page.children.map((node) => ({ id: node.id, name: node.name, x: node.x, y: node.y, width: node.width, height: node.height })) };"
  }
}
```

Expected: The result lists eight frames, each with width `380` and height `720`.

- [ ] **Step 3: Verify the page shell visually**

Run this Figma tool call:

```json
{
  "tool": "figma_capture_screenshot",
  "arguments": {
    "format": "PNG",
    "scale": 1
  }
}
```

Expected: The screenshot shows eight blank side-panel frames arranged in two rows of four, with no overlap.

---

### Task 2: Populate Input, Review, and Wizard Frames

**Files:**
- Read: `packages/extension/public/side-panel.html`
- Read: `packages/extension/public/side-panel.css`
- Modify: Figma frames `01 Input`, `02 Review`, and `03 Wizard`

**Interfaces:**
- Consumes: Frames created by Task 1.
- Produces: Three populated frames that establish the desktop extension visual system for later states.

- [ ] **Step 1: Draw the first three frames**

Run this Figma tool call:

```json
{
  "tool": "figma_execute",
  "arguments": {
    "timeout": 30000,
    "code": "const page = figma.root.children.find((p) => p.name === 'Desktop Extension');\nif (!page) throw new Error('Desktop Extension page not found');\nawait figma.setCurrentPageAsync(page);\nconst C = { bg: '#F7F6F2', surface: '#FFFFFF', text: '#1C1C1E', muted: '#6E6E73', border: '#E5E2DA', blue: '#007AFF', blueSoft: '#EEF5FF', green: '#18A058', greenSoft: '#EAF8F0', amber: '#C77700', amberSoft: '#FFF8EA', chip: '#E8F1FF' };\nfunction rgb(hex) { const h = hex.replace('#',''); return { r: parseInt(h.slice(0,2),16)/255, g: parseInt(h.slice(2,4),16)/255, b: parseInt(h.slice(4,6),16)/255 }; }\nasync function font(style = 'Regular') { await figma.loadFontAsync({ family: 'Inter', style }); return { family: 'Inter', style }; }\nfunction rect(parent, name, x, y, w, h, fill, radius = 12, stroke = null) { const n = figma.createRectangle(); n.name = name; n.x = x; n.y = y; n.resize(w, h); n.cornerRadius = radius; n.fills = [{ type: 'SOLID', color: rgb(fill) }]; if (stroke) { n.strokes = [{ type: 'SOLID', color: rgb(stroke) }]; n.strokeWeight = 1; } parent.appendChild(n); return n; }\nasync function text(parent, name, value, x, y, size, fill = C.text, style = 'Regular') { const n = figma.createText(); n.name = name; n.fontName = await font(style); n.characters = value; n.fontSize = size; n.fills = [{ type: 'SOLID', color: rgb(fill) }]; n.x = x; n.y = y; parent.appendChild(n); return n; }\nasync function button(parent, label, x, y, w, h, variant = 'secondary') { const fill = variant === 'primary' ? C.blue : C.surface; const stroke = variant === 'primary' ? C.blue : C.border; const color = variant === 'primary' ? '#FFFFFF' : C.text; rect(parent, `Button / ${label}`, x, y, w, h, fill, 10, stroke); const t = await text(parent, `Label / ${label}`, label, x, y + 10, 14, color, 'Semi Bold'); t.resize(w, 20); t.textAlignHorizontal = 'CENTER'; return t; }\nasync function header(parent, title) { await text(parent, 'Brand', 'ListRunner', 24, 24, 22, C.text, 'Bold'); await text(parent, 'Header subtitle', title, 24, 54, 12, C.muted); rect(parent, 'Pantry settings icon', 326, 26, 32, 32, C.surface, 10, C.border); await text(parent, 'Settings glyph', '⚙', 336, 31, 16, C.muted); }\nasync function label(parent, value, x, y) { return text(parent, `Label / ${value}`, value, x, y, 12, C.muted, 'Semi Bold'); }\nasync function itemRow(parent, y, qty, name, muted = false) { rect(parent, `Item row / ${name}`, 24, y, 332, 44, C.surface, 10, C.border); rect(parent, `Quantity / ${qty}`, 36, y + 11, 56, 22, C.chip, 999, null); const q = await text(parent, `Qty text / ${qty}`, qty, 36, y + 14, 11, C.blue, 'Semi Bold'); q.resize(56, 16); q.textAlignHorizontal = 'CENTER'; await text(parent, `Item name / ${name}`, name, 108, y + 13, 14, muted ? C.muted : C.text, 'Semi Bold'); await text(parent, `Remove / ${name}`, '×', 332, y + 11, 16, C.muted, 'Regular'); }\nasync function inputFrame() { const f = page.findOne((n) => n.name === '01 Input'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await header(f, 'Paste a list, then step through the store'); await label(f, 'Shopping list', 24, 100); rect(f, 'Multiline input', 24, 122, 332, 316, C.surface, 16, C.border); await text(f, 'Input sample', 'eggs\\n500g flour\\n2x chicken breast\\n1 can (400g) tomatoes\\nfresh basil\\n200g mozzarella', 44, 146, 16, C.text); rect(f, 'Hint card', 24, 462, 332, 72, C.blueSoft, 14, '#D7E7FF'); await text(f, 'Hint title', 'Import from a file or paste from anywhere.', 44, 480, 13, C.text, 'Semi Bold'); await text(f, 'Hint body', 'ListRunner cleans up quantities before the wizard starts.', 44, 504, 12, C.muted); await button(f, 'Import file...', 24, 574, 152, 44, 'secondary'); await button(f, 'Parse List', 188, 574, 168, 44, 'primary'); }\nasync function reviewFrame() { const f = page.findOne((n) => n.name === '02 Review'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await header(f, 'Review parsed items before starting'); await label(f, 'Store', 24, 94); rect(f, 'Store selector', 24, 116, 332, 42, C.surface, 10, C.border); await text(f, 'Store value', 'Woolworths (AU)', 40, 128, 14, C.text, 'Semi Bold'); await text(f, 'Store chevron', '⌄', 334, 126, 16, C.muted); await text(f, 'List title', 'Your list', 24, 188, 18, C.text, 'Bold'); await text(f, 'List count', '6 items', 276, 192, 12, C.muted, 'Semi Bold'); await itemRow(f, 226, '12 ct', 'eggs'); await itemRow(f, 278, '500g', 'flour'); await itemRow(f, 330, '2x', 'chicken breast'); await itemRow(f, 382, '400g', 'tomatoes'); rect(f, 'Add row', 24, 450, 248, 40, C.surface, 10, C.border); await text(f, 'Add placeholder', 'Add another item...', 40, 462, 13, C.muted); await button(f, 'Add', 282, 450, 74, 40, 'secondary'); await text(f, 'Filtered title', 'Filtered out (pantry)', 24, 528, 13, C.muted, 'Semi Bold'); await text(f, 'Filtered row', 'salt', 36, 556, 13, C.muted); await button(f, 'Restore', 280, 546, 76, 34, 'secondary'); await button(f, 'Back', 24, 646, 112, 44, 'secondary'); await button(f, 'Start Wizard', 148, 646, 208, 44, 'primary'); }\nasync function wizardFrame() { const f = page.findOne((n) => n.name === '03 Wizard'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; rect(f, 'Back to list icon', 24, 24, 32, 32, C.surface, 10, C.border); await text(f, 'Back glyph', '↩', 34, 30, 16, C.muted); rect(f, 'Shortcuts icon', 324, 24, 32, 32, C.surface, 10, C.border); await text(f, 'Shortcuts glyph', '?', 336, 30, 16, C.muted, 'Semi Bold'); await label(f, 'Progress', 24, 80); rect(f, 'Progress track', 24, 104, 270, 8, '#E5E2DA', 999, null); rect(f, 'Progress fill', 24, 104, 112, 8, C.green, 999, null); await text(f, 'Progress text', '2/6', 314, 96, 13, C.muted, 'Semi Bold'); rect(f, 'Current item card', 24, 146, 332, 264, C.surface, 18, C.border); rect(f, 'Quantity chip', 140, 174, 100, 28, C.chip, 999, null); const chip = await text(f, 'Quantity chip text', '2x', 140, 180, 12, C.blue, 'Semi Bold'); chip.resize(100, 18); chip.textAlignHorizontal = 'CENTER'; const title = await text(f, 'Current item', 'chicken breast', 54, 226, 28, C.text, 'Bold'); title.resize(272, 36); title.textAlignHorizontal = 'CENTER'; await label(f, 'Search term', 44, 292); rect(f, 'Search input', 44, 316, 216, 40, C.surface, 10, C.border); await text(f, 'Search value', 'chicken breast', 58, 328, 14, C.text); await button(f, 'Update', 268, 316, 68, 40, 'secondary'); rect(f, 'Loupe hint', 44, 374, 292, 62, C.blueSoft, 14, '#D7E7FF'); rect(f, 'Loupe image', 58, 388, 34, 34, '#D9E8FF', 8, null); await text(f, 'Loupe label', 'Last time you picked:', 106, 386, 11, C.muted); await text(f, 'Loupe product', 'Free range chicken breast 500g', 106, 406, 12, C.text, 'Semi Bold'); await button(f, 'Skip', 24, 452, 332, 46, 'secondary'); rect(f, 'Desktop tip', 24, 526, 332, 70, C.surface, 14, C.border); await text(f, 'Desktop tip title', 'Keyboard friendly', 44, 544, 13, C.text, 'Semi Bold'); await text(f, 'Desktop tip body', 'Press E to edit, S to skip, ? for shortcuts.', 44, 568, 12, C.muted); }\nawait inputFrame();\nawait reviewFrame();\nawait wizardFrame();\nreturn { populated: ['01 Input','02 Review','03 Wizard'] };"
  }
}
```

Expected: The first three frames contain realistic content, compact controls, and the approved mobile-inspired visual language.

- [ ] **Step 2: Verify the first row visually**

Run this Figma tool call:

```json
{
  "tool": "figma_capture_screenshot",
  "arguments": {
    "format": "PNG",
    "scale": 1
  }
}
```

Expected: The screenshot shows readable input, review, and wizard frames. Text should not spill outside the `380 x 720` frame bounds.

---

### Task 3: Populate Cooldown, Warning, Done, Pantry, and Shortcuts Frames

**Files:**
- Read: `packages/extension/public/side-panel.html`
- Read: `packages/extension/src/side-panel/side-panel.ts`
- Modify: Figma frames `04 Wizard Cooldown`, `05 Wizard Warning`, `06 Done`, `07 Pantry`, and `08 Shortcuts Overlay`

**Interfaces:**
- Consumes: Frames created by Task 1 and visual language established by Task 2.
- Produces: Five additional frames covering success, fallback, completion, settings, and modal states.

- [ ] **Step 1: Draw the remaining five frames**

Run this Figma tool call:

```json
{
  "tool": "figma_execute",
  "arguments": {
    "timeout": 30000,
    "code": "const page = figma.root.children.find((p) => p.name === 'Desktop Extension');\nif (!page) throw new Error('Desktop Extension page not found');\nawait figma.setCurrentPageAsync(page);\nconst C = { bg: '#F7F6F2', surface: '#FFFFFF', text: '#1C1C1E', muted: '#6E6E73', border: '#E5E2DA', blue: '#007AFF', blueSoft: '#EEF5FF', green: '#18A058', greenSoft: '#EAF8F0', amber: '#C77700', amberSoft: '#FFF8EA', chip: '#E8F1FF', overlay: '#111827' };\nfunction rgb(hex) { const h = hex.replace('#',''); return { r: parseInt(h.slice(0,2),16)/255, g: parseInt(h.slice(2,4),16)/255, b: parseInt(h.slice(4,6),16)/255 }; }\nasync function font(style = 'Regular') { await figma.loadFontAsync({ family: 'Inter', style }); return { family: 'Inter', style }; }\nfunction rect(parent, name, x, y, w, h, fill, radius = 12, stroke = null, opacity = 1) { const n = figma.createRectangle(); n.name = name; n.x = x; n.y = y; n.resize(w, h); n.cornerRadius = radius; n.fills = [{ type: 'SOLID', color: rgb(fill), opacity }]; if (stroke) { n.strokes = [{ type: 'SOLID', color: rgb(stroke) }]; n.strokeWeight = 1; } parent.appendChild(n); return n; }\nasync function text(parent, name, value, x, y, size, fill = C.text, style = 'Regular') { const n = figma.createText(); n.name = name; n.fontName = await font(style); n.characters = value; n.fontSize = size; n.fills = [{ type: 'SOLID', color: rgb(fill) }]; n.x = x; n.y = y; parent.appendChild(n); return n; }\nasync function button(parent, label, x, y, w, h, variant = 'secondary') { const fill = variant === 'primary' ? C.blue : C.surface; const stroke = variant === 'primary' ? C.blue : C.border; const color = variant === 'primary' ? '#FFFFFF' : C.text; rect(parent, `Button / ${label}`, x, y, w, h, fill, 10, stroke); const t = await text(parent, `Label / ${label}`, label, x, y + 10, 14, color, 'Semi Bold'); t.resize(w, 20); t.textAlignHorizontal = 'CENTER'; }\nasync function headerIcons(parent) { rect(parent, 'Back to list icon', 24, 24, 32, 32, C.surface, 10, C.border); await text(parent, 'Back glyph', '↩', 34, 30, 16, C.muted); rect(parent, 'Shortcuts icon', 324, 24, 32, 32, C.surface, 10, C.border); await text(parent, 'Shortcuts glyph', '?', 336, 30, 16, C.muted, 'Semi Bold'); }\nasync function progress(parent, added, total, fill = C.green) { await text(parent, 'Progress label', 'Progress', 24, 80, 12, C.muted, 'Semi Bold'); rect(parent, 'Progress track', 24, 104, 270, 8, '#E5E2DA', 999, null); rect(parent, 'Progress fill', 24, 104, 270 * added / total, 8, fill, 999, null); await text(parent, 'Progress text', `${added}/${total}`, 314, 96, 13, C.muted, 'Semi Bold'); }\nasync function itemCard(parent, item, qty, y = 146) { rect(parent, 'Current item card', 24, y, 332, 236, C.surface, 18, C.border); rect(parent, 'Quantity chip', 140, y + 28, 100, 28, C.chip, 999, null); const chip = await text(parent, 'Quantity chip text', qty, 140, y + 34, 12, C.blue, 'Semi Bold'); chip.resize(100, 18); chip.textAlignHorizontal = 'CENTER'; const title = await text(parent, 'Current item', item, 54, y + 80, 28, C.text, 'Bold'); title.resize(272, 36); title.textAlignHorizontal = 'CENTER'; await text(parent, 'Search label', 'Search term', 44, y + 146, 12, C.muted, 'Semi Bold'); rect(parent, 'Search input', 44, y + 170, 216, 40, C.surface, 10, C.border); await text(parent, 'Search value', item, 58, y + 182, 14, C.text); await button(parent, 'Update', 268, y + 170, 68, 40, 'secondary'); }\nasync function cooldownFrame() { const f = page.findOne((n) => n.name === '04 Wizard Cooldown'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await headerIcons(f); await progress(f, 3, 6); await itemCard(f, 'tomatoes', '400g'); rect(f, 'Success card', 24, 420, 332, 120, C.greenSoft, 16, '#CDEEDB'); await text(f, 'Success title', 'Added! Next item in 2s...', 44, 446, 18, C.green, 'Bold'); rect(f, 'Cooldown track', 44, 484, 292, 8, '#CDEEDB', 999, null); rect(f, 'Cooldown fill', 44, 484, 172, 8, C.green, 999, null); await button(f, 'Add another', 44, 512, 132, 40, 'secondary'); await button(f, 'Undo', 188, 512, 88, 40, 'secondary'); }\nasync function warningFrame() { const f = page.findOne((n) => n.name === '05 Wizard Warning'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await headerIcons(f); await progress(f, 2, 6, C.amber); await itemCard(f, 'fresh basil', '1 bunch'); await button(f, 'Skip', 24, 404, 332, 46, 'secondary'); rect(f, 'Automation warning', 24, 478, 332, 144, C.amberSoft, 16, '#F3D49A'); await text(f, 'Warning title', 'Automation is not working for this store', 44, 502, 15, C.amber, 'Bold'); const body = await text(f, 'Warning body', 'You can search and add manually on the store page, then continue to the next item.', 44, 530, 12, C.amber); body.resize(292, 42); await button(f, 'Skip, try next item', 44, 574, 168, 38, 'secondary'); await text(f, 'Report issue link', 'Report issue', 236, 584, 13, C.blue, 'Semi Bold'); }\nasync function doneFrame() { const f = page.findOne((n) => n.name === '06 Done'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await text(f, 'Done icon', '✓', 166, 92, 48, C.green, 'Bold'); const title = await text(f, 'Done title', 'All done!', 24, 164, 28, C.text, 'Bold'); title.resize(332, 36); title.textAlignHorizontal = 'CENTER'; const sub = await text(f, 'Done subtitle', 'Your cart is ready to review on the store site.', 44, 204, 14, C.muted); sub.resize(292, 40); sub.textAlignHorizontal = 'CENTER'; rect(f, 'Summary card', 24, 284, 332, 168, C.surface, 18, C.border); await text(f, 'Added count', '5', 58, 322, 30, C.green, 'Bold'); await text(f, 'Added label', 'items added to cart', 104, 330, 14, C.text, 'Semi Bold'); await text(f, 'Skipped count', '1', 58, 374, 24, C.amber, 'Bold'); await text(f, 'Skipped label', 'item skipped for revisit', 104, 380, 13, C.muted); await button(f, 'Revisit skipped items', 24, 548, 332, 44, 'secondary'); await button(f, 'New List', 24, 604, 332, 46, 'primary'); }\nasync function pantryFrame() { const f = page.findOne((n) => n.name === '07 Pantry'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; rect(f, 'Back icon', 24, 24, 32, 32, C.surface, 10, C.border); await text(f, 'Back glyph', '←', 35, 30, 16, C.muted); await text(f, 'Pantry title', 'Pantry', 68, 28, 22, C.text, 'Bold'); await text(f, 'Pantry subtitle', 'Items here are skipped automatically.', 24, 78, 13, C.muted); rect(f, 'Add pantry field', 24, 124, 236, 42, C.surface, 10, C.border); await text(f, 'Add pantry placeholder', 'e.g. salt', 40, 136, 14, C.muted); await button(f, 'Add', 272, 124, 84, 42, 'primary'); const rows = ['salt', 'black pepper', 'olive oil', 'plain flour']; for (let i = 0; i < rows.length; i++) { const y = 204 + i * 50; rect(f, `Pantry row / ${rows[i]}`, 24, y, 332, 42, C.surface, 10, C.border); await text(f, `Pantry item / ${rows[i]}`, rows[i], 42, y + 12, 14, C.text, 'Semi Bold'); await text(f, `Pantry remove / ${rows[i]}`, '×', 332, y + 10, 16, C.muted); } rect(f, 'Data card', 24, 470, 332, 154, C.surface, 16, C.border); await text(f, 'Data title', 'Local data', 44, 494, 15, C.text, 'Bold'); const data = await text(f, 'Data copy', 'Selection history is stored locally and powers last-time-you-picked hints.', 44, 522, 12, C.muted); data.resize(292, 42); await button(f, 'Clear selection history', 44, 574, 180, 38, 'secondary'); }\nasync function shortcutsFrame() { const f = page.findOne((n) => n.name === '08 Shortcuts Overlay'); f.fills = [{ type: 'SOLID', color: rgb(C.bg) }]; await headerIcons(f); await progress(f, 2, 6); await itemCard(f, 'chicken breast', '2x'); rect(f, 'Dim overlay', 0, 0, 380, 720, C.overlay, 0, null, 0.42); rect(f, 'Shortcuts modal', 36, 168, 308, 384, C.surface, 20, C.border); await text(f, 'Modal title', 'Keyboard shortcuts', 64, 198, 20, C.text, 'Bold'); const entries = [['S','Skip current item'], ['E','Edit search term'], ['Space / Enter','Advance during cooldown'], ['U','Undo during cooldown'], ['A','Add another during cooldown'], ['D','Dismiss during revisit'], ['R','Revisit skipped from done']]; for (let i = 0; i < entries.length; i++) { const y = 246 + i * 36; rect(f, `Key ${entries[i][0]}`, 64, y - 4, 86, 24, '#F0F0F0', 6, C.border); const k = await text(f, `Key label ${entries[i][0]}`, entries[i][0], 64, y, 11, C.text, 'Semi Bold'); k.resize(86, 16); k.textAlignHorizontal = 'CENTER'; await text(f, `Shortcut desc ${entries[i][0]}`, entries[i][1], 166, y, 12, C.text); } await button(f, 'Got it', 64, 496, 252, 40, 'primary'); }\nawait cooldownFrame();\nawait warningFrame();\nawait doneFrame();\nawait pantryFrame();\nawait shortcutsFrame();\nreturn { populated: ['04 Wizard Cooldown','05 Wizard Warning','06 Done','07 Pantry','08 Shortcuts Overlay'] };"
  }
}
```

Expected: The remaining frames show the required states and match the first three frames in color, spacing, and density.

- [ ] **Step 2: Verify the completed board visually**

Run this Figma tool call:

```json
{
  "tool": "figma_capture_screenshot",
  "arguments": {
    "format": "PNG",
    "scale": 1
  }
}
```

Expected: All eight frames are visible, readable, and use the same visual language. The shortcuts frame has a dimmed wizard background and a centered modal.

---

### Task 4: Final Verification and Handoff

**Files:**
- Read: `docs/superpowers/specs/2026-07-07-desktop-extension-figma-page-design.md`
- Verify: Figma page `Desktop Extension`

**Interfaces:**
- Consumes: All Figma frames from Tasks 1-3.
- Produces: Verified Figma page ready for user review.

- [ ] **Step 1: Inspect Figma page contents**

Run this Figma tool call:

```json
{
  "tool": "figma_get_file_data",
  "arguments": {
    "depth": 2,
    "verbosity": "summary"
  }
}
```

Expected: The response includes page `Desktop Extension` and all eight frame names from the spec.

- [ ] **Step 2: Capture a higher-scale board screenshot if the first capture is too compressed**

Run this Figma tool call:

```json
{
  "tool": "figma_capture_screenshot",
  "arguments": {
    "format": "PNG",
    "scale": 2
  }
}
```

Expected: The board screenshot remains within the tool's image-size limits and the individual frame content is easier to inspect.

- [ ] **Step 3: Compare against the spec**

Confirm these checks manually from screenshots and file data:

```text
Page named Desktop Extension exists: yes
01 Input exists: yes
02 Review exists: yes
03 Wizard exists: yes
04 Wizard Cooldown exists: yes
05 Wizard Warning exists: yes
06 Done exists: yes
07 Pantry exists: yes
08 Shortcuts Overlay exists: yes
Frame size is 380 x 720: yes for all frames
Mobile phone chrome is absent: yes
Store selector appears in Review: yes
Keyboard shortcut affordance appears in Wizard and Shortcuts Overlay: yes
Amber automation warning appears in Warning: yes
Green success treatment appears in Cooldown and Done: yes
Pantry/local-data controls appear in Pantry: yes
```

- [ ] **Step 4: Report completion to the user**

Use this response format:

```text
Created the Figma page `Desktop Extension` with eight side-panel frames: Input, Review, Wizard, Wizard Cooldown, Wizard Warning, Done, Pantry, and Shortcuts Overlay.

Verified with Figma page contents and screenshot capture. No extension code was changed.
```

---

## Self-Review

- Spec coverage: Tasks 1-4 cover the page name, all eight frames, side-panel dimensions, visual direction, screen-specific content, and verification.
- Placeholder scan: The plan contains no unresolved markers, incomplete task names, or open-ended implementation steps.
- Type consistency: The Figma page name, frame names, and dimensions are consistent across tasks.
