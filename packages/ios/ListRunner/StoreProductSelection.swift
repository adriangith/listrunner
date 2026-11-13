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

struct StoreProductAddLabel: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "text.badge.plus").font(.title2)
            Text("Add item to your list")
                .font(.caption).multilineTextAlignment(.center)
        }
        .frame(width: 88)
        .frame(minHeight: 88)
    }
}

struct StoreProductAddButton: View {
    let width: CGFloat
    let alignment: Alignment
    let insertion: ShoppingLists.AdditionPosition
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Clip the label inside the Button so its real hit/accessibility
            // bounds shrink too, not just a wrapper around an 88-point button.
            StoreProductAddLabel()
                .frame(width: width, alignment: alignment)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
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
    let alignment: Alignment
    let insertion: ShoppingLists.AdditionPosition
    let action: () -> Void

    private var opacity: Double {
        let fraction = min(1, max(0, Double(uncoveredWidth / 88)))
        return fraction * fraction
    }

    var body: some View {
        if uncoveredWidth >= 44 {
            StoreProductAddButton(width: uncoveredWidth, alignment: alignment, insertion: insertion, action: action)
                .opacity(opacity)
        } else if uncoveredWidth > 0 {
            // Keep the last sliver of the fade visual only. Fully covered
            // controls have no subtree, so no invisible AX button can survive.
            StoreProductAddLabel()
                .frame(width: uncoveredWidth, alignment: alignment)
                .clipped()
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

struct StoreProductRailEdges: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct StoreProductRailAddControls: View {
    let width: CGFloat
    let leadingEnd: CGFloat?
    let trailingStart: CGFloat?
    let action: (ShoppingLists.AdditionPosition) -> Void

    var body: some View {
        let inset = max(0, (width - 160) / 2 - 100)
        let leadingWidth = min(88, max(0, (leadingEnd ?? 0) - inset))
        let trailingWidth = min(88, max(0, width - inset - (trailingStart ?? width)))
        ZStack(alignment: .bottomLeading) {
            // Buttons stay fixed beneath the moving rail. Clip both rendering
            // and hit targets to the uncovered end slots, never over a card.
            StoreProductRailEndControl(uncoveredWidth: leadingWidth, alignment: .leading, insertion: .start) { action(.start) }
                .offset(x: inset)
            StoreProductRailEndControl(uncoveredWidth: trailingWidth, alignment: .trailing, insertion: .end) { action(.end) }
                .offset(x: width - inset - trailingWidth)
        }
        .frame(width: width, height: 222, alignment: .bottomLeading)
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
      } catch { finish(null); }
    });
    """#
}
