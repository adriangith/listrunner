# Your list scrolling performance

## Scope and diagnosis

The iPhone 17e reported sluggish vertical dragging on **Your list** after installing `2ab9f814a92f007f2ee950d4e95e95a92281cb75`. The screen continuously stored every visible grocery row's global position, even without an added-item reveal. It also updated editor/action geometry while unfocused, assigned a new cancellation UUID on every drag update, and invalidated the native text editor's intrinsic size on every representable update.

Repeated screen rendering additionally called `shoppingVisibleIDs(in:)` through screen state and row colours. That helper rebuilt shopping eligibility by fully validating each available store definition, including locale and regular-expression checks. A registry of 32 destinations made this avoidable work significant.

## Baseline measurement

A standalone Mac microbenchmark compiled against unchanged native source measured 20 samples after three warmups. This is **not an iPhone scrolling profile**, and eight accesses are a representative repeated-access scenario, not a measured per-frame call count.

- Debug (`-Onone`): one eligibility lookup, median **3.432 ms**; eight lookups **28.355 ms**; eight intersections against precomputed availability **0.005 ms**.
- Optimized (`-O`): one lookup, median **1.860 ms**; eight lookups **11.164 ms**; eight cached intersections **0.003 ms**.

The physical-device Time Profiler attempts failed to attach by name and by PID, although CoreDevice reported the running ListRunner process. No phone CPU trace, FPS or hitch-rate baseline was obtained. These numbers therefore support removing repeated validation but do not establish a quantified device-wide frame-rate improvement.

Benchmark source: `/tmp/opencode/listrunner-scroll-benchmark.swift`. Initial investigation: `/tmp/opencode/listrunner-scroll-investigation.md`.

A follow-up Debug run against the actual new `StoreShoppingAvailability.visibleIDs(in:)` helper measured **0.006 ms** for eight accesses. This was run while simulator tests were active; concurrent-load legacy timings are not used for a before/after speedup claim. It verifies the new hot-path projection is cheap, not an FPS result.

## Focused correction

Implementation `cf0c17d3ec588542b4054e70f254d4a72448d7a2`:

- `StoreSessions` creates a `StoreShoppingAvailability` snapshot for its immutable loaded registry. List rendering intersects that prevalidated ID set with the current enabled IDs; visibility and country preferences remain live. Replacement registries must create a new snapshot. Full configuration validation and native capability ceilings are unchanged; malformed configurations remain unavailable.
- Row geometry returns `nil` unless that exact row is the current reveal target. New submissions discard stale target frames. Idle scrolling does not store unrelated row positions.
- Editor/action geometry returns `nil` when input is not focused. The fixed viewport and Show Store inset still report layout/keyboard changes as required by reveal behaviour.
- A `GestureState` transition cancels reveal work once at the beginning of a manual drag, resets automatically when the gesture ends/cancels, and clears measured row frames. Cancelling an already-idle scroll task does not allocate a new request ID.
- The native editor invalidates intrinsic size only when its bound text changes; typing continues to invalidate through the native delegate. Placeholder updates request layout only when placeholder visibility or font changes.

There is no visual redesign, model migration, store/cart action, or change to ingredient parsing. OpenPencil was disconnected; existing layout, colours, row insets and control hit areas are retained.

## Regression coverage

Seven new standalone checks verify snapshot equivalence, current enabled-ID projection, independent registry replacement and malformed configuration refusal. A focused UI regression verifies that manual scrolling ends with no reveal target, no pending scroll and zero tracked row frames. Existing focused tests cover first-item/Return reveals, repeated additions, already-visible rows, growing entry fields and keyboard dismissal.

At the implementation revision, **1,701 native checks**, **313 DOM tests**, **3 expansion consistency tests** and **2 release-metadata tests** pass. Simulator UI and final installation outcomes are recorded in `packages/ios/VALIDATION.md` once available. The physical phone is not modified by isolated simulator UI tests.
