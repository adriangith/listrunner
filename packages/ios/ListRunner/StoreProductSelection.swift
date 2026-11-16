import SwiftUI
import WebKit

struct StoreProductDraft: Identifiable {
    let id = UUID()
    let name: String
    let insertion: ShoppingLists.AdditionPosition
}

enum StoreProductChoice {
    case cancelled, manual, product(String)
}

struct StoreProductSelectionBar: View {
    let onCancel: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Tap a highlighted product")
                .font(.headline)
            Text("Scroll to browse. Your store cart won’t change.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(action: onCancel) {
                    Text("Cancel").frame(minHeight: 44).contentShape(Rectangle())
                }
                Spacer()
                Button(action: onManual) {
                    Text("Enter manually").frame(minHeight: 44).contentShape(Rectangle())
                }
            }
            .frame(minHeight: 44)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-product-selection-bar")
    }
}

/// Pull-to-add: dragging a rail end past its resting edge arms Add, and lifting
/// the finger while armed starts it. Only a pull that begins with that end
/// already showing counts, so flicking through the cards never adds by accident.
enum StoreProductRailPull {
    /// Rubber-band overscroll (not finger travel) past the scroll view's edge.
    static let multiCardThreshold: CGFloat = 56
    /// Finger travel for the one-card rail, which has no native scroll range.
    /// Either direction arms the side it uncovers; well beyond the 64 pt side
    /// switch, so a moderate pull still only switches sides.
    static let singleCardThreshold: CGFloat = 120
    /// Pulling back this far below the threshold disarms; avoids flicker.
    static let disarmHysteresis: CGFloat = 8
    /// How close to an edge the rail must rest at touch-down to pull from it:
    /// any part of that end's Add label showing (the 88 pt slot) counts.
    static let edgeTolerance: CGFloat = 88

    /// Distances past each edge: positive when overscrolled, negative before it.
    static func overscroll(offset: CGFloat, viewport: CGFloat, content: CGFloat,
                           leadingInset: CGFloat, trailingInset: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let minOffset = -leadingInset
        let maxOffset = max(minOffset, content + trailingInset - viewport)
        return (minOffset - offset, offset - maxOffset)
    }

    /// Whether a pull of `distance` past one edge is armed, given its last state.
    static func isArmed(wasArmed: Bool, distance: CGFloat, threshold: CGFloat) -> Bool {
        distance >= threshold || (wasArmed && distance >= threshold - disarmHysteresis)
    }
}

/// Per-frame pull progress (0...1 of the threshold) for each rail end. Kept out
/// of StoreShoppingView's state, held there in @State (which does not observe
/// it), so only the end labels redraw while a finger drags.
final class StoreProductRailPullProgress: ObservableObject {
    @Published private(set) var leading: CGFloat = 0
    @Published private(set) var trailing: CGFloat = 0

    func update(leading: CGFloat, trailing: CGFloat) {
        // Quantize so a slow drag doesn't publish sub-pixel changes.
        let l = (min(1, max(0, leading)) * 50).rounded() / 50
        let t = (min(1, max(0, trailing)) * 50).rounded() / 50
        if l != self.leading { self.leading = l }
        if t != self.trailing { self.trailing = t }
    }

    func reset() { update(leading: 0, trailing: 0) }
}

struct StoreProductAddLabel: View {
    var armed = false
    /// How far toward the threshold a pull past this end is; 0 when not pulling.
    var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulling: Bool { progress > 0 && !armed }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                if pulling {
                    // Fills as the finger approaches the threshold; full means armed.
                    Circle().stroke(.secondary.opacity(0.3), lineWidth: 2.5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                } else if armed {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
            .frame(width: 28, height: 28)
            Text(armed ? "Release to add" : "Pull to add")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(armed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        // Blank at rest: the hint only appears as a pull begins, fully by a
        // third of the way to the threshold, and stays while armed.
        .opacity(armed ? 1 : Double(min(1, progress / 0.35)))
        .scaleEffect(armed && !reduceMotion ? 1.1 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.25, dampingFraction: 0.6), value: armed)
        // Weight the label toward the lower half of its slot without shifting
        // the button's bottom edge into the Back/Skip navigation row.
        .padding(.top, 24)
        .frame(width: 88)
        .frame(minHeight: 88)
    }
}

struct StoreProductAddButton: View {
    let width: CGFloat
    let insertion: ShoppingLists.AdditionPosition
    let action: () -> Void

