import SwiftUI
import UIKit
import WebKit
import OSLog

struct StoreShoppingView: View {
    // The controls and card carousel retain their existing geometry. Only the
    // material surface is shorter, so selected cards continue to overlap it at
    // exactly the same position.
    private static let expandedPanelSurfaceHeight: CGFloat = 180

    let items: [GroceryItem]
    @ObservedObject var browser: StoreBrowser
    let initialSelectedID: UUID?
    let saveFailed: Bool
    let onSelectionChange: (UUID) -> Void
    let onStatusChange: (GroceryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: UUID?
    @State private var selectionHistory: [UUID] = []
    @State private var isCollapsed = false
    @State private var entranceNudge: CGFloat = 0
    @State private var pressedCardID: UUID?
    @State private var secondsRemaining = 0
    @State private var didRunPreloadTestFixture = false
    @State private var undoRecord: (id: UUID, previous: GroceryStatus, cartAdd: StoreBrowser.CartAddRecord?)?
    @State private var task: Task<Void, Never>?
    @State private var manuallyPaused = false
    @State private var navigationRightActionEdge: CGFloat = 0
    @State private var showingVerificationDetails = false
    @State private var showingCartDetectionDetails = false
    @GestureState private var isTouchingOverlay = false
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.4, dampingFraction: 0.86)))
    private var overlayDrag = OverlayDrag()

    private struct OverlayDrag {
        enum Axis { case undecided, horizontal, vertical }
        var axis: Axis = .undecided
        var distance: CGFloat = 0
    }

    private struct NavigationRightActionEdgeKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct NavigationRightActionEdgeReporter: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NavigationRightActionEdgeKey.self,
                    value: proxy.frame(in: .named("store-navigation-controls")).maxX
                )
            }
        }
    }

    init(items: [GroceryItem], browser: StoreBrowser, initialSelectedID: UUID?, saveFailed: Bool = false, onSelectionChange: @escaping (UUID) -> Void, onStatusChange: @escaping (GroceryItem) -> Void) {
        self.items = items
        self.browser = browser
        self.initialSelectedID = initialSelectedID
        self.saveFailed = saveFailed
        self.onSelectionChange = onSelectionChange
        self.onStatusChange = onStatusChange
        _selectedID = State(initialValue: initialSelectedID)
    }

    private var selected: GroceryItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }
    private var pending: [GroceryItem] { items.filter { $0.status == .pending } }
    private var isFinalConfirmation: Bool { pending.isEmpty && undoRecord != nil }
    private var collapseProgress: CGFloat {
        isCollapsed ? 1 : min(max(overlayDrag.distance, 0) / 240, 1)
    }
    private var upwardOverlayPull: CGFloat {
        guard !isCollapsed, !reduceMotion else { return 0 }
        let pull = max(-overlayDrag.distance, 0)
        // Rubber-band resistance approaches an 80 pt limit rather than following
        // the finger indefinitely. GestureState's reset spring restores zero.
        return 80 * pull / (pull + 180)
    }
    private var overlayAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.86)
    }
    private var addedStatusAccent: Color {
        browser.addedStatusGradient.first ?? Color(red: 0.09, green: 0.36, blue: 0.80)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
            if let preload = browser.preloadWebView {
                PreloadedStoreWebView(webView: preload)
                    .id(ObjectIdentifier(preload))
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            #if DEBUG
            if browser.isStoreResumeTestFixture {
                Text(browser.storeResumeTestStatus)
                    .accessibilityIdentifier("store-resume-test-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            if browser.isResultsScrollLiveProbe {
                Text(browser.resultsScrollProbeStatus)
                    .accessibilityIdentifier("results-scroll-probe-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            if browser.isRegionalSearchTestFixture {
                Text(browser.regionalSearchTestStatus)
                    .accessibilityIdentifier("regional-search-test-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            if browser.isIdleRecoveryTestFixture {
                Text(browser.idleRecoveryTestStatus)
                    .accessibilityIdentifier("idle-recovery-test-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            if ProcessInfo.processInfo.environment["LISTRUNNER_PRELOAD_TEST_FIXTURE"] == "enabled" {
                Text(browser.preloadDebugStatus)
                    .accessibilityIdentifier("preload-debug-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            #endif

            StoreWebView(browser: browser, bottomOverlayInset: 0)
                .id(ObjectIdentifier(browser.webView))
                .ignoresSafeArea(edges: .top)
                .opacity(browser.storeRecovery == .processTerminated ? 0 : 1)
                // Reserve layout space for the collapsed bar instead of drawing
                // it over the retailer's page. This keeps fixed website actions
                // (such as checkout confirmation buttons) fully reachable.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    collapsedBar(bottomSafeAreaInset: geometry.safeAreaInsets.bottom)
                        .opacity(isCollapsed ? 1 : 0)
                        .allowsHitTesting(isCollapsed)
                        .accessibilityHidden(!isCollapsed)
                        .frame(height: isCollapsed ? 70 : 0)
                }

            VStack(spacing: 0) {
                Capsule().fill(.secondary.opacity(0.65)).frame(width: 42, height: 5)
                    .padding(.top, 10).padding(.bottom, 9)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissStore() }
                    .accessibilityElement()
                    .accessibilityLabel("Dismiss store")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { dismissStore() }
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.height > 24 { dismissStore() }
                    })

                Spacer(minLength: 0)
                if saveFailed { PersistenceWarning().padding(.horizontal, 20) }
                if browser.cartUndoWarning {
                    CartUndoWarning(storeName: browser.store.displayName) { browser.dismissCartUndoWarning() }
                        .padding(.horizontal, 20)
                }
                if browser.store.cart?.strategy == .verifiedCartSnapshot && browser.cartUndoInProgress {
                    ProgressView("Undoing store cart change…")
                        .font(.caption)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("store-cart-undo-progress")
                }
                ZStack(alignment: .bottom) {
                    expandedPanel(bottomSafeAreaInset: geometry.safeAreaInsets.bottom)
                        .offset(y: reduceMotion ? 0 : 250 * collapseProgress)
                        .offset(y: entranceNudge)
                        .opacity(1 - collapseProgress)
                        .allowsHitTesting(!isCollapsed)
                        .accessibilityHidden(isCollapsed)
                }
                .frame(height: isCollapsed ? 0 : 330, alignment: .bottom)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .interactiveDismissDisabled(isTouchingOverlay)
            .confirmationDialog("\(browser.store.displayName) has paused browsing", isPresented: $showingVerificationDetails,
                                titleVisibility: .visible) {
                Button("Retry store page", action: browser.retryAfterVerification)
                    .disabled(!browser.canRetryAfterVerification)
                Button("Return to List", action: dismissStore)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The store is checking this browser. Searches are paused. Complete any verification shown on the page, or wait before retrying. Repeated refreshes may extend the block.")
            }
            .alert(browser.cartDetectionTitle, isPresented: $showingCartDetectionDetails) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(browser.cartDetectionExplanation + " You can still add the product on the store page, then use Mark Added in ListRunner. This changes ListRunner's status only; it does not change the store cart.")
            }
            .onAppear {
            browser.setBrowsingActive(scenePhase == .active)
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
            if let selected {
                browser.resumeInteraction(itemID: selected.id, searchTerm: selected.searchTerm)
            } else {
                browser.loadIfNeeded()
            }
            #if DEBUG
            if !didRunPreloadTestFixture,
               ProcessInfo.processInfo.environment["LISTRUNNER_PRELOAD_TEST_FIXTURE"] == "enabled",
               let item = selected {
                didRunPreloadTestFixture = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard selectedID == item.id, item.status == .pending else { return }
                    confirmAutomaticAdd(item)
                }
            }
            #endif
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["LISTRUNNER_STORE_RESUME_TEST_FIXTURE"] == "checks" {
                    await browser.runStoreResumeTestChecks()
                }
                if browser.isResultsScrollLiveProbe {
                    await browser.runResultsScrollLiveProbe()
                }
                if browser.isIdleRecoveryTestFixture {
                    await browser.runIdleRecoveryTestChecks()
                }
                if ProcessInfo.processInfo.environment["LISTRUNNER_REGIONAL_SEARCH_TEST_FIXTURE"] == "checks" {
                    await browser.runRegionalSearchTestChecks()
                }
                #endif
                // Wait until the presentation transition has settled so the
                // entrance cue reads as an intentional gesture hint.
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, !isCollapsed else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { entranceNudge = 24 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.72, dampingFraction: 0.48)) {
                    entranceNudge = 0
                }
            }
            .onChange(of: browser.detectedAddSequence) { _, _ in
            guard let id = browser.lastDetectedItemID,
                  let item = items.first(where: { $0.id == id }) else { return }
            confirmAutomaticAdd(item)
            }
            .onChange(of: browser.storeRecovery) { _, recovery in
            guard recovery != nil else { return }
            task?.cancel()
            secondsRemaining = 0
            manuallyPaused = false
            if !isFinalConfirmation { undoRecord = nil }
            }
            .onChange(of: browser.siteVerificationRequired) { _, blocked in
                guard blocked else { return }
                task?.cancel()
                secondsRemaining = 0
                manuallyPaused = false
                if !isFinalConfirmation { undoRecord = nil }
            }
            .onChange(of: scenePhase) { _, phase in
            browser.setBrowsingActive(phase == .active)
            if phase == .active {
                if let selected {
                    browser.resumeInteraction(itemID: selected.id, searchTerm: selected.searchTerm)
                } else {
                    browser.loadIfNeeded()
                }
            } else {
                task?.cancel()
                secondsRemaining = 0
                manuallyPaused = false
                if !isFinalConfirmation { undoRecord = nil }
                browser.endInteraction()
            }
            }
            .alert("Could not load \(browser.store.displayName)", isPresented: Binding(get: { browser.storeRecovery != nil }, set: { _ in })) {
            Button("Retry") { browser.retryStoreLoad() }
            Button("Return to List", role: .cancel) {
                browser.leaveStoreRecovery()
                dismissStore()
            }
            } message: {
            Text("Your shopping run is safe. Try again or return to your list.")
            }
            .onDisappear {
            browser.setBrowsingActive(false)
            task?.cancel()
            browser.endInteraction()
            browser.dismissCartUndoWarning()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func expandedPanel(bottomSafeAreaInset: CGFloat) -> some View {
        // The reference design keeps its original card/control geometry while
        // using a shorter 180 pt visible panel with a larger card overhang.
        // Keep the cards in a sibling layer, rather than shifting content outside
        // its own layout region, so the overhang remains visible and tappable.
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                navigationControls
            }
            .frame(height: 220)
            .offset(y: -upwardOverlayPull)
            .contentShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))

            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(items) { item in
                                card(item)
                                    .id(item.id)
                            }
                        }
                        // Allow even the first and last selected cards to sit centrally.
                        .padding(.horizontal, max(0, (geometry.size.width - 160) / 2))
                        .padding(.top, 5)
                        .padding(.bottom, 14)
                    }
                    // Cards intentionally overlap the panel edge; let their shadows
                    // render over the panel instead of clipping at the scroll viewport.
                    .scrollClipDisabled()
                    .scrollDisabled(overlayDrag.axis == .vertical)
                    .onAppear {
                        if let id = selected?.id { scrollProxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id {
                            withAnimation(overlayAnimation) {
                                scrollProxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)
            .contentShape(Rectangle())
            // Keep only a small breathing gap above the navigation controls.
            // The previous 80 pt spacer left the cards visually detached from
            // the controls on shorter phones.
            .padding(.bottom, 56)
            // A subtle depth cue: the cards travel slightly farther than the
            // panel while collapsing, without changing their resting position.
            .offset(y: (reduceMotion ? 0 : 90 * collapseProgress) - upwardOverlayPull)
        }
        .frame(height: 330)
        .background(alignment: .bottom) {
            // Own the entire screen-facing surface at the expanded overlay level,
            // matching the collapsed bar. Its top remains fixed while its bottom
            // reaches the physical screen edge through the safe area.
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(.regularMaterial)
                .frame(height: Self.expandedPanelSurfaceHeight + bottomSafeAreaInset)
                .offset(y: bottomSafeAreaInset)
        }
        .simultaneousGesture(collapseDragGesture)
    }

    private var collapseDragGesture: some Gesture {
        // The panel itself moves while dragging. Local coordinates would feed
        // that movement back into translation and make slow drags oscillate.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouchingOverlay) { _, touching, _ in touching = true }
            .updating($overlayDrag) { value, drag, transaction in
                // Follow the finger directly; animate only the release/snap.
                transaction.animation = nil
                let translation = value.translation
                // Choose once, after a small movement threshold. Do not switch
                // back to card scrolling if the finger drifts sideways mid-collapse.
                if drag.axis == .undecided,
                   max(abs(translation.width), abs(translation.height)) >= 8 {
                    drag.axis = abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
                }
                if drag.axis == .vertical {
                    drag.distance = translation.height
                }
            }
            .onEnded { value in
                // SwiftUI can reset GestureState before delivering onEnded.
                let vertical = overlayDrag.axis == .vertical
                    || (overlayDrag.axis == .undecided && value.translation.height > abs(value.translation.width))
                if vertical,
                   value.translation.height > 12,
                   (value.translation.height > 80 || value.predictedEndTranslation.height > 160) {
                    collapse()
                }
            }
    }

    private var navigationControls: some View {
        ZStack(alignment: .trailing) {
            // Preserve the original three-column control geometry. The reload
            // control is intentionally an overlay so it never displaces Back,
            // the centre status, or the current right-hand action.
            HStack(spacing: 4) {
                if secondsRemaining > 0 || isFinalConfirmation || manuallyPaused, undoRecord != nil {
                    Button("Undo", action: undo)
                        .navigationButtonStyle()
                        .accessibilityHint(browser.store.capabilities.cartUndo
                            ? "Restores the ListRunner item and attempts a verified store cart reversal when available."
                            : "Restores the ListRunner item only. Does not change the \(browser.store.displayName) cart.")
                } else {
                    Button(action: selectPrevious) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .navigationButtonStyle()
                    .disabled(!selectionHistory.contains(where: { id in items.contains(where: { $0.id == id }) }))
                }

                if browser.siteVerificationRequired {
                    Button { showingVerificationDetails = true } label: {
                        VStack(spacing: 3) {
                            Label("Browsing paused", systemImage: "exclamationmark.triangle")
                            Text("Tap for details").font(.caption2)
                        }
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: 112, height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("store-verification-notice")
                    .accessibilityLabel("\(browser.store.displayName) browsing paused")
                    .accessibilityHint("Shows why browsing is paused and recovery options")
                } else {
                if browser.cartDetectionUnavailable {
                    Button { showingCartDetectionDetails = true } label: {
                        VStack(spacing: 3) {
                            Label(browser.searchUnavailable && !browser.searchNotIncluded ? "Automation unavailable" : browser.cartDetectionTitle,
                                   systemImage: browser.cartDetectionNotIncluded ? "info.circle" : "exclamationmark.triangle")
                            Text("Tap for details").font(.caption2)
                        }
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: 112, height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cart-detection-notice")
                    .accessibilityHint("Explains automatic cart detection support and how to continue manually")
                } else {
                VStack(spacing: 3) {
                    if isFinalConfirmation { Text("Final item") }
                    else if secondsRemaining > 0 { Text("Next in \(secondsRemaining)s") }
                    else if manuallyPaused { Text("Paused · Next when ready") }
                    else if browser.searchUnavailable {
                        Label("Search unavailable", systemImage: "exclamationmark.triangle")
                    }
                    else { Text("Swipe cards to browse") }
                    if browser.searchUnavailable { Text("Search manually in \(browser.store.displayName)").font(.caption2) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 112, height: 48)
                .accessibilityElement(children: .combine)
                }
                }

                if isFinalConfirmation {
                    Button("Finish", action: finish)
                        .navigationButtonStyle(prominent: true)
                        .background(NavigationRightActionEdgeReporter())
                } else if pending.isEmpty {
                    VStack(spacing: 2) {
                        Text("All items handled").font(.caption.weight(.semibold))
                        Text("Continue to checkout when ready.").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 140, height: 48)
                    .background(NavigationRightActionEdgeReporter())
                } else if selected?.status == .pending {
                    Button("Skip", action: skip)
                        .navigationButtonStyle()
                        .background(NavigationRightActionEdgeReporter())
                } else {
                    Button("Next", action: next)
                        .navigationButtonStyle(prominent: true)
                        .disabled(pending.isEmpty)
                        .background(NavigationRightActionEdgeReporter())
                }
            }
            .frame(maxWidth: .infinity)

            GeometryReader { proxy in
                // This is the midpoint of the actual blank trailing area, so
                // it remains correctly placed as Skip changes to Next, Finish,
                // or the checkout message without moving those controls.
                if navigationRightActionEdge > 0, (!pending.isEmpty || isFinalConfirmation) {
                    Button { browser.reloadSearch(for: selected?.searchTerm) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reload product search")
                    .accessibilityHint("Returns to this item's original \(browser.store.displayName) search without changing its ListRunner status")
                    // Optical centring needs a small left correction because the
                    // trailing edge has more visual weight than the glyph.
                    .position(x: max(22, (navigationRightActionEdge + proxy.size.width) / 2 - 10),
                              y: proxy.size.height / 2)
                }
            }
        }
        // GeometryReader is used only to position the independent reload glyph.
        // Pin this container to the original control-row height so it cannot
        // consume the panel's flexible space or move behind the cards.
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .coordinateSpace(name: "store-navigation-controls")
        .onPreferenceChange(NavigationRightActionEdgeKey.self) { navigationRightActionEdge = $0 }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    private func collapsedBar(bottomSafeAreaInset: CGFloat) -> some View {
        Button {
            withAnimation(overlayAnimation) { isCollapsed = false }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.up")
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected?.name ?? "Shopping").font(.headline)
                    Text("\(selected?.displayQuantity ?? "") · \(selected?.status.rawValue ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if secondsRemaining > 0 {
                        Label("Next in \(secondsRemaining)s", systemImage: "timer")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("Expand overlay")
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 70)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
                    .frame(height: 70 + bottomSafeAreaInset)
                    .offset(y: bottomSafeAreaInset)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let vertical = abs(value.translation.height) > abs(value.translation.width)
                    guard vertical, value.translation.height < -32 else { return }
                    withAnimation(overlayAnimation) { isCollapsed = false }
                }
        )
        .accessibilityLabel("\(selected?.name ?? "Selected item")\(secondsRemaining > 0 ? ", next item in \(secondsRemaining) seconds" : ""), Expand overlay")
        .accessibilityHint("Shows shopping controls")
    }

    private func card(_ item: GroceryItem) -> some View {
        let current = item.id == selectedID
        let position = (items.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(item.status.rawValue.uppercased())
                    .font(.system(size: current ? 10 : 11, weight: .bold))
                    .opacity(current ? 0.85 : 1)
                if current {
                    Spacer(minLength: 0)
                    Button(action: collapse) {
                        HStack(spacing: 4) {
                            Text("\(position) / \(items.count)")
                                .font(.system(size: 12))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse overlay")
                    .accessibilityValue("Item \(position) of \(items.count)")
                    .accessibilityHint("Hides shopping controls and shows the compact bar")
                }
            }
            .frame(height: current ? 15 : 13)
            .padding(.bottom, 5)
            Button { select(item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sentenceCase(item.name))
                        .font(.system(size: current ? 26 : 17, weight: current ? .bold : .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    QuantityMarquee(
                        text: "Quantity · \(item.displayQuantity)",
                        shouldScroll: current && !reduceMotion,
                        fontSize: current ? 15 : 13,
                        color: UIColor(cardForeground(item.status, active: current).opacity(current ? 0.9 : 0.78))
                    )
                    .frame(width: current ? 128 : 117, height: 19, alignment: .leading)
                }
                .frame(height: current ? 86 : 62, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)\(current ? ", selected" : "")")
            .accessibilityAddTraits(current ? .isSelected : [])

            if current && (!isFinalConfirmation || item.status != .pending) {
                Divider().overlay(.white.opacity(0.33))
                Spacer(minLength: 0)
                Button(action: primaryAction) {
                    Text(isFinalConfirmation || item.status == .added
                         ? (secondsRemaining > 0 && item.status == .added ? "Pause" : "Mark Pending")
                         : "Mark Added")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(item.status == .added ? addedStatusAccent : .white)
                        .background(item.status == .added ? Color.white : addedStatusAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.status == .added
                    ? (secondsRemaining > 0
                        ? "Stop automatic progression. Continue with Next when ready."
                        : "Marks this grocery item pending in ListRunner only. Does not remove it from your \(browser.store.displayName) cart.")
                    : "Marks this grocery item added in ListRunner only")
                Spacer(minLength: 0)
            }
        }
            .padding(current ? 16 : 14)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(width: current ? 160 : 145, height: current ? 224 : 203)
            .foregroundStyle(cardForeground(item.status, active: current))
            .background(cardBackground(item.status, active: current), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(current ? 0.18 : 0.08), radius: current ? 12 : 6, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .simultaneousGesture(TapGesture().onEnded { select(item) })
            .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 12, pressing: { pressing in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
                    pressedCardID = pressing ? item.id : (pressedCardID == item.id ? nil : pressedCardID)
                }
            }, perform: {})
            .scaleEffect(pressedCardID == item.id ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: pressedCardID == item.id)
            .animation(overlayAnimation, value: current)
            .animation(overlayAnimation, value: item.status)
    }

    private func cardBackground(_ status: GroceryStatus, active: Bool) -> LinearGradient {
        switch status {
        case .pending: return LinearGradient(colors: [Color(red: 1, green: 0.988, blue: 0.961), Color(red: 0.949, green: 0.906, blue: 0.808)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .added:
            return LinearGradient(colors: browser.addedStatusGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .skipped: return LinearGradient(colors: [Color.gray.opacity(0.85), Color.gray.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func cardForeground(_ status: GroceryStatus, active: Bool) -> Color {
        status == .pending ? Color(red: 0.188, green: 0.204, blue: 0.227) : .white
    }

    private func primaryAction() {
        guard let item = selected else { return }
        if isFinalConfirmation && item.status != .pending {
            markPending(item)
            return
        }
        if item.status == .added {
            if secondsRemaining == 0 {
                markPending(item)
                return
            }
            // Pause is a manual hold; it never edits cart quantities.
            guard undoRecord?.id == item.id, !pending.isEmpty else { return }
            task?.cancel()
            secondsRemaining = 0
            manuallyPaused = true
        } else {
            markAdded(item)
        }
    }

    private func markPending(_ item: GroceryItem) {
        task?.cancel()
        browser.cancelPreload()
        secondsRemaining = 0
        manuallyPaused = false
        undoRecord = nil
        item.status = .pending
        onStatusChange(item)
        // Keep the current selection and the Coles cart unchanged.
    }

    private func markAdded(_ item: GroceryItem) {
        task?.cancel()
        undoRecord = (item.id, item.status, nil)
        secondsRemaining = 0
        manuallyPaused = false
        item.status = .added
        onStatusChange(item)
        if !pending.isEmpty {
            undoRecord = nil
            advanceToNextPending()
        }
    }

    private func confirmAutomaticAdd(_ item: GroceryItem) {
        if item.status == .added && pending.isEmpty { return }
        withAnimation(overlayAnimation) { isCollapsed = false }
        task?.cancel()
        secondsRemaining = 0
        undoRecord = (item.id, item.status, browser.lastDetectedAdd)
        item.status = .added
        onStatusChange(item)
        if !pending.isEmpty && !manuallyPaused { beginCooldown() }
    }

    private func beginCooldown() {
        secondsRemaining = 3
        if let next = nextPending(after: selectedID) {
            browser.logPreload("Cooldown started; preloading next item")
            browser.preloadSearch(itemID: next.id, searchTerm: next.searchTerm)
        } else {
            browser.logPreload("Cooldown started; no pending item to preload")
        }
        task = Task { @MainActor in
            #if DEBUG
            // This fixture proves the ready-preload path, not simulator cold
            // WebKit startup speed. Production cooldown remains three seconds.
            await browser.waitForPreloadResultsFixture()
            #endif
            while secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, browser.canPresentStore, browser.storeRecovery == nil else { return }
                secondsRemaining -= 1
            }
            undoRecord = nil
            advanceToNextPending()
        }
    }

    private func nextPending(after id: UUID?) -> GroceryItem? {
        let currentIndex = items.firstIndex(where: { $0.id == id }) ?? -1
        return items.dropFirst(max(0, currentIndex + 1)).first(where: { $0.status == .pending })
            ?? pending.first
    }

    private func undo() {
        task?.cancel()
        browser.cancelPreload()
        secondsRemaining = 0
        manuallyPaused = false
        guard let record = undoRecord, let item = items.first(where: { $0.id == record.id }) else { return }
        item.status = record.previous
        undoRecord = nil
        onStatusChange(item)
        if let cartAdd = record.cartAdd { browser.undoCartAdd(cartAdd) }
    }

    private func finish() {
        task?.cancel()
        browser.cancelPreload()
        undoRecord = nil
        secondsRemaining = 0
    }

    private func next() {
        task?.cancel()
        browser.cancelPreload()
        undoRecord = nil
        secondsRemaining = 0
        manuallyPaused = false
        advanceToNextPending()
    }

    private func skip() {
        guard let item = selected else { return }
        task?.cancel()
        browser.cancelPreload()
        undoRecord = nil
        secondsRemaining = 0
        manuallyPaused = false
        item.status = .skipped
        onStatusChange(item)
        advanceToNextPending()
    }

    private func advanceToNextPending() {
        guard !pending.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? -1
        let after = items.dropFirst(max(0, currentIndex + 1)).first(where: { $0.status == .pending })
        let next = after ?? pending.first
        guard let next else { return }
        select(next)
    }

    private func selectPrevious() {
        while let id = selectionHistory.popLast() {
            if let item = items.first(where: { $0.id == id }), id != selectedID {
                select(item, recordHistory: false)
                return
            }
        }
    }

    private func select(_ item: GroceryItem, recordHistory: Bool = true) {
        guard item.id != selectedID else { return }
        if recordHistory, let previousID = selectedID {
            selectionHistory.append(previousID)
        }
        task?.cancel()
        secondsRemaining = 0
        manuallyPaused = false
        selectedID = item.id
        onSelectionChange(item.id)
        browser.beginInteraction(itemID: item.id, searchTerm: item.searchTerm)
    }

    private func collapse() {
        if secondsRemaining > 0 {
            task?.cancel()
            browser.cancelPreload()
            secondsRemaining = 0
            undoRecord = nil
        }
        withAnimation(overlayAnimation) { isCollapsed = true }
    }

    private func dismissStore() {
        if secondsRemaining > 0 { task?.cancel(); secondsRemaining = 0; undoRecord = nil }
        dismiss()
    }
}

private struct QuantityMarquee: UIViewRepresentable {
    let text: String
    let shouldScroll: Bool
    let fontSize: CGFloat
    let color: UIColor

    func makeUIView(context: Context) -> QuantityMarqueeLabel {
        QuantityMarqueeLabel()
    }

    func updateUIView(_ uiView: QuantityMarqueeLabel, context: Context) {
        uiView.configure(text: text, shouldScroll: shouldScroll, fontSize: fontSize, color: color)
    }
}

private final class QuantityMarqueeLabel: UIView {
    private let firstLabel = UILabel()
    private let secondLabel = UILabel()
    private let gap: CGFloat = 28
    private var text = ""
    private var fontSize: CGFloat = 15
    private var textColor: UIColor = .label
    private var shouldScroll = false
    private var layoutKey: LayoutKey?
    private var cycle = 0

    private struct LayoutKey: Equatable {
        let text: String
        let fontSize: CGFloat
        let width: CGFloat
        let scroll: Bool
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        for label in [firstLabel, secondLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, shouldScroll: Bool, fontSize: CGFloat, color: UIColor) {
        guard self.text != text || self.shouldScroll != shouldScroll || self.fontSize != fontSize || !self.textColor.isEqual(color) else { return }
        self.text = text
        self.shouldScroll = shouldScroll
        self.fontSize = fontSize
        textColor = color
        for label in [firstLabel, secondLabel] {
            label.text = text
            label.font = .systemFont(ofSize: fontSize)
            label.textColor = color
        }
        layoutKey = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let measured = firstLabel.sizeThatFits(CGSize(width: 10_000, height: bounds.height)).width
        let key = LayoutKey(text: text, fontSize: fontSize, width: bounds.width, scroll: shouldScroll && measured > bounds.width + 1)
        guard key != layoutKey else { return }
        layoutKey = key
        cycle += 1
        let currentCycle = cycle
        firstLabel.layer.removeAllAnimations()
        secondLabel.layer.removeAllAnimations()
        firstLabel.lineBreakMode = key.scroll ? .byClipping : .byTruncatingTail
        firstLabel.frame = CGRect(x: 0, y: 0, width: key.scroll ? measured : bounds.width, height: bounds.height)
        secondLabel.isHidden = !key.scroll
        secondLabel.frame = CGRect(x: measured + gap, y: 0, width: measured, height: bounds.height)
        guard key.scroll else { return }
        beginCycle(currentCycle, distance: measured + gap)
    }

    private func beginCycle(_ currentCycle: Int, distance: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.cycle == currentCycle else { return }
            let duration = max(3, Double(distance / 18))
            UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
                self.firstLabel.frame.origin.x = -distance
                self.secondLabel.frame.origin.x = 0
            } completion: { [weak self] finished in
                guard let self, finished, self.cycle == currentCycle else { return }
                self.firstLabel.frame.origin.x = 0
                self.secondLabel.frame.origin.x = distance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, self.cycle == currentCycle else { return }
                    self.beginCycle(currentCycle, distance: distance)
                }
            }
        }
    }
}

@MainActor
final class StoreBrowser: ObservableObject {
    private static let recoveryLogger = Logger(subsystem: "ListRunner", category: "StoreRecovery")
    private var uiTestMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil
        #else
        return false
        #endif
    }
    struct CartAddRecord {
        let id = UUID()
        let storeID: StoreID
        let sessionID: String
        let interactionID: String
        let documentGeneration: Int
        let itemID: UUID
        let confirmationID: String
        let productID: String
        // Explicit retailer success receipts may confirm an addition without
        // publishing quantities. Never invent totals or permit reversal for them.
        let before: Int?
        let after: Int?
    }

    @Published private(set) var webView: WKWebView
    @Published private(set) var preloadWebView: WKWebView?
    #if DEBUG
    @Published private(set) var preloadDebugStatus = ""
    #endif
    @Published private(set) var resetPhase: SessionResetPhase = .ready
    @Published private(set) var storeRecovery: StoreRecovery?
    let diagnostics: DiagnosticStore
    let store: StoreDefinition
    private let websiteDataStore: WKWebsiteDataStore
    var canPresentStore: Bool { resetPhase == .ready }
    private var resetOperation = SessionResetOperation()
    private var intendedURL: URL
    private var interactionEnabled = false
    // Presentation/foreground state is separate from automation: a visible
    // browser can have detection disabled, paused or unsupported.
    private var browsingActive = false
    private var needsIdleBrowserRebuild = false
    private var retiredNavigations: Set<WKNavigation> = []
    @Published private(set) var searchUnavailable = false
    var searchNotIncluded: Bool { store.isConfigurationValid && !store.capabilities.search }
    @Published private(set) var cartDetectionUnavailable = false
    @Published private(set) var cartDetectionIssue: CartDetectionIssue?
    var cartDetectionNotIncluded: Bool { store.isConfigurationValid && !store.capabilities.cartDetection }
    var cartDetectionTitle: String { cartDetectionNotIncluded ? "Cart detection not included" : "Cart detection unavailable" }
    var cartDetectionExplanation: String {
        if cartDetectionNotIncluded {
            return "Automatic cart detection isn't included for \(store.displayName) in this app version."
        }
        switch cartDetectionIssue {
        case .cartPreflightUnavailable:
            return String(localized: "ListRunner couldn't verify your cart before adding. That Add was not sent. Tap Add on the store website again to shop manually, then use Mark Added when you've checked your cart.")
        case .productIDUnavailable:
            return "ListRunner couldn't identify which store product was tapped, so it couldn't safely match a cart update to this item."
        case .quantityUnavailable:
            return "ListRunner couldn't read this product's current cart quantity, so it couldn't verify whether the add succeeded."
        case .confirmationTimedOut:
            return "The store page didn't show a stable quantity increase before the detection window expired. The add may still have succeeded."
        case .none:
            return "This store page didn't provide a reliable product-specific cart quantity for ListRunner to verify."
        }
    }
    @Published private(set) var detectedAddSequence = 0
    @Published private(set) var lastDetectedItemID: UUID?
    @Published private(set) var cartUndoWarning = false
    @Published private(set) var siteVerificationRequired = false
    private var navigationPacing = StoreNavigationPacing()
    private var preloadedSearch: (itemID: UUID, term: String, effectiveTerm: String, namingGeneration: UUID, url: URL, view: WKWebView)?
    private var preloadedSearchReady = false
    private var preloadedResponseStatus: Int?
    private var scheduledPreload: (itemID: UUID, term: String)?
    private var pendingPreloadTask: Task<Void, Never>?
    private var latestRequestedSearchURL: URL?
    private var ingredientSearchContext: IngredientSearchContext = .unchanged
    private var namingGeneration = UUID()
    // A failed old search must not be replayed by recovery after preferences change.
    private var intendedSearchNamingGeneration: UUID?

    #if DEBUG
    var isStoreResumeTestFixture: Bool {
        uiTestMode && ProcessInfo.processInfo.environment["LISTRUNNER_STORE_RESUME_TEST_FIXTURE"] != nil
    }
    @Published private(set) var storeResumeTestStatus = ""

    func runStoreResumeTestChecks() async {
        guard isStoreResumeTestFixture else { return }
        var failures: [String] = []
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures.append(name) }
        }
        for id in [StoreID.coles, .woolworths, .tesco] {
            let subject = StoreBrowser(store: .load(id), websiteDataStore: .nonPersistent(), diagnostics: DiagnosticStore(fileURL: nil))
            subject.setBrowsingActive(true)
            let item = UUID()
            subject.resumeInteraction(itemID: item, searchTerm: "milk")
            check(subject.interactionEnabled && subject.itemID == item, "\(id) first open starts interaction")
            for _ in 0..<120 {
                if subject.pendingSearchTask == nil && !subject.webView.isLoading { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            let view = subject.webView
            let navigation = subject.latestNavigation
            let interaction = subject.interactionID
            subject.setBrowsingActive(false)
            subject.endInteraction()
            check(!subject.interactionEnabled && subject.activeCandidate == nil && subject.preloadedSearch == nil,
                  "\(id) dismissal stops automation")
            subject.setBrowsingActive(true)
            subject.resumeInteraction(itemID: item, searchTerm: "milk")
            check(subject.webView === view && subject.latestNavigation === navigation && subject.pendingSearchTask == nil,
                  "\(id) same selection keeps document without queued navigation")
            check(subject.interactionEnabled && subject.interactionID != interaction,
                  "\(id) resume uses fresh automation context")
            if subject.store.capabilities.search {
                subject.endInteraction()
                subject.resumeInteraction(itemID: item, searchTerm: "bread")
                check(subject.pendingSearchTask != nil && subject.latestRequestedSearchURL == subject.store.searchURL(for: "bread"),
                      "\(id) edited query searches")
                subject.endInteraction()
                subject.resumeInteraction(itemID: item, searchTerm: "bread")
                check(subject.pendingSearchTask != nil, "\(id) cancelled paced search is requested on reopen")
                subject.endInteraction()
                let other = UUID()
                subject.resumeInteraction(itemID: other, searchTerm: "bread")
                check(subject.itemID == other && subject.pendingSearchTask != nil, "\(id) different item searches")
                subject.endInteraction()
                subject.navigationPacing = StoreNavigationPacing()
                subject.resumeInteraction(itemID: other, searchTerm: "zucchini")
                for _ in 0..<120 {
                    if subject.pendingSearchTask == nil && !subject.webView.isLoading { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                subject.endInteraction()
                subject.updateIngredientSearchContext(IngredientSearchContext(countryCode: "NZ", enabled: true))
                subject.resumeInteraction(itemID: other, searchTerm: "zucchini")
                check(subject.pendingSearchTask != nil && subject.latestRequestedSearchURL == subject.store.searchURL(for: "courgette"),
                      "\(id) changed naming settings search")
            }
            subject.endInteraction()
            subject.enterStoreRecovery(.loadFailed)
            subject.resumeInteraction(itemID: item, searchTerm: "milk")
            check(subject.storeRecovery == .loadFailed && !subject.interactionEnabled && subject.pendingSearchTask == nil,
                  "\(id) resume does not bypass recovery")
            subject.leaveStoreRecovery()
            subject.rebuildWebView()
            subject.resumeInteraction(itemID: item, searchTerm: "milk")
            check(subject.webView !== view && subject.interactionEnabled && subject.resumableSearch?.itemID == item,
                  "\(id) rebuilt browser starts fresh")
            subject.endInteraction()
            subject.webView.stopLoading()
        }
        storeResumeTestStatus = failures.isEmpty ? "PASS: \(checks) store resume checks" : "FAIL: " + failures.joined(separator: ", ")
    }

    var isIdleRecoveryTestFixture: Bool {
        uiTestMode && ProcessInfo.processInfo.environment["LISTRUNNER_IDLE_RECOVERY_TEST_FIXTURE"] == "enabled"
    }
    @Published private(set) var idleRecoveryTestStatus = ""

    // Inject delegate callbacks against isolated browsers instead of hoping iOS
    // reclaims a real retailer process after an unpredictable idle interval.
    func runIdleRecoveryTestChecks() async {
        guard isIdleRecoveryTestFixture else { return }
        var failures: [String] = []
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures.append(name) }
        }
        for id in [StoreID.coles, .woolworths, .bunnings, .tesco] {
            let dataStore = WKWebsiteDataStore.nonPersistent()
            let records = DiagnosticStore(fileURL: nil)
            let subject = StoreBrowser(store: .load(id), websiteDataStore: dataStore, diagnostics: records)
            let item = UUID()
            let cookie = HTTPCookie(properties: [.domain: subject.store.homepage.host!, .path: "/",
                                               .name: "idle-recovery-fixture", .value: "preserved", .secure: "TRUE"])!
            await dataStore.httpCookieStore.setCookie(cookie)
            subject.setBrowsingActive(true)
            subject.beginInteraction(itemID: item, searchTerm: "milk")
            // Exercise both dismissal/reopen and background/foreground resumption.
            for resume in [false, true] {
                subject.setBrowsingActive(false)
                subject.endInteraction()
                let oldView = subject.webView
                let oldNavigation = subject.latestNavigation
                let generation = subject.documentGeneration
                let session = subject.sessionID
                let interaction = subject.interactionID
                // Pretend the last page was a checkout: it must never be replayed.
                subject.intendedURL = subject.store.homepage.appendingPathComponent("checkout/fixture")
                subject.coordinator.webViewWebContentProcessDidTerminate(oldView)
                // SwiftUI may update a still-mounted WebView while backgrounded.
                subject.loadIfNeeded()
                check(subject.storeRecovery == nil && subject.needsIdleBrowserRebuild,
                      "\(id) idle termination deferred")
                check(subject.webView === oldView && subject.pendingSearchTask == nil && !subject.interactionEnabled,
                      "\(id) no hidden reload or automation")
                subject.setBrowsingActive(true)
                if resume { subject.resumeInteraction(itemID: item, searchTerm: "milk") }
                else { subject.beginInteraction(itemID: item, searchTerm: "milk") }
                check(subject.webView !== oldView && !subject.needsIdleBrowserRebuild && subject.storeRecovery == nil,
                      "\(id) fresh browser without alert")
                check(subject.webView.configuration.websiteDataStore === dataStore && subject.sessionID == session,
                      "\(id) website data and session retained")
                check(subject.documentGeneration > generation && subject.interactionID != interaction && subject.itemID == item,
                      "\(id) stale bridge context invalidated, selection retained")
                let cookies = await dataStore.httpCookieStore.allCookies()
                check(cookies.contains { $0.name == cookie.name && $0.value == cookie.value }, "\(id) cookie retained")
                for _ in 0..<120 {
                    if subject.pendingSearchTask == nil && !subject.webView.isLoading { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let safeURL = subject.store.capabilities.search ? subject.store.searchURL(for: "milk") : subject.store.homepage
                check(subject.intendedURL == safeURL, "\(id) selected search/homepage, never checkout")
                subject.coordinator.webViewWebContentProcessDidTerminate(oldView)
                check(subject.storeRecovery == nil && !subject.needsIdleBrowserRebuild, "\(id) replaced-view callback ignored")
                if let oldNavigation {
                    subject.didFailMainFrameNavigation(oldNavigation, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                    check(subject.storeRecovery == nil, "\(id) retired-navigation failure ignored")
                }
            }
            check(records.entries.contains { $0.event == .processExit && $0.browsingActive == false }
                  && records.entries.contains { $0.event == .browserRecovery }, "\(id) idle failure/rebuild diagnosed")
            let currentView = subject.webView
            subject.coordinator.webViewWebContentProcessDidTerminate(currentView)
            check(subject.storeRecovery == .processTerminated && subject.webView === currentView,
                  "\(id) active termination still requires Retry")
            subject.retryStoreLoad()
            check(subject.storeRecovery == nil && subject.webView !== currentView, "\(id) explicit Retry rebuilds")
            subject.enterStoreRecovery(.loadFailed, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
            subject.setBrowsingActive(false)
            subject.setBrowsingActive(true)
            subject.beginInteraction(itemID: item, searchTerm: "milk")
            check(subject.storeRecovery == .loadFailed && !subject.needsIdleBrowserRebuild,
                  "\(id) timeout never silently retried")
            check(records.entries.last?.reason == .timedOut && records.entries.last?.failureCode == .timedOut,
                  "\(id) timeout retains safe numeric diagnosis")
            subject.leaveStoreRecovery()
            subject.enterStoreRecovery(.loadFailed, httpStatus: 503)
            check(records.entries.last?.reason == .httpResponse && records.entries.last?.httpStatus == 503,
                  "\(id) HTTP failure distinguished")
            subject.leaveStoreRecovery()
            subject.setBrowsingActive(false)
            subject.siteVerificationRequired = true
            subject.contentProcessDidTerminate()
            check(subject.storeRecovery == .processTerminated && !subject.needsIdleBrowserRebuild,
                  "\(id) verification never bypassed by idle recovery")
            subject.leaveStoreRecovery()
            subject.siteVerificationRequired = false
            subject.contentProcessDidTerminate()
            subject.setBrowsingActive(true)
            subject.loadIfNeeded()
            check(subject.storeRecovery == nil && !subject.needsIdleBrowserRebuild && subject.intendedURL == subject.store.homepage,
                  "\(id) no-selection recovery uses homepage")
            subject.endInteraction()
        }
        idleRecoveryTestStatus = failures.isEmpty ? "PASS: \(checks) idle recovery checks" : "FAIL: " + failures.joined(separator: ", ")
    }

    var isRegionalSearchTestFixture: Bool {
        uiTestMode && ProcessInfo.processInfo.environment["LISTRUNNER_REGIONAL_SEARCH_TEST_FIXTURE"] != nil
    }
    @Published private(set) var regionalSearchTestStatus = ""

    // Isolated XCTest fixture exercises real browser scheduling/promotion state,
    // but every WebKit navigation is loadHTMLString with a nonpersistent store.
    func runRegionalSearchTestChecks() async {
        guard isRegionalSearchTestFixture else { return }
        var failures: [String] = []
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures.append(name) }
        }
        let originalContext = ingredientSearchContext
        let originalSession = sessionID
        let originalInteraction = interactionID
        let originalItem = itemID
        let nz = IngredientSearchContext(countryCode: "NZ", enabled: true)
        let au = IngredientSearchContext(countryCode: "AU", enabled: true)
        let off = IngredientSearchContext(countryCode: "NZ", enabled: false)
        updateIngredientSearchContext(nz)
        let originalPage = intendedURL
        search(for: "zucchini")
        check(latestRequestedSearchURL == store.searchURL(for: "courgette"), "normal localized URL")
        check(pendingSearchTask != nil, "normal request deferred")
        updateIngredientSearchContext(off)
        check(pendingSearchTask == nil && latestRequestedSearchURL == nil, "cancel queued search/recovery URL")
        try? await Task.sleep(for: .milliseconds(700))
        check(intendedURL == originalPage, "cancelled query cannot navigate")
        check(sessionID == originalSession && interactionID == originalInteraction && itemID == originalItem,
              "preferences preserve interaction and session")
        check(effectiveSearchTerm("Zucchini") == "Zucchini", "disabled exact source")
        updateIngredientSearchContext(nz)
        navigationPacing = StoreNavigationPacing()
        let next = UUID()
        preloadSearch(itemID: next, searchTerm: "zucchini")
        check(preloadedSearch?.url == store.searchURL(for: "courgette")
              && preloadedSearch?.effectiveTerm == "courgette", "preload localized URL")
        let oldGeneration = namingGeneration
        updateIngredientSearchContext(au)
        updateIngredientSearchContext(nz)
        check(namingGeneration != oldGeneration && preloadedSearch == nil && preloadWebView == nil,
              "off/on-equivalent context cannot revive preload")
        navigationPacing.requested(at: ProcessInfo.processInfo.systemUptime)
        preloadSearch(itemID: next, searchTerm: "zucchini")
        check(scheduledPreload != nil && pendingPreloadTask != nil, "preload deferred by pacing")
        updateIngredientSearchContext(au)
        check(scheduledPreload == nil && pendingPreloadTask == nil, "deferred preload cancelled")
        updateIngredientSearchContext(nz)
        navigationPacing = StoreNavigationPacing()
        preloadSearch(itemID: next, searchTerm: "zucchini")
        // WebKit startup can exceed two seconds on a cold simulator. Wait for
        // the actual fixture completion rather than assuming a fixed latency.
        for _ in 0..<100 {
            if preloadedSearchReady { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        check(preloadedSearchReady, "fixture preload completed")
        let preloadedView = preloadedSearch?.view
        beginInteraction(itemID: next, searchTerm: "zucchini")
        check(webView === preloadedView && intendedURL == store.searchURL(for: "courgette"), "localized preload promoted")
        let promotedPage = intendedURL
        updateIngredientSearchContext(au)
        check(intendedURL == promotedPage && preloadedSearch == nil, "context does not replace visible page")
        enterStoreRecovery(.loadFailed)
        retryStoreLoad()
        check(intendedURL == store.homepage, "recovery cannot replay stale search")
        navigationPacing = StoreNavigationPacing()
        intendedURL = store.homepage.appendingPathComponent("product/fixture")
        let reloadInteraction = interactionID
        let reloadItem = itemID
        reloadSearch(for: "zucchini")
        check(latestRequestedSearchURL == store.searchURL(for: "zucchini"), "reload uses selected item with current naming preferences")
        try? await Task.sleep(for: .seconds(2))
        check(intendedURL == store.searchURL(for: "zucchini"), "reload leaves product page for original search")
        check(interactionID == reloadInteraction && itemID == reloadItem, "reload preserves selected interaction")
        updateIngredientSearchContext(nz)
        navigationPacing = StoreNavigationPacing()
        reloadSearch(for: "zucchini")
        check(latestRequestedSearchURL == store.searchURL(for: "courgette"), "reload reapplies regional naming")
        reloadSearch(for: "milk")
        check(latestRequestedSearchURL == store.searchURL(for: "milk"), "rapid reloads use latest selected item")
        updateIngredientSearchContext(au)
        let manual = StoreBrowser(store: StoreDefinition.load(.tesco), websiteDataStore: .nonPersistent(), diagnostics: diagnostics)
        manual.updateIngredientSearchContext(nz)
        manual.search(for: "zucchini")
        manual.preloadSearch(itemID: next, searchTerm: "zucchini")
        manual.reloadSearch(for: "zucchini")
        check(manual.searchUnavailable && manual.latestRequestedSearchURL == nil && manual.preloadedSearch == nil
              && manual.intendedURL == manual.store.homepage, "naming never enables browsing-only search")
        updateIngredientSearchContext(originalContext)
        regionalSearchTestStatus = failures.isEmpty ? "PASS: \(checks) browser regional search checks" : "FAIL: " + failures.joined(separator: ", ")
    }
    #endif

    func effectiveSearchTerm(_ source: String) -> String {
        RegionalIngredientSearchResolver.application.resolve(source, context: ingredientSearchContext).query
    }

    func updateIngredientSearchContext(_ context: IngredientSearchContext) {
        guard context != ingredientSearchContext else { return }
        ingredientSearchContext = context
        namingGeneration = UUID()
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        searchRequestID = UUID()
        cancelPreload()
        latestRequestedSearchURL = nil
        // Do not navigate, end the current interaction or discard cart/Undo state.
    }
    private var mainFrameResponseStatus: Int?
    var canRetryAfterVerification: Bool {
        navigationPacing.canRetry(at: ProcessInfo.processInfo.systemUptime)
    }
    var addedStatusGradient: [Color] { Self.addedGradient(for: store.addedColor) }
    private(set) var lastDetectedAdd: CartAddRecord?
    private var consumedUndoRecords: Set<UUID> = []
    @Published private(set) var cartUndoInProgress = false
    private var undoOperationID: UUID? {
        didSet { cartUndoInProgress = undoOperationID != nil }
    }
    private var undoTimeoutTask: Task<Void, Never>?
    private var hasLoaded = false
    private var sessionID = UUID().uuidString
    private var interactionID = UUID().uuidString
    private var itemID: UUID?
    // Retain the selected search across sheet dismissal, independently of the
    // short-lived automation context. Website navigation may now be on a product
    // or cart page; resuming must not replace that document with search results.
    private var resumableSearch: (itemID: UUID, term: String, namingGeneration: UUID)?
    private var documentGeneration = 0
    private var activeCandidate: (productID: String, before: Int, deadline: TimeInterval)?
    private var candidatePageURL: URL?
    private var loginReplay: StoreLoginReplay?
    private var loginReplayUserScript: WKUserScript?
    private var loginReplayTimeoutTask: Task<Void, Never>?
    private var loginReplayReceiptInFlight = false
    // Fixed state labels only: never retain authentication URLs, credentials,
    // account identifiers or basket bodies in replay diagnostics.
    private enum LoginReplayState: String {
        case idle, awaitingReturn, awaitingReceipt, checkingQuantity, confirmed
        case cancelled, rejectedNavigation, expired, quantityNotConfirmed
    }
    private var loginReplayState: LoginReplayState = .idle
    private var lastAcknowledgedSequence: (generation: Int, value: UInt64)?
    private var candidateTimeoutTask: Task<Void, Never>?
    private var pendingSearchTask: Task<Void, Never>?
    private var searchRequestID = UUID()
    private var latestNavigation: WKNavigation?
    private var activeSearchNavigation: WKNavigation?
    private let automationWorld: WKContentWorld
    private var cartConfirmationTimeout: TimeInterval {
        if let profiles = store.cart?.profiles, let window = profiles.map(\.confirmationWindowMS).max() {
            return Double(window) / 1_000
        }
        return store.id == .woolworths ? 8 : 3
    }

    // The isolated detector remains the authority for the original trusted tap.
    // This narrowly scoped page-world adapter observes Tesco's normal Apollo
    // promise, not the optimistic UI, and never initiates a basket operation.
    private static let loginReplayObserver = #"""
    (() => {
      'use strict';
      const rule = window.__listRunnerReplayRule;
      if (!rule || window.__listRunnerReplayObserver || location.protocol !== 'https:' ||
          location.hostname !== rule.host || !/^\d{1,32}$/.test(rule.productID)) return;
      window.__listRunnerReplayObserver = true;
      const canonicalPath = path => path.replace('/groceries/en-GB/', '/shop/en-GB/');
      if (canonicalPath(location.pathname) !== rule.path || location.search !== rule.search) return;
      const target = value => value === rule.productID ||
        (typeof value === 'number' && Number.isSafeInteger(value) && String(value) === rule.productID);
      const quantity = value => typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 9999;
      const clients = new WeakSet();
      let finished = false;
      const started = Date.now();
      const valid = () => !finished && Date.now() - started <= 300000 &&
        canonicalPath(location.pathname) === rule.path && location.search === rule.search;
      const metadata = options => {
        const document = options?.mutation;
        if (document?.kind !== 'Document' || !Array.isArray(document.definitions) || document.definitions.length > 20) return null;
        const operations = document.definitions.filter(value => value.kind === 'OperationDefinition');
        if (operations.length !== 1 || operations[0].operation !== 'mutation' || operations[0].name?.value !== 'UpdateBasket' ||
            !operations[0].selectionSet?.selections?.some(value => value.kind === 'Field' && value.name?.value === 'basket')) return null;
        const items = options.variables?.items;
        if (!Array.isArray(items) || items.length > 200) return null;
        const matches = items.filter(value => target(value?.id));
        return matches.length === 1 && quantity(matches[0].newValue) && matches[0].newValue > 0 ? matches[0].newValue : null;
      };
      const receive = (result, requested) => {
        if (!valid() || result?.error || (Array.isArray(result?.errors) && result.errors.length)) return;
        const basket = result?.data?.basket;
        const updates = basket?.updates?.items;
        if (!Array.isArray(updates) || updates.length > 1000) return;
        const matches = updates.filter(value => target(value?.id));
        if (matches.length !== 1 || matches[0].successful !== true) return;
        const values = new Set();
        let ambiguous = false;
        const scan = items => {
          if (!Array.isArray(items) || items.length > 1000) { ambiguous = true; return; }
          for (const item of items) if (target(item?.product?.id)) {
            if (quantity(item.quantity)) values.add(item.quantity); else ambiguous = true;
          }
        };
        if (Array.isArray(basket.items)) scan(basket.items);
        if (Array.isArray(basket.splitView)) {
          if (basket.splitView.length > 20) return;
          for (const group of basket.splitView) scan(group?.items);
        }
        if (ambiguous || values.size !== 1 || !values.has(requested)) return;
        finished = true;
        window.webkit?.messageHandlers?.listRunnerLoginReplay?.postMessage({
          nonce: rule.nonce, productID: rule.productID, successful: true,
          requestedQuantity: requested, resultingQuantity: requested
        });
      };
      const attach = orchestrator => {
        if (!valid() || typeof orchestrator?.resolveProps !== 'function') return false;
        try {
          // No account configuration is read. This public accessor returns the
          // existing client; it does not query, mutate or inspect the Apollo cache.
          const client = orchestrator.resolveProps({ name: 'ListRunnerLoginReplay' }).client;
          if (typeof client?.mutate !== 'function') return false;
          if (clients.has(client)) return true;
          const original = client.mutate;
          client.mutate = function(options) {
            let requested = null;
            try { if (valid()) requested = metadata(options); } catch (_) {}
            const promise = Reflect.apply(original, this, arguments);
            if (requested !== null && typeof promise?.then === 'function') {
              promise.then(result => { try { receive(result, requested); } catch (_) {} }, () => {}).catch(() => {});
            }
            return promise;
          };
          clients.add(client);
          return true;
        } catch (_) { return false; }
      };
      if (!attach(window.Orchestrator)) {
        const descriptor = Object.getOwnPropertyDescriptor(window, 'Orchestrator');
        if (!descriptor || (descriptor.configurable && !descriptor.get && !descriptor.set)) {
          let current = descriptor?.value;
          Object.defineProperty(window, 'Orchestrator', { configurable: true, enumerable: descriptor?.enumerable ?? true,
            get: () => current, set: value => { current = value; attach(value); } });
        }
      }
    })();
    """#

    private static let automationScript = #"""
    (() => {
      const config = window.__listRunnerStoreConfig;
      if (!config || !config.capabilities.cartDetection || !config.cart || location.protocol !== 'https:' || !config.allowedHosts.includes(location.hostname.toLowerCase())) return;
      const rules = config.cart;
      const automationSchemaVersion = Number.isInteger(config.automationSchemaVersion)
        ? config.automationSchemaVersion : config.schemaVersion;
      const supportsSchema4Features = automationSchemaVersion === 4;
      // Woolworths' web components settle more slowly after their asynchronous
      // cart request. This only widens observation; it never clicks controls.
      const confirmationWindow = config.id === 'woolworths' ? 8000 : 3000;
      const bridge = window.webkit?.messageHandlers?.listRunner;
      if (!bridge) return;
      let context = null;
      let candidate = null;
      let reversal = null;
      let confirmationSequence = 0;
      const confirmedAdds = new Map();
      const contextFingerprint = value => value ? JSON.stringify([
        value.sessionID, value.interactionID, value.itemID, value.documentGeneration
      ]) : 'null';
      const productLinkPattern = new RegExp(rules.productURLPattern, 'i');
      const normalize = value => (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const profiles = rules.strategy === 'profiled' ? rules.profiles : null;
       const usesScopedProductIdentity = config.id === 'bunnings' || config.id === 'kmart';
       const isAddControl = element => {
         if (!usesScopedProductIdentity) {
          return element.matches(rules.addSelector) || rules.addLabelPatterns.some(pattern =>
            new RegExp(pattern).test(normalize(element.getAttribute('aria-label'))));
        }
         const label = normalize(element.getAttribute('aria-label') || element.textContent);
        return element.matches(rules.addSelector) && rules.addLabelPatterns.some(pattern =>
          new RegExp(pattern).test(label));
      };
      const deepQueryAll = (root, selector) => {
        const results = [];
        const visited = new Set();
        const visit = current => {
          if (!current || visited.has(current)) return;
          visited.add(current);
          try { results.push(...current.querySelectorAll(selector)); } catch (_) { return; }
          if (current.shadowRoot) visit(current.shadowRoot);
          try {
            for (const element of current.querySelectorAll('*')) {
              if (element.shadowRoot) visit(element.shadowRoot);
            }
          } catch (_) {}
        };
        visit(root);
        return results;
      };
      const deepClosest = (element, selector) => {
        let current = element;
        while (current) {
          if (current.matches?.(selector)) return current;
          if (current.parentElement) current = current.parentElement;
          else current = current.getRootNode?.().host || null;
        }
        return null;
      };
      const validProductIdentity = value => typeof value === 'string' &&
        (supportsSchema4Features && rules.identityStrategy === 'capturedURLComponent'
          ? value.length <= 256 && /^[A-Za-z0-9]/.test(value) && !/[^A-Za-z0-9_-]/.test(value)
          : value.length >= 1 && value.length <= 32 && !/[^0-9]/.test(value));
      const linkedProductIDs = root => {
        const ids = new Set();
        const links = deepQueryAll(root, rules.linkSelector);
        if (root.matches?.(rules.linkSelector)) links.unshift(root);
        for (const link of links) {
          try {
            const url = new URL(link.href || link.getAttribute('href'), location.href);
            if (url.protocol !== 'https:' || !config.allowedHosts.includes(url.hostname.toLowerCase()) ||
                (url.port && url.port !== '443') || url.username || url.password) continue;
            const match = url.pathname.match(productLinkPattern);
            if (match && validProductIdentity(match[1])) ids.add(match[1]);
          } catch (_) {}
        }
        return ids;
      };
      const bunningsPageProductID = () => {
        const match = location.pathname.match(productLinkPattern);
        return match && validProductIdentity(match[1]) ? match[1] : null;
      };
      const isPageBoundary = element => element === document.body || element === document.documentElement ||
        String(element.tagName || '').toLowerCase() === 'main';
      const productTile = element => {
         if (usesScopedProductIdentity) {
          const heading = deepQueryAll(document, 'h1')[0];
          const pageID = bunningsPageProductID();
          // Grid/recommendation controls belong to their own smallest container
          // with an exact product link and Add/increment control. Never use the
          // search term, a page-wide link, or another card's quantity as identity.
          for (let current = element; current && !isPageBoundary(current);
               current = current.parentElement || current.getRootNode?.().host || null) {
            if (pageID && heading && deepQueryAll(current, 'h1').includes(heading)) break;
            const ids = linkedProductIDs(current);
            if (ids.size > 1) return null;
            if (ids.size === 1 && deepQueryAll(current, 'button').some(isAddControl)) return current;
          }
          if (!heading || !pageID) return null;
          const stickyProductControls = deepClosest(element, '#pdp-footer-container');
          if (stickyProductControls) {
            const ids = linkedProductIDs(stickyProductControls);
            return [...ids].every(id => id === pageID) ? stickyProductControls : null;
          }
          const headingAncestors = [];
          for (let current = heading; current; current = current.parentElement || current.getRootNode?.().host || null) {
            headingAncestors.push(current);
          }
          for (let current = element; current; current = current.parentElement || current.getRootNode?.().host || null) {
            const shared = headingAncestors.find(ancestor => ancestor === current);
            if (!shared) continue;
            if (!isPageBoundary(shared) && [...linkedProductIDs(shared)].every(id => id === pageID)) return shared;
            return null;
          }
          return null;
        }
        // Woolworths renders product identity, cart controls and quantity in nested
        // open shadow roots. Prefer the semantic tile. Some responsive Woolworths
        // layouts render that tile as ordinary divs, so fall back to the nearest
        // composed ancestor whose product links identify exactly one product.
        const semanticTile = element.closest?.(rules.tileSelector) || deepClosest(element, rules.tileSelector);
        if (semanticTile) return semanticTile;
        if (config.id !== 'woolworths') return null;
        let current = element;
        while (current) {
          if (linkedProductIDs(current).size === 1) return current;
          current = current.parentElement || current.getRootNode?.().host || null;
        }
        return null;
      };
      const productID = tile => {
        if (!tile) return null;
         if (usesScopedProductIdentity) {
          if (isPageBoundary(tile)) return null;
          const ids = linkedProductIDs(tile);
          const heading = deepQueryAll(document, 'h1')[0];
          if (bunningsPageProductID() && heading &&
              (tile.matches?.('#pdp-footer-container') || deepQueryAll(tile, 'h1').includes(heading))) {
            const pageID = bunningsPageProductID();
            return [...ids].every(id => id === pageID) ? pageID : null;
          }
          return ids.size === 1 ? [...ids][0] : null;
        }
        // Woolworths progressively hydrates its product cards. On some physical
        // devices the trusted Add tap can arrive before the product link has
        // been exposed through the tile's shadow tree, even though the tile
        // already has the retailer's numeric product identifier. Read only
        // explicit product-ID attributes as a narrow fallback; never infer an
        // ID from labels, names, prices, or arbitrary page text.
        const numericID = value => {
          const text = String(value || '').trim();
          return /^\d{1,32}$/.test(text) ? text : null;
        };
        const identityAttributes = ['data-product-id', 'data-productid', 'product-id', 'productid'];
        const candidates = [tile, ...deepQueryAll(tile, '*')];
        for (const element of candidates) {
          for (const attribute of identityAttributes) {
            const id = numericID(element.getAttribute?.(attribute));
            if (id) return id;
          }
        }
        for (const link of deepQueryAll(tile, 'a[href]')) {
          try {
            const url = new URL(link.href, location.href);
            if (url.protocol !== 'https:' || !config.allowedHosts.includes(url.hostname.toLowerCase()) || url.port && url.port !== '443' || url.username || url.password) continue;
            const match = url.pathname.match(productLinkPattern);
            if (match) return match[1];
          } catch (_) {}
        }
        return null;
      };
      const findProductTile = id => {
         if (usesScopedProductIdentity) {
          // Reacquire only a card for the same product after a React replacement.
          for (const link of deepQueryAll(document, rules.linkSelector)) {
            if (!linkedProductIDs(link).has(id)) continue;
            const tile = productTile(link);
            if (tile && productID(tile) === id && deepQueryAll(tile, rules.quantitySelector).length) return tile;
          }
          if (bunningsPageProductID() !== id) return null;
          const heading = deepQueryAll(document, 'h1')[0];
          if (!heading) return null;
          for (let current = heading; current; current = current.parentElement || current.getRootNode?.().host || null) {
            if (isPageBoundary(current)) break;
            if (productID(current) === id && deepQueryAll(current, rules.quantitySelector).length) return current;
          }
          return null;
        }
        for (const link of deepQueryAll(document, rules.linkSelector)) {
          const tile = productTile(link);
          if (tile && productID(tile) === id) return tile;
        }
        return null;
      };
      const quantity = tile => {
        if (!tile) return null;
        const configured = deepQueryAll(tile, rules.quantitySelector);
        // Woolworths mobile can render an unadorned numeric stepper input instead
        // of desktop's quantity-input/aria-valuenow markup. This fallback stays
        // inside the uniquely product-identified card, never at page scope.
        const candidates = [...new Set([
          ...configured,
          ...deepQueryAll(tile, 'input[type="number"],[role="spinbutton"]')
        ])];
        for (const input of candidates) {
          const rawValue = input.value || input.getAttribute('aria-valuenow');
          if (rawValue === null || rawValue === '') continue;
          const value = Number(rawValue);
          if (Number.isInteger(value) && value >= 0 && value <= 9999) return value;
        }
        const empty = deepQueryAll(tile, rules.emptyStatusSelector)
          .some(status => normalize(status.textContent) === normalize(rules.emptyStatusText));
        return empty ? 0 : null;
      };
      const profileControlMatches = (control, profile) => control.matches(profile.addSelector) &&
        profile.addLabelPatterns.some(pattern => new RegExp(pattern).test(
          normalize(control.getAttribute('aria-label') || control.textContent)));
      const profileName = (root, profile) => {
        // Responsive pages may duplicate the same heading. Different names are
        // ambiguous; never choose an arbitrary page title or seller badge.
        const titles = deepQueryAll(root, profile.titleSelector);
        if (supportsSchema4Features && root.matches?.(profile.titleSelector)) titles.unshift(root);
        const names = new Set(titles
          .map(title => normalize(title.textContent)).filter(Boolean));
        return names.size === 1 ? [...names][0] : null;
      };
      const resolveProfile = control => {
        const matches = [];
        for (const profile of profiles || []) {
          if (!profileControlMatches(control, profile)) continue;
          if (profile.identity === 'cardLink') {
            for (let tile = control; tile && !isPageBoundary(tile);
                 tile = tile.parentElement || tile.getRootNode?.().host || null) {
              const ids = linkedProductIDs(tile);
              if (ids.size > 1) break;
              if (!tile.matches(profile.containerSelector) || ids.size !== 1) continue;
              const links = deepQueryAll(tile, rules.linkSelector);
              const names = new Set(links.map(link => profileName(link, profile)).filter(Boolean));
              if (names.size !== 1) continue;
              matches.push({ profile, tile, productID: [...ids][0], productName: [...names][0] });
              break;
            }
          } else if (profile.identity === 'pageURL') {
            const id = bunningsPageProductID();
            const tile = deepClosest(control, profile.containerSelector);
            const name = profileName(document, profile);
            // Page identity is permitted only for an explicitly scoped detail
            // control, never for a recommendation with its own product links.
            if (id && tile && !isPageBoundary(tile) && name && linkedProductIDs(tile).size === 0) {
              matches.push({ profile, tile, productID: id, productName: name });
            }
          }
        }
        // Overlapping profile rules fail closed rather than guessing precedence.
        return matches.length === 1 ? matches[0] : null;
      };
      const profileReceipt = (profile, name, id) => {
        for (const root of deepQueryAll(document, profile.receipt.selector)) {
          const text = normalize(root.innerText || root.textContent);
          const start = text.lastIndexOf(normalize(profile.receipt.successText));
          if (start < 0) continue;
          const receipt = text.slice(start);
          if (supportsSchema4Features && profile.receipt.productSelector && profile.receipt.quantitySelector) {
            if (!root.getClientRects().length || getComputedStyle(root).visibility === 'hidden') continue;
            if (deepQueryAll(root, profile.receipt.failureSelector).some(error => error.getClientRects().length &&
                getComputedStyle(error).visibility !== 'hidden' && normalize(error.innerText || error.textContent))) continue;
            const rows = deepQueryAll(root, profile.receipt.productSelector).filter(row => {
              const ids = linkedProductIDs(row);
              const imageRule = profile.receipt.imageIdentity;
              if (imageRule) {
                for (const image of deepQueryAll(row, imageRule.selector)) {
                  try {
                    const url = new URL(image.getAttribute('src'), location.href);
                    if (url.protocol !== 'https:' || !imageRule.allowedHosts.includes(url.hostname.toLowerCase()) ||
                        url.username || url.password || (url.port && url.port !== '443')) continue;
                    const match = url.pathname.match(new RegExp(imageRule.productURLPattern));
                    if (match && validProductIdentity(match[1])) ids.add(match[1]);
                  } catch (_) {}
                }
              }
              return row.getClientRects().length && getComputedStyle(row).visibility !== 'hidden'
                && ids.size === 1 && ids.has(id) && normalize(row.innerText || row.textContent).includes(name);
            });
            if (rows.length !== 1) continue;
            const inputs = deepQueryAll(rows[0], profile.receipt.quantitySelector)
              .filter(input => input.getClientRects().length && getComputedStyle(input).visibility !== 'hidden');
            if (!inputs.length) continue;
            const values = inputs.map(input => input.value || input.getAttribute('aria-valuenow'));
            if (values.some(value => value === null || value === '' || !/^\d{1,4}$/.test(String(value)))) continue;
            const quantities = new Set(values.map(Number));
            if (quantities.size !== 1) continue;
            const value = [...quantities][0];
            if (value > 0 && value <= 9999) return { text: `${receipt}|product:${id}|quantity:${value}`, quantity: value };
            continue;
          }
          const qty = receipt.match(new RegExp(profile.receipt.quantityPattern));
          if (!qty || !receipt.includes(name)) continue;
          const value = Number(qty[1]);
          if (Number.isInteger(value) && value > 0 && value <= 9999) return { text: receipt, quantity: value };
        }
        return null;
      };
      const profileQuantity = (tile, profile) => {
        if (!tile?.isConnected) return null;
        // Editable retailer quantities can be drafts awaiting an explicit Update.
        // Never arm detection from, or confirm against, an unapplied draft.
        if (supportsSchema4Features && profile.quantityDraftSelector &&
            deepQueryAll(tile, profile.quantityDraftSelector).some(element =>
              element.getClientRects().length && getComputedStyle(element).visibility !== 'hidden')) return null;
        const inputs = deepQueryAll(tile, profile.quantitySelector);
        const values = new Set();
        for (const input of inputs) {
          const textQuantity = supportsSchema4Features && profile.quantityText === true;
          // Text quantities must be non-editable visible labels, never intended
          // quantities, hidden templates, or arbitrary text coerced by Number().
          if (textQuantity && (!['SPAN', 'OUTPUT'].includes(input.tagName) ||
              input.getAttribute('contenteditable') !== null || !input.getClientRects().length ||
              getComputedStyle(input).visibility === 'hidden')) return null;
          const raw = textQuantity ? input.textContent.trim() : input.value || input.getAttribute('aria-valuenow');
          if (textQuantity && !/^(0|[1-9][0-9]{0,3})$/.test(raw)) return null;
          if (raw === null || raw === '') return null;
          const value = Number(raw);
          if (!Number.isInteger(value) || value < 0 || value > 9999) return null;
          values.add(value);
        }
        if (values.size === 1) return [...values][0];
        // A reviewed dedicated Add state is explicit zero evidence. Do not use
        // it if a present quantity input is invalid or disagrees with another.
         if (!inputs.length && profile.emptyStatusText && deepQueryAll(tile, profile.addSelector)
             .some(control => profileControlMatches(control, profile) &&
               (normalize(control.getAttribute('aria-label') || control.textContent) === normalize(profile.emptyStatusText) ||
                 (supportsSchema4Features && normalize(control.textContent) === normalize(profile.emptyStatusText))))) return 0;
        return null;
      };
      const profileAcknowledgement = (profile, name) => {
        const rule = profile.acknowledgement;
        if (!rule) return null;
        const visible = element => {
          if (!element.getClientRects().length) return false;
          for (let current = element; current; current = current.parentElement) {
            const style = getComputedStyle(current);
            if (style.visibility === 'hidden' || style.display === 'none' || Number(style.opacity) === 0) return false;
            // Retailers can keep a success label in the DOM, translated outside
            // an overflow-clipped Add button. Its centre must actually enter
            // every clipping ancestor; layout rectangles alone are not proof.
            if (current !== element) {
              const clipsX = ['hidden', 'clip', 'scroll', 'auto'].includes(style.overflowX);
              const clipsY = ['hidden', 'clip', 'scroll', 'auto'].includes(style.overflowY);
              if (clipsX || clipsY) {
                const bounds = current.getBoundingClientRect();
                const label = element.getBoundingClientRect();
                if (label.width <= 0 || label.height <= 0) return false;
                const x = label.left + label.width / 2, y = label.top + label.height / 2;
                if ((clipsX && (x <= bounds.left || x >= bounds.right)) ||
                    (clipsY && (y <= bounds.top || y >= bounds.bottom))) return false;
              }
            }
          }
          return true;
        };
        const matches = [];
        for (const root of deepQueryAll(document, rule.selector)) {
          if (!visible(root) || deepQueryAll(root, rule.failureSelector)
              .some(error => visible(error) && normalize(error.innerText || error.textContent))) continue;
          const success = deepQueryAll(root, rule.successSelector).filter(element =>
            visible(element) && normalize(element.innerText || element.textContent) === normalize(rule.successText));
          const titles = new Set(deepQueryAll(root, rule.titleSelector)
            .filter(visible).map(element => normalize(element.innerText || element.textContent)).filter(Boolean));
          if (success.length === 1 && titles.size === 1 && titles.has(name)) matches.push(`${normalize(rule.successText)}|${name}`);
        }
        return matches.length === 1 ? matches[0] : null;
      };
      const findProfileState = (id, profile) => {
        const states = [];
        const seen = new Set();
        for (const control of deepQueryAll(document, profile.addSelector)) {
          const resolved = resolveProfile(control);
          if (!resolved || resolved.profile.id !== profile.id || resolved.productID !== id || seen.has(resolved.tile)) continue;
          seen.add(resolved.tile);
          states.push({ ...resolved, quantity: profileQuantity(resolved.tile, profile) });
        }
        if (!states.length || states.some(state => state.quantity === null) ||
            new Set(states.map(state => state.quantity)).size !== 1) return null;
        // Detail pages can have main/sticky duplicates. Require consistent
        // values but only ever click a visible product control during Undo.
        return states.find(state => state.tile.getClientRects().length &&
          getComputedStyle(state.tile).visibility !== 'hidden') || null;
      };
      const post = (type, fields) => {
        if (!context) return;
        bridge.postMessage(JSON.stringify({
          schemaVersion: 1, type, storeID: config.id, sessionID: context.sessionID,
          interactionID: context.interactionID, itemID: context.itemID,
          documentGeneration: context.documentGeneration, pageURL: location.href, ...fields
        }));
      };
      const candidateIsValid = value => {
        if (value.profile && (value.pageURL !== location.href || document.visibilityState === 'hidden')) {
          candidate = null;
          return false;
        }
        const setup = value.profile?.setupPrompt;
        if (setup) {
          const promptVisible = deepQueryAll(document, setup.selector).some(element =>
            element.getClientRects().length && getComputedStyle(element).visibility !== 'hidden' &&
            new RegExp(setup.textPattern, 'i').test(normalize(element.innerText || element.textContent)));
          if (promptVisible && Date.now() <= value.setupDeadline) {
            // The user's availability choice is not a cart failure. Preserve the
            // original trusted product/baseline, never infer a new baseline here.
            value.expires = Math.min(value.setupDeadline + value.profile.confirmationWindowMS,
              Date.now() + value.profile.confirmationWindowMS);
          }
        }
        if (Date.now() > value.expires) {
          if (setup) post('automationUnavailable', { capability: 'cartDetection', reason: 'confirmationTimedOut', scope: 'interaction' });
          candidate = null;
          return false;
        }
        return true;
      };
      const checkCandidate = () => {
        if (!candidate || candidate.reported || candidate.checking) return;
        const checkingCandidate = candidate;
        if (!candidateIsValid(checkingCandidate)) return;
        checkingCandidate.checking = true;
        setTimeout(() => {
          if (candidate !== checkingCandidate) return;
          if (!candidateIsValid(checkingCandidate)) return;
          if (checkingCandidate.profile?.confirmation === 'productAcknowledgement') {
            const signature = profileAcknowledgement(checkingCandidate.profile, checkingCandidate.productName);
            if (signature && signature !== checkingCandidate.initialAcknowledgement) checkingCandidate.stableCount++;
            else checkingCandidate.stableCount = 0;
            if (checkingCandidate.stableCount >= 2) {
              post('addAcknowledged', { confirmationID: String(++confirmationSequence), productID: checkingCandidate.productID,
                profileID: checkingCandidate.profile.id });
              candidate = null;
              return;
            }
            checkingCandidate.checking = false;
            checkCandidate();
            return;
          }
          if (checkingCandidate.profile?.confirmation === 'productReceipt') {
            const receipt = profileReceipt(checkingCandidate.profile, checkingCandidate.productName, checkingCandidate.productID);
            if (receipt && receipt.text !== checkingCandidate.initialToast) {
              if (checkingCandidate.lastReceipt === receipt.text) checkingCandidate.stableCount++;
              else { checkingCandidate.lastReceipt = receipt.text; checkingCandidate.stableCount = 1; }
              if (checkingCandidate.stableCount >= 2) {
                const before = receipt.quantity - 1;
                const confirmationID = String(++confirmationSequence);
                const fields = { confirmationID, productID: checkingCandidate.productID,
                  beforeQuantity: before, resultingQuantity: receipt.quantity };
                confirmedAdds.set(confirmationID, { ...fields, context: contextFingerprint(context) });
                if (confirmedAdds.size > 32) confirmedAdds.delete(confirmedAdds.keys().next().value);
                post('cartInteractionStarted', { productID: checkingCandidate.productID, beforeQuantity: before,
                  intent: before === 0 ? 'add' : 'increment' });
                post('addDetected', fields);
                candidate = null;
                return;
              }
            } else {
              checkingCandidate.lastReceipt = null;
              checkingCandidate.stableCount = 0;
            }
            checkingCandidate.checking = false;
            checkCandidate();
            return;
          }
          const tile = checkingCandidate.tile.isConnected && (checkingCandidate.profile || productID(checkingCandidate.tile) === checkingCandidate.productID)
            ? checkingCandidate.tile : findProductTile(checkingCandidate.productID);
          const resolved = checkingCandidate.profile
            ? findProfileState(checkingCandidate.productID, checkingCandidate.profile) : null;
          const current = checkingCandidate.profile
            ? resolved?.quantity ?? null
            : quantity(tile);
          if (current !== null && current > checkingCandidate.before) {
            if (checkingCandidate.lastValue === current) checkingCandidate.stableCount++;
            else { checkingCandidate.lastValue = current; checkingCandidate.stableCount = 1; }
            if (checkingCandidate.stableCount >= 2) {
              const confirmationID = String(++confirmationSequence);
              const fields = { confirmationID, productID: checkingCandidate.productID, beforeQuantity: checkingCandidate.before, resultingQuantity: current };
              confirmedAdds.set(confirmationID, { ...fields, profileID: checkingCandidate.profile?.id,
                pageURL: location.href, context: contextFingerprint(context) });
              if (confirmedAdds.size > 32) confirmedAdds.delete(confirmedAdds.keys().next().value);
              if (checkingCandidate.profile?.setupPrompt) {
                // Native's short confirmation deadline begins only when the
                // product-scoped evidence settles, not before a human setup flow.
                post('cartInteractionStarted', { productID: checkingCandidate.productID, beforeQuantity: checkingCandidate.before,
                  intent: checkingCandidate.before === 0 ? 'add' : 'increment' });
              }
              post('addDetected', fields);
              candidate = null;
              return;
            }
          } else {
            checkingCandidate.lastValue = null;
            checkingCandidate.stableCount = 0;
          }
          checkingCandidate.checking = false;
          checkCandidate();
        }, 180);
      };
      window.__listRunnerSetContext = next => {
        // didFinish may repeat the context delivered by the installation handshake.
        // Do not discard an in-flight trusted tap when nothing has changed.
        if (contextFingerprint(context) === contextFingerprint(next)) return;
        context = next;
        candidate = null;
        reversal = null;
        confirmedAdds.clear();
      };
      window.__listRunnerCancelUndo = () => { reversal = null; };
      window.__listRunnerConfirmLoginQuantity = async (id, expected) => {
        // A replay acknowledgement cannot create a quantity baseline or Undo
        // record. Require the exact product to agree in the isolated DOM world.
        const fingerprint = contextFingerprint(context);
        if (!context || !profiles || !Number.isInteger(expected) || expected < 1 || expected > 9999) return false;
        for (let attempt = 0, stable = 0; attempt < 20; attempt++) {
          if (contextFingerprint(context) !== fingerprint || document.visibilityState === 'hidden') return false;
          const states = profiles.filter(profile => profile.confirmation === 'quantityIncrease')
            .map(profile => findProfileState(id, profile)).filter(Boolean);
          if (states.length && states.every(state => state.quantity === expected)) stable++; else stable = 0;
          if (stable >= 2) return true;
          await new Promise(resolve => setTimeout(resolve, 180));
        }
        return false;
      };
      window.__listRunnerUndoAdd = async record => {
        const saved = confirmedAdds.get(record.confirmationID);
        const profile = saved?.profileID ? profiles?.find(value => value.id === saved.profileID) : null;
        const contextKey = contextFingerprint(context);
        if (!config.capabilities.cartUndo || record.storeID !== config.id || !saved || reversal || candidate || !context || saved.context !== contextKey ||
            record.sessionID !== context.sessionID || record.interactionID !== context.interactionID ||
            record.itemID !== context.itemID || record.documentGeneration !== context.documentGeneration ||
            saved.productID !== record.productID || saved.beforeQuantity !== record.beforeQuantity ||
            saved.resultingQuantity !== record.resultingQuantity || (profiles && (!profile?.undo || saved.pageURL !== location.href))) return false;
        // Consume provenance once, even if a control is unsupported or confirmation fails.
        confirmedAdds.delete(record.confirmationID);
        const operation = {};
        reversal = operation;
        const deadline = Date.now() + 3000;
        const valid = () => reversal === operation && contextFingerprint(context) === contextKey &&
          (!profile || location.href === saved.pageURL) &&
          document.visibilityState !== 'hidden' && Date.now() <= deadline;
        const pause = () => new Promise(resolve => setTimeout(resolve, 120));
        const locate = () => profile ? findProfileState(record.productID, profile)?.tile : findProductTile(record.productID);
        const currentQuantity = () => profile ? findProfileState(record.productID, profile)?.quantity ?? null : quantity(locate());
        try {
          let expected = record.resultingQuantity;
          while (expected > record.beforeQuantity) {
            if (!valid()) return false;
            const tile = locate();
            if (!tile || (!profile && productID(tile) !== record.productID) || currentQuantity() !== expected) return false;
            const buttons = deepQueryAll(tile, profile?.undo.decrementSelector || 'button').filter(button =>
              new RegExp(profile?.undo.decrementLabelPattern || rules.decrementLabelPattern)
                .test(normalize(button.getAttribute('aria-label'))));
            if (buttons.length !== 1 || buttons[0].disabled || buttons[0].getAttribute('aria-disabled') === 'true') return false;
            // One decrement per confirmed step; never use a remove-all control.
            buttons[0].click();
            let stable = 0;
            while (stable < 2) {
              await pause();
              if (!valid()) return false;
              const current = currentQuantity();
              if (current === expected - 1) stable++;
              else if (current === expected || current === null) stable = 0;
              else return false;
            }
            expected--;
          }
          return valid() && currentQuantity() === record.beforeQuantity;
        } catch (_) {
          return false;
        } finally {
          if (reversal === operation) reversal = null;
        }
      };
      document.addEventListener('click', event => {
        if (!event.isTrusted) return;
        // A real user action supersedes reversal. Our own synthetic decrement
        // cannot arm add detection or recursively create an Undo record.
        reversal = null;
        if (!context) return;
        // A second real action, including manually opening an old cart receipt,
        // cannot complete a previous Add. Synthetic site updates do not arm it.
        if (supportsSchema4Features) candidate = null;
        // Events from web components are retargeted at each shadow boundary. The
        // composed path retains the original trusted control for exact attribution.
        const origin = event.composedPath?.().find(node => node instanceof Element) || event.target;
        const control = origin instanceof Element
          ? deepClosest(origin, 'button,[role="button"],input[type="button"],input[type="submit"]') : null;
        if (!control) return;
        if (profiles) {
          const resolved = resolveProfile(control);
          if (!resolved) return;
          const { profile, tile, productID: id, productName: name } = resolved;
          const before = profile.confirmation === 'quantityIncrease' ? profileQuantity(tile, profile) : null;
          // A quantity profile must observe its baseline; no page-wide count or
          // guessed zero is allowed. Receipt profiles defer both bridge messages.
          if (profile.confirmation === 'quantityIncrease' && before === null) return;
          candidate = { ...resolved, control, before, pageURL: location.href,
            initialToast: profile.confirmation === 'productReceipt' ? profileReceipt(profile, name, id)?.text || null : null,
            initialAcknowledgement: profile.confirmation === 'productAcknowledgement' ? profileAcknowledgement(profile, name) : null,
            expires: Date.now() + profile.confirmationWindowMS,
            setupDeadline: Date.now() + (profile.setupPrompt?.maximumWaitMS || 0), stableCount: 0, checking: false };
          if (before !== null && !profile.setupPrompt) post('cartInteractionStarted', { productID: id, beforeQuantity: before, intent: before === 0 ? 'add' : 'increment' });
          setTimeout(checkCandidate, 180);
          return;
        }
        if (!isAddControl(control)) return;
        const tile = productTile(control);
        const id = productID(tile);
        const observedBefore = quantity(tile);
        const explicitEmptyStatus = tile && deepQueryAll(tile, rules.emptyStatusSelector)
          .some(status => normalize(status.textContent) === normalize(rules.emptyStatusText));
        // The trusted click is captured before Woolworths handles it. Its
        // dedicated Add control is explicit evidence of the zero-quantity state,
        // even when the mobile button's visible text differs from its accessible
        // label (or is rendered inside another shadow root).
        const notInTrolley = explicitEmptyStatus || (config.id === 'woolworths' && isAddControl(control)) ||
           (usesScopedProductIdentity && isAddControl(control));
        const before = observedBefore === null && notInTrolley ? 0 : observedBefore;
        if (!id || before === null) {
          post('automationUnavailable', { capability: 'cartDetection', reason: !id ? 'productIdUnavailable' : 'quantityUnavailable', scope: 'interaction' });
          return;
        }
         candidate = { tile, productID: id, before, expires: Date.now() + confirmationWindow, lastValue: null, stableCount: 0, reported: false };
        post('cartInteractionStarted', { productID: id, beforeQuantity: before, intent: before === 0 ? 'add' : 'increment' });
        setTimeout(checkCandidate, 180);
      }, true);
      new MutationObserver(() => { if (candidate) checkCandidate(); })
        .observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
      // Coles can be interactive long before all page resources finish loading.
      // Ask native for context now rather than silently ignoring early Add taps.
      bridge.postMessage('automationReady');
    })();
    """#

    private var isLiveCartProbe: Bool {
        #if DEBUG
        return uiTestMode && [4, 5].contains(store.automationSchemaVersion) && store.cart != nil &&
            StoreProbeIsolation.permitsCartProbe(for: store.id, isPersistent: websiteDataStore.isPersistent,
                                                identifier: websiteDataStore.identifier,
                                                environment: ProcessInfo.processInfo.environment)
        #else
        return false
        #endif
    }

    private var isLiveWebsiteProbe: Bool {
        #if DEBUG
        // Browsing-only handoffs permit direct user authentication in an
        // isolated UI-test session without pretending a detector is supported.
        return isLiveCartProbe || (uiTestMode && !websiteDataStore.isPersistent &&
            ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_BROWSE_PROBE"] == store.id.rawValue)
        #else
        return false
        #endif
    }

    init(store suppliedStore: StoreDefinition, websiteDataStore: WKWebsiteDataStore, diagnostics: DiagnosticStore) {
        var store = suppliedStore
        #if DEBUG
        // Prospective bundled profiles can be tested through the real native
        // bridge without raising production ceilings. This requires BOTH an
        // isolated UI-test UUID and an explicit single-store live opt-in. The
        // Officeworks persistent experiment additionally requires its exact
        // isolated store ID and a third flag, never any canonical website store.
        // Ordinary/offline tests stay offline; release does not use this gate.
        if StoreProbeIsolation.permitsCartProbe(for: store.id, isPersistent: websiteDataStore.isPersistent,
                                               identifier: websiteDataStore.identifier,
                                               environment: ProcessInfo.processInfo.environment),
           [4, 5].contains(store.automationSchemaVersion), store.cart != nil {
            store.capabilities.cartDetection = true
            // Reversal needs its own explicit opt-in in the already isolated
            // single-store probe, plus a complete quantity/decrement contract.
            store.capabilities.cartUndo = ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_UNDO_PROBE"] == store.id.rawValue
                && (store.cart?.strategy == .verifiedCartSnapshot || store.cart?.profiles?.allSatisfy {
                    $0.confirmation == .quantityIncrease && $0.undo != nil && $0.emptyStatusText != nil
                } == true)
        }
        #endif
        self.store = store
        self.websiteDataStore = websiteDataStore
        self.intendedURL = store.homepage
        self.diagnostics = diagnostics
        self.searchUnavailable = !store.capabilities.search
        self.cartDetectionUnavailable = !store.capabilities.cartDetection
        let coordinator = Coordinator()
        self.coordinator = coordinator
        let world = WKContentWorld.world(name: "ListRunner.StoreAutomation.\(store.id.rawValue)")
        self.automationWorld = world
        self.webView = Self.makeWebView(coordinator: coordinator, world: world, store: store, dataStore: websiteDataStore)
        coordinator.browser = self
    }

    // Installed at document start even without cart automation. Remember early
    // interaction so slow images/loading cannot later pull the user backwards.
    private static let resultsScrollScript = #"""
    (() => {
      window.__listRunnerResultsScrollState = 'watching';
      let stopped = false, started = false, background = false, interval = null, deadline = null;
      // A scroll event alone is not user intent: retailers reset/restore their
      // own scroll position during hydration. Actual input (and the native pan
      // recognizer) cancels without suppressing those page-owned layout changes.
      const inputs = ['touchstart', 'pointerdown', 'wheel', 'keydown'];
      function cancel() {
        window.__listRunnerResultsScrollState = 'cancelled';
        stopped = true;
        clearInterval(interval); clearTimeout(deadline);
        for (const name of inputs) window.removeEventListener(name, cancel, true);
        window.removeEventListener('pagehide', cancel, true);
        document.removeEventListener('visibilitychange', visibility, true);
      }
      function visibility() { if (started && !background && document.visibilityState !== 'visible') cancel(); }
      for (const name of inputs) window.addEventListener(name, cancel, {capture: true, passive: true});
      window.addEventListener('pagehide', cancel, true);
      document.addEventListener('visibilitychange', visibility, true);
      window.__listRunnerCancelResultsScroll = cancel;
      window.__listRunnerScrollResults = (selector, offset, expectedURL, preload = false) => {
        // Only promotion may re-arm a background attempt. Keep input listeners
        // alive between phases so a touch before the visible check wins.
        if (stopped || (started && (!background || preload))) return;
        clearInterval(interval); clearTimeout(deadline);
        background = preload;
        started = true;
        window.__listRunnerResultsScrollState = 'waiting';
        deadline = setTimeout(() => {
          if (!background) { cancel(); return; }
          clearInterval(interval);
          window.__listRunnerResultsScrollState = 'preloadTimedOut';
        }, 8000);
        let previous = null, stable = 0, seenVisible = false;
        function check() {
          if (stopped) return;
          if (location.href !== expectedURL) { cancel(); return; }
          if (!background && document.visibilityState !== 'visible') {
            if (seenVisible) cancel();
            return;
          }
          seenVisible = true;
          if (document.readyState === 'loading') return;
          let nodes;
          try { nodes = document.querySelectorAll(selector); } catch { cancel(); return; }
          const target = Array.from(nodes).find(node => {
            const box = node.getBoundingClientRect(), style = getComputedStyle(node);
            return node.isConnected && box.width > 0 && box.height > 0 && node.getClientRects().length > 0 &&
              style.visibility === 'visible' && style.display !== 'none' && style.opacity !== '0' &&
              node.getAttribute('aria-busy') !== 'true' && !!node.textContent.trim();
          });
          if (!target) { previous = null; stable = 0; return; }
          const box = target.getBoundingClientRect();
          const position = {top: box.top + window.scrollY, height: box.height};
          stable = previous && Math.abs(previous.top - position.top) < 1 &&
            Math.abs(previous.height - position.height) < 1 ? stable + 1 : 0;
          previous = position;
          if (stable < 3) return;
          const root = document.scrollingElement;
          if (!root || !Number.isFinite(offset) || offset < 0 || offset > 500) { cancel(); return; }
          const top = Math.max(0, Math.min(position.top - offset, root.scrollHeight - window.innerHeight));
          if (background) {
            clearInterval(interval); clearTimeout(deadline);
          } else { cancel(); }
          // 'instant' overrides retailer CSS scroll-behavior:smooth, including Reduce Motion.
          // Promotion verifies geometry without an unnecessary second scroll.
          if (Math.abs(window.scrollY - top) > 1)
            window.scrollTo({top, left: window.scrollX, behavior: 'instant'});
          window.__listRunnerResultsScrollState = background ? 'preloadScrolled' : 'scrolled';
        }
        interval = setInterval(check, 100);
        check();
      };
    })();
    """#

    private var autoScrollToResults = true
    private var resultsScrollNavigation: WKNavigation?
    private var resultsScrollTask: Task<Void, Never>?
    private var resultsScrollRequestAllowed = false

    #if DEBUG
    var isResultsScrollLiveProbe: Bool {
        isLiveWebsiteProbe && ProcessInfo.processInfo.environment["LISTRUNNER_RESULTS_SCROLL_PROBE"] == store.id.rawValue
    }
    @Published private(set) var resultsScrollProbeStatus = "Waiting for results"
    private var preloadScrollFixturePositioned = false

    func waitForPreloadResultsFixture() async {
        guard uiTestMode,
              ProcessInfo.processInfo.environment["LISTRUNNER_PRELOAD_TEST_FIXTURE"] == "enabled" else { return }
        let needsPositioning = ProcessInfo.processInfo.environment["LISTRUNNER_RESULTS_SCROLL_TEST_FIXTURE"] == "enabled"
        for _ in 0..<150 {
            guard !Task.isCancelled, browsingActive, storeRecovery == nil else { return }
            if needsPositioning ? preloadScrollFixturePositioned : preloadedSearchReady { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func observePreloadScrollFixture(_ view: WKWebView, promoted: Bool, prepared: Bool = false) {
        guard uiTestMode,
              ProcessInfo.processInfo.environment["LISTRUNNER_PRELOAD_TEST_FIXTURE"] == "enabled",
              ProcessInfo.processInfo.environment["LISTRUNNER_RESULTS_SCROLL_TEST_FIXTURE"] == "enabled",
              let selector = store.search.resultsSelector else { return }
        Task { @MainActor [weak self, weak view] in
            for _ in 0..<40 {
                guard !Task.isCancelled, let self, let view,
                      (promoted ? self.webView === view : self.preloadedSearch?.view === view) else { return }
                let value = try? await view.callAsyncJavaScript("""
                    const target = document.querySelector(selector);
                    return {state: window.__listRunnerResultsScrollState || '',
                        top: target?.getBoundingClientRect().top ?? -1, y: window.scrollY};
                    """, arguments: ["selector": selector], in: nil, contentWorld: self.automationWorld)
                guard (promoted ? self.webView === view : self.preloadedSearch?.view === view) else { return }
                if let sample = value as? [String: Any],
                   sample["state"] as? String == (promoted ? "scrolled" : "preloadScrolled"),
                   let top = sample["top"] as? Double, let y = sample["y"] as? Double,
                   y > 0, abs(top - (self.store.search.resultsTopOffset ?? 12)) <= 3 {
                    if promoted {
                        self.logPreload(prepared ? "PASS: results positioned before promotion and preserved" : "FAIL: no background positioning observed")
                    } else {
                        self.preloadScrollFixturePositioned = true
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // Read-only, explicit isolated live-search proof. Reports only enum states,
    // booleans and geometry, never product/account text, query values or HTML.
    func runResultsScrollLiveProbe() async {
        guard isResultsScrollLiveProbe, let selector = store.search.resultsSelector else { return }
        for _ in 0..<60 {
            guard !Task.isCancelled, browsingActive else { return }
            let value = try? await webView.callAsyncJavaScript("""
                const target = document.querySelector(selector);
                const rect = target?.getBoundingClientRect();
                return {state: window.__listRunnerResultsScrollState || 'notInstalled',
                    matches: document.querySelectorAll(selector).length,
                    top: rect?.top ?? -1, height: rect?.height ?? 0, y: window.scrollY};
                """, arguments: ["selector": selector], in: nil, contentWorld: automationWorld)
            if let sample = value as? [String: Any] {
                let state = sample["state"] as? String ?? "unknown"
                let matches = sample["matches"] as? Int ?? 0
                let top = (sample["top"] as? NSNumber)?.doubleValue ?? -1
                let height = (sample["height"] as? NSNumber)?.doubleValue ?? 0
                let y = (sample["y"] as? NSNumber)?.doubleValue ?? 0
                let expected = store.search.resultsTopOffset ?? 12
                let passed = state == "scrolled" && matches > 0 && height > 0 && y > 0 && abs(top - expected) <= 3
                resultsScrollProbeStatus = "\(passed ? "PASS" : "WAIT"): state=\(state) matches=\(matches) top=\(Int(top)) y=\(Int(y)) urlMatches=\(webView.url == latestRequestedSearchURL)"
                if passed { return }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        resultsScrollProbeStatus = "FAIL: " + resultsScrollProbeStatus
    }
    #endif

    func setAutoScrollToResults(_ enabled: Bool) {
        autoScrollToResults = enabled
        if !enabled {
            cancelResultsScroll()
            preloadedSearch?.view.evaluateJavaScript("window.__listRunnerCancelResultsScroll?.();", in: nil, in: automationWorld)
        }
    }

    private func cancelResultsScroll() {
        resultsScrollRequestAllowed = false
        resultsScrollNavigation = nil
        resultsScrollTask?.cancel()
        resultsScrollTask = nil
        webView.evaluateJavaScript("window.__listRunnerCancelResultsScroll?.();", in: nil, in: automationWorld)
    }

    private func scrollToResults(expectedURL: URL) {
        guard autoScrollToResults, let selector = store.search.resultsSelector,
              store.allows(expectedURL), !siteVerificationRequired, storeRecovery == nil else { return }
        let view = webView
        let generation = documentGeneration
        let request = searchRequestID
        resultsScrollTask?.cancel()
        resultsScrollTask = Task { @MainActor [weak self, weak view] in
            // Promotion publishes the view before SwiftUI attaches it. Verify
            // background positioning only after attachment at the visible size.
            for _ in 0..<20 {
                guard !Task.isCancelled, let self, let view, self.webView === view,
                      self.documentGeneration == generation, self.searchRequestID == request,
                      self.autoScrollToResults, self.browsingActive, !self.siteVerificationRequired,
                      self.storeRecovery == nil, view.url == expectedURL else { return }
                if view.window != nil {
                    let arguments: [String: Any] = ["selector": selector,
                        "offset": self.store.search.resultsTopOffset ?? 12, "url": expectedURL.absoluteString]
                    // Values are arguments, never interpolated executable page content.
                    view.callAsyncJavaScript(
                        "window.__listRunnerScrollResults?.(selector, offset, url);",
                        arguments: arguments, in: nil, in: self.automationWorld)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func scrollPreloadToResults() {
        guard autoScrollToResults, browsingActive, let selector = store.search.resultsSelector,
              let preload = preloadedSearch, preloadedSearchReady,
              preload.namingGeneration == namingGeneration, preload.view.url == preload.url,
              store.allows(preload.url), !siteVerificationRequired, storeRecovery == nil else { return }
        preload.view.callAsyncJavaScript(
            "window.__listRunnerScrollResults?.(selector, offset, url, true);",
            arguments: ["selector": selector, "offset": store.search.resultsTopOffset ?? 12,
                        "url": preload.url.absoluteString], in: nil, in: automationWorld)
        #if DEBUG
        observePreloadScrollFixture(preload.view, promoted: false)
        #endif
    }

    private static func makeWebView(coordinator: Coordinator, world: WKContentWorld, store: StoreDefinition, dataStore: WKWebsiteDataStore) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if store.search.resultsSelector != nil {
            configuration.userContentController.addUserScript(WKUserScript(source: resultsScrollScript,
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
        configuration.userContentController.add(coordinator, contentWorld: world, name: "listRunner")
        if store.id == .tesco, store.capabilities.cartDetection {
            configuration.userContentController.add(coordinator, contentWorld: .page, name: "listRunnerLoginReplay")
        }
        if store.capabilities.cartDetection, let data = try? JSONEncoder().encode(store), let json = String(data: data, encoding: .utf8) {
        #if DEBUG
        let debugSource = "window.__listRunnerDebug = true;\n"
        #else
        let debugSource = ""
        #endif
        let script: String
        if store.cart?.strategy == .verifiedCartSnapshot {
            // Missing engine means manual shopping, never intended-quantity detection.
            script = Bundle.main.url(forResource: "CartSnapshotAutomation", withExtension: "js")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        } else {
            script = Self.automationScript
        }
        // The snapshot engine intercepts a user-requested Add before replaying
        // it. Install its window capture listener before retailer scripts: a
        // prior retailer window-capture handler must never send the original
        // Add as well as our one replay. Existing passive engines stay unchanged.
        let injectionTime: WKUserScriptInjectionTime = store.cart?.strategy == .verifiedCartSnapshot
            ? .atDocumentStart : .atDocumentEnd
        configuration.userContentController.addUserScript(WKUserScript(source: debugSource + "window.__listRunnerStoreConfig = \(json);\n" + script,
                                                                         injectionTime: injectionTime,
                                                                         forMainFrameOnly: true,
                                                                         in: world))
        }
        configuration.websiteDataStore = dataStore
        let view = WKWebView(frame: .zero, configuration: configuration)
        // Native edge swipe navigation stays within this WebView's history. It
        // applies to the webpage area only, leaving the card carousel gestures
        // untouched in the overlay above it.
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.scrollView.panGestureRecognizer.addTarget(coordinator, action: #selector(Coordinator.userPanned(_:)))
        return view
    }

    private let coordinator: Coordinator

    func loadIfNeeded(searchTerm: String? = nil) {
        guard canPresentStore, storeRecovery == nil else { return }
        guard !needsIdleBrowserRebuild || browsingActive else { return }
        prepareIdleBrowserIfNeeded()
        if hasLoaded {
            if let searchTerm, !searchTerm.isEmpty { search(for: searchTerm) }
            return
        }
        hasLoaded = true
        if let searchTerm, !searchTerm.isEmpty {
            search(for: searchTerm)
        } else {
            loadStoreURL(store.homepage)
        }
    }

    func reloadSearch(for searchTerm: String?) {
        guard canPresentStore, storeRecovery == nil else { return }
        if store.capabilities.search, let searchTerm,
           !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancelCartUndo()
            cancelPreload()
            // Rebuild from the selected item's saved query, not webView.url or
            // intendedURL, which may now point at a product or retailer cart.
            // search(for:) retains regional naming, coalescing and pacing.
            search(for: searchTerm)
            if siteVerificationRequired { retryAfterVerification() }
            return
        }
        // Browsing-only stores have no supported automatic search. Return to
        // their trusted homepage rather than inventing one or refreshing a cart.
        if siteVerificationRequired { retryAfterVerification(); return }
        guard navigationPacing.delay(at: ProcessInfo.processInfo.systemUptime) == 0 else { return }
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        searchRequestID = UUID()
        cancelCartUndo()
        retireCurrentNavigation()
        loadStoreURL(store.homepage)
    }

    func beginInteraction(itemID: UUID, searchTerm: String) {
        guard canPresentStore, storeRecovery == nil else { return }
        guard !needsIdleBrowserRebuild || browsingActive else { return }
        prepareIdleBrowserIfNeeded()
        cancelResultsScroll()
        cancelLoginReplay()
        cancelCartUndo()
        dismissCartUndoWarning()
        candidateTimeoutTask?.cancel()
        self.itemID = itemID
        resumableSearch = (itemID, searchTerm, namingGeneration)
        interactionEnabled = true
        interactionID = UUID().uuidString
        activeCandidate = nil
        cartDetectionUnavailable = !store.capabilities.cartDetection
        cartDetectionIssue = nil
        applyCartDetectionTestFixture()
        updateIsolatedContext()
        let effectiveTerm = effectiveSearchTerm(searchTerm)
        if let preload = preloadedSearch, preloadedSearchReady,
            preload.itemID == itemID, preload.term == searchTerm,
            preload.effectiveTerm == effectiveTerm, preload.namingGeneration == namingGeneration,
            preload.url == store.searchURL(for: effectiveTerm),
           preload.view.url.map({ store.allows($0) }) == true,
            preload.view.url?.host?.lowercased() == preload.url.host?.lowercased() {
            pendingSearchTask?.cancel()
            pendingSearchTask = nil
            searchRequestID = UUID()
            logPreload("Promoting completed preload to visible web view")
            preloadedSearch = nil
            preloadWebView = nil
            preloadedSearchReady = false
            preloadedResponseStatus = nil
            webView = preload.view
            hasLoaded = true
            documentGeneration += 1
            intendedURL = preload.view.url ?? preload.url
            latestRequestedSearchURL = preload.url
            intendedSearchNamingGeneration = namingGeneration
            latestNavigation = nil
            activeSearchNavigation = nil
            updateIsolatedContext()
            scrollToResults(expectedURL: preload.url)
            #if DEBUG
            observePreloadScrollFixture(preload.view, promoted: true, prepared: preloadScrollFixturePositioned)
            #endif
            return
        }
        if preloadedSearch != nil { logPreload("Preload unavailable or stale; falling back to normal search") }
        cancelPreload()
        search(for: searchTerm)
    }

    func preloadSearch(itemID: UUID, searchTerm: String) {
        guard !isLiveWebsiteProbe else { return }
        cancelPreload()
        guard canPresentStore, storeRecovery == nil, !siteVerificationRequired else {
            logPreload("Skipped: store is unavailable or verification is active")
            return
        }
        guard store.capabilities.search else {
            logPreload("Skipped: store search is unsupported")
            return
        }
        let pacingDelay = navigationPacing.delay(at: ProcessInfo.processInfo.systemUptime)
        let generation = namingGeneration
        if pacingDelay > 0 {
            scheduledPreload = (itemID, searchTerm)
            logPreload("Waiting \(String(format: "%.1f", pacingDelay))s for retailer navigation pacing")
            pendingPreloadTask = Task { @MainActor [weak self] in
                let nanoseconds = UInt64(max(0.05, pacingDelay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled, let self,
                      self.namingGeneration == generation,
                      self.scheduledPreload?.itemID == itemID,
                      self.scheduledPreload?.term == searchTerm else { return }
                self.pendingPreloadTask = nil
                self.scheduledPreload = nil
                self.preloadSearch(itemID: itemID, searchTerm: searchTerm)
            }
            return
        }
        let effectiveTerm = effectiveSearchTerm(searchTerm)
        guard let url = store.searchURL(for: effectiveTerm), store.allows(url) else {
            logPreload("Skipped: search URL is invalid or outside the store allowlist")
            return
        }
        let view = Self.makeWebView(coordinator: coordinator, world: automationWorld, store: store, dataStore: websiteDataStore)
        preloadedSearch = (itemID, searchTerm, effectiveTerm, generation, url, view)
        #if DEBUG
        preloadScrollFixturePositioned = false
        #endif
        preloadWebView = view
        preloadedSearchReady = false
        preloadedResponseStatus = nil
        navigationPacing.requested(at: ProcessInfo.processInfo.systemUptime)
        logPreload("Starting background navigation to \(url.host ?? "store")")
        if uiTestMode {
            // Hidden navigation must use local fixtures too: automatic UI tests
            // must never contact a retailer, even for a background preload.
            let html = ProcessInfo.processInfo.environment["LISTRUNNER_RESULTS_SCROLL_TEST_FIXTURE"] == "enabled" ? """
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
                <body style="margin:0"><h1>Preload scroll fixture</h1><div style="height:1200px">Above results</div>
                <article data-testid="product-tile" style="height:400px">Preloaded results fixture item</article>
                <div style="height:1400px">Below results</div></body></html>
                """ : "<html><head><title>Search fixture</title></head><body><h1>Search fixture</h1></body></html>"
            _ = view.loadHTMLString(html, baseURL: url)
        } else {
            _ = view.load(URLRequest(url: url))
        }
    }

    fileprivate func logPreload(_ message: String) {
        #if DEBUG
        preloadDebugStatus = message
        #endif
        automationLog("Preload: \(message)")
    }

    func cancelPreload() {
        pendingPreloadTask?.cancel()
        pendingPreloadTask = nil
        let hadScheduledPreload = scheduledPreload != nil
        scheduledPreload = nil
        guard let preload = preloadedSearch else {
            if hadScheduledPreload { logPreload("Cancelled deferred preload") }
            return
        }
        logPreload("Cancelling unused preload")
        preload.view.evaluateJavaScript("window.__listRunnerCancelResultsScroll?.();", in: nil, in: automationWorld)
        preloadedSearch = nil
        preloadWebView = nil
        preloadedSearchReady = false
        preloadedResponseStatus = nil
        preload.view.stopLoading()
        preload.view.navigationDelegate = nil
        preload.view.uiDelegate = nil
        preload.view.configuration.userContentController.removeScriptMessageHandler(forName: "listRunner", contentWorld: automationWorld)
        preload.view.configuration.userContentController.removeAllUserScripts()
    }

    func resumeInteraction(itemID: UUID, searchTerm: String) {
        guard canPresentStore, storeRecovery == nil else { return }
        if needsIdleBrowserRebuild || !hasLoaded
            || resumableSearch?.itemID != itemID
            || resumableSearch?.term != searchTerm
            || resumableSearch?.namingGeneration != namingGeneration {
            beginInteraction(itemID: itemID, searchTerm: searchTerm)
            return
        }
        self.itemID = itemID
        interactionID = UUID().uuidString
        interactionEnabled = true
        activeCandidate = nil
        updateIsolatedContext()
    }

    func search(for term: String) {
        cancelResultsScroll()
        guard canPresentStore, storeRecovery == nil else { return }
        guard store.capabilities.search else { searchUnavailable = true; loadIfNeeded(); return }
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchUnavailable = true
            return
        }
        let effectiveTerm = effectiveSearchTerm(term)
        guard let url = store.searchURL(for: effectiveTerm), store.allows(url) else {
            searchUnavailable = true
            return
        }
        latestRequestedSearchURL = url
        guard !siteVerificationRequired else { return }
        // Card taps can arrive faster than WebKit can start and cancel a navigation.
        // Coalesce them so only the final selection starts a request.
        pendingSearchTask?.cancel()
        let requestID = UUID()
        let generation = namingGeneration
        searchRequestID = requestID
        searchUnavailable = false
        hasLoaded = true
        resultsScrollRequestAllowed = autoScrollToResults && store.search.resultsSelector != nil
        let delay = max(0.5, navigationPacing.delay(at: ProcessInfo.processInfo.systemUptime))
        pendingSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.searchRequestID == requestID,
                  self.namingGeneration == generation else { return }
            self.pendingSearchTask = nil
            guard !self.siteVerificationRequired else { return }
            self.loadStoreURL(url, scrollResults: self.resultsScrollRequestAllowed)
        }
    }

    private func updateIsolatedContext() {
        guard interactionEnabled, canPresentStore, storeRecovery == nil, !siteVerificationRequired,
              let itemID, let data = try? JSONSerialization.data(withJSONObject: [
            "sessionID": sessionID,
            "interactionID": interactionID,
            "itemID": itemID.uuidString,
            "documentGeneration": documentGeneration
        ]), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__listRunnerSetContext && window.__listRunnerSetContext(\(json));",
                                   in: nil, in: automationWorld)
    }

    private var loginReplayContext: String {
        [sessionID, interactionID, itemID?.uuidString ?? ""].joined(separator: "|")
    }

    private func cancelLoginReplay(reason: LoginReplayState = .cancelled) {
        if loginReplay != nil {
            loginReplayState = reason
            Self.recoveryLogger.info("Login replay: \(reason.rawValue, privacy: .public)")
        }
        loginReplay = nil
        loginReplayReceiptInFlight = false
        loginReplayTimeoutTask?.cancel()
        if let script = loginReplayUserScript {
            let controller = webView.configuration.userContentController
            let retained = controller.userScripts.filter { $0 !== script }
            controller.removeAllUserScripts()
            retained.forEach(controller.addUserScript)
            loginReplayUserScript = nil
        }
    }

    fileprivate func observeLoginNavigation(_ url: URL) {
        let now = ProcessInfo.processInfo.systemUptime
        if var replay = loginReplay {
            guard replay.visit(url, store: store, context: loginReplayContext, now: now) else {
                cancelLoginReplay(reason: .rejectedNavigation)
                return
            }
            loginReplay = replay
            loginReplayState = StoreLoginReplay.isAuthentication(url) ? .awaitingReturn : .awaitingReceipt
            return
        }
        guard interactionEnabled, !siteVerificationRequired, storeRecovery == nil,
              StoreLoginReplay.isAuthentication(url), let activeCandidate,
              now <= activeCandidate.deadline, let sourceURL = candidatePageURL,
              var replay = StoreLoginReplay(store: store, productID: activeCandidate.productID,
                                           context: loginReplayContext, nonce: UUID().uuidString,
                                           sourceURL: sourceURL, now: now),
              replay.visit(url, store: store, context: loginReplayContext, now: now),
              let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let host = sourceURL.host,
              let data = try? JSONSerialization.data(withJSONObject: [
                "productID": replay.productID, "nonce": replay.nonce, "host": host,
                "path": components.path.replacingOccurrences(of: "/groceries/en-GB/", with: "/shop/en-GB/"),
                "search": components.percentEncodedQuery.map { "?" + $0 } ?? ""
              ]), let json = String(data: data, encoding: .utf8) else { return }
        let script = WKUserScript(source: "window.__listRunnerReplayRule = \(json);\n" + Self.loginReplayObserver,
                                  injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
        loginReplay = replay
        loginReplayState = .awaitingReturn
        Self.recoveryLogger.info("Login replay: trusted intent retained")
        loginReplayUserScript = script
        webView.configuration.userContentController.addUserScript(script)
        candidateTimeoutTask?.cancel()
        self.activeCandidate = nil
        cartDetectionIssue = nil
        let nonce = replay.nonce
        loginReplayTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, let self, self.loginReplay?.nonce == nonce else { return }
            self.cancelLoginReplay(reason: .expired)
        }
    }

    private func receiveLoginReplay(_ message: WKScriptMessage) {
        guard store.id == .tesco, store.capabilities.cartDetection, interactionEnabled,
              canPresentStore, storeRecovery == nil, !siteVerificationRequired,
              message.frameInfo.isMainFrame, message.webView === webView,
              message.frameInfo.securityOrigin.protocol == "https",
              store.allowedHosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              let url = webView.url, store.allows(url), let replay = loginReplay,
              let object = message.body as? [String: Any],
              let quantity = replay.accepts(object, url: url, context: loginReplayContext,
                                            now: ProcessInfo.processInfo.systemUptime),
              !loginReplayReceiptInFlight else { return }
        loginReplayReceiptInFlight = true
        loginReplayState = .checkingQuantity
        Self.recoveryLogger.info("Login replay: product receipt received; checking quantity")
        let generation = documentGeneration
        let view = webView
        // The page adapter cannot itself mark a native item Added. Pair its
        // product-specific receipt with the retained trusted intent and a stable
        // exact-product observation in the separate automation content world.
        view.callAsyncJavaScript("""
            for (let attempt = 0; attempt < 20; attempt++) {
                if (window.__listRunnerConfirmLoginQuantity) return await window.__listRunnerConfirmLoginQuantity(productID, quantity);
                await new Promise(resolve => setTimeout(resolve, 180));
            }
            return false;
            """, arguments: ["productID": replay.productID, "quantity": quantity], in: nil, in: automationWorld) { [weak self] result in
            guard let self, self.webView === view, self.loginReplay?.nonce == replay.nonce else { return }
            self.loginReplayReceiptInFlight = false
            guard case .success(let value) = result, value as? Bool == true,
                  self.documentGeneration == generation, self.interactionEnabled,
                  self.storeRecovery == nil, !self.siteVerificationRequired,
                  let currentURL = self.webView.url, let itemID = self.itemID,
                  replay.accepts(object, url: currentURL, context: self.loginReplayContext,
                                 now: ProcessInfo.processInfo.systemUptime) != nil else {
                self.loginReplayState = .quantityNotConfirmed
                Self.recoveryLogger.info("Login replay: returned product quantity not confirmed")
                return
            }
            self.cancelLoginReplay(reason: .confirmed)
            self.activeCandidate = nil
            self.candidateTimeoutTask?.cancel()
            self.cartDetectionUnavailable = false
            self.cartDetectionIssue = nil
            self.lastDetectedItemID = itemID
            // The authenticated baseline was not observed before this Add.
            // Acknowledgement grants local status progression, NOT cart reversal.
            self.lastDetectedAdd = CartAddRecord(storeID: self.store.id, sessionID: self.sessionID,
                interactionID: self.interactionID, documentGeneration: self.documentGeneration,
                itemID: itemID, confirmationID: replay.nonce, productID: replay.productID, before: nil, after: nil)
            self.diagnostics.record(.automation, .cartDetection, outcome: .succeeded, host: self.diagnosticHost)
            self.detectedAddSequence += 1
            self.automationLog("Post-login product acknowledgement confirmed; no inferred cart baseline")
        }
    }

    fileprivate func navigationStarted(_ navigation: WKNavigation) {
        guard canPresentStore, storeRecovery == nil, !retiredNavigations.contains(navigation), pendingSearchTask == nil else { return }
        if navigation !== resultsScrollNavigation { cancelResultsScroll() }
        // A stale start callback from a replaced search must not reclaim ownership.
        if navigation !== latestNavigation { retireCurrentNavigation() }
        if activeSearchNavigation == nil || navigation === activeSearchNavigation {
            cancelCartUndo()
            mainFrameResponseStatus = nil
            latestNavigation = navigation
        }
    }

    fileprivate func didCommitMainFrameNavigation(_ navigation: WKNavigation) {
        guard navigation === latestNavigation else { return }
        cancelCartUndo()
        documentGeneration += 1
        activeCandidate = nil
        if store.cart?.strategy == .verifiedCartSnapshot {
            // Its capture listener installs at document start, before didCommit.
            // Deliver the newly committed generation now: interactive products
            // need not wait for all retailer images/third-party resources to end.
            updateIsolatedContext()
        }
    }

    fileprivate func didFinishMainFrameNavigation(_ navigation: WKNavigation) {
        guard navigation === latestNavigation else { return }
        let shouldScroll = navigation === resultsScrollNavigation
        resultsScrollNavigation = nil
        if navigation === activeSearchNavigation {
            activeSearchNavigation = nil
            searchUnavailable = !store.capabilities.search
        }
        let status = mainFrameResponseStatus
        let generation = documentGeneration
        // Read only the title and first heading, never credentials or page body.
        webView.evaluateJavaScript("({title: document.title, heading: document.querySelector('h1')?.textContent || ''})") { [weak self] value, _ in
            guard let self, navigation === self.latestNavigation, self.documentGeneration == generation,
                  self.canPresentStore, self.storeRecovery == nil else { return }
            let page = value as? [String: String]
            if status == 429 || StoreNavigationPacing.isVerificationPage(title: page?["title"] ?? "", heading: page?["heading"] ?? "") {
                self.pauseForSiteVerification()
            } else if status == 403 {
                self.enterStoreRecovery(.loadFailed, httpStatus: status)
            } else if page != nil {
                self.siteVerificationRequired = false
                self.navigationPacing.clearBlock()
                self.cartDetectionUnavailable = !self.store.capabilities.cartDetection
                self.cartDetectionIssue = nil
                self.applyCartDetectionTestFixture()
                self.diagnostics.record(.store, .load, outcome: .succeeded, host: self.diagnosticHost)
                self.updateIsolatedContext()
                if shouldScroll, let url = self.latestRequestedSearchURL {
                    self.scrollToResults(expectedURL: url)
                }
            }
        }
    }

    private func pauseForSiteVerification() {
        cancelResultsScroll()
        cancelLoginReplay()
        siteVerificationRequired = true
        cancelPreload()
        navigationPacing.blocked(at: ProcessInfo.processInfo.systemUptime)
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        searchRequestID = UUID()
        candidateTimeoutTask?.cancel()
        activeCandidate = nil
        cartDetectionUnavailable = true
        cancelCartUndo()
        // Leave the page running so a legitimate retailer challenge can complete.
        webView.evaluateJavaScript("window.__listRunnerSetContext?.(null);", in: nil, in: automationWorld)
        diagnostics.record(.store, .load, reason: .verificationFailed, outcome: .failed, host: diagnosticHost)
    }

    func retryAfterVerification() {
        guard siteVerificationRequired, canRetryAfterVerification, canPresentStore, storeRecovery == nil else { return }
        navigationPacing.blocked(at: ProcessInfo.processInfo.systemUptime)
        // Use a known storefront URL, not the challenge document's URL. Preserve
        // the website data store (login/cart cookies) and avoid automatic retries.
        loadStoreURL(latestRequestedSearchURL ?? store.homepage, scrollResults: latestRequestedSearchURL != nil)
    }

    #if false // Replaced by StoreDefinition.addedColor; retained temporarily for source-history clarity.
    private func discoverStoreBrand(from pageURL: URL) {
        // Never inspect or fetch visual assets while on the separately trusted
        // Coles identity provider; branding is derived only from the storefront.
        guard store.allows(pageURL), !uiTestMode else { return }
        // Do not retain a colour derived from a previous storefront page when the
        // current page cannot provide a trustworthy logo.
        // A cached gradient appears immediately on later runs. Recalculate only
        // when the store has no cached, logo-derived colour yet.
        guard addedStatusGradient == nil else { return }
        let script = #"""
        (() => {
          const labelPattern = /logo|coles|woolworths/i;
          const header = document.querySelector('header, [role="banner"]');
          if (!header) return null;
          const image = Array.from(header.querySelectorAll('img')).find(image => {
            // Do not use the image URL as a signal: product and promotional
            // image CDN URLs often contain the retailer name too.
            const label = `${image.alt || ''} ${image.getAttribute('aria-label') || ''} ${image.className || ''} ${image.id || ''}`;
            return labelPattern.test(label) && image.naturalWidth > 0 && image.naturalHeight > 0;
          });
          if (image) return { imageURL: image.currentSrc || image.src };
          const logo = header.querySelector('[aria-label*="logo" i], [class*="logo" i], [id*="logo" i], [aria-label*="coles" i], [aria-label*="woolworths" i]');
          const coloured = logo?.querySelector?.('[fill]:not([fill="none"])') || logo?.querySelector?.('svg *') || logo;
          const fill = coloured ? getComputedStyle(coloured).fill : null;
          return fill && fill !== 'none' ? { cssColor: fill } : null;
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let candidate = result as? [String: Any] else { return }
            if let cssColor = candidate["cssColor"] as? String, let color = Self.color(css: cssColor) {
                self.setAddedStatusGradient(from: color)
                return
            }
            guard let source = candidate["imageURL"] as? String,
                  let imageURL = URL(string: source, relativeTo: pageURL)?.absoluteURL,
                  imageURL.scheme?.lowercased() == "https", imageURL.user == nil,
                  imageURL.password == nil, imageURL.port == nil || imageURL.port == 443 else { return }
            self.brandColorTask?.cancel()
            self.brandColorTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let (data, response) = try await URLSession.shared.data(from: imageURL)
                    guard !Task.isCancelled, data.count <= 2_000_000,
                          let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                          let color = Self.dominantLogoColor(in: data) else { return }
                    guard self.webView.url?.host?.lowercased() == pageURL.host?.lowercased() else { return }
                    self.setAddedStatusGradient(from: color)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private static func dominantLogoColor(in data: Data) -> UIColor? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = 48, height = 48, bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * bytesPerPixel, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var buckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2]), alpha = Int(pixels[offset + 3])
            let maximum = max(red, green, blue), minimum = min(red, green, blue)
            // Exclude transparent, black/white and low-saturation background pixels.
            guard alpha > 220, maximum > 55, maximum - minimum > 45 else { continue }
            let key = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.count += 1; bucket.red += red; bucket.green += green; bucket.blue += blue
            buckets[key] = bucket
        }
        guard let winner = buckets.values.max(by: { $0.count < $1.count }), winner.count >= 4 else { return nil }
        return UIColor(red: CGFloat(winner.red) / CGFloat(winner.count * 255),
                       green: CGFloat(winner.green) / CGFloat(winner.count * 255),
                       blue: CGFloat(winner.blue) / CGFloat(winner.count * 255), alpha: 1)
    }

    private static func color(css: String) -> UIColor? {
        let numbers = css.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard numbers.count >= 3 else { return nil }
        return UIColor(red: CGFloat(numbers[0]) / 255, green: CGFloat(numbers[1]) / 255,
                       blue: CGFloat(numbers[2]) / 255, alpha: 1)
    }

    private static func addedGradient(from color: UIColor) -> [Color] {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return [Color(uiColor: color), Color(uiColor: color)]
        }
        let rich = UIColor(hue: hue, saturation: max(0.55, saturation), brightness: max(0.42, brightness * 0.76), alpha: 1)
        let light = UIColor(hue: hue, saturation: min(1, max(0.45, saturation * 0.82)), brightness: min(0.90, max(0.58, brightness * 1.08)), alpha: 1)
        return [Color(uiColor: rich), Color(uiColor: light)]
    }

    private func setAddedStatusGradient(from color: UIColor) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            addedStatusGradient = [Color(uiColor: color), Color(uiColor: color)]
            cacheBrandGradient([color, color])
            return
        }
        let rich = UIColor(hue: hue, saturation: max(0.55, saturation), brightness: max(0.42, brightness * 0.76), alpha: 1)
        let light = UIColor(hue: hue, saturation: min(1, max(0.45, saturation * 0.82)), brightness: min(0.90, max(0.58, brightness * 1.08)), alpha: 1)
        addedStatusGradient = [Color(uiColor: rich), Color(uiColor: light)]
        cacheBrandGradient([rich, light])
    }

    private func cacheBrandGradient(_ colors: [UIColor]) {
        guard colors.count == 2 else { return }
        func components(of color: UIColor) -> [CGFloat]? {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            return color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) ? [red, green, blue] : nil
        }
        guard let primary = components(of: colors[0]), let secondary = components(of: colors[1]),
              let data = try? JSONEncoder().encode(StoredBrandGradient(primary: primary, secondary: secondary)) else { return }
        UserDefaults.standard.set(data, forKey: brandGradientDefaultsKey)
    }
    #endif

    private static func addedGradient(for color: StoreDefinition.AddedColor) -> [Color] {
        let base = UIColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                           blue: CGFloat(color.blue) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return [Color(uiColor: base), Color(uiColor: base)]
        }
        let rich = UIColor(hue: hue, saturation: max(0.55, saturation), brightness: max(0.42, brightness * 0.76), alpha: 1)
        let light = UIColor(hue: hue, saturation: min(1, max(0.45, saturation * 0.82)), brightness: min(0.90, max(0.58, brightness * 1.08)), alpha: 1)
        return [Color(uiColor: rich), Color(uiColor: light)]
    }

    fileprivate func didFailMainFrameNavigation(_ navigation: WKNavigation, error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        guard navigation === latestNavigation, !retiredNavigations.contains(navigation), canPresentStore else { return }
        enterStoreRecovery(.loadFailed, error: error)
    }

    private var diagnosticHost: DiagnosticEntry.Host? {
        webView.url?.host.flatMap { DiagnosticEntry.Host(rawValue: $0.lowercased()) } ?? defaultDiagnosticHost
    }

    private var defaultDiagnosticHost: DiagnosticEntry.Host? {
        store.homepage.host.flatMap { DiagnosticEntry.Host(rawValue: $0.lowercased()) }
    }

    private func retireCurrentNavigation() {
        if let latestNavigation { retiredNavigations.insert(latestNavigation) }
        if let activeSearchNavigation { retiredNavigations.insert(activeSearchNavigation) }
        latestNavigation = nil
        activeSearchNavigation = nil
    }

    private func loadStoreURL(_ requestedURL: URL, scrollResults: Bool = false) {
        cancelResultsScroll()
        var url = requestedURL
        #if DEBUG
        // Live PDP verification may enter an explicitly named product directly;
        // search has its own live probes. Never expose this in normal sessions,
        // persistent website stores, or Release builds, and keep host trust intact.
        if isLiveCartProbe,
           let raw = ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_CART_DETAIL_URL"],
           let detailURL = URL(string: raw), store.allows(detailURL),
           store.cart?.profiles?.contains(where: { $0.scope == .productPage }) == true {
            url = detailURL
        }
        if isLiveWebsiteProbe,
           ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_BROWSE_PROBE"] == store.id.rawValue,
           let raw = ProcessInfo.processInfo.environment["LISTRUNNER_LIVE_LOGIN_URL"],
           let loginURL = URL(string: raw), store.allowsNavigation(loginURL) {
            url = loginURL
        }
        #endif
        guard canPresentStore, storeRecovery == nil else { return }
        navigationPacing.requested(at: ProcessInfo.processInfo.systemUptime)
        mainFrameResponseStatus = nil
        retireCurrentNavigation()
        intendedURL = url
        intendedSearchNamingGeneration = url == latestRequestedSearchURL ? namingGeneration : nil
        #if DEBUG
        if isRegionalSearchTestFixture,
           ProcessInfo.processInfo.environment["LISTRUNNER_REGIONAL_SEARCH_TEST_FIXTURE"] == "query" {
            regionalSearchTestStatus = url.absoluteString
        }
        #endif
        hasLoaded = true
        let navigation: WKNavigation?
        if uiTestMode && !isLiveWebsiteProbe {
            // Deterministic UI fixtures never contact a retailer or a real account.
            let verificationFixture = ProcessInfo.processInfo.environment["LISTRUNNER_VERIFICATION_TEST_FIXTURE"] == "enabled"
            let resultsFixture = ProcessInfo.processInfo.environment["LISTRUNNER_RESULTS_SCROLL_TEST_FIXTURE"] == "enabled"
            // Do not expose the interactive fixture on the initial homepage:
            // XCTest must wait for the selected item's paced search to load.
            let resumeFixture = ProcessInfo.processInfo.environment["LISTRUNNER_STORE_RESUME_TEST_FIXTURE"] != nil
                && (!store.capabilities.search || url == latestRequestedSearchURL)
            let html = resumeFixture ? """
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
                <body style="margin:20px;font-size:20px">
                <button onclick="history.pushState({}, '', '/product/fixture');this.textContent='Fixture product opened'">Open fixture product</button>
                <div style="height:700px">Store resume fixture</div>
                <label>Store page note <input aria-label="Store page note" style="font-size:20px;width:90%"></label>
                <button onclick="document.activeElement.blur()">Save fixture note</button>
                <div style="height:1600px">Below fixture note</div></body></html>
                """ : resultsFixture ? """
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
                <body style="margin:0"><h1>Results scroll fixture</h1><div style="height:1200px">Content above results</div>
                <article data-testid="product-tile" style="height:400px"><h2>Results scroll fixture item</h2></article>
                <div style="height:1400px">Content below results</div></body></html>
                """ : verificationFixture
                ? "<!doctype html><html><head><title>Pardon Our Interruption</title></head><body><h1>Pardon Our Interruption</h1><p>Please stand by</p></body></html>"
                : "<!doctype html><html><body><p>Store browsing fixture</p></body></html>"
            navigation = webView.loadHTMLString(html, baseURL: url)
        } else {
            navigation = webView.load(URLRequest(url: url))
        }
        latestNavigation = navigation
        activeSearchNavigation = navigation
        resultsScrollNavigation = scrollResults && autoScrollToResults ? navigation : nil
        if navigation == nil { enterStoreRecovery(.loadFailed) }
    }

    func endInteraction() {
        cancelResultsScroll()
        cancelLoginReplay()
        cancelPreload()
        interactionEnabled = false
        interactionID = UUID().uuidString
        // A paced search cancelled before it navigated has no page to resume.
        // Reopen must request that selection rather than keep the previous item.
        if pendingSearchTask != nil { resumableSearch = nil }
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
        searchRequestID = UUID()
        candidateTimeoutTask?.cancel()
        activeCandidate = nil
        cancelCartUndo()
        webView.evaluateJavaScript("window.__listRunnerSetContext?.(null);", in: nil, in: automationWorld)
    }

    func setBrowsingActive(_ active: Bool) {
        browsingActive = active
        if !active {
            cancelResultsScroll()
            cancelPreload()
        }
    }

    fileprivate func contentProcessDidTerminate() {
        guard canPresentStore, storeRecovery == nil else { return }
        if browsingActive || siteVerificationRequired {
            enterStoreRecovery(.processTerminated)
            return
        }
        recordStoreFailure(.processTerminated)
        endInteraction()
        retireCurrentNavigation()
        webView.stopLoading()
        // Do not reload hidden stores, replay the last page/form, or clear cookies.
        // The next explicit open/resume supplies a selected search or homepage.
        needsIdleBrowserRebuild = true
        hasLoaded = false
    }

    private func prepareIdleBrowserIfNeeded() {
        guard needsIdleBrowserRebuild else { return }
        rebuildWebView()
        diagnostics.record(.store, .browserRecovery, reason: .unavailable, outcome: .succeeded,
                           host: defaultDiagnosticHost, browsingActive: browsingActive)
        Self.recoveryLogger.info("Idle browser rebuilt: store=\(self.store.id.rawValue, privacy: .public) active=\(self.browsingActive, privacy: .public)")
    }

    private func recordStoreFailure(_ recovery: StoreRecovery, error: Error? = nil, httpStatus: Int? = nil) {
        let nsError = error as NSError?
        let domain: DiagnosticEntry.FailureDomain? = nsError.map {
            $0.domain == NSURLErrorDomain ? .url : ($0.domain == WKErrorDomain ? .webKit : .other)
        }
        let reason: DiagnosticEntry.Reason
        if recovery == .processTerminated { reason = .unavailable }
        else if httpStatus != nil { reason = .httpResponse }
        else if domain == .url && nsError?.code == NSURLErrorTimedOut { reason = .timedOut }
        else if domain == .webKit { reason = .webKit }
        else { reason = .network }
        let event: DiagnosticEntry.Event = recovery == .processTerminated ? .processExit : .load
        diagnostics.record(.store, event, reason: reason, outcome: .failed, host: diagnosticHost,
                           failureDomain: domain,
                           failureCode: (domain == .url || domain == .webKit) ? nsError.flatMap { DiagnosticEntry.FailureCode(rawValue: $0.code) } : nil,
                           httpStatus: httpStatus, browsingActive: browsingActive)
        // Only enum values/numbers reach the console; never log a request URL,
        // search term, NSError description, cookies or userInfo.
        Self.recoveryLogger.error("Store failure: store=\(self.store.id.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public) domain=\(domain?.rawValue ?? "none", privacy: .public) code=\(nsError?.code ?? 0, privacy: .public) http=\(httpStatus ?? 0, privacy: .public) active=\(self.browsingActive, privacy: .public)")
    }

    fileprivate func enterStoreRecovery(_ recovery: StoreRecovery, error: Error? = nil, httpStatus: Int? = nil) {
        guard canPresentStore, storeRecovery == nil else { return }
        recordStoreFailure(recovery, error: error, httpStatus: httpStatus)
        endInteraction()
        retireCurrentNavigation()
        webView.stopLoading()
        storeRecovery = recovery
    }

    func leaveStoreRecovery() {
        storeRecovery = nil
        hasLoaded = false
    }

    func retryStoreLoad() {
        guard canPresentStore, let recovery = storeRecovery else { return }
        let staleSearch = intendedSearchNamingGeneration.map { $0 != namingGeneration } ?? false
        let url = staleSearch ? store.homepage : intendedURL
        if recovery == .processTerminated { rebuildWebView() }
        storeRecovery = nil
        interactionID = UUID().uuidString
        interactionEnabled = itemID != nil
        searchUnavailable = !store.capabilities.search
        cartDetectionUnavailable = !store.capabilities.cartDetection
        loadStoreURL(url, scrollResults: !staleSearch && url == latestRequestedSearchURL)
    }

    private func rebuildWebView() {
        needsIdleBrowserRebuild = false
        resumableSearch = nil
        cancelPreload()
        endInteraction()
        retireCurrentNavigation()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "listRunner", contentWorld: automationWorld)
        if store.id == .tesco {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "listRunnerLoginReplay", contentWorld: .page)
        }
        webView.configuration.userContentController.removeAllUserScripts()
        webView = Self.makeWebView(coordinator: coordinator, world: automationWorld, store: store, dataStore: websiteDataStore)
        documentGeneration += 1
        retiredNavigations.removeAll()
        hasLoaded = false
    }

    func resetStoreSession() {
        guard let generation = resetOperation.begin() else { return }
        resetPhase = .resetting
        endInteraction()
        sessionID = UUID().uuidString
        storeRecovery = nil
        siteVerificationRequired = false
        navigationPacing = StoreNavigationPacing()
        latestRequestedSearchURL = nil
        retireCurrentNavigation()
        webView.stopLoading()
        // Detach scripts and delegates before clearing data so an old Coles page
        // cannot repopulate website storage during reset.
        rebuildWebView()
        lastDetectedAdd = nil
        consumedUndoRecords.removeAll()
        cartUndoWarning = false
        let dataStore = websiteDataStore
        let storeID = store.id
        Task { @MainActor [weak self] in
            let verified = await StoreWebsiteData.clear(in: dataStore, for: storeID)
            guard let self, self.resetOperation.complete(generation, verified: verified) else { return }
            guard verified else {
                self.resetPhase = .failed
                self.diagnostics.record(.store, .sessionReset, reason: .verificationFailed, outcome: .failed, host: self.defaultDiagnosticHost)
                return
            }
            self.startFreshSession()
            self.diagnostics.record(.store, .sessionReset, outcome: .succeeded, host: self.defaultDiagnosticHost)
        }
    }

    func cancelFailedSessionReset() {
        guard resetOperation.cancelFailure() else { return }
        diagnostics.record(.store, .sessionReset, outcome: .cancelled, host: defaultDiagnosticHost)
        startFreshSession()
    }

    private func startFreshSession() {
        sessionID = UUID().uuidString
        interactionID = UUID().uuidString
        documentGeneration += 1
        searchUnavailable = !store.capabilities.search
        cartDetectionUnavailable = !store.capabilities.cartDetection
        resetPhase = .ready
        loadStoreURL(store.homepage)
    }

    func setBottomOverlayInset(_ inset: CGFloat) {
        // WKWebView owns the page scroll view. Its content inset creates real
        // scrollable room, so the page's final content can sit above our collapsed bar.
        let clampedInset = max(0, inset)
        guard webView.scrollView.contentInset.bottom != clampedInset else { return }
        webView.scrollView.contentInset.bottom = clampedInset
        webView.scrollView.verticalScrollIndicatorInsets.bottom = clampedInset
    }

    func dismissCartUndoWarning() {
        cartUndoWarning = false
    }

    func cancelCartUndo() {
        guard undoOperationID != nil else { return }
        undoOperationID = nil
        undoTimeoutTask?.cancel()
        webView.evaluateJavaScript("window.__listRunnerCancelUndo?.();", in: nil, in: automationWorld)
        if store.cart?.strategy == .verifiedCartSnapshot {
            // A multi-step reversal may already have issued one decrement. Do
            // not leave a restored local row looking like full retailer success.
            showCartUndoWarning()
        }
    }

    private func showCartUndoWarning() {
        cartUndoWarning = true
        diagnostics.record(.automation, .cartUndo, reason: .unavailable, outcome: .failed, host: diagnosticHost)
        UIAccessibility.post(notification: .announcement, argument: "Could not undo store cart change. ListRunner was restored. Check your \(store.displayName) cart.")
    }

    func undoCartAdd(_ record: CartAddRecord) {
        // Some retailers support observed cart adds before their reversal controls
        // are verified. Local ListRunner Undo remains available there, but must not
        // warn or attempt any store-side mutation.
        guard store.capabilities.cartUndo else { return }
        guard consumedUndoRecords.insert(record.id).inserted else { return }
        guard record.storeID == store.id, undoOperationID == nil,
              record.sessionID == sessionID, record.interactionID == interactionID,
              record.documentGeneration == documentGeneration, record.itemID == itemID,
              let before = record.before, let after = record.after,
              before >= 0, after > before, after <= 9999,
              let url = webView.url, store.allows(url) else {
            showCartUndoWarning()
            return
        }
        let operationID = UUID()
        undoOperationID = operationID
        let arguments: [String: Any] = [
            "storeID": record.storeID.rawValue,
            "sessionID": record.sessionID, "interactionID": record.interactionID,
            "documentGeneration": record.documentGeneration, "itemID": record.itemID.uuidString,
            "confirmationID": record.confirmationID, "productID": record.productID,
            "beforeQuantity": before, "resultingQuantity": after
        ]
        // The isolated script verifies its own saved confirmation as well as current
        // quantity, then confirms each decrement. It never receives arbitrary JS.
        webView.callAsyncJavaScript("return await window.__listRunnerUndoAdd(record);",
                                    arguments: ["record": arguments], in: nil, in: automationWorld) { [weak self] result in
            guard let self, self.undoOperationID == operationID else { return }
            self.undoOperationID = nil
            self.undoTimeoutTask?.cancel()
            if case .success(let value) = result, let success = value as? Bool, success {
                self.diagnostics.record(.automation, .cartUndo, outcome: .succeeded, host: self.diagnosticHost)
                self.automationLog("Store cart Undo confirmed")
            } else {
                self.showCartUndoWarning()
            }
        }
        let timeout: Duration = store.cart?.strategy == .verifiedCartSnapshot ? .seconds(46) : .seconds(4)
        undoTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.undoOperationID == operationID else { return }
            self.undoOperationID = nil
            self.webView.evaluateJavaScript("window.__listRunnerCancelUndo?.();", in: nil, in: self.automationWorld)
            self.showCartUndoWarning()
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        if message.name == "listRunnerLoginReplay" {
            receiveLoginReplay(message)
            return
        }
        guard store.capabilities.cartDetection, canPresentStore, storeRecovery == nil, !siteVerificationRequired,
              message.name == "listRunner", message.frameInfo.isMainFrame,
              message.webView === webView, let url = webView.url, store.allows(url),
              message.frameInfo.securityOrigin.protocol == "https",
              store.allowedHosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              let raw = message.body as? String, raw.utf8.count <= 8192 else { return }
        if raw == "automationReady" {
            automationLog("Detector installed; delivering item context")
            updateIsolatedContext()
            return
        }
        guard interactionEnabled,
              let object = StoreBridge.decode(raw, store: store),
              let pageText = object["pageURL"] as? String, let pageURL = URL(string: pageText), store.allows(pageURL),
              let type = object["type"] as? String,
              let messageSession = object["sessionID"] as? String, messageSession == sessionID,
              let interaction = object["interactionID"] as? String, interaction == interactionID,
              let itemText = object["itemID"] as? String, itemText == itemID?.uuidString,
              let generation = object["documentGeneration"] as? Int, generation == documentGeneration,
              object["schemaVersion"] as? Int == 1, object["storeID"] as? String == store.id.rawValue else {
            automationLog("Ignored cart message: invalid or stale context")
            return
        }

        let commonKeys: Set<String> = ["schemaVersion", "type", "storeID", "sessionID", "interactionID", "itemID", "documentGeneration", "pageURL"]
        if type == "addAcknowledged" {
            guard store.automationSchemaVersion == 4, !store.capabilities.cartUndo,
                  Set(object.keys) == commonKeys.union(["confirmationID", "productID", "profileID"]),
                  let confirmationID = object["confirmationID"] as? String,
                  let sequence = UInt64(confirmationID), sequence > 0,
                  lastAcknowledgedSequence?.generation != documentGeneration || sequence > (lastAcknowledgedSequence?.value ?? 0),
                  let productID = object["productID"] as? String, store.acceptsProductIdentity(productID),
                  let profileID = object["profileID"] as? String,
                  store.cart?.profiles?.contains(where: { $0.id == profileID && $0.confirmation == .productAcknowledgement }) == true,
                  let itemID else { return }
            lastAcknowledgedSequence = (documentGeneration, sequence)
            activeCandidate = nil
            candidateTimeoutTask?.cancel()
            cartDetectionUnavailable = false
            cartDetectionIssue = nil
            lastDetectedItemID = itemID
            lastDetectedAdd = CartAddRecord(storeID: store.id, sessionID: sessionID, interactionID: interactionID,
                                           documentGeneration: documentGeneration, itemID: itemID,
                                           confirmationID: confirmationID, productID: productID, before: nil, after: nil)
            diagnostics.record(.automation, .cartDetection, outcome: .succeeded, host: diagnosticHost)
            detectedAddSequence += 1
            automationLog("Product-specific retailer acknowledgement confirmed; notifying overlay")
            return
        }
        if type == "cartInteractionStarted" {
            guard Set(object.keys) == commonKeys.union(["productID", "beforeQuantity", "intent"]),
                  let productID = object["productID"] as? String, store.acceptsProductIdentity(productID),
                  let before = object["beforeQuantity"] as? Int, (0...9999).contains(before),
                  let intent = object["intent"] as? String,
                  intent == (before == 0 ? "add" : "increment") else { return }
            cancelLoginReplay()
            activeCandidate = (productID, before, ProcessInfo.processInfo.systemUptime + cartConfirmationTimeout)
            candidatePageURL = pageURL
            automationLog("Trusted cart tap armed quantity confirmation")
            let candidateInteraction = interactionID
            let timeout = cartConfirmationTimeout
            candidateTimeoutTask?.cancel()
            candidateTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let self, self.interactionID == candidateInteraction,
                      self.activeCandidate?.productID == productID else { return }
                self.activeCandidate = nil
                self.cartDetectionUnavailable = true
                self.cartDetectionIssue = .confirmationTimedOut
                self.diagnostics.record(.automation, .cartDetection, reason: .timedOut, outcome: .failed, host: self.diagnosticHost)
                self.automationLog("Cart confirmation timed out")
            }
            return
        }
        if type == "automationUnavailable" {
            guard Set(object.keys) == commonKeys.union(["capability", "reason", "scope"]),
                  ["productIdUnavailable", "quantityUnavailable", "confirmationTimedOut", "cartPreflightUnavailable"].contains(object["reason"] as? String ?? ""),
                  object["capability"] as? String == "cartDetection",
                  object["scope"] as? String == "interaction" else { return }
            cartDetectionUnavailable = true
            switch object["reason"] as? String {
            case "cartPreflightUnavailable": cartDetectionIssue = .cartPreflightUnavailable
            case "productIdUnavailable": cartDetectionIssue = .productIDUnavailable
            case "confirmationTimedOut": cartDetectionIssue = .confirmationTimedOut
            default: cartDetectionIssue = .quantityUnavailable
            }
            automationLog("Cart tap unsupported: \(object["reason"] as? String ?? "unknown")")
            return
        }
        guard type == "addDetected",
              Set(object.keys) == commonKeys.union(["confirmationID", "productID", "beforeQuantity", "resultingQuantity"]),
              let confirmationID = object["confirmationID"] as? String, Self.validProductID(confirmationID),
              let activeCandidate,
              ProcessInfo.processInfo.systemUptime <= activeCandidate.deadline,
              object["productID"] as? String == activeCandidate.productID,
              object["beforeQuantity"] as? Int == activeCandidate.before,
              let resulting = object["resultingQuantity"] as? Int,
              (1...9999).contains(resulting), resulting > activeCandidate.before,
              let itemID, let parsedItemID = UUID(uuidString: itemText), parsedItemID == itemID else { return }
        self.activeCandidate = nil
        cancelLoginReplay()
        candidateTimeoutTask?.cancel()
        cartDetectionUnavailable = false
        cartDetectionIssue = nil
        lastDetectedItemID = itemID
        diagnostics.record(.automation, .cartDetection, outcome: .succeeded, host: diagnosticHost)
        lastDetectedAdd = CartAddRecord(storeID: store.id, sessionID: sessionID, interactionID: interactionID,
                                       documentGeneration: documentGeneration, itemID: itemID,
                                       confirmationID: confirmationID, productID: activeCandidate.productID,
                                       before: activeCandidate.before, after: resulting)
        detectedAddSequence += 1
        automationLog("Quantity increase confirmed; notifying overlay")
    }

    private func automationLog(_ message: String) {
        #if DEBUG
        print("[ListRunner automation] \(message)")
        #endif
    }

    private func applyCartDetectionTestFixture() {
        guard uiTestMode, let fixture = ProcessInfo.processInfo.environment["LISTRUNNER_CART_DETECTION_TEST_FIXTURE"] else { return }
        cartDetectionUnavailable = true
        switch fixture {
        case "productIDUnavailable": cartDetectionIssue = .productIDUnavailable
        case "quantityUnavailable": cartDetectionIssue = .quantityUnavailable
        default: cartDetectionIssue = .confirmationTimedOut
        }
    }

    private static func validProductID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    @MainActor
    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var browser: StoreBrowser?

        private func checkPreloadReadiness(_ webView: WKWebView, browser: StoreBrowser, attempt: Int = 0) {
            guard browser.preloadedSearch?.view === webView, !browser.preloadedSearchReady else { return }
            guard browser.preloadedResponseStatus.map({ $0 < 400 }) ?? true else {
                browser.logPreload("Not usable: HTTP error response")
                return
            }
            webView.evaluateJavaScript("({state: document.readyState, title: document.title, heading: document.querySelector('h1')?.textContent || ''})") { [weak browser, weak webView] value, error in
                guard let browser, let webView, browser.preloadedSearch?.view === webView, !browser.preloadedSearchReady else { return }
                guard error == nil, let page = value as? [String: String],
                      let currentURL = webView.url, browser.store.allows(currentURL),
                      currentURL.host?.lowercased() == browser.preloadedSearch?.url.host?.lowercased() else {
                    if attempt < 15 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.checkPreloadReadiness(webView, browser: browser, attempt: attempt + 1)
                        }
                    } else {
                        browser.logPreload("Not usable: page did not reach a readable search state")
                    }
                    return
                }
                guard !StoreNavigationPacing.isVerificationPage(title: page["title"] ?? "", heading: page["heading"] ?? "") else {
                    browser.logPreload("Not usable: retailer verification page")
                    return
                }
                let readyState = page["state"] ?? "loading"
                if readyState == "interactive" || readyState == "complete" {
                    browser.preloadedSearchReady = true
                    browser.scrollPreloadToResults()
                    browser.logPreload("Background search DOM ready (\(readyState)); ready to promote")
                } else if attempt < 15 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.checkPreloadReadiness(webView, browser: browser, attempt: attempt + 1)
                    }
                } else {
                    browser.logPreload("Not usable: document remained in loading state")
                }
            }
        }

        @objc func userPanned(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began, gesture.view === browser?.webView.scrollView else { return }
            browser?.cancelResultsScroll()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            browser?.receive(message)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let browser, browser.preloadedSearch?.view === webView {
                if browser.uiTestMode && navigationAction.request.url?.absoluteString == "about:blank" {
                    decisionHandler(.allow)
                    return
                }
                decisionHandler(navigationAction.request.url.map(browser.store.allowsNavigation) == true ? .allow : .cancel)
                return
            }
            guard let browser, webView === browser.webView, browser.canPresentStore, browser.storeRecovery == nil else {
                decisionHandler(.cancel)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if browser.uiTestMode && url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            if !browser.store.allowsNavigation(url) {
                if navigationAction.targetFrame?.isMainFrame != false { browser.cancelLoginReplay() }
                if navigationAction.targetFrame?.isMainFrame != false, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame != false { browser.observeLoginNavigation(url) }
            if navigationAction.targetFrame?.isMainFrame == true,
               [.linkActivated, .formSubmitted, .backForward, .reload, .formResubmitted].contains(navigationAction.navigationType) {
                browser.cancelResultsScroll()
                browser.intendedURL = url
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let browser, browser.preloadedSearch?.view === webView {
                if navigationResponse.isForMainFrame,
                   let response = navigationResponse.response as? HTTPURLResponse {
                    browser.preloadedResponseStatus = response.statusCode
                    browser.logPreload("Received preload response HTTP \(response.statusCode)")
                }
                decisionHandler(navigationResponse.response.url.map(browser.store.allowsNavigation) == true ? .allow : .cancel)
                return
            }
            guard let browser, webView === browser.webView, browser.canPresentStore, browser.storeRecovery == nil else {
                decisionHandler(.cancel)
                return
            }
            if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
                browser.mainFrameResponseStatus = response.statusCode
                // Verification pages can return 200, 403 or 429. Let them render
                // so the user can complete the retailer's legitimate challenge.
                if response.statusCode >= 400 && ![403, 429].contains(response.statusCode) {
                    browser.enterStoreRecovery(.loadFailed, httpStatus: response.statusCode)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard webView === browser?.webView else { return }
            browser?.contentProcessDidTerminate()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let browser, browser.preloadedSearch?.view === webView {
                browser.logPreload("Background navigation failed: \(error.localizedDescription)")
                return
            }
            guard webView === browser?.webView, let navigation else { return }
            browser?.didFailMainFrameNavigation(navigation, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if let browser, browser.preloadedSearch?.view === webView {
                browser.logPreload("Background page failed: \(error.localizedDescription)")
                return
            }
            guard webView === browser?.webView, let navigation else { return }
            browser?.didFailMainFrameNavigation(navigation, error: error)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let browser, browser.preloadedSearch?.view === webView {
                browser.logPreload("Background navigation started")
                return
            }
            guard webView === browser?.webView, let navigation else { return }
            browser?.navigationStarted(navigation)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let browser, browser.preloadedSearch?.view === webView {
                browser.logPreload("Background main document committed")
                checkPreloadReadiness(webView, browser: browser)
                return
            }
            guard webView === browser?.webView, let navigation else { return }
            browser?.didCommitMainFrameNavigation(navigation)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let browser, browser.preloadedSearch?.view === webView {
                browser.logPreload("Background navigation finished")
                checkPreloadReadiness(webView, browser: browser)
                return
            }
            guard webView === browser?.webView, let navigation else { return }
            browser?.didFinishMainFrameNavigation(navigation)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let browser, webView === browser.webView, let url = navigationAction.request.url {
                if browser.store.allowsNavigation(url) { browser.loadStoreURL(url) }
                else if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
            }
            return nil
        }
    }
}

struct CartUndoWarning: View {
    let storeName: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Could not undo store cart change").font(.subheadline.weight(.semibold))
                Text("ListRunner was restored. Check your \(storeName) cart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss cart undo warning")
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PreloadedStoreWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct StoreWebView: UIViewRepresentable {
    let browser: StoreBrowser
    let bottomOverlayInset: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        browser.loadIfNeeded()
        browser.setBottomOverlayInset(bottomOverlayInset)
        return browser.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        browser.loadIfNeeded()
        browser.setBottomOverlayInset(bottomOverlayInset)
    }
}

private extension Color {
    static let listRunnerGreen = Color(red: 0.10, green: 0.52, blue: 0.37)
}

private extension View {
    @ViewBuilder
    func navigationButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            self
                .frame(minWidth: 106, maxWidth: 106, minHeight: 48)
                .buttonStyle(.borderedProminent)
        } else {
            self
                .frame(minWidth: 106, maxWidth: 106, minHeight: 48)
                .buttonStyle(.bordered)
        }
    }
}
