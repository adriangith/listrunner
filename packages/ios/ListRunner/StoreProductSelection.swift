import SwiftUI
import WebKit

struct StoreProductDraft: Identifiable {
    let id = UUID()
    let name: String
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

struct StoreProductAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: "text.badge.plus").font(.title2)
                Text("Add store item to list")
                    .font(.caption).multilineTextAlignment(.center)
            }
            .frame(width: 88)
            .frame(minHeight: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Add store item to list")
        .accessibilityHint("Choose a product from the current website. Does not change the store cart.")
        .accessibilityIdentifier("add-store-product")
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
    let action: () -> Void

    var body: some View {
        let inset = max(0, (width - 160) / 2 - 100)
        let leadingWidth = min(88, max(0, (leadingEnd ?? 0) - inset))
        let trailingWidth = min(88, max(0, width - inset - (trailingStart ?? width)))
        ZStack(alignment: .bottomLeading) {
            // Buttons stay fixed beneath the moving rail. Clip both rendering
            // and hit targets to the uncovered end slots, never over a card.
            StoreProductAddButton(action: action)
                .frame(width: leadingWidth, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(leadingWidth >= 44)
                .accessibilityHidden(leadingWidth < 44)
                .offset(x: inset)
            StoreProductAddButton(action: action)
                .frame(width: trailingWidth, alignment: .trailing)
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(trailingWidth >= 44)
                .accessibilityHidden(trailingWidth < 44)
                .offset(x: width - inset - trailingWidth)
        }
        .frame(width: width, height: 222, alignment: .bottomLeading)
    }
}

struct StoreProductReview: View {
    let storeName: String
    let initialName: String
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
            .navigationTitle("Add store item")
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
      let root = null, timer = null, done = false, shields = new Map();
      const startURL = location.href;
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      function finish(value) {
        if (done) return;
        done = true;
        clearInterval(timer);
        root?.remove();
        window.removeEventListener('pagehide', cancel);
        document.removeEventListener('visibilitychange', visibility);
        if (window.__listRunnerCancelProductSelection === cancel)
          delete window.__listRunnerCancelProductSelection;
        resolve(value);
      }
      function cancel() { finish(null); }
      function visibility() { if (document.visibilityState !== 'visible') cancel(); }
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
        root = document.createElement('div');
        root.style.cssText = 'all:initial!important;position:fixed!important;inset:0!important;z-index:2147483647!important;pointer-events:auto!important;touch-action:pan-y pinch-zoom!important;';
        // Shadow DOM avoids retailer CSS and keeps shields outside the product
        // subtree. Underlying links, buttons and their tile handlers are not hit.
        const shadow = root.attachShadow({mode:'closed'});
        document.body.appendChild(root);
        root.addEventListener('click', event => { event.preventDefault(); event.stopImmediatePropagation(); });
        function update() {
          if (done) return;
          if (location.href !== startURL || !root.isConnected || document.visibilityState !== 'visible') { cancel(); return; }
          const tiles = [...document.querySelectorAll(config.grid.containerSelector)];
          if (tiles.length > 200) { cancel(); return; }
          const retained = new Set();
          let recognised = 0;
          for (const tile of tiles) {
            const candidate = product(tile);
            if (!candidate) continue;
            recognised++;
            const box = tile.getBoundingClientRect();
            if (box.bottom <= 0 || box.top >= innerHeight || box.right <= 0 || box.left >= innerWidth) continue;
            retained.add(tile);
            const previous = shields.get(tile);
            if (previous && previous.productID === candidate.productID && previous.name === candidate.name) {
              Object.assign(previous.button.style, {left:`${box.left}px`, top:`${box.top}px`, width:`${box.width}px`, height:`${box.height}px`});
              previous.box = box;
              continue;
            }
            previous?.button.remove();
            const button = document.createElement('button');
            const entry = {...candidate, button, box};
            button.type = 'button';
            const label = document.createElement('span');
            label.textContent = chooseLabel;
            label.style.cssText = 'background:#1565c0;color:white;padding:8px 12px;border-radius:999px;box-shadow:0 2px 8px #0003;font:600 16px -apple-system,sans-serif;';
            button.appendChild(label);
            button.setAttribute('aria-label', `${chooseLabel}: ${candidate.name}`);
            button.style.cssText = `all:initial;box-sizing:border-box;position:fixed;left:${box.left}px;top:${box.top}px;width:${box.width}px;height:${box.height}px;border:3px solid #1976d2;border-radius:12px;background:#1976d21a;display:flex;align-items:center;justify-content:center;padding:8px;touch-action:pan-y pinch-zoom;`;
            button.addEventListener('click', event => {
              event.preventDefault(); event.stopImmediatePropagation();
              if (!event.isTrusted) { cancel(); return; }
              // Recycled grid nodes must still represent the exact same product.
              const current = location.href === startURL ? product(tile) : null;
              const rect = tile.getBoundingClientRect();
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
          }
          for (const [tile, entry] of shields) {
            if (!retained.has(tile)) { entry.button.remove(); shields.delete(tile); }
          }
          if (!recognised) { cancel(); }
        }
        window.addEventListener('pagehide', cancel);
        document.addEventListener('visibilitychange', visibility);
        let ticks = 0;
        timer = setInterval(() => {
          if (++ticks >= 600) cancel(); else { try { update(); } catch { cancel(); } }
        }, 100);
        update();
      } catch { finish(null); }
    });
    """#
}