    var body: some View {
        // Accessibility only: pull-to-add replaced the touch target, so a touch
        // here falls through to the rail and can start the pull. VoiceOver and
        // Switch Control still activate Add directly, since they cannot pull.
        Color.clear
            .frame(width: width, height: 88)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityLabel("Add item to your list")
        .accessibilityValue(insertion == .start ? Text("Start of list") : Text("End of list"))
        .accessibilityHint(insertion == .start
            ? Text("Choose a product to add to the start of your list. Does not change the store cart.")
            : Text("Choose a product to add to the end of your list. Does not change the store cart."))
        .accessibilityIdentifier("add-store-product")
    }
}

struct StoreProductRailEndControl: View {
    let uncoveredWidth: CGFloat
    let insertion: ShoppingLists.AdditionPosition
    let action: () -> Void

    var body: some View {
        if uncoveredWidth >= 44 {
            StoreProductAddButton(width: uncoveredWidth, insertion: insertion, action: action)
        }
    }
}

struct StoreProductRailEndLabel: View {
    let uncoveredWidth: CGFloat
    var armed = false
    var progress: CGFloat = 0

    private var opacity: Double {
        let fraction = min(1, max(0, Double(uncoveredWidth / 88)))
        return fraction * fraction
    }

    var body: some View {
        if uncoveredWidth > 0 {
            // No rectangular crop: the actual rounded card paints over this
            // full-width label. Fade remains proportional to real card coverage.
            StoreProductAddLabel(armed: armed, progress: progress)
                .opacity(opacity)
        }
    }
}

struct StoreProductRailLayout {
    let width: CGFloat
    let leadingCardMinX: CGFloat?
    let trailingCardMaxX: CGFloat?
    let isSingleCard: Bool

    var inset: CGFloat { max(0, (width - 160) / 2 - 100) }
    var leadingWidth: CGFloat { min(88, max(0, (leadingCardMinX ?? inset) - inset)) }
    var trailingWidth: CGFloat { min(88, max(0, width - inset - (trailingCardMaxX ?? (width - inset)))) }
}

enum StoreProductSingleCardReveal {
    static func position(horizontal: CGFloat, vertical: CGFloat) -> ShoppingLists.AdditionPosition? {
        guard abs(horizontal) >= 64, abs(horizontal) > abs(vertical) * 1.25 else { return nil }
        return horizontal > 0 ? .start : .end
    }

    static func pullValue(origin: CGFloat, horizontal: CGFloat) -> CGFloat {
        let distance = max(0, abs(horizontal) - 8)
        let change = (horizontal < 0 ? 1 : -1) * distance / 28
        return min(1, max(-1, origin + change))
    }

    static func displacement(horizontal: CGFloat) -> CGFloat {
        return 84 * horizontal / (abs(horizontal) + 84)
    }
}

struct StoreProductRailAddLabels: View, Animatable {
    let layout: StoreProductRailLayout
    var revealValue: CGFloat
    var armed: ShoppingLists.AdditionPosition? = nil
    @ObservedObject var pull: StoreProductRailPullProgress

    // Clamp spring overshoot while interpolating the signed fade-through-zero
    // value. Derive the side per frame, not from the final enum, to avoid a pop.
    var animatableData: CGFloat {
        get { revealValue }
        set { revealValue = min(1, max(-1, newValue)) }
    }

    private var leadingVisibility: Double { layout.isSingleCard ? Double(max(0, -revealValue)) : 1 }
    private var trailingVisibility: Double { layout.isSingleCard ? Double(max(0, revealValue)) : 1 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if leadingVisibility > 0 {
                StoreProductRailEndLabel(uncoveredWidth: layout.leadingWidth, armed: armed == .start,
                                         progress: pull.leading)
                    .opacity(leadingVisibility)
                    .offset(x: layout.inset)
            }
            if trailingVisibility > 0 {
                StoreProductRailEndLabel(uncoveredWidth: layout.trailingWidth, armed: armed == .end,
                                         progress: pull.trailing)
                    .opacity(trailingVisibility)
                    .offset(x: layout.width - layout.inset - 88)
            }
        }
        .frame(width: layout.width, height: 222, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct StoreProductRailEdges: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct StoreProductRailAddControls: View, Animatable {
    let layout: StoreProductRailLayout
    var revealValue: CGFloat
    let action: (ShoppingLists.AdditionPosition) -> Void

    var animatableData: CGFloat {
        get { revealValue }
        set { revealValue = min(1, max(-1, newValue)) }
    }

    private var leadingVisibility: CGFloat { layout.isSingleCard ? max(0, -revealValue) : 1 }
    private var trailingVisibility: CGFloat { layout.isSingleCard ? max(0, revealValue) : 1 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Only the transparent hit regions sit above the rail. They end at
            // the actual card bounds, so none of a card becomes an Add target.
            if leadingVisibility >= 0.5 {
                StoreProductRailEndControl(uncoveredWidth: layout.leadingWidth, insertion: .start) { action(.start) }
                    .offset(x: layout.inset)
            }
            if trailingVisibility >= 0.5 {
                StoreProductRailEndControl(uncoveredWidth: layout.trailingWidth, insertion: .end) { action(.end) }
                    .offset(x: layout.width - layout.inset - layout.trailingWidth)
            }
        }
        .frame(width: layout.width, height: 222, alignment: .bottomLeading)
    }
}

struct StoreProductReview: View {
    let storeName: String
    let initialName: String
    let insertion: ShoppingLists.AdditionPosition
    let onAdd: (String, Int) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var saveFailed = false
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product name", text: $name, axis: .vertical)
                        .accessibilityIdentifier("store-product-name")
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    LabeledContent("Position") {
                        insertion == .start ? Text("Start of list") : Text("End of list")
                    }
                    .accessibilityIdentifier("store-product-insertion")
                } header: {
                    Text("Add to \(storeName)")
                } footer: {
                    Text("Adds a Pending item to your ListRunner list only. The store cart is unchanged.")
                }
                if initialName.isEmpty {
                    Text("Could not read a product on this page. Enter its name to add it manually.")
                        .foregroundStyle(.secondary)
                }
                if saveFailed {
                    Text("Could not save this item. Your draft is still here. Retry after resolving any pending list changes.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("store-product-save-error")
                }
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !submitting else { return }
                        submitting = true
                        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onAdd(title, quantity) { dismiss() }
                        else {
                            saveFailed = true
                            submitting = false
                        }
                    }
                    .disabled(submitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.utf8.count > 512)
                    .accessibilityIdentifier("confirm-store-product")
                }
            }
            .onAppear { name = initialName }
        }
    }
}

enum StoreProductSelection {
    // Executed only on explicit Add, in the isolated automation world. No store
    // events are replayed, no private state is read, and no URLs are persisted.
    static let script = #"""
    window.__listRunnerCancelProductSelection?.();
    return await new Promise(resolve => {
      let root = null, deadline = null, frame = null, done = false, needsDiscovery = false;
      let mutations = null, sizes = null;
      let update = null, reposition = null;
      const shields = new Map(), observed = new Set();
      // Entrance only: the first batch staggers top-to-bottom, later shields
      // (scroll/infinite load) just fade in. Never affects hit testing or
      // positioning; skipped where Web Animations are unavailable.
      const reduceMotion = !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      let firstBatch = true, staggered = 0;
      function reveal(button, label) {
        if (typeof button.animate !== 'function') return;
        if (reduceMotion) {
          button.animate([{opacity: 0}, {opacity: 1}], {duration: 150, easing: 'ease-out', fill: 'backwards'});
          return;
        }
        const delay = firstBatch ? Math.min(staggered++ * 40, 320) : 0;
        button.animate([{opacity: 0, transform: 'scale(0.94)'}, {opacity: 1, transform: 'scale(1)'}],
          {duration: 280, delay, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)', fill: 'backwards'});
        label.animate([{opacity: 0, transform: 'translateY(8px) scale(0.85)'}, {opacity: 1, transform: 'none'}],
          {duration: 360, delay: delay + 80, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)', fill: 'backwards'});
      }
      const startURL = location.href;
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      function finish(value) {
        if (done) return;
        done = true;
        clearTimeout(deadline);
        if (frame !== null) cancelAnimationFrame(frame);
        mutations?.disconnect(); sizes?.disconnect();
        root?.remove();
        window.removeEventListener('pagehide', cancel);
        window.removeEventListener('resize', changed);
        document.removeEventListener('scroll', scrolled, true);
        document.removeEventListener('load', changed, true);
        document.fonts?.removeEventListener('loadingdone', changed);
        document.removeEventListener('visibilitychange', visibility);
        if (window.__listRunnerCancelProductSelection === cancel) {
          delete window.__listRunnerCancelProductSelection;
          delete window.__listRunnerProductSelectionID;
        }
        resolve(value);
      }
      function cancel() { finish(null); }
      function visibility() { if (document.visibilityState !== 'visible') cancel(); }
      function changed() { schedule(true); }
      function scrolled() { schedule(false); }
      function schedule(discover) {
        if (done) return;
        needsDiscovery = needsDiscovery || discover;
        if (frame !== null) return;
        frame = requestAnimationFrame(() => {
          frame = null;
          const discover = needsDiscovery;
          needsDiscovery = false;
          try { if (discover) update(); else reposition(); } catch { cancel(); }
        });
      }
      window.__listRunnerCancelProductSelection = cancel;
      window.__listRunnerProductSelectionID = requestID;
      function visible(node) {
        if (!node?.isConnected || !node.getClientRects().length) return false;
        const box = node.getBoundingClientRect(), style = getComputedStyle(node);
        return box.width > 0 && box.height > 0 && style.visibility === 'visible' &&
          style.display !== 'none' && style.opacity !== '0' && !node.closest('[hidden], [inert], [aria-hidden="true"]');
      }
      function identity(raw) {
        try {
          const url = new URL(raw, startURL);
          if (url.protocol !== 'https:' || url.username || url.password ||
              (url.port && url.port !== '443') || !hosts.includes(url.hostname) ||
              (pathPrefix && !url.pathname.startsWith(pathPrefix))) return null;
          const match = url.pathname.match(new RegExp(config.productURLPattern));
          return match?.[1] ? match[1] : null;
        } catch { return null; }
      }
      function title(container, selector) {
        const names = [...container.querySelectorAll(selector)].filter(visible)
          .map(node => clean(node.innerText)).filter(Boolean);
        const unique = [...new Set(names)];
        return unique.length === 1 && unique[0].length <= 256 ? unique[0] : null;
      }
      function product(tile) {
        if (!visible(tile)) return null;
        const links = [...tile.querySelectorAll(config.grid.linkSelector)].filter(visible);
        const ids = [...new Set(links.map(link => identity(link.href)).filter(Boolean))];
        const name = title(tile, config.grid.titleSelector);
        return ids.length === 1 && name ? {name, productID: ids[0]} : null;
      }
      try {
        if (!config || document.visibilityState !== 'visible' || !document.body) { finish(null); return; }
        if ([...document.querySelectorAll('[role="dialog"][aria-modal="true"]')].some(visible)) { finish(null); return; }
        // A product URL plus one visible dedicated heading is required. Never
        // choose a recommendation tile instead of the main product automatically.
        if (identity(startURL)) {
          const details = [...document.querySelectorAll(config.detail.containerSelector)].filter(visible);
          const names = details.map(node => title(node, config.detail.titleSelector)).filter(Boolean);
          if (details.length === 1 && names.length === 1) {
            finish({name: names[0], productID: identity(startURL)}); return;
          }
          finish(null); return;
        }
        // Assistive activation can target a covered website control directly,
        // bypassing visual hit testing. Use the native manual composer on grids
        // until a dedicated accessible website-selection mode is verified.
        if (!allowGrid) { finish(null); return; }
        if (typeof MutationObserver !== 'function' || typeof ResizeObserver !== 'function') { finish(null); return; }
        root = document.createElement('div');
        root.style.cssText = 'all:initial!important;position:absolute!important;left:0!important;top:0!important;width:0!important;height:0!important;overflow:visible!important;z-index:2147483647!important;pointer-events:none!important;';
        // Shadow DOM avoids retailer CSS and keeps shields outside the product
        // subtree. Underlying links, buttons and their tile handlers are not hit.
        const shadow = root.attachShadow({mode:'closed'});
        document.body.appendChild(root);
        // Only the transparent tap-blocker is viewport-fixed. Product shields
        // live in the document's scrolling plane, so WebKit scrolls them with
        // their products even when JavaScript is busy or paused during a fling.
        const blocker = document.createElement('div');
        blocker.style.cssText = 'all:initial;position:fixed;inset:0;z-index:0;pointer-events:auto;touch-action:pan-y pinch-zoom;';
        blocker.setAttribute('aria-hidden', 'true');
        shadow.appendChild(blocker);
        root.addEventListener('click', event => { event.preventDefault(); event.stopImmediatePropagation(); });
        function current() {
          if (done) return false;
          if (location.href !== startURL || !root.isConnected || document.visibilityState !== 'visible') { cancel(); return false; }
          return true;
        }
        function documentBox(tile) {
          const box = tile.getBoundingClientRect(), origin = root.getBoundingClientRect();
          // Subtract this actual containing-block origin, not an assumed body
          // origin. Page margins and positioned body elements remain correct.
          return {left: box.left - origin.left, top: box.top - origin.top, width: box.width, height: box.height};
        }
        function position(entry) {
          const box = documentBox(entry.tile);
          for (const key of ['left', 'top', 'width', 'height']) {
            if (!entry.box || Math.abs(box[key] - entry.box[key]) > 0.01)
              entry.button.style[key] = `${box[key]}px`;
          }
          entry.box = box;
        }
        reposition = () => {
          if (!current()) return;
          for (const entry of shields.values()) {
            if (!visible(entry.tile)) { schedule(true); continue; }
            position(entry);
          }
        };
        update = () => {
          if (!current()) return;
          const tiles = [...document.querySelectorAll(config.grid.containerSelector)];
          if (tiles.length > 200) { cancel(); return; }
          const retained = new Set();
          let recognised = 0;
          for (const tile of tiles) {
            const candidate = product(tile);
            if (!candidate) continue;
            recognised++;
            retained.add(tile);
            const previous = shields.get(tile);
            if (previous && previous.productID === candidate.productID && previous.name === candidate.name) {
              position(previous);
              continue;
            }
            previous?.button.remove();
            const button = document.createElement('button');
            const entry = {...candidate, tile, button, box: null};
            button.type = 'button';
            const label = document.createElement('span');
            label.textContent = chooseLabel;
            label.style.cssText = 'background:#1565c0;color:white;padding:8px 12px;border-radius:999px;box-shadow:0 2px 8px #0003;font:600 16px -apple-system,sans-serif;';
            button.appendChild(label);
            button.setAttribute('aria-label', `${chooseLabel}: ${candidate.name}`);
            button.style.cssText = 'all:initial;box-sizing:border-box;position:absolute;z-index:1;pointer-events:auto;border:3px solid #1976d2;border-radius:12px;background:#1976d21a;display:flex;align-items:center;justify-content:center;padding:8px;touch-action:pan-y pinch-zoom;';
            button.addEventListener('click', event => {
              event.preventDefault(); event.stopImmediatePropagation();
              if (!event.isTrusted) { cancel(); return; }
              // Recycled grid nodes must still represent the exact same product.
              const current = location.href === startURL ? product(tile) : null;
              const rect = documentBox(tile);
              const aligned = ['left','top','width','height'].every(key => Math.abs(rect[key] - entry.box[key]) < 2);
              root.style.setProperty('display', 'none', 'important');
              const hit = event.detail === 0 || tile.contains(document.elementFromPoint(event.clientX, event.clientY));
              root.style.removeProperty('display');
              if (hit && aligned && current?.productID === candidate.productID && current?.name === candidate.name) {
                // Absorb the complete tap before removing the blocking layer.
                finish(current);
              } else { cancel(); }
            });
            shadow.appendChild(button); shields.set(tile, entry);
            position(entry);
            reveal(button, label);
            if (!observed.has(tile)) { sizes.observe(tile); observed.add(tile); }
          }
          for (const [tile, entry] of shields) {
            if (!retained.has(tile)) {
              entry.button.remove(); shields.delete(tile);
              sizes.unobserve(tile); observed.delete(tile);
            }
          }
          if (!recognised) { cancel(); }
        };
        window.addEventListener('pagehide', cancel);
        window.addEventListener('resize', changed);
        document.addEventListener('scroll', scrolled, {capture: true, passive: true});
        document.addEventListener('load', changed, true);
        document.fonts?.addEventListener('loadingdone', changed);
        document.addEventListener('visibilitychange', visibility);
        sizes = new ResizeObserver(() => schedule(true));
        sizes.observe(document.documentElement); sizes.observe(document.body);
        mutations = new MutationObserver(records => {
          if (records.some(record => record.target !== root && !root.contains(record.target))) schedule(true);
        });
        mutations.observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true});
        // A deadline bounds the mode; it never drives product positioning.
        deadline = setTimeout(cancel, 60_000);
        update();
        firstBatch = false;
      } catch { finish(null); }
    });
    """#
}
