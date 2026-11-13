import SwiftData
import SwiftUI
import UIKit

struct ShoppingRootScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allItems: [GroceryItem]
    @StateObject private var sessions: StoreSessions
    @StateObject private var visibility: StoreVisibilityPreferences
    @StateObject private var paprikaReminders = PaprikaReminders()
    @AppStorage("activeStoreID") private var activeStoreID = StoreID.coles.rawValue
    @State private var drafts: [StoreID: String] = [:]
    @AppStorage("allItemsScope.v1") private var showingAllItems = false
    @State private var storeLaunchRequested = false
    @State private var importLaunchRequested = false
    @AppStorage("allItemsRecentStoreOrder.v1") private var allItemsRecentStoreOrder = ""
    @AppStorage("allItemsRecentItemOrder.v1") private var allItemsRecentItemOrder = ""
    @AppStorage("allItemsDraft.v1") private var allItemsDraft = ""
    @AppStorage("allItemsAddDestination.v1") private var allItemsAddDestination = ""
    @State private var welcomeCompletion = 0
    @State private var welcomeTransition = WelcomeCompletionTransition()
    // A store is one level below All items, never a growing store-to-store history.
    // nil lets the first render restore the saved scope without a launch animation.
    @State private var listPath: [StoreID]?
    @State private var overviewEnabled: Bool?
    @State private var listContentVisible = false
    @State private var previewingStoreWelcome: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--preview-store-welcome")
        #else
        return false
        #endif
    }()

    init(diagnostics: DiagnosticStore) {
        let preferences = StoreVisibilityPreferences()
        _visibility = StateObject(wrappedValue: preferences)
        _sessions = StateObject(wrappedValue: StoreSessions(diagnostics: diagnostics, preferences: preferences))
    }

    private var shoppingVisibleIDs: Set<StoreID> { sessions.shoppingAvailability.visibleIDs(in: visibility.visibleIDs) }
    private var nonEmptyListIDs: Set<UUID> {
        Set(allItems.compactMap { item in
            guard let id = item.listID, StoreID.allCases.contains(where: { $0.listID == id }) else { return nil }
            return id
        })
    }

    private var overviewAvailable: Bool {
        ShoppingListNavigationPolicy.offersAllItems(enabledStoreIDs: shoppingVisibleIDs,
                                                    itemListIDs: allItems.map(\.listID))
    }

    private var usesOverview: Bool {
        !previewingStoreWelcome && (overviewEnabled ?? overviewAvailable)
    }

    private var navigationPath: Binding<[StoreID]> {
        Binding(get: {
            listPath ?? (usesOverview && !showingAllItems
                ? [StoreID(rawValue: activeStoreID) ?? .coles] : [])
        }, set: { path in
            // SwiftUI writes this only when the native Back action/edge pop commits.
            // A cancelled interactive swipe must not change the remembered scope.
            sessions.endAllInteractions()
            listPath = path
            if let store = path.last { activeStoreID = store.rawValue }
            showingAllItems = usesOverview && path.isEmpty
        })
    }

    var body: some View {
        let storeID = StoreID(rawValue: activeStoreID) ?? .coles
        NavigationStack(path: navigationPath) {
                // A one-launch preview takes precedence without changing the saved scope.
                Group {
                    if usesOverview {
                        AllItemsScreen(sessions: sessions, visibility: visibility, paprikaReminders: paprikaReminders,
                            draft: $allItemsDraft, destinationRawValue: $allItemsAddDestination,
                            onChooseStoreList: { selectStore($0) }, onPromoteStore: promote,
                            onListVisibilityChange: listVisibilityChanged)
                    } else {
                        storeList(storeID)
                    }
                }
                .navigationDestination(for: StoreID.self) { id in
                    storeList(id)
                        // Keep the compact editor-style navigation chrome.
                        .toolbarRole(.editor)
                }
            }
            .id(welcomeCompletion)
            .background(WelcomeTransitionAnchor(transition: welcomeTransition))
            .sensoryFeedback(.success, trigger: welcomeCompletion)
            .onChange(of: shoppingVisibleIDs) { previous, current in
                // Opening management is not a choice. Keep the one-run welcome
                // preview when backing out, and finish only on an enable action.
                if !current.subtracting(previous).isEmpty {
                    previewingStoreWelcome = false
                }
            }
            .onChange(of: overviewAvailable) { _, _ in
                // Never replace the stack underneath Settings/Manage Stores.
                if listContentVisible { reconcileNavigation() }
            }
            .onAppear {
                visibility.updateNonEmptyListIDs(nonEmptyListIDs)
                let context = modelContext
                let reminders = paprikaReminders
                visibility.listItemCountsProvider = {
                    // Do not disable a destination while a local mutation has
                    // not been saved, or when the saved rows cannot be read.
                    guard !context.hasChanges, !reminders.importing else { throw StoreDefinition.ConfigurationError.invalid }
                    let rows = try context.fetch(FetchDescriptor<GroceryItem>())
                    return Dictionary(grouping: rows.compactMap(\.listID), by: { $0 }).mapValues(\.count)
                }
            }
            .onChange(of: nonEmptyListIDs) { _, ids in visibility.updateNonEmptyListIDs(ids) }
    }

    // Shared route construction for a direct single-store root and a store detail.
    private func storeList(_ storeID: StoreID) -> some View {
        GroceryListScreen(storeID: storeID, sessions: sessions, visibility: visibility,
            paprikaReminders: paprikaReminders, previewingStoreWelcome: $previewingStoreWelcome,
            rawInput: Binding(get: { drafts[storeID] ?? "" }, set: { drafts[storeID] = $0 }),
            onWelcomeStoreEnabled: completeWelcome,
            onSelectStore: { selectStore($0) }, onSelectAllItems: selectAllItems,
            storeLaunchRequested: $storeLaunchRequested, importLaunchRequested: $importLaunchRequested,
            onPromoteStore: promote, ownsNavigationStack: false,
            offersAllItems: usesOverview, onListVisibilityChange: listVisibilityChanged)
            .id(storeID)
    }

    private func selectStore(_ store: StoreID) {
        guard shoppingVisibleIDs.contains(store) else { return }
        guard showingAllItems || activeStoreID != store.rawValue else { return }
        sessions.endAllInteractions()
        var transaction = Transaction(animation: reduceMotion ? nil : .default)
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) {
            activeStoreID = store.rawValue
            showingAllItems = false
            listPath = usesOverview ? [store] : []
        }
    }

    private func selectAllItems() {
        guard usesOverview else { return }
        sessions.endAllInteractions()
        if allItemsAddDestination.isEmpty { allItemsAddDestination = activeStoreID }
        var transaction = Transaction(animation: reduceMotion ? nil : .default)
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) {
            showingAllItems = true
            listPath = []
        }
    }

    private func listVisibilityChanged(_ visible: Bool) {
        listContentVisible = visible
        if visible { reconcileNavigation() }
    }

    private func reconcileNavigation() {
        guard !previewingStoreWelcome else { return }
        let available = overviewAvailable
        guard overviewEnabled != available || (!available && showingAllItems) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            overviewEnabled = available
            if !available {
                if let onlyStore = shoppingVisibleIDs.first, shoppingVisibleIDs.count == 1 {
                    activeStoreID = onlyStore.rawValue
                }
                showingAllItems = false
            }
            listPath = available && !showingAllItems
                ? [StoreID(rawValue: activeStoreID) ?? .coles] : []
        }
    }

    private func completeWelcome(_ store: StoreID) {
        sessions.endAllInteractions()
        _ = visibility.selectionForList(current: store, definitions: sessions.definitions)
        welcomeTransition.perform(reduceMotion: reduceMotion) {
            previewingStoreWelcome = false
            activeStoreID = store.rawValue
            showingAllItems = false
            overviewEnabled = overviewAvailable
            listPath = overviewAvailable ? [store] : []
            welcomeCompletion += 1
        }
    }

    private func promote(_ store: StoreID, _ itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else { return }
        var order = allItemsRecentStoreOrder.split(separator: ",")
            .compactMap { StoreID(rawValue: String($0)) }.filter { $0 != store }
        order.insert(store, at: 0)
        allItemsRecentStoreOrder = order.map(\.rawValue).joined(separator: ",")
        allItemsRecentItemOrder = ItemPromotionOrder.promoting(itemIDs, in: allItemsRecentItemOrder,
                                                               existing: Set(allItems.map(\.id)).union(itemIDs))
    }
}

@MainActor
private final class WelcomeCompletionTransition {
    weak var anchor: UIView?
    private var overlay: UIView?

    func perform(reduceMotion: Bool, updates: () -> Void) {
        overlay?.removeFromSuperview()
        // Use this scene's window, never UIApplication's global window list.
        let window = anchor?.window
        let snapshot = reduceMotion ? nil : window?.snapshotView(afterScreenUpdates: false)
        if let window, let snapshot {
            snapshot.frame = window.bounds
            snapshot.isAccessibilityElement = false
            snapshot.accessibilityElementsHidden = true
            snapshot.isUserInteractionEnabled = true
            window.addSubview(snapshot)
            overlay = snapshot
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
        guard let snapshot else { return }
        // Give SwiftUI one update turn to build the selected store underneath.
        DispatchQueue.main.async { [weak self, weak snapshot, weak window] in
            guard let snapshot else { return }
            window?.layoutIfNeeded()
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                snapshot.alpha = 0
            } completion: { _ in
                snapshot.removeFromSuperview()
                if self?.overlay === snapshot { self?.overlay = nil }
            }
        }
    }
}

private struct WelcomeTransitionAnchor: UIViewRepresentable {
    let transition: WelcomeCompletionTransition

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        transition.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        transition.anchor = view
    }
}

// Shared presentation for store lists and the aggregate. Each screen supplies
// its data/actions, not a second implementation of the page's visual structure.
// SpatialTapGesture alone can accept a short drag. Give movement priority so a
// small repositioning scroll cannot also become an outside tap-to-dismiss.
private func entryDismissTap(_ action: @escaping (CGPoint) -> Void) -> some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
        .exclusively(before: SpatialTapGesture(coordinateSpace: .global))
        .onEnded { value in
            if case .second(let tap) = value { action(tap.location) }
        }
}

private struct ShoppingListPage<Scope: View, Footer: View, Rows: View>: View {
    var isWelcome = false
    var joinsScopeControls = false
    var keyboardDismissMode: ScrollDismissesKeyboardMode = .interactively
    var onViewportChange: (CGRect) -> Void = { _ in }
    @ViewBuilder let scope: () -> Scope
    @ViewBuilder let footer: () -> Footer
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        List { rows() }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .scrollIndicators(isWelcome ? .hidden : .automatic, axes: .vertical)
            .scrollDismissesKeyboard(keyboardDismissMode)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onViewportChange($0) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isWelcome {
                    HStack {
                        Text("ListRunner").font(.title3.weight(.bold))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        if !isWelcome { scope() }
                    }
                    .sharedBackgroundVisibility(joinsScopeControls ? .hidden : .automatic)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        if !isWelcome { scope() }
                    }
                }
            }
            .toolbar(isWelcome ? .hidden : .visible, for: .navigationBar)
    }
}

private struct StoreListScopeControl<Picker: View>: View {
    let showsBack: Bool
    let tint: Color
    @ViewBuilder let picker: () -> Picker

    var body: some View {
        picker()
            .frame(minHeight: showsBack ? 44 : nil)
            .padding(.trailing, showsBack ? 10 : 0)
        .modifier(JoinedStoreScopeChrome(joined: showsBack, tint: tint))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-navigation-control")
    }
}

private struct JoinedStoreScopeChrome: ViewModifier {
    let joined: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if joined, #available(iOS 26.0, *) {
            content.buttonStyle(.plain)
                .background {
                    GeometryReader { geometry in
                        // The compact native Back target is 44 points, followed
                        // by the system's 16-point gap to leading custom items.
                        // Extend only the decoration, never the chooser hit area.
                        Color.clear
                            .frame(width: geometry.size.width + 60, height: geometry.size.height)
                            .glassEffect(.regular, in: .capsule)
                            .overlay(alignment: .leading) {
                                // The shared material is composited above the
                                // native item's glyph. Draw decoration over it;
                                // the native Back remains the sole hit/AX target.
                                Image(systemName: "chevron.backward")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(tint)
                                    .frame(width: 44, height: geometry.size.height)
                            }
                            .frame(width: geometry.size.width, alignment: .trailing)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}

// Import sheets still own a stack; list routes share the root stack so the
// platform supplies both the transition and cancellable interactive edge pop.
private struct ListNavigationContainer<Content: View>: View {
    let standalone: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if standalone {
            NavigationStack { content() }
        } else {
            content()
        }
    }
}

// Keep the actual native Back button and interactive pop. Only its colour and
// individual decoration change; the chooser supplies their shared glass surface.
private struct StoreListNativeBack: UIViewControllerRepresentable {
    let tint: Color
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.storeTint = UIColor(tint)
        DispatchQueue.main.async { [weak controller] in controller?.apply() }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore()
    }

    final class Controller: UIViewController {
        var storeTint = UIColor.label
        private weak var styledItem: UINavigationItem?
        private var originalBack: UIBarButtonItem?
        private let storeBack = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        override func loadView() {
            let anchor = UIView()
            anchor.isUserInteractionEnabled = false
            view = anchor
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                self?.apply()
                DispatchQueue.main.async { [weak self] in self?.apply() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }

        func apply() {
            guard viewIfLoaded?.window != nil, let navigationController else { return }
            var host = parent
            while let candidate = host, !navigationController.viewControllers.contains(where: { $0 === candidate }) {
                host = candidate.parent
            }
            guard let host, navigationController.topViewController === host,
                  navigationController.viewControllers.count > 1 else { return }
            guard let index = navigationController.viewControllers.firstIndex(where: { $0 === host }), index > 0 else { return }
            let item = navigationController.viewControllers[index - 1].navigationItem
            if styledItem !== item {
                restore()
                styledItem = item
                originalBack = item.backBarButtonItem
            }
            storeBack.tintColor = storeTint
            storeBack.accessibilityLabel = String(localized: "Back to All items")
            if #available(iOS 26.0, *) { storeBack.hidesSharedBackground = true }
            if item.backBarButtonItem !== storeBack { item.backBarButtonItem = storeBack }
        }

        func restore() {
            if styledItem?.backBarButtonItem === storeBack { styledItem?.backBarButtonItem = originalBack }
            styledItem = nil
            originalBack = nil
        }
    }
}

private struct ListScopePicker: View {
    let stores: [StoreDefinition]
    let selectedStoreID: StoreID?
    let tint: Color
    let onChooseAllItems: () -> Void
    let onChooseStore: (StoreID) -> Void
    let onManageStores: () -> Void
    var offersAllItems = true

    var body: some View {
        Menu {
            if offersAllItems {
                if selectedStoreID == nil {
                    Label("All items", systemImage: "checkmark")
                } else {
                    Button(action: onChooseAllItems) { Label("All items", systemImage: "square.grid.2x2") }
                }
                Divider()
            }
            ForEach(stores, id: \.id) { store in
                Button(store.displayName) { onChooseStore(store.id) }
            }
            Divider()
            Button("Manage Stores", action: onManageStores)
                .accessibilityIdentifier("store-picker-manage-stores")
        } label: {
            HStack(spacing: 6) {
                Text(selectedStoreID?.displayName ?? "All items")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.black))
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(selectedStoreID == nil ? "all-items-scope-picker" : "store-picker")
        .accessibilityHint("Each store has its own shopping list and basket")
    }
}

private struct ListPageToolbar: ToolbarContent {
    var showSettings = true
    let onSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if showSettings {
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
    }
}

private struct ListPageSummary: View {
    let pending: Int
    let added: Int
    let skipped: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pending + added + skipped > 0 && pending == 0 ? "Complete" : "Ready when you are")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ListSummaryMetric(count: pending, title: "Pending", tint: tint)
                Divider().frame(height: 32)
                ListSummaryMetric(count: added, title: "Added", tint: tint)
                Divider().frame(height: 32)
                ListSummaryMetric(count: skipped, title: "Skipped", tint: .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pending) pending, \(added) added, \(skipped) skipped")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ListSummaryMetric: View {
    let count: Int
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(count, format: .number).font(.headline.monospacedDigit()).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProductEntryActionsLayout: Layout {
    var preferStacked: Bool
    private let spacing: CGFloat = 8

    private func fits(_ subviews: Subviews, width: CGFloat) -> Bool {
        !preferStacked && subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(max(0, subviews.count - 1)) <= width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width } + spacing
        let horizontal = fits(subviews, width: width)
        let sizes = subviews.map { $0.sizeThatFits(horizontal ? .unspecified : ProposedViewSize(width: width, height: nil)) }
        let height = horizontal ? (sizes.map(\.height).max() ?? 0)
            : sizes.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let horizontal = fits(subviews, width: bounds.width)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(horizontal ? .unspecified : ProposedViewSize(width: bounds.width, height: nil))
            let x = horizontal && index == subviews.count - 1 ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: horizontal ? bounds.midY - size.height / 2 : y),
                          anchor: .topLeading, proposal: ProposedViewSize(size))
            y += size.height + spacing
        }
    }
}

private struct ProductAddButtonChrome: ViewModifier {
    var tint: Color = .accentColor
    @ScaledMetric(relativeTo: .body) private var lineHeight = 20.333333
    @ScaledMetric(relativeTo: .body) private var verticalPadding = 7.0

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background {
                Capsule().fill(tint)
                    .padding(.vertical, max(0, (44 - lineHeight - 2 * verticalPadding) / 2))
            }
            .contentShape(Rectangle())
    }
}

private struct ProductAddButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var verticalPadding = 7.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body)
            .padding(.horizontal, 14).padding(.vertical, verticalPadding)
            .frame(minHeight: 44)
            .modifier(ProductAddButtonChrome(tint: tint))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

private struct ProductEntrySection<AddButton: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusControl: ProductEntryFocus
    let tint: Color
    var accessibilityIdentifier = "grocery-input"
    let importing: Bool
    let importConfigured: Bool
    var importDisabled = false
    var compactImport = false
    let removeReminders: Bool
    let onSubmit: () -> Void
    let onImport: () -> Void
    let onTextChange: (String) -> Void
    var onFocus: () -> Void = {}
    var onEditorFrame: (CGRect) -> Void = { _ in }
    var onActionsFrame: (CGRect) -> Void = { _ in }
    var onManualScroll: () -> Void = {}
    @ViewBuilder let addButton: () -> AddButton

    var body: some View {
        Section("Add products") {
            ProductEntryEditor(text: $text, isFocused: $isFocused, focusControl: focusControl,
                               onSubmit: onSubmit, accessibilityIdentifier: accessibilityIdentifier,
                               onManualScroll: onManualScroll)
                .onChange(of: text) { _, value in onTextChange(value) }
                .modifier(ProductEntryFieldStyle(tint: tint, isFocused: isFocused))
                .simultaneousGesture(TapGesture().onEnded {
                    isFocused = true
                    onFocus()
                })
                .onGeometryChange(for: CGRect?.self) { isFocused ? $0.frame(in: .global) : nil } action: { frame in
                    if let frame { onEditorFrame(frame) }
                }
                .padding(.vertical, 4)
                .id("product-entry-editor")
            ProductEntryActionsLayout(preferStacked: dynamicTypeSize.isAccessibilitySize) {
                Button(action: onImport) {
                    Label(importing ? "Importing…" : compactImport ? "Import" :
                            importConfigured ? "Import from Paprika" : "Import items...",
                          systemImage: importing ? "hourglass" : "checklist")
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .disabled(importing || importDisabled)
                .accessibilityIdentifier(importConfigured ? "import-from-paprika" : "set-import-source")
                .accessibilityHint(importConfigured ?
                    (removeReminders ? "Imports unchecked Paprika reminders and removes them after saving groceries" : "Imports unchecked Paprika reminders and keeps them linked") : "Choose your grocery import source")
                addButton()
            }
            .padding(.vertical, 4)
            .id("product-entry-actions")
            .onGeometryChange(for: CGRect?.self) { isFocused ? $0.frame(in: .global) : nil } action: { frame in
                if let frame { onActionsFrame(frame) }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }
}

private struct ListItemContent: View {
    let name: String
    let quantity: String
    var ownerName: String?
    var unavailable = false
    let status: GroceryStatus
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentenceCase(name)).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let ownerName {
                    Text("\(ownerName) · Quantity \(quantity)\(unavailable ? " · Unavailable" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Quantity \(quantity)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            Text(status.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(tint.opacity(0.11), in: Capsule())
        }
        .contentShape(Rectangle())
    }
}

private struct ListItemActions<Actions: View>: View {
    let name: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Menu { actions() } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for \(name)")
    }
}

private enum ListItemRowLayout {
    // Native List traits must be applied after row geometry/identity modifiers.
    // Otherwise List can add its default 15 pt vertical insets as well.
    static let insets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
}

private struct ShoppingListItemRow<Actions: View>: View {
    let name: String
    let quantity: String
    var ownerName: String?
    var unavailable = false
    let status: GroceryStatus
    let tint: Color
    let accessibilityLabel: String
    var nativeSelection = false
    let onOpen: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            if nativeSelection {
                // UITableView cancels selection for a swipe or drag. A hosted
                // SwiftUI Button can also fire on touch cancellation, opening
                // the store over the Delete action underneath it.
                itemContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onOpen() }
            } else {
                Button(action: onOpen) { itemContent }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel)
            }
            ListItemActions(name: name, actions: actions)
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 48)
        // Include padding inside measured scroll identity, not outside it.
        .padding(.vertical, 15)
        .tint(tint)
    }

    private var itemContent: some View {
        ListItemContent(name: name, quantity: quantity, ownerName: ownerName,
                        unavailable: unavailable, status: status,
                        tint: status == .skipped ? .secondary : tint)
    }
}

private struct AllItemsAddButton: View {
    @ScaledMetric(relativeTo: .body) private var verticalPadding = 7.0
    let destination: StoreID?
    let stores: [StoreDefinition]
    let onChooseDestination: (StoreID) -> Void
    let canAdd: Bool
    let onAdd: () -> Void
    let onManageStores: () -> Void

    var body: some View {
        if let destination {
            HStack(spacing: 0) {
                Button(action: onAdd) {
                    Text("Add to \(destination.displayName)")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 14).padding(.trailing, 12)
                        .padding(.vertical, verticalPadding)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!canAdd)
                .accessibilityIdentifier("all-items-add")
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 26)
                Menu {
                    ForEach(stores, id: \.id) { store in
                        Button { onChooseDestination(store.id) } label: {
                            if store.id == destination { Label(store.displayName, systemImage: "checkmark") }
                            else { Text(store.displayName) }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Choose add destination")
                .accessibilityValue(destination.displayName)
                .accessibilityIdentifier("all-items-add-destination")
            }
            .modifier(ProductAddButtonChrome())
        } else {
            Menu {
                if stores.isEmpty { Button("Manage Stores", action: onManageStores) }
                else {
                    ForEach(stores, id: \.id) { store in
                        Button(store.displayName) { onChooseDestination(store.id) }
                    }
                }
            } label: {
                Label("Choose Store", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct AllItemsShoppingFooter: View {
    let stores: [StoreDefinition]
    let hasItems: Bool
    let isTyping: Bool
    let onChooseStore: (StoreID) -> Void
    let onManageStores: () -> Void

    var body: some View {
        if !isTyping && !stores.isEmpty {
            Menu {
                ForEach(stores, id: \.id) { store in
                    Button("Shop at \(store.displayName)") { onChooseStore(store.id) }
                }
            } label: {
                Label("Show Store...", systemImage: "cart.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .modifier(StoreLaunchButtonStyle(tint: .accentColor))
            .accessibilityIdentifier("all-items-show-store")
            .padding(.horizontal, 20).padding(.top, 8)
            .padding(.bottom, -12)
        } else if !isTyping && hasItems {
            Button("Manage Stores", action: onManageStores)
                .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                .padding(.horizontal, 20)
        }
    }
}

private enum AllItemsGrouping: String {
    case store
    case category
}

private struct AllItemsGroupingSwitcher: View {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var selection: AllItemsGrouping

    var body: some View {
        HStack(spacing: 0) {
            option("By store", value: .store)
            option("By category", value: .category)
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group items")
        .accessibilityIdentifier("all-items-grouping")
    }

    private func option(_ title: LocalizedStringKey, value: AllItemsGrouping) -> some View {
        Button { selection = value } label: {
            Text(title)
                .font(.body.weight(selection == value ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selection == value ? Color.white : Color.primary)
                .background(selection == value ? Color.accentColor : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .accessibilityIdentifier("all-items-grouping-\(value.rawValue)")
    }
}

private struct AllItemsGroup: Identifiable {
    let id: String
    let title: String
    let storeIDs: [StoreID]
    let items: [GroceryItem]
}

private struct AllItemsClearRequest {
    let groupID: String
    let itemIDs: Set<UUID>
}

private struct AllItemsGroupHeader: View {
    let group: AllItemsGroup
    let tint: Color
    let addStore: StoreID?
    let openStore: StoreID?
    let onOpenStore: (StoreID) -> Void
    let onAdd: (StoreID) -> Void
    var onAddFrame: (StoreID, CGRect) -> Void = { _, _ in }

    var body: some View {
        HStack {
            if let openStore {
                Button { onOpenStore(openStore) } label: {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint("Opens the \(group.title) shopping list")
                .accessibilityIdentifier("all-items-group-title-\(group.id)")
            } else {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("all-items-group-title-\(group.id)")
            }
            Spacer()
            if let addStore {
                Button { onAdd(addStore) } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add items to \(group.title)")
                .accessibilityIdentifier("all-items-group-add-\(addStore.rawValue)")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    onAddFrame(addStore, $0)
                }
                .onDisappear { onAddFrame(addStore, .zero) }
            }
            Text(group.items.count, format: .number).foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .frame(minHeight: 44)
    }
}

// These measurements drive hit testing and imperative reveal corrections, not
// view rendering. Updating them during a drag must not invalidate every group.
@MainActor
private final class AllItemsInteractionGeometry {
    var editor: CGRect = .zero
    var actions: CGRect = .zero
    var groupAddButtons: [StoreID: CGRect] = [:]
}

private struct AllItemsGroupRegion<Content: View>: View {
    let nativeRows: Bool
    let order: [StoreID]
    let reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if nativeRows {
            content()
        } else {
            Section {
                // One native host row keeps section-slot reuse out of group
                // reorders. SwiftUI moves the complete, stably identified cards.
                VStack(spacing: 16, content: content)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: order)
                    .padding(.vertical, 1)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

private struct AllItemsGroupCard<Content: View>: View {
    let nativeRows: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if nativeRows {
            Section(content: content)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// Each browse card owns real native item rows, but never a second scrolling
// surface. The outer List scrolls; this table supplies swipe actions and local
// drag/drop while SwiftUI animates the complete card around it.
private struct AllItemsItemRows<Row: View>: View {
    let groupID: String
    let items: [GroceryItem]
    let canReorder: Bool
    let onReorder: ([UUID], UUID?) -> Void
    let onDelete: (GroceryItem) -> Void
    let onSelect: (GroceryItem) -> Void
    @ViewBuilder let row: (GroceryItem) -> Row
    @State private var height: CGFloat = 0

    var body: some View {
        AllItemsItemTable(groupID: groupID, items: items, canReorder: canReorder,
            onReorder: onReorder, onDelete: onDelete, onSelect: onSelect, onHeightChange: { value in
                if abs(height - value) > 0.5 { height = value }
            }, row: row)
            .frame(height: height > 0 ? height : CGFloat(items.count) * 78)
    }
}

private struct AllItemsItemTable<Row: View>: UIViewRepresentable {
    let groupID: String
    let items: [GroceryItem]
    let canReorder: Bool
    let onReorder: ([UUID], UUID?) -> Void
    let onDelete: (GroceryItem) -> Void
    let onSelect: (GroceryItem) -> Void
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let row: (GroceryItem) -> Row

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ContentTable {
        let table = ContentTable(frame: .zero, style: .plain)
        table.onHeightChange = onHeightChange
        table.backgroundColor = .clear
        table.isScrollEnabled = false
        table.contentInsetAdjustmentBehavior = .never
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 78
        table.sectionHeaderHeight = 0
        table.sectionFooterHeight = 0
        table.sectionHeaderTopPadding = 0
        table.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.dragDelegate = context.coordinator
        table.dropDelegate = context.coordinator
        table.dragInteractionEnabled = canReorder
        table.allowsSelection = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "item")
        table.reloadData()
        return table
    }

    func updateUIView(_ table: ContentTable, context: Context) {
        let changed = context.coordinator.items.map(\.id) != items.map(\.id)
        context.coordinator.parent = self
        context.coordinator.items = items
        table.onHeightChange = onHeightChange
        table.dragInteractionEnabled = canReorder
        if changed {
            table.reloadData()
        } else {
            for path in table.indexPathsForVisibleRows ?? [] {
                if let cell = table.cellForRow(at: path) { context.coordinator.configure(cell, at: path) }
            }
        }
    }

    final class ContentTable: UITableView {
        var onHeightChange: ((CGFloat) -> Void)?
        private var heightUpdateScheduled = false

        override var contentSize: CGSize {
            didSet {
                guard abs(oldValue.height - contentSize.height) > 0.5, !heightUpdateScheduled else { return }
                heightUpdateScheduled = true
                // Never lay out hosting cells synchronously from SwiftUI's
                // sizeThatFits: that re-enters its active AttributeGraph pass.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.heightUpdateScheduled = false
                    if self.contentSize.height > 0 { self.onHeightChange?(self.contentSize.height) }
                }
            }
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate {
        var parent: AllItemsItemTable
        var items: [GroceryItem]

        init(parent: AllItemsItemTable) { self.parent = parent; items = parent.items }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { parent.canReorder }

        func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
            guard items.indices.contains(indexPath.row) else { return }
            let item = items[indexPath.row]
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.contentConfiguration = UIHostingConfiguration { parent.row(item) }.margins(.all, 0)
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
            configure(cell, at: indexPath)
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: false)
            guard items.indices.contains(indexPath.row) else { return }
            parent.onSelect(items[indexPath.row])
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard items.indices.contains(indexPath.row) else { return nil }
            let item = items[indexPath.row]
            let action = UIContextualAction(style: .destructive, title: String(localized: "Delete")) { [weak self] _, _, done in
                guard let self, self.items.contains(where: { $0.id == item.id }) else { done(false); return }
                self.parent.onDelete(item)
                done(true)
            }
            action.image = UIImage(systemName: "trash")
            let actions = UISwipeActionsConfiguration(actions: [action])
            actions.performsFirstActionWithFullSwipe = false
            return actions
        }

        func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            guard parent.canReorder, items.indices.contains(indexPath.row) else { return [] }
            let item = items[indexPath.row]
            session.localContext = parent.groupID
            let drag = UIDragItem(itemProvider: NSItemProvider(object: item.id.uuidString as NSString))
            drag.localObject = item.id
            return [drag]
        }

        func tableView(_ tableView: UITableView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

        func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
            parent.canReorder && (session.localDragSession?.localContext as? String) == parent.groupID
        }

        func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession,
                       withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
            UITableViewDropProposal(operation: self.tableView(tableView, canHandle: session) ? .move : .forbidden,
                                    intent: .insertAtDestinationIndexPath)
        }

        func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
            guard self.tableView(tableView, canHandle: coordinator.session),
                  let drop = coordinator.items.first, let id = drop.dragItem.localObject as? UUID,
                  let source = items.firstIndex(where: { $0.id == id }) else { return }
            let destination = min(coordinator.destinationIndexPath?.row ?? items.count - 1, items.count - 1)
            guard destination >= 0 else { return }
            let item = items.remove(at: source)
            items.insert(item, at: destination)
            tableView.moveRow(at: IndexPath(row: source, section: 0), to: IndexPath(row: destination, section: 0))
            parent.onReorder([id], items.indices.contains(destination + 1) ? items[destination + 1].id : nil)
            coordinator.drop(drop.dragItem, toRowAt: IndexPath(row: destination, section: 0))
        }
    }
}

private struct AllItemsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GroceryItem.position) private var allItems: [GroceryItem]
    @Query private var lists: [GroceryList]
    @ObservedObject var sessions: StoreSessions
    @ObservedObject var visibility: StoreVisibilityPreferences
    @ObservedObject var paprikaReminders: PaprikaReminders
    @Binding var draft: String
    @Binding var destinationRawValue: String
    let onChooseStoreList: (StoreID) -> Void
    let onPromoteStore: (StoreID, [UUID]) -> Void
    var onListVisibilityChange: (Bool) -> Void = { _ in }
    @AppStorage("allItemsGrouping.v1") private var groupingRawValue = AllItemsGrouping.store.rawValue
    @AppStorage("allItemsRecentStoreOrder.v1") private var recentStoreOrderRawValue = ""
    @AppStorage("allItemsRecentItemOrder.v1") private var recentItemOrderRawValue = ""
    @State private var notice: String?
    @State private var showingStoreManagement = false
    @State private var showingSettings = false
    @State private var editMode = EditMode.inactive
    @State private var workingStoreID: StoreID?
    @State private var workingStoreOrder: [StoreID] = []
    @State private var groupAddRequest: UUID?
    @State private var groupAddFocusRequest: UUID?
    @State private var clearRequest: AllItemsClearRequest?
    @State private var editingItem: GroceryItem?
    @State private var shoppingDestination: StoreID?
    @State private var importDestination: StoreID?
    @State private var importRequested = false
    @State private var pendingReminderWrites: [UUID: ReminderWriteback] = [:]
    @State private var entryFocused = false
    @State private var entryFocus = ProductEntryFocus()
    @State private var listViewportFrame: CGRect = .zero
    @State private var interactionGeometry = AllItemsInteractionGeometry()
    @State private var entryRevealTask: Task<Void, Never>?
    @State private var entryRevealSuppressed = false
    @State private var isRevealingEntry = false
    @State private var scrollTargetItemID: UUID?
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var addedItemScrollTask: Task<Void, Never>?
    @State private var addedItemScrollRequestID = UUID()
    @State private var highlightedItemIDs = Set<UUID>()
    @State private var saveFailed = false
    @AppStorage(GroceryImportSource.removeRemindersKey) private var removeRemindersAfterImport = true
    @AppStorage(GroceryImportSource.preferenceKey) private var importSourceID = ""

    private var grouping: AllItemsGrouping {
        AllItemsGrouping(rawValue: groupingRawValue) ?? .store
    }
    private var usesNativeGroupRows: Bool {
        editMode.isEditing
    }
    private var shoppingVisibleIDs: Set<StoreID> {
        sessions.shoppingAvailability.visibleIDs(in: visibility.visibleIDs)
    }
    private var destinationID: StoreID? {
        let id = StoreID(rawValue: destinationRawValue)
        return id.flatMap { shoppingVisibleIDs.contains($0) ? $0 : nil }
    }
    private var visibleStores: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                               enabledIDs: shoppingVisibleIDs)
    }
    private var shoppingStores: [StoreDefinition] {
        let populatedListIDs = Set(allItems.map(\.listID))
        return visibleStores.filter { populatedListIDs.contains($0.id.listID) }
    }
    private var pendingCount: Int { allItems.filter { $0.status == .pending }.count }
    private var addedCount: Int { allItems.filter { $0.status == .added }.count }
    private var skippedCount: Int { allItems.filter { $0.status == .skipped }.count }
    private var recency: [StoreID] {
        recentStoreOrderRawValue.split(separator: ",").compactMap { StoreID(rawValue: String($0)) }
    }

    private var groups: [AllItemsGroup] {
        let itemRanks = ItemPromotionOrder.ranks(recentItemOrderRawValue)
        func groupRank(_ group: AllItemsGroup) -> Int {
            group.items.compactMap { itemRanks[$0.id] }.min() ?? Int.max
        }
        let storesByList = Dictionary(uniqueKeysWithValues: StoreID.allCases.map { ($0.listID, $0) })
        let owned = allItems.compactMap { item -> (StoreID?, GroceryItem)? in
            guard let listID = item.listID, let store = storesByList[listID] else { return (nil, item) }
            return (store, item)
        }
        let definitions = Dictionary(uniqueKeysWithValues: sessions.definitions.map { ($0.id, $0) })
        func storeOrder(_ ids: [StoreID]) -> [StoreID] {
            let ranked = ids.sorted { lhs, rhs in
                let li = recency.firstIndex(of: lhs) ?? Int.max
                let ri = recency.firstIndex(of: rhs) ?? Int.max
                return li == ri ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending : li < ri
            }
            return ranked
        }
        if grouping == .store {
            var known: [AllItemsGroup] = []
            for id in StoreID.allCases {
                let matching: [GroceryItem] = owned.filter { $0.0 == id }.map(\.1)
                let values = matching.sorted { left, right in
                    if left.position == right.position { return left.id.uuidString < right.id.uuidString }
                    return left.position < right.position
                }
                if !values.isEmpty || (!editMode.isEditing && workingStoreID == id && shoppingVisibleIDs.contains(id)) {
                    known.append(AllItemsGroup(id: "store-\(id.rawValue)", title: id.displayName, storeIDs: [id], items: values))
                }
            }
            known.sort { lhs, rhs in
                if workingStoreID != nil {
                    let left = lhs.storeIDs.first.flatMap { workingStoreOrder.firstIndex(of: $0) } ?? Int.max
                    let right = rhs.storeIDs.first.flatMap { workingStoreOrder.firstIndex(of: $0) } ?? Int.max
                    if left != right { return left < right }
                }
                let li = groupRank(lhs), ri = groupRank(rhs)
                return li == ri ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : li < ri
            }
            let orphaned = owned.filter { $0.0 == nil }.map(\.1).sorted { $0.position < $1.position }
            return known + (orphaned.isEmpty ? [] : [AllItemsGroup(id: "uncategorised", title: "Uncategorised", storeIDs: [], items: orphaned)])
        }
        let byCategory: [StoreCategory?: [(StoreID?, GroceryItem)]] = Dictionary(grouping: owned) { pair in
            pair.0.flatMap { definitions[$0]?.category ?? $0.defaultCategory }
        }
        let categorized = StoreCategory.allCases.compactMap { category -> AllItemsGroup? in
            let values = byCategory[.some(category)] ?? []
            guard !values.isEmpty else { return nil }
            let storeIDs = storeOrder(Array(Set(values.compactMap(\.0))))
            let order = Dictionary(uniqueKeysWithValues: storeIDs.enumerated().map { ($1, $0) })
            let historicalItems = values.sorted { lhs, rhs in
                let li = lhs.0.flatMap { order[$0] } ?? Int.max, ri = rhs.0.flatMap { order[$0] } ?? Int.max
                return li == ri ? (lhs.1.position == rhs.1.position ? lhs.1.id.uuidString < rhs.1.id.uuidString : lhs.1.position < rhs.1.position) : li < ri
            }.map(\.1)
            let sortedItems = historicalItems.enumerated().sorted { lhs, rhs in
                let left = itemRanks[lhs.element.id] ?? Int.max, right = itemRanks[rhs.element.id] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
            return AllItemsGroup(id: "category-\(category.rawValue)", title: category.displayName,
                                 storeIDs: storeIDs, items: sortedItems)
        }.sorted { lhs, rhs in
            let li = groupRank(lhs), ri = groupRank(rhs)
            return li == ri ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : li < ri
        }
        let orphaned = byCategory[.none] ?? []
        guard !orphaned.isEmpty else { return categorized }
        return categorized + [AllItemsGroup(id: "uncategorised", title: "Uncategorised", storeIDs: [],
                                             items: orphaned.map(\.1).sorted { $0.position < $1.position })]
    }

    var body: some View {
        ScrollViewReader { proxy in
        ShoppingListPage(keyboardDismissMode: isRevealingEntry ? .never : .interactively,
            onViewportChange: { frame in
                listViewportFrame = frame
                revealFocusedEntry()
                if let id = scrollTargetItemID { scrollToAddedItem(id, using: proxy) }
            }, scope: {
                ListScopePicker(stores: visibleStores, selectedStoreID: nil, tint: .accentColor,
                    onChooseAllItems: {}, onChooseStore: onChooseStoreList,
                    onManageStores: { showingStoreManagement = true })
            }, footer: {
                AllItemsShoppingFooter(stores: shoppingStores, hasItems: !allItems.isEmpty,
                    isTyping: entryFocused, onChooseStore: { shoppingDestination = $0 },
                    onManageStores: { showingStoreManagement = true })
            }) {
            Section {
                ListPageSummary(pending: pendingCount, added: addedCount, skipped: skippedCount, tint: .accentColor)
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
                    .onTapGesture { entryFocused = false }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
            ProductEntrySection(text: $draft, isFocused: $entryFocused, focusControl: entryFocus,
                tint: .accentColor, accessibilityIdentifier: "all-items-entry",
                importing: paprikaReminders.importing,
                importConfigured: GroceryImportSource(rawValue: importSourceID) == .paprika,
                importDisabled: destinationID == nil, compactImport: true,
                removeReminders: removeRemindersAfterImport, onSubmit: {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { entryFocused = false }
                    else { addItems() }
                }, onImport: importItems, onTextChange: { value in
                    guard value == draft else { return }
                    if value.contains(where: { $0.isNewline }) { addItems() }
                    else if !value.isEmpty {
                        addedItemScrollTask?.cancel()
                        addedItemScrollTask = nil
                        scrollTargetItemID = nil
                        entryRevealSuppressed = false
                        revealFocusedEntry()
                    }
                }, onFocus: {
                    addedItemScrollTask?.cancel()
                    addedItemScrollTask = nil
                    scrollTargetItemID = nil
                    entryRevealSuppressed = false
                    revealFocusedEntry()
                }, onEditorFrame: { frame in
                    let heightChanged = abs(interactionGeometry.editor.height - frame.height) > 0.5
                    interactionGeometry.editor = frame
                    if heightChanged { revealFocusedEntry() }
                }, onActionsFrame: { interactionGeometry.actions = $0 }, onManualScroll: userScrolled) {
                    AllItemsAddButton(destination: destinationID, stores: visibleStores,
                         onChooseDestination: selectAddDestination,
                        canAdd: !ParsedGrocery.productEntries(in: draft).isEmpty,
                        onAdd: addItems, onManageStores: { showingStoreManagement = true })
                }
            Section {
                AllItemsGroupingSwitcher(selection: Binding(
                    get: { grouping }, set: { groupingRawValue = $0.rawValue }))
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            if groups.isEmpty {
                ContentUnavailableView("Your lists are empty", systemImage: "basket",
                                       description: Text("Add products above, or choose a store list."))
                    .listRowBackground(Color.clear)
            } else {
                AllItemsGroupRegion(nativeRows: usesNativeGroupRows, order: workingStoreOrder, reduceMotion: reduceMotion) {
                ForEach(groups) { group in
                    AllItemsGroupCard(nativeRows: usesNativeGroupRows) {
                        AllItemsGroupHeader(group: group,
                            tint: grouping == .store && !group.storeIDs.isEmpty ? storeTint(group.storeIDs[0]) : .secondary,
                            addStore: grouping == .store
                                ? group.storeIDs.first.flatMap { shoppingVisibleIDs.contains($0) ? $0 : nil } : nil,
                            openStore: grouping == .store
                                ? group.storeIDs.first.flatMap { shoppingVisibleIDs.contains($0) ? $0 : nil } : nil,
                            onOpenStore: onChooseStoreList,
                            onAdd: { store in
                                // Let this tap finish before moving its button.
                                // Otherwise outside-tap dismissal can compare
                                // the original touch with its new frame.
                                DispatchQueue.main.async { beginAdding(to: store, using: proxy) }
                            },
                            onAddFrame: { interactionGeometry.groupAddButtons[$0] = $1 })
                        .padding(.horizontal, usesNativeGroupRows ? 0 : 20)
                        .padding(.vertical, usesNativeGroupRows ? 0 : 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        if group.items.isEmpty {
                            Text("No items yet. Add products above.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, usesNativeGroupRows ? 0 : 20)
                                .padding(.vertical, 16)
                                .accessibilityIdentifier("all-items-empty-\(group.id)")
                        } else {
                            if !usesNativeGroupRows { Divider().padding(.horizontal, 16) }
                            groupItemRows(group, using: proxy)
                        }
                        if !group.items.isEmpty {
                        ClearListButton {
                            entryFocused = false
                            entryFocus.resignFirstResponder()
                            clearRequest = AllItemsClearRequest(groupID: group.id,
                                itemIDs: Set(group.items.map(\.id)))
                        }
                        .accessibilityLabel("Clear \(group.title) list")
                        .accessibilityIdentifier("all-items-clear-\(group.id)")
                        .confirmationDialog("Clear your list?", isPresented: Binding(
                            get: { clearRequest?.groupID == group.id },
                            set: { if !$0 { clearRequest = nil } }), titleVisibility: .visible) {
                            if clearCandidates.contains(where: { $0.status == .added }) {
                                Button("Clear Added", role: .destructive) { clearItems(addedOnly: true) }
                            }
                            Button("Clear All", role: .destructive) { clearItems(addedOnly: false) }
                            Button("Cancel", role: .cancel) { clearRequest = nil }
                        } message: {
                            if grouping == .store {
                                Text("This clears only your \(group.title) list in ListRunner. It does not change any store cart or Apple Reminders.")
                            } else {
                                Text("This clears only items shown in the \(group.title) category in ListRunner, across its store lists. It does not change any store cart or Apple Reminders.")
                            }
                        }
                        }
                    }
                    .id(group.id)
                    .zIndex(!editMode.isEditing && group.storeIDs.first == workingStoreID ? 1 : 0)
                }
                }
            }
            if let notice {
                Section {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                    if saveFailed { Button("Retry save") { saveChanges() } }
                }
            }
        }
        .onChange(of: recentItemOrderRawValue) { _, value in
            if let itemID = groups.first?.items.first?.id {
                // Promote/reveal the new group within the same scrolling page.
                // Typing again reveals the shared editor, as on a store list.
                entryRevealSuppressed = true
                entryRevealTask?.cancel()
                scrollTargetItemID = itemID
                if usesNativeGroupRows {
                    withAnimation { proxy.scrollTo(itemID, anchor: .bottom) }
                } else {
                    scrollToAddedItem(itemID, using: proxy)
                }
            }
        }
        .onChange(of: groupingRawValue) { _, _ in
            workingStoreID = nil
            groupAddRequest = nil
        }
        .task(id: groupAddFocusRequest) {
            guard let request = groupAddFocusRequest else { return }
            // A section move can preserve List's old visible-row anchor and
            // displace the editor after the simultaneous scroll. Resolve its
            // stable row ID again against the finished section layout.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                proxy.scrollTo("product-entry-editor", anchor: .top)
            }
            // List can attach/reuse the editor after the section animation has
            // completed. Keep the intent until UIKit actually accepts focus,
            // rather than treating a SwiftUI Boolean as an acknowledgement.
            for _ in 0..<20 {
                guard !Task.isCancelled, groupAddRequest == request,
                      !showingSettings, !showingStoreManagement,
                      editingItem == nil, shoppingDestination == nil,
                      importDestination == nil, clearRequest == nil else { return }
                if let editor = entryFocus.view, editor.window != nil {
                    entryFocused = true
                    if !editor.isFirstResponder { editor.becomeFirstResponder() }
                    await Task.yield()
                    guard !Task.isCancelled, groupAddRequest == request else { return }
                    if entryFocus.view === editor, editor.isFirstResponder {
                        groupAddRequest = nil
                        entryRevealSuppressed = false
                        revealFocusedEntry()
                        return
                    }
                }
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
            if groupAddRequest == request { groupAddRequest = nil }
        }
        .onChange(of: destinationRawValue) { _, value in
            if let workingStoreID, workingStoreID.rawValue != value {
                self.workingStoreID = nil
                groupAddRequest = nil
            }
        }
        .onChange(of: shoppingVisibleIDs) { _, ids in
            if let workingStoreID, !ids.contains(workingStoreID) {
                self.workingStoreID = nil
                groupAddRequest = nil
            }
        }
        .onChange(of: scrollTargetItemID) { _, id in
            addedItemScrollTask?.cancel()
            addedItemScrollTask = nil
            if let id { scrollToAddedItem(id, using: proxy) }
        }
        .onChange(of: entryFocused) { _, focused in
            entryRevealSuppressed = focused && !highlightedItemIDs.isEmpty
            if focused { revealFocusedEntry() }
            else { entryRevealTask?.cancel() }
        }
        .task(id: recentItemOrderRawValue) {
            guard !highlightedItemIDs.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.25))
            guard !Task.isCancelled else { return }
            highlightedItemIDs.removeAll()
        }
        }
        .toolbar {
            ListPageToolbar {
                entryFocused = false
                entryFocus.resignFirstResponder()
                showingSettings = true
            }
        }
        .environment(\.editMode, $editMode)
        .simultaneousGesture(
            entryDismissTap { location in
                guard entryFocused,
                      !interactionGeometry.editor.contains(location),
                      !interactionGeometry.actions.contains(location),
                      !interactionGeometry.groupAddButtons.values.contains(where: { $0.contains(location) }) else { return }
                groupAddRequest = nil
                entryFocused = false
            },
            including: entryFocused && !showingSettings && !showingStoreManagement
                && shoppingDestination == nil && importDestination == nil ? .all : .subviews
        )
        .onChange(of: editMode) { _, value in
            if value.isEditing {
                groupAddRequest = nil
                entryFocused = false
                entryFocus.resignFirstResponder()
            }
        }
        .onChange(of: allItems.isEmpty) { _, isEmpty in
            if isEmpty { editMode = .inactive }
        }
        .navigationDestination(isPresented: $showingSettings) {
            SettingsOverviewScreen(sessions: sessions, visibility: visibility,
                importInProgress: paprikaReminders.importing,
                importDestinationName: destinationID?.displayName ?? "selected store",
                onOpenStoreList: { id in
                    showingSettings = false
                    onChooseStoreList(id)
                }) {
                    showingSettings = false
                    importItems()
                }
        }
        .navigationDestination(isPresented: $showingStoreManagement) {
            StoreVisibilityScreen(sessions: sessions, visibility: visibility,
                onOpenStoreList: { id in
                    showingStoreManagement = false
                    onChooseStoreList(id)
                })
        }
        .sheet(item: $editingItem) { item in
            ItemEditorSheet(item: item) { name, amount, unit in
                item.name = name
                item.searchTerm = name
                item.quantityAmount = amount
                item.quantityUnit = amount == nil ? nil : unit
                item.status = .pending
                stageReminderWriteback(for: item)
                saveChanges()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $shoppingDestination) { store in
            StoreShoppingView(items: allItems.filter { $0.listID == store.listID }.sorted { $0.position < $1.position },
                browser: sessions.browser(for: store),
                initialSelectedID: lists.first { $0.id == store.listID }?.selectedItemID,
                saveFailed: saveFailed,
                onSelectionChange: { id in
                    lists.first { $0.id == store.listID }?.selectedItemID = id
                    saveChanges()
                }, onStatusChange: { item in
                    stageReminderWriteback(for: item)
                    saveChanges()
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $importDestination) { store in
            GroceryListScreen(storeID: store, sessions: sessions, visibility: visibility,
                paprikaReminders: paprikaReminders, previewingStoreWelcome: .constant(false),
                rawInput: .constant(""), onWelcomeStoreEnabled: { _ in },
                onSelectStore: { _ in }, onSelectAllItems: { importDestination = nil },
                storeLaunchRequested: .constant(false), importLaunchRequested: $importRequested,
                onPromoteStore: onPromoteStore, onImportCompleted: { message in
                    notice = message
                    importDestination = nil
                })
                .interactiveDismissDisabled(paprikaReminders.importing)
        }
        .onAppear {
            onListVisibilityChange(true)
            if destinationRawValue.isEmpty, !visibleStores.isEmpty {
                // The root supplies the previously viewed store on first entry.
                // Do not reach into a different defaults suite here (UI tests
                // and recovery use their own isolated app preferences).
                destinationRawValue = visibleStores[0].id.rawValue
            }
        }
        .onDisappear {
            onListVisibilityChange(false)
            entryFocused = false
            entryFocus.resignFirstResponder()
            if let workingStoreID, !allItems.contains(where: { $0.listID == workingStoreID.listID }) {
                self.workingStoreID = nil
            }
            groupAddRequest = nil
            entryRevealTask?.cancel()
            addedItemScrollTask?.cancel()
            addedItemScrollTask = nil
            scrollTargetItemID = nil
        }
    }

    private func userScrolled() {
        groupAddRequest = nil
        entryRevealTask?.cancel()
        entryRevealSuppressed = true
        addedItemScrollTask?.cancel()
        addedItemScrollTask = nil
        scrollTargetItemID = nil
        itemFrames.removeAll(keepingCapacity: true)
    }

    @ViewBuilder
    private func groupItemRows(_ group: AllItemsGroup, using proxy: ScrollViewProxy) -> some View {
        if usesNativeGroupRows {
            ForEach(group.items, id: \.id) { item in
                groupItemRow(item, using: proxy)
            }
            .onMove(perform: grouping == .store && group.storeIDs.count == 1 ? { source, destination in
                moveItems(in: group, from: source, to: destination)
            } : nil)
        } else {
            AllItemsItemRows(groupID: group.id, items: group.items,
                canReorder: grouping == .store && group.storeIDs.count == 1,
                onReorder: { reorderItems($0, before: $1, in: group) }, onDelete: delete,
                onSelect: openAllItem) { item in
                    groupItemRow(item, using: proxy)
                }
        }
    }

    @ViewBuilder
    private func groupItemRow(_ item: GroceryItem, using proxy: ScrollViewProxy) -> some View {
        let row = allItemRow(item, nativeSelection: !usesNativeGroupRows)
            .padding(.horizontal, usesNativeGroupRows ? 0 : 16)
            .background(highlightedItemIDs.contains(item.id) ? Color.accentColor.opacity(0.12) : Color.clear)
            .id(item.id)
            .onGeometryChange(for: CGRect?.self) { geometry in
                scrollTargetItemID == item.id ? geometry.frame(in: .global) : nil
            } action: { frame in
                guard let frame, scrollTargetItemID == item.id else { return }
                itemFrames[item.id] = frame
                scrollToAddedItem(item.id, using: proxy)
            }
            .onAppear {
                if scrollTargetItemID == item.id { scrollToAddedItem(item.id, using: proxy) }
            }
            .listRowBackground(highlightedItemIDs.contains(item.id)
                ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
            .listRowInsets(ListItemRowLayout.insets)
        if usesNativeGroupRows {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                    .accessibilityHint("Removes this item from ListRunner only, not the store cart")
                    .accessibilityIdentifier("all-items-delete-\(item.id.uuidString)")
            }
        } else {
            // Browse items already have UITableView contextual actions. A
            // SwiftUI swipeActions trait here bubbles up to the outer List's
            // shared host cell, making every header swipe expose all Deletes.
            row
        }
    }

    private func revealFocusedEntry() {
        entryRevealTask?.cancel()
        guard entryFocused, !entryRevealSuppressed else { return }
        entryRevealTask = entryFocus.revealCard(geometry: {
            guard entryFocused, !entryRevealSuppressed else { return nil }
            return ProductEntryRevealGeometry(editor: interactionGeometry.editor, actions: interactionGeometry.actions,
                                              viewport: listViewportFrame)
        }, onRevealing: { isRevealingEntry = $0 })
    }

    private func selectAddDestination(_ store: StoreID) {
        guard shoppingVisibleIDs.contains(store) else { return }
        groupAddRequest = nil
        groupAddFocusRequest = nil
        let promotedOrder = workingOrder(promoting: store)
        destinationRawValue = store.rawValue
        guard grouping == .store, !editMode.isEditing else { return }
        // Changing destination is not a request to open/dismiss the keyboard or
        // submit the draft. Animate only the same temporary group priority.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            workingStoreOrder = promotedOrder
            workingStoreID = store
        }
    }

    private func workingOrder(promoting store: StoreID) -> [StoreID] {
        [store] + groups.compactMap { $0.storeIDs.first }.filter { $0 != store }
    }

    private func beginAdding(to store: StoreID, using proxy: ScrollViewProxy) {
        guard grouping == .store, !editMode.isEditing, shoppingVisibleIDs.contains(store) else { return }
        addedItemScrollTask?.cancel()
        addedItemScrollTask = nil
        scrollTargetItemID = nil
        itemFrames.removeAll(keepingCapacity: true)
        highlightedItemIDs.removeAll()
        entryRevealTask?.cancel()
        // Do not let keyboard/viewport corrections compete with the move.
        // Keep an existing first responder, but defer new focus until it finishes.
        entryRevealSuppressed = true
        destinationRawValue = store.rawValue
        let request = UUID()
        groupAddRequest = request
        groupAddFocusRequest = nil
        // Promote within the currently displayed order, not the saved recency
        // order: the old first group becomes second, with no long-distance swap.
        let promotedOrder = workingOrder(promoting: store)
        // This is a temporary working-group priority, not a fabricated add event.
        // Saved recency is updated only by the existing successful add/import path.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4), completionCriteria: .removed) {
            workingStoreOrder = promotedOrder
            workingStoreID = store
        } completion: {
            DispatchQueue.main.async { finishGroupAdd(request, to: store) }
        }
        if reduceMotion {
            proxy.scrollTo("product-entry-editor", anchor: .top)
        } else {
            // List's scrollTo can synchronously relayout its host row and
            // consume the card animation if both start in the same update.
            // Give the card its first rendered frames, then overlap the scroll.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard groupAddRequest == request else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo("product-entry-editor", anchor: .top)
                }
            }
        }
    }

    private func finishGroupAdd(_ request: UUID, to store: StoreID) {
        guard groupAddRequest == request, workingStoreID == store,
              destinationID == store, !editMode.isEditing,
              shoppingVisibleIDs.contains(store) else { return }
        groupAddFocusRequest = request
    }

    private func scrollToAddedItem(_ id: UUID, using proxy: ScrollViewProxy) {
        guard addedItemScrollTask == nil else { return }
        let requestID = UUID()
        addedItemScrollRequestID = requestID
        addedItemScrollTask = ListItemReveal.start(isCurrent: {
            scrollTargetItemID == id && allItems.contains { $0.id == id }
        }, geometry: {
            guard let target = itemFrames[id] else { return nil }
            return ListItemRevealGeometry(target: target, viewport: listViewportFrame)
        }, scroll: { anchor, animated in
            if !usesNativeGroupRows, let frame = itemFrames[id] {
                // Browse cards share a native host row; scroll to the measured
                // item, not to the bottom of that entire native cell.
                let adjustment = anchor == .bottom
                    ? frame.maxY - listViewportFrame.maxY : frame.minY - listViewportFrame.minY
                entryFocus.adjustListOffset(by: adjustment, animated: animated, requiresFocus: false)
            } else {
                withAnimation(animated ? .easeInOut(duration: 0.35) : nil) { proxy.scrollTo(id, anchor: anchor) }
            }
        }, finished: {
            if addedItemScrollRequestID == requestID { addedItemScrollTask = nil }
        })
    }

    private func allItemRow(_ item: GroceryItem, nativeSelection: Bool = false) -> some View {
        let owner = StoreID.allCases.first { $0.listID == item.listID }
        let available = owner.map { shoppingVisibleIDs.contains($0) } ?? false
        return ShoppingListItemRow(name: item.name, quantity: item.displayQuantity,
            ownerName: owner?.displayName ?? "Uncategorised", unavailable: !available,
            status: item.status, tint: owner.map(storeTint) ?? .accentColor,
            accessibilityLabel: "\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)\(owner.map { ", \($0.displayName)" } ?? ", Uncategorised")\(available ? "" : ", Unavailable")",
            nativeSelection: nativeSelection, onOpen: { openAllItem(item) }) {
                Button("Edit Item", systemImage: "pencil") { editingItem = item }
                if item.status == .pending {
                    Button("Mark Added", systemImage: "checkmark.circle") { setStatus(.added, for: item) }
                } else if item.status == .added {
                    Button("Mark Pending", systemImage: "arrow.uturn.backward.circle") { setStatus(.pending, for: item) }
                }
                if item.status != .skipped {
                    Button("Mark Skipped", systemImage: "forward.end") { setStatus(.skipped, for: item) }
                } else {
                    Button("Mark Pending", systemImage: "arrow.uturn.backward.circle") { setStatus(.pending, for: item) }
                }
                    Menu("Move to Another Store", systemImage: "arrow.right.arrow.left") {
                        ForEach(visibleStores.filter { $0.id != owner }, id: \.id) { store in
                            Button(store.displayName) { move(item, to: store.id) }
                        }
                    }
                Button("Delete Item", systemImage: "trash", role: .destructive) { delete(item) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("all-item-\(item.id.uuidString)")
    }

    private func openAllItem(_ item: GroceryItem) {
        guard !editMode.isEditing else { editingItem = item; return }
        guard let owner = StoreID.allCases.first(where: { $0.listID == item.listID }) else {
            notice = "This saved item has no recognized store list. It remains visible and has not been moved or deleted."
            return
        }
        guard shoppingVisibleIDs.contains(owner) else {
            notice = "Shopping with \(owner.displayName) is unavailable. This saved item remains editable here; use its Actions menu to edit or move it."
            return
        }
        let list = lists.first { $0.id == owner.listID }
        list?.selectedItemID = item.id
        if saveChanges() { shoppingDestination = owner }
    }

    private func setStatus(_ status: GroceryStatus, for item: GroceryItem) {
        item.status = status
        stageReminderWriteback(for: item)
        saveChanges()
    }

    private func moveItems(in group: AllItemsGroup, from source: IndexSet, to destination: Int) {
        guard grouping == .store, group.storeIDs.count == 1 else { return }
        var orderedItems = group.items
        orderedItems.move(fromOffsets: source, toOffset: destination)
        for (position, item) in orderedItems.enumerated() {
            item.position = position
        }
        saveChanges()
    }

    private func reorderItems(_ sources: [UUID], before destination: UUID?, in group: AllItemsGroup) {
        guard grouping == .store, group.storeIDs.count == 1, let store = group.storeIDs.first else { return }
        let current = allItems.filter { $0.listID == store.listID }.sorted {
            $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position
        }
        // A drag from another card must never become a cross-store transfer.
        guard let order = ShoppingLists.reorderedIDs(current.map(\.id), moving: sources, before: destination),
              order != current.map(\.id) else { return }
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for (position, id) in order.enumerated() { byID[id]?.position = position }
        saveChanges()
    }

    private func move(_ item: GroceryItem, to destination: StoreID) {
        guard visibleStores.contains(where: { $0.id == destination }) else { return }
        let source = StoreID.allCases.first(where: { $0.listID == item.listID })
        if let source, let sourceList = lists.first(where: { $0.id == source.listID }), sourceList.selectedItemID == item.id {
            sourceList.selectedItemID = ShoppingLists.selection(afterRemoving: item.id,
                from: allItems.filter { $0.listID == source.listID })
        }
        if let source { sessions.browser(for: source).endInteraction() }
        ShoppingLists.move(item, to: destination, allItems: allItems)
        stageReminderWriteback(for: item)
        if saveChanges() { notice = "Moved item to \(destination.displayName)." }
    }

    private func delete(_ item: GroceryItem) {
        if let owner = StoreID.allCases.first(where: { $0.listID == item.listID }) {
            let sourceItems = allItems.filter { $0.listID == owner.listID }
            if let list = lists.first(where: { $0.id == owner.listID }), list.selectedItemID == item.id {
                list.selectedItemID = ShoppingLists.selection(afterRemoving: item.id, from: sourceItems)
            }
            for (position, remaining) in sourceItems.filter({ $0.id != item.id }).enumerated() {
                remaining.position = position
            }
        }
        modelContext.delete(item)
        pendingReminderWrites.removeValue(forKey: item.id)
        paprikaReminders.cancelQueuedWriteback(for: item)
        saveChanges()
    }

    private var clearCandidates: [GroceryItem] {
        guard let clearRequest, let group = groups.first(where: { $0.id == clearRequest.groupID }) else { return [] }
        // Clear only rows covered by this confirmation that still belong to this
        // group. A concurrent import or move must not expand the destructive scope.
        return group.items.filter { clearRequest.itemIDs.contains($0.id) }
    }

    private func clearItems(addedOnly: Bool) {
        let removed = clearCandidates.filter { !addedOnly || $0.status == .added }
        let removedIDs = Set(removed.map(\.id))
        clearRequest = nil
        guard !removed.isEmpty else { return }
        for listID in Set(removed.map(\.listID)) {
            let remaining = allItems.filter { $0.listID == listID && !removedIDs.contains($0.id) }
            if let owner = StoreID.allCases.first(where: { $0.listID == listID }) {
                sessions.browser(for: owner).endInteraction()
            }
            if let list = lists.first(where: { $0.id == listID }) {
                if remaining.isEmpty {
                    list.selectedItemID = nil
                } else if let selectedID = list.selectedItemID, removedIDs.contains(selectedID) {
                    list.selectedItemID = remaining.first { $0.status == .pending }?.id ?? remaining.first?.id
                }
            }
            for (position, item) in remaining.enumerated() { item.position = position }
        }
        for item in removed {
            pendingReminderWrites.removeValue(forKey: item.id)
            paprikaReminders.cancelQueuedWriteback(for: item)
            modelContext.delete(item)
        }
        highlightedItemIDs.subtract(removedIDs)
        notice = nil
        saveChanges()
    }

    private func stageReminderWriteback(for item: GroceryItem) {
        guard !removeRemindersAfterImport else { return }
        if let write = paprikaReminders.desiredWriteback(for: item) { pendingReminderWrites[item.id] = write }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            saveFailed = false
            let writes = Array(pendingReminderWrites.values)
            pendingReminderWrites.removeAll()
            for write in writes { paprikaReminders.queueWriteback(write) }
            return true
        } catch {
            saveFailed = true
            notice = "Changes may not be saved. Try again."
            return false
        }
    }

    private func importItems() {
        guard let destinationID else {
            notice = "Choose an enabled store before importing."
            return
        }
        entryFocused = false
        entryFocus.resignFirstResponder()
        entryRevealTask?.cancel()
        importRequested = true
        importDestination = destinationID
    }

    private func addItems() {
        let entries = ParsedGrocery.productEntries(in: draft)
        guard let destinationID, !entries.isEmpty else { return }
        guard !modelContext.hasChanges else {
            notice = "Save or retry your pending list changes before adding more items. Your text is still here."
            return
        }
        let promoted = ShoppingLists.stageAdd(entries, to: destinationID, allItems: allItems, context: modelContext)
        for item in promoted { stageReminderWriteback(for: item) }
        do {
            try modelContext.save()
            let writes = Array(pendingReminderWrites.values)
            pendingReminderWrites.removeAll()
            for write in writes { paprikaReminders.queueWriteback(write) }
            var order = recency.filter { $0 != destinationID }
            order.insert(destinationID, at: 0)
            recentStoreOrderRawValue = order.map(\.rawValue).joined(separator: ",")
            onPromoteStore(destinationID, promoted.map(\.id))
            highlightedItemIDs = Set(promoted.map(\.id))
            draft = ""
            entryFocused = true
            notice = "Added \(promoted.count) \(promoted.count == 1 ? "item" : "items") to \(destinationID.displayName)."
            UIAccessibility.post(notification: .announcement, argument: notice)
        } catch {
            modelContext.rollback()
            pendingReminderWrites.removeAll()
            notice = "Could not save the items. Your text is still here; try again."
        }
    }

    private func storeTint(_ id: StoreID) -> Color {
        guard let definition = sessions.definitions.first(where: { $0.id == id }) else { return .secondary }
        let color = definition.brandColors?.primary ?? definition.addedColor
        return Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }


}

struct GroceryListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \GroceryItem.position) private var allItems: [GroceryItem]
    @Query private var lists: [GroceryList]
    @StateObject private var browser: StoreBrowser
    @ObservedObject var visibility: StoreVisibilityPreferences
    @ObservedObject var paprikaReminders: PaprikaReminders
    let storeID: StoreID
    let sessions: StoreSessions
    let onSelectStore: (StoreID) -> Void
    let onSelectAllItems: () -> Void
    @Binding var storeLaunchRequested: Bool
    @Binding var importLaunchRequested: Bool
    let onPromoteStore: (StoreID, [UUID]) -> Void
    let onImportCompleted: ((String) -> Void)?
    let onWelcomeStoreEnabled: (StoreID) -> Void
    let ownsNavigationStack: Bool
    let offersAllItems: Bool
    let onListVisibilityChange: (Bool) -> Void
    @Binding private var rawInput: String
    @State private var routedLaunch = false
    @State private var itemToMove: GroceryItem?
    @State private var editingItem: GroceryItem?
    @State private var showingStore = false
    @State private var showingStoreManagement = false
    @State private var managingWelcomeStores = false
    // Root-owned so changing the active store cannot restart a dismissed preview.
    @Binding private var previewingStoreWelcome: Bool
    @State private var showingImportSetup = false
    @State private var showingSettings = false
    @AppStorage(GroceryImportSource.preferenceKey) private var importSourceID = ""
    @AppStorage(GroceryImportSource.removeRemindersKey) private var removeRemindersAfterImport = true
    @AppStorage(GroceryImportSource.remindersListIDKey) private var remindersListID = ""
    @AppStorage(GroceryImportSource.remindersListNameKey) private var remindersListName = ""
    @State private var showingRemindersListPicker = false
    @State private var showingClearConfirmation = false
    @State private var notice: String?
    @State private var importFailure: PaprikaImportError?
    @State private var showingPaprikaInstructions = false
    @State private var saveFailed = false
    @State private var pendingReminderWrites: [UUID: ReminderWriteback] = [:]
    // The native editor owns first-responder focus; mirror it as view state.
    @State private var groceryInputFocused = false
    @State private var productEntryFocus = ProductEntryFocus()
    @State private var productActionsFrame: CGRect = .zero
    @State private var showStoreFrame: CGRect = .zero
    @State private var productEntryRevealTask: Task<Void, Never>?
    @State private var isRevealingProductEntry = false
    @State private var productEntryRevealStatus = "idle"
    @State private var recentlyAddedItemIDs = Set<UUID>()
    @State private var scrollTargetItemID: UUID?
    @State private var addedItemScrollTask: Task<Void, Never>?
    @State private var addedItemScrollRequestID = UUID()
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var listViewportFrame: CGRect = .zero
    @State private var groceryInputFrame: CGRect = .zero
    @State private var addItemsButtonFrame: CGRect = .zero
    @State private var isListScreenVisible = false
    #if DEBUG
    @State private var entryDismissalAnimationStatus = "not-dismissed"
    #endif

    init(storeID: StoreID, sessions: StoreSessions, visibility: StoreVisibilityPreferences, paprikaReminders: PaprikaReminders,
         previewingStoreWelcome: Binding<Bool>, rawInput: Binding<String>,
          onWelcomeStoreEnabled: @escaping (StoreID) -> Void,
          onSelectStore: @escaping (StoreID) -> Void,
          onSelectAllItems: @escaping () -> Void,
          storeLaunchRequested: Binding<Bool>,
          importLaunchRequested: Binding<Bool>,
          onPromoteStore: @escaping (StoreID, [UUID]) -> Void,
          onImportCompleted: ((String) -> Void)? = nil,
          ownsNavigationStack: Bool = true, offersAllItems: Bool = true,
          onListVisibilityChange: @escaping (Bool) -> Void = { _ in }) {
        self.storeID = storeID; self.sessions = sessions
        self.visibility = visibility
        self.paprikaReminders = paprikaReminders
        self.onWelcomeStoreEnabled = onWelcomeStoreEnabled
        self._previewingStoreWelcome = previewingStoreWelcome
        self.onSelectStore = onSelectStore; self._rawInput = rawInput
        self.onSelectAllItems = onSelectAllItems
        self._storeLaunchRequested = storeLaunchRequested
        self._importLaunchRequested = importLaunchRequested
        self.onPromoteStore = onPromoteStore
        self.onImportCompleted = onImportCompleted
        self.ownsNavigationStack = ownsNavigationStack
        self.offersAllItems = offersAllItems
        self.onListVisibilityChange = onListVisibilityChange
        _browser = StateObject(wrappedValue: sessions.browser(for: storeID))
    }

    private var items: [GroceryItem] { allItems.filter { $0.listID == storeID.listID } }
    private var selectedList: GroceryList? { lists.first { $0.id == storeID.listID } }
    private var shoppingVisibleIDs: Set<StoreID> { sessions.shoppingAvailability.visibleIDs(in: visibility.visibleIDs) }
    private var moveDestinations: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil, enabledIDs: shoppingVisibleIDs).filter { $0.id != storeID }
    }

    private func userScrolled() {
        // A deliberate scroll wins over automatic editor/item reveal.
        cancelAddedItemScroll()
        productEntryRevealTask?.cancel()
        scrollTargetItemID = nil
        itemFrames.removeAll(keepingCapacity: true)
    }

    private var pendingCount: Int { items.filter { $0.status == .pending }.count }
    private var addedCount: Int { items.filter { $0.status == .added }.count }
    private var skippedCount: Int { items.filter { $0.status == .skipped }.count }
    private var showingStoreWelcome: Bool {
        #if DEBUG
        if previewingStoreWelcome { return true }
        #endif
        return shoppingVisibleIDs.isEmpty && !visibility.hasCompletedStoreSetup
    }
    private var showsJoinedBack: Bool {
        offersAllItems && !ownsNavigationStack && !showingStoreWelcome && !shoppingVisibleIDs.isEmpty
    }
    // The storefront configuration is the single source of truth for the
    // selected store's visual identity, including all list-screen accents.
    private var storePrimaryColor: Color {
        guard !shoppingVisibleIDs.isEmpty else { return .primary }
        let color = browser.store.brandColors?.primary ?? browser.store.addedColor
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }
    private var storeHighlightColor: Color {
        guard !shoppingVisibleIDs.isEmpty else { return .primary }
        guard let color = browser.store.brandColors?.highlight else { return storePrimaryColor }
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ListNavigationContainer(standalone: ownsNavigationStack) {
            ShoppingListPage(isWelcome: showingStoreWelcome, joinsScopeControls: showsJoinedBack,
                keyboardDismissMode: isRevealingProductEntry ? .never : .interactively,
                onViewportChange: { frame in
                    listViewportFrame = frame
                    revealFocusedProductEntry()
                    if let itemID = scrollTargetItemID { scrollToAddedItem(itemID, using: scrollProxy) }
                }, scope: {
                    if !showingStoreWelcome && !shoppingVisibleIDs.isEmpty {
                        StoreListScopeControl(showsBack: showsJoinedBack, tint: storePrimaryColor) {
                            ListScopePicker(stores: StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                                enabledIDs: shoppingVisibleIDs), selectedStoreID: storeID, tint: storePrimaryColor,
                                onChooseAllItems: onSelectAllItems, onChooseStore: onSelectStore,
                                onManageStores: { showingStoreManagement = true }, offersAllItems: offersAllItems)
                        }
                    }
                }, footer: {
                    if !showingStoreWelcome && !shoppingVisibleIDs.isEmpty && !items.isEmpty {
                        Button(action: presentStore) {
                            Label("Show Store", systemImage: "cart.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .modifier(StoreLaunchButtonStyle(tint: storePrimaryColor))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            showStoreFrame = frame
                            revealFocusedProductEntry()
                        }
                        .disabled(!browser.canPresentStore || !shoppingVisibleIDs.contains(storeID))
                        .padding(.horizontal, 20).padding(.top, 8)
                        // Tuck the fixed action closer to the home indicator, but
                        // retain its comfortable keyboard clearance while editing.
                        .padding(.bottom, groceryInputFocused ? 16 : -12)
                    }
                }) {
                if showingStoreWelcome {
                    StoreWelcomeContent {
                        managingWelcomeStores = true
                        showingStoreManagement = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if shoppingVisibleIDs.isEmpty {
                    ContentUnavailableView {
                        Label("No stores enabled", systemImage: "basket")
                    } description: {
                        Text("Enable a store to see its shopping list.")
                    } actions: {
                        Button("Manage Stores") { showingStoreManagement = true }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("no-stores-manage")
                        if !allItems.isEmpty {
                            Button("View saved items", action: onSelectAllItems)
                                .accessibilityIdentifier("view-saved-items")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ListPageSummary(pending: pendingCount, added: addedCount, skipped: skippedCount, tint: storePrimaryColor)
                            // Keep the native separator farther below the totals;
                            // this leaves the summary itself in place.
                            .padding(.bottom, 20)
                            .contentShape(Rectangle())
                            .onTapGesture { groceryInputFocused = false }
                        if let notice {
                            messageBanner(notice)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                        if saveFailed { PersistenceWarning() }
                        if browser.cartUndoWarning {
                            CartUndoWarning(storeName: storeID.displayName) { browser.dismissCartUndoWarning() }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                    // Animate only notice visibility, not typing, item statuses,
                    // or the rest of the grocery list's frequent updates.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: notice != nil)

                    ProductEntrySection(text: $rawInput, isFocused: $groceryInputFocused,
                        focusControl: productEntryFocus, tint: storePrimaryColor,
                        importing: paprikaReminders.importing,
                        importConfigured: GroceryImportSource(rawValue: importSourceID) == .paprika,
                        removeReminders: removeRemindersAfterImport, onSubmit: addItems, onImport: {
                            groceryInputFocused = false
                            if GroceryImportSource(rawValue: importSourceID) == .paprika { importPaprika() }
                            else { showingImportSetup = true }
                        }, onTextChange: { value in
                                // Return can submit and clear the binding before
                                // SwiftUI delivers the preceding typing change.
                                // That obsolete edit must not cancel its reveal.
                                guard value == rawInput else { return }
                                // Multiline paste is submitted in a single edit.
                                // Keyboard Return is intercepted before insertion.
                                if value.contains(where: { $0.isNewline }) {
                                    addItems()
                                 } else if !value.isEmpty {
                                     cancelAddedItemScroll()
                                     scrollTargetItemID = nil
                                     revealFocusedProductEntry()
                                }
                        }, onFocus: {
                            cancelAddedItemScroll()
                            scrollTargetItemID = nil
                            revealFocusedProductEntry()
                        }, onEditorFrame: { frame in
                                 let heightChanged = abs(groceryInputFrame.height - frame.height) > 0.5
                                 groceryInputFrame = frame
                                 if heightChanged { revealFocusedProductEntry() }
                        }, onActionsFrame: { productActionsFrame = $0 }, onManualScroll: userScrolled) {
                            Button("Add Items") {
                                addItems(keepingInputFocused: true)
                            }
                                .buttonStyle(ProductAddButtonStyle(tint: storePrimaryColor))
                                .disabled(ParsedGrocery.productEntries(in: rawInput).isEmpty)
                                .onGeometryChange(for: CGRect?.self) { geometry in
                                    groceryInputFocused ? geometry.frame(in: .global) : nil
                                } action: { frame in
                                    guard let frame else { return }
                                    addItemsButtonFrame = frame
                                }
                    }

                    Section {
                        if items.isEmpty {
                            ContentUnavailableView("Your list is empty", systemImage: "basket",
                                                   description: Text("Add products above, then shop though them with ListRunner"))
                                .padding(.vertical, 12)
                        } else {
                            groceryList(using: scrollProxy)
                            ClearListButton(action: clearList)
                             .confirmationDialog("Clear your list?", isPresented: $showingClearConfirmation,
                                                 titleVisibility: .visible) {
                                if addedCount > 0 {
                                    Button("Clear Added", role: .destructive) { clearItems(addedOnly: true) }
                                }
                                Button("Clear All", role: .destructive) { clearItems(addedOnly: false) }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This clears only your \(storeID.displayName) list in ListRunner. It does not change any store cart or Apple Reminders.")
                            }
                        }
                    } header: {
                        if !items.isEmpty {
                            Text("Items", comment: "Section heading for shopping-list items at any retailer, not only groceries.")
                                .accessibilityIdentifier("store-list-items-heading")
                        }
                    }
                }
            }
            .onAppear {
                isListScreenVisible = true
                if storeLaunchRequested {
                    storeLaunchRequested = false
                    presentStore()
                }
                if importLaunchRequested {
                    importLaunchRequested = false
                    if GroceryImportSource(rawValue: importSourceID) == .paprika {
                        importPaprika()
                    } else {
                        showingImportSetup = true
                    }
                }
                if let selected = visibility.selectionForList(current: storeID, definitions: sessions.definitions),
                   selected != storeID {
                    onSelectStore(selected)
                }
                onListVisibilityChange(true)
            }
            .onDisappear {
                groceryInputFocused = false
                isListScreenVisible = false
                onListVisibilityChange(false)
            }
            .navigationDestination(isPresented: $showingStoreManagement) {
                StoreVisibilityScreen(sessions: sessions, visibility: visibility,
                    onWelcomeStoreEnabled: managingWelcomeStores ? { id in
                        // Let the root crossfade to a fresh list navigation stack.
                        // Do not pop this outgoing stack during its fade.
                        onWelcomeStoreEnabled(id)
                    } : nil,
                    onOpenStoreList: { id in
                        showingStoreManagement = false
                        onSelectStore(id)
                    })
            }
            .onChange(of: showingStoreManagement) { _, presented in
                if !presented { managingWelcomeStores = false }
            }
            .navigationDestination(isPresented: $showingImportSetup) {
                ImportSourceSelectionScreen(selectedSourceID: importSourceID, destinationName: browser.store.displayName) { _ in
                    showingImportSetup = false
                    importPaprika()
                }
            }
            .navigationDestination(isPresented: $showingPaprikaInstructions) {
                PaprikaImportInstructionsScreen(destinationName: browser.store.displayName) {
                    showingPaprikaInstructions = false
                    importPaprika()
                }
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsOverviewScreen(sessions: sessions, visibility: visibility,
                                        importInProgress: paprikaReminders.importing,
                                        importDestinationName: browser.store.displayName,
                                        onOpenStoreList: { id in
                                            showingSettings = false
                                            onSelectStore(id)
                                        }) {
                    showingSettings = false
                    importPaprika()
                }
            }
            .toolbar {
                ListPageToolbar(showSettings: !showingStoreWelcome) {
                    groceryInputFocused = false
                    showingSettings = true
                }
            }
            .sheet(isPresented: $showingRemindersListPicker) {
                NavigationStack {
                    PaprikaRemindersListScreen { list in
                        remindersListID = list.id
                        remindersListName = list.name
                        showingRemindersListPicker = false
                        importPaprika()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingRemindersListPicker = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingStore) {
                StoreShoppingView(items: items, browser: browser, initialSelectedID: selectedList?.selectedItemID, saveFailed: saveFailed, onSelectionChange: { id in
                    selectedList?.selectedItemID = id
                    saveChanges()
                }, onStatusChange: { item in
                    stageReminderWriteback(for: item)
                    saveChanges()
                })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(32)
            }
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(item: item) { name, amount, unit in
                    item.name = name
                    item.searchTerm = name
                    item.quantityAmount = amount
                    item.quantityUnit = amount == nil ? nil : unit
                    item.status = .pending
                    stageReminderWriteback(for: item)
                    saveChanges()
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Move item to another store?", isPresented: Binding(get: { itemToMove != nil }, set: { if !$0 { itemToMove = nil } }), titleVisibility: .visible) {
                if let item = itemToMove {
                    ForEach(moveDestinations, id: \.id) { destination in
                        Button("Move to \(destination.displayName)") { moveItem(item, to: destination.id); itemToMove = nil }
                    }
                }
                Button("Cancel", role: .cancel) { itemToMove = nil }
            } message: {
                Text("The item moves to the other list as Pending. Neither store basket is changed. Existing items in the other list are not merged.")
            }
        }
        .tint(storePrimaryColor)
        .background {
            if showsJoinedBack {
                StoreListNativeBack(tint: storePrimaryColor)
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["LISTRUNNER_REVEAL_TEST_FIXTURE"] == "enabled" {
                Text(verbatim: "target=\(scrollTargetItemID?.uuidString ?? "none"); trackedRows=\(itemFrames.count); frame=\(scrollTargetItemID.flatMap { itemFrames[$0] }.debugDescription); viewport=\(listViewportFrame); pending=\(addedItemScrollTask != nil); editor=\(groceryInputFrame); actions=\(productActionsFrame); focused=\(groceryInputFocused); responder=\(productEntryFocus.view?.isFirstResponder == true); entryReveal=\(productEntryRevealStatus)")
                    .accessibilityIdentifier("item-reveal-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            if ProcessInfo.processInfo.environment["LISTRUNNER_ENTRY_ANIMATION_TEST_FIXTURE"] == "enabled" {
                Text(entryDismissalAnimationStatus)
                    .accessibilityIdentifier("entry-dismissal-animation-status")
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
        #endif
        .simultaneousGesture(
            entryDismissTap { location in
                guard groceryInputFocused,
                      !groceryInputFrame.contains(location),
                      !addItemsButtonFrame.contains(location) else { return }
                groceryInputFocused = false
            },
            // An inactive recognizer can still interfere with UIKit table-row
            // selection on pushed screens. Remove it from gesture arbitration,
            // rather than merely returning early from its callback.
            including: groceryInputFocused && isListScreenVisible ? .all : .subviews
        )
        .onAppear {
            guard !routedLaunch else { return }
            routedLaunch = true
            let today = Self.localDay()
            selectedList?.lastActiveDay = today
            saveChanges()
        }
        .onChange(of: shoppingVisibleIDs) { _, visibleIDs in
            guard !visibleIDs.contains(storeID) else { return }
            browser.endInteraction()
            showingStore = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                browser.diagnostics.purge()
                if saveFailed { saveChanges() }
                selectedList?.lastActiveDay = Self.localDay()
                saveChanges()
            }
        }
        .onChange(of: scrollTargetItemID) { _, itemID in
            guard let itemID else { return }
            scrollToAddedItem(itemID, using: scrollProxy)
        }
        .onChange(of: groceryInputFocused) { _, focused in
            productEntryRevealTask?.cancel()
            if focused { revealFocusedProductEntry() }
        }
        .onChange(of: items.map(\.id)) { _, itemIDs in
            // When adding the first row, SwiftUI replaces the empty-state row
            // and may not have registered the new row when the target changes.
            // Retry after the query reflects the inserted row.
            guard let itemID = scrollTargetItemID, itemIDs.contains(itemID) else { return }
            scrollToAddedItem(itemID, using: scrollProxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            revealFocusedProductEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            #if DEBUG
            if let enabled = ProductEntryEditor.EntryTextView.lastResignAnimationsEnabled {
                let updateEnabled = ProductEntryEditor.EntryTextView.lastFocusUpdateAnimationsEnabled == true
                entryDismissalAnimationStatus = "update-animations-\(updateEnabled ? "enabled" : "disabled"); resign-animations-\(enabled ? "enabled" : "disabled")"
            }
            #endif
            // Return can briefly change the field's focus while UIKit keeps the
            // keyboard open. Only retire the target on an actual dismissal.
            let targetAtDismissal = scrollTargetItemID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !groceryInputFocused,
                      productEntryFocus.view?.isFirstResponder != true,
                      scrollTargetItemID == targetAtDismissal else { return }
                cancelAddedItemScroll()
                scrollTargetItemID = nil
            }
        }
        .onDisappear {
            productEntryRevealTask?.cancel()
            cancelAddedItemScroll()
            scrollTargetItemID = nil
        }
        }
    }

    private func groceryList(using scrollProxy: ScrollViewProxy) -> some View {
        ForEach(items) { item in
            ShoppingListItemRow(name: item.name, quantity: item.displayQuantity,
                status: item.status, tint: storePrimaryColor,
                accessibilityLabel: "\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue). Find in \(storeID.displayName)",
                onOpen: {
                    guard browser.canPresentStore, shoppingVisibleIDs.contains(storeID) else { return }
                    selectedList?.selectedItemID = item.id
                    saveChanges()
                    presentStore()
                }) {
                    if item.status == .pending {
                        Button("Mark Added", systemImage: "checkmark.circle") { setStatus(.added, for: item) }
                    } else if item.status == .added {
                        Button("Mark Pending", systemImage: "arrow.uturn.backward.circle") { setStatus(.pending, for: item) }
                    }
                    if item.status != .skipped {
                        Button("Mark Skipped", systemImage: "forward.end") { setStatus(.skipped, for: item) }
                    }
                    Button("Edit Item", systemImage: "pencil") { editingItem = item }
                    Button("Move to Another Store", systemImage: "arrow.right.arrow.left") { itemToMove = item }
                    Button("Delete Item", systemImage: "trash", role: .destructive) { delete(item) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                    .accessibilityHint("Removes this item from ListRunner only, not the store cart")
            }
            .id(item.id)
            .onGeometryChange(for: CGRect?.self) { geometry in
                scrollTargetItemID == item.id ? geometry.frame(in: .global) : nil
            } action: { frame in
                guard let frame, scrollTargetItemID == item.id else { return }
                itemFrames[item.id] = frame
                // UIKit may restore the field's scroll position after Return.
                // Correct a clipped row after that layout, with room for insets.
                scrollToAddedItem(item.id, using: scrollProxy, animated: false)
            }
            .onAppear {
                // List registers a new row lazily. The query/target can change
                // before ScrollViewReader can resolve that row, especially when
                // replacing the empty-state cell.
                guard scrollTargetItemID == item.id else { return }
                scrollToAddedItem(item.id, using: scrollProxy)
            }
            .onTapGesture { groceryInputFocused = false }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
            .listRowBackground(
                recentlyAddedItemIDs.contains(item.id)
                    ? storeHighlightColor.opacity(0.18)
                    : Color(uiColor: .secondarySystemGroupedBackground)
            )
            .listRowInsets(ListItemRowLayout.insets)
        }
        .onMove(perform: moveItems)
    }

    private func messageBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(message, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Dismiss") { notice = nil; importFailure = nil }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Dismiss notice")
            }
            if let importFailure {
                VStack(alignment: .leading, spacing: 0) {
                    Button("View instructions") { showingPaprikaInstructions = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("paprika-view-instructions")
                    if importFailure == .permissionDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("paprika-open-settings")
                    }
                    Button("Try again") { importPaprika() }
                        .frame(minHeight: 44)
                        .disabled(paprikaReminders.importing)
                        .accessibilityIdentifier("paprika-retry")
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }
        }
    }

    private func addItems() {
        guard !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rawInput = ""
            groceryInputFocused = false
            return
        }
        addItems(keepingInputFocused: true)
    }

    private func addItems(keepingInputFocused: Bool) {
        let entries = ParsedGrocery.productEntries(in: rawInput)
        guard !entries.isEmpty else { return }
        if modelContext.hasChanges {
            saveChanges()
            guard !saveFailed else { return }
        }
        let submittedInput = rawInput
        cancelAddedItemScroll()
        var newlyAddedIDs = Set<UUID>()
        // Do not animate the empty-state replacement and new bottom inset while
        // trying to position the first row. Later additions keep their animation;
        // the first row still gets the added-item highlight and animated scroll.
        withAnimation(items.isEmpty ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            let existingIDs = Set(items.map(\.id))
            let promotedItems = ShoppingLists.stageAdd(entries, to: storeID, allItems: allItems, context: modelContext)
            for item in promotedItems {
                if existingIDs.contains(item.id) { stageReminderWriteback(for: item) }
                else { newlyAddedIDs.insert(item.id) }
            }
            recentlyAddedItemIDs.formUnion(newlyAddedIDs)
            // Idle rows no longer track geometry. Never reuse a frame captured
            // for an earlier reveal of a reactivated item.
            itemFrames.removeAll(keepingCapacity: true)
            scrollTargetItemID = promotedItems.first?.id
            rawInput = ""
            groceryInputFocused = keepingInputFocused
            saveChanges()
            if saveFailed {
                modelContext.rollback()
                pendingReminderWrites.removeAll()
                rawInput = submittedInput
                recentlyAddedItemIDs.subtract(newlyAddedIDs)
                scrollTargetItemID = nil
            } else {
                onPromoteStore(storeID, promotedItems.map(\.id))
            }
        }

        guard !newlyAddedIDs.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            withAnimation(.easeOut(duration: 0.45)) {
                recentlyAddedItemIDs.subtract(newlyAddedIDs)
            }
        }
    }

    private func revealFocusedProductEntry() {
        productEntryRevealTask?.cancel()
        guard groceryInputFocused, scrollTargetItemID == nil else { return }
        productEntryRevealTask = productEntryFocus.revealCard(geometry: {
            guard groceryInputFocused, scrollTargetItemID == nil else { return nil }
            return ProductEntryRevealGeometry(editor: groceryInputFrame, actions: productActionsFrame,
                viewport: listViewportFrame, footerTop: items.isEmpty || showStoreFrame.height == 0 ? nil : showStoreFrame.minY)
        }, onRevealing: { isRevealingProductEntry = $0 }, onStatus: { productEntryRevealStatus = $0 })
    }

    private func scrollToAddedItem(_ itemID: UUID, using proxy: ScrollViewProxy, animated: Bool = true) {
        // Geometry, query and onAppear callbacks can arrive in the same layout
        // pass. Coalesce them instead of repeatedly cancelling the queued scroll.
        guard !isAddedItemFullyVisible(itemID) else { return }
        guard addedItemScrollTask == nil else { return }
        let requestID = UUID()
        addedItemScrollRequestID = requestID
        addedItemScrollTask = ListItemReveal.start(isCurrent: {
            scrollTargetItemID == itemID && items.contains { $0.id == itemID }
        }, geometry: {
            guard let target = itemFrames[itemID] else { return nil }
            return ListItemRevealGeometry(target: target, viewport: listViewportFrame)
        }, scroll: { anchor, firstAdjustment in
            withAnimation(animated && firstAdjustment ? .easeInOut(duration: 0.35) : nil) {
                proxy.scrollTo(itemID, anchor: anchor)
            }
        }, finished: {
            if addedItemScrollRequestID == requestID { addedItemScrollTask = nil }
        })
    }

    private func isAddedItemFullyVisible(_ itemID: UUID) -> Bool {
        guard let target = itemFrames[itemID],
              listViewportFrame.height > 0 else { return false }
        return ListItemRevealGeometry(target: target, viewport: listViewportFrame).isFullyVisible
    }

    private func cancelAddedItemScroll() {
        guard addedItemScrollTask != nil else { return }
        addedItemScrollTask?.cancel()
        addedItemScrollTask = nil
        addedItemScrollRequestID = UUID()
    }


    private func delete(_ item: GroceryItem) {
        pendingReminderWrites.removeValue(forKey: item.id)
        paprikaReminders.cancelQueuedWriteback(for: item)
        if selectedList?.selectedItemID == item.id {
            selectedList?.selectedItemID = ShoppingLists.selection(afterRemoving: item.id, from: items)
        }
        modelContext.delete(item)
        normalizePositions()
        saveChanges()
    }

    private func setStatus(_ status: GroceryStatus, for item: GroceryItem) {
        item.status = status
        stageReminderWriteback(for: item)
        saveChanges()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var orderedItems = items
        orderedItems.move(fromOffsets: source, toOffset: destination)
        for (position, item) in orderedItems.enumerated() {
            item.position = position
        }
        saveChanges()
    }

    private func clearList() {
        groceryInputFocused = false
        productEntryFocus.resignFirstResponder()
        showingClearConfirmation = true
    }

    private func presentStore() {
        groceryInputFocused = false
        // This action runs outside updateUIView, so UIKit can animate. Resign
        // before presenting: otherwise the sheet can remember the old responder
        // and restore the keyboard when it is dismissed, ahead of the queued blur.
        productEntryFocus.resignFirstResponder()
        showingStore = true
    }

    private func clearItems(addedOnly: Bool) {
        let removed = items.filter { !addedOnly || $0.status == .added }
        let removedIDs = Set(removed.map(\.id))
        let remaining = items.filter { !removedIDs.contains($0.id) }
        browser.endInteraction()
        for item in removed {
            pendingReminderWrites.removeValue(forKey: item.id)
            paprikaReminders.cancelQueuedWriteback(for: item)
        }
        if remaining.isEmpty {
            selectedList?.selectedItemID = nil
        } else if let selectedID = selectedList?.selectedItemID, removedIDs.contains(selectedID) {
            selectedList?.selectedItemID = remaining.first { $0.status == .pending }?.id ?? remaining.first?.id
        }
        recentlyAddedItemIDs.subtract(removedIDs)
        if let target = scrollTargetItemID, removedIDs.contains(target) {
            cancelAddedItemScroll()
            scrollTargetItemID = nil
        }
        for item in removed { modelContext.delete(item) }
        for (position, item) in remaining.enumerated() { item.position = position }
        notice = nil
        saveChanges()
    }

    private func normalizePositions() {
        for (index, item) in items.enumerated() { item.position = index }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
            saveFailed = false
            let writes = Array(pendingReminderWrites.values)
            pendingReminderWrites.removeAll()
            for write in writes { paprikaReminders.queueWriteback(write) }
        } catch {
            if !saveFailed {
                UIAccessibility.post(notification: .announcement, argument: "Changes may not be saved")
            }
            saveFailed = true
            browser.diagnostics.record(.storage, .localSave, reason: .storageFailure, outcome: .failed)
        }
    }

    private func moveItem(_ item: GroceryItem, to destination: StoreID) {
        guard item.listID == storeID.listID, destination != storeID,
              shoppingVisibleIDs.contains(destination) else { return }
        if selectedList?.selectedItemID == item.id {
            selectedList?.selectedItemID = ShoppingLists.selection(afterRemoving: item.id, from: items)
        }
        browser.endInteraction()
        ShoppingLists.move(item, to: destination, allItems: allItems)
        stageReminderWriteback(for: item)
        saveChanges()
    }

    private func stageReminderWriteback(for item: GroceryItem) {
        guard !removeRemindersAfterImport else { return }
        if let write = paprikaReminders.desiredWriteback(for: item) {
            pendingReminderWrites[item.id] = write
        }
    }

    private func importPaprika() {
        guard !paprikaReminders.importing else { return }
        guard !remindersListID.isEmpty else {
            showingRemindersListPicker = true
            return
        }
        let sourceListID = remindersListID
        notice = nil
        importFailure = nil
        let removeAfterImport = removeRemindersAfterImport
        Task { @MainActor in
            defer {
                paprikaReminders.finishImport()
                if let notice { UIAccessibility.post(notification: .announcement, argument: notice) }
                if importFailure == nil, let notice { onImportCompleted?(notice) }
            }
            do {
                // Keep the import transaction isolated from any earlier failed
                // save. The existing local list must be durable before staging
                // a second, all-or-nothing transaction.
                saveChanges()
                guard !saveFailed else { throw PaprikaImportError.transaction }
                let snapshot = try await paprikaReminders.fetchPaprikaSnapshot(calendarID: sourceListID)
                let sourceListName = paprikaReminders.snapshotListName ?? remindersListName
                remindersListName = sourceListName
                let linkedIDs = Set(items.compactMap(\.paprikaReminderID))
                let staged = PaprikaImportPlanner.stage(reminders: snapshot, existingIDs: linkedIDs)
                guard !staged.isEmpty else {
                    if removeAfterImport {
                        let cleanup = PaprikaImportPlanner.removalCandidates(reminders: snapshot, savedIDs: linkedIDs)
                        if !cleanup.isEmpty {
                            let failed = paprikaReminders.removeImportedReminders(cleanup, calendarID: sourceListID)
                            notice = failed == 0
                                ? String(localized: "These groceries are already in your list. Their Apple reminders have now been removed. Paprika is unchanged.")
                                : String(localized: "Your groceries are already saved. Some Apple reminders could not be removed. Import again to retry; your saved groceries won’t be duplicated.")
                            return
                        }
                    }
                    throw PaprikaImportPlanner.emptyImportError(reminders: snapshot, existingIDs: linkedIDs)
                }
                let alreadyImportedCount = Set(snapshot.map(\.id)).intersection(linkedIDs).count
                var importedItemIDs: [UUID] = []
                let previousItems = items
                do {
                    try modelContext.transaction {
                        var position = (items.map(\.position).max() ?? -1) + 1
                        var importedItems: [GroceryItem] = []
                        for entry in staged {
                            let item = GroceryItem(name: entry.grocery.name,
                                                   amount: entry.grocery.amount,
                                                   unit: entry.grocery.unit,
                                                   position: position,
                                                   listID: storeID.listID)
                            item.paprikaReminderID = entry.reminderID
                            modelContext.insert(item)
                            importedItemIDs.append(item.id)
                            importedItems.append(item)
                            position += 1
                        }
                        for (index, item) in (importedItems + previousItems).enumerated() { item.position = index }
                    }
                    saveFailed = false
                } catch {
                    modelContext.rollback()
                    throw PaprikaImportError.transaction
                }
                importSourceID = GroceryImportSource.paprika.rawValue
                onPromoteStore(storeID, importedItemIDs)
                if removeAfterImport {
                    let savedIDs = linkedIDs.union(staged.compactMap(\.reminderID))
                    let failed = paprikaReminders.removeImportedReminders(PaprikaImportPlanner.removalCandidates(reminders: snapshot, savedIDs: savedIDs), calendarID: sourceListID)
                    notice = failed == 0
                        ? String(localized: "Groceries added to your \(browser.store.displayName) list: \(staged.count). Removed their reminders from ‘\(sourceListName)’. Paprika is unchanged.")
                        : String(localized: "Added \(staged.count) groceries to your \(browser.store.displayName) list. Some Apple reminders could not be removed. Import again to retry; your saved groceries won’t be duplicated.")
                    return
                }
                if alreadyImportedCount > 0 && staged.count == 1 {
                    notice = String(localized: "Added 1 item to your \(browser.store.displayName) list. Already-imported reminders skipped: \(alreadyImportedCount).")
                } else if alreadyImportedCount > 0 {
                    notice = String(localized: "Added \(staged.count) items to your \(browser.store.displayName) list. Already-imported reminders skipped: \(alreadyImportedCount).")
                } else if staged.count == 1 {
                    notice = String(localized: "Added 1 item to your \(browser.store.displayName) list.")
                } else {
                    notice = String(localized: "Added \(staged.count) items to your \(browser.store.displayName) list.")
                }
            } catch let error as PaprikaImportError {
                if error == .listNotFound {
                    remindersListID = ""
                    remindersListName = ""
                    showingRemindersListPicker = true
                }
                importFailure = error
                notice = String(localized: error.message)
            } catch {
                importFailure = .transaction
                notice = String(localized: PaprikaImportError.transaction.message)
            }
        }
    }

    private static func localDay() -> String {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: Date())
    }
}

private struct StoreWelcomeContent: View {
    let chooseStore: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            StoreWelcomeIllustration()
            StoreWelcomeIntroduction()

            VStack(spacing: 12) {
                Button(action: chooseStore) {
                    Text("Choose Your First Store")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(StoreWelcomeButtonStyle())
                .accessibilityIdentifier("welcome-choose-store")
                Text("Add more stores and lists whenever you like.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
}

private struct StoreWelcomeIntroduction: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A list for every store.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Keep your shopping lists organised by where you shop, ready whenever you need them. Shopping online? Work through your list right on the store’s website.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StoreWelcomeIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            // A fixed illustration coordinate space scales as one unit. Rotation
            // and shadows stay inside the panel even on narrow phones; surrounding
            // onboarding text and the real action still follow Dynamic Type.
            let scale = geometry.size.width / 320
            ZStack(alignment: .topLeading) {
                StoreWelcomeExampleCard(name: "Apples", completed: true, selected: false)
                    .frame(width: 122, height: 190)
                    .rotationEffect(.degrees(-6))
                    .position(x: 84, y: 132)
                StoreWelcomeExampleCard(name: "Milk", completed: false, selected: false)
                    .frame(width: 122, height: 190)
                    .rotationEffect(.degrees(6))
                    .position(x: 236, y: 132)
                StoreWelcomeExampleCard(name: "Bread", completed: false, selected: true)
                    .frame(width: 142, height: 204)
                    .position(x: 160, y: 125)
            }
            .frame(width: 320, height: 250)
            .dynamicTypeSize(.large)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(320.0 / 250.0, contentMode: .fit)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        // Decorative example only: no fake control or sample item is exposed as
        // real shopping data or a second action to VoiceOver / Switch Control.
        .accessibilityHidden(true)
    }
}

private enum StoreWelcomePalette {
    static let blue = LinearGradient(
        colors: [Color(red: 18.0 / 255, green: 106.0 / 255, blue: 190.0 / 255),
                 Color(red: 70.0 / 255, green: 148.0 / 255, blue: 222.0 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cream = LinearGradient(
        colors: [Color(red: 1, green: 253.0 / 255, blue: 243.0 / 255),
                 Color(red: 238.0 / 255, green: 233.0 / 255, blue: 213.0 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct StoreWelcomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                Capsule()
                    .fill(StoreWelcomePalette.blue)
                    .overlay {
                        StoreWelcomeButtonShimmer()
                            .clipShape(Capsule())
                    }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct StoreWelcomeButtonShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        GeometryReader { geometry in
            if !reduceMotion && scenePhase == .active && isVisible {
                // Only the small background highlight updates, not the welcome
                // screen or button label. No timer runs off-screen or inactive.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5)
                    let progress = min(cycle / 1.6, 1)
                    let bandWidth = max(geometry.size.width * 0.28, 44)
                    LinearGradient(colors: [.clear, .white.opacity(0.18), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: bandWidth, height: geometry.size.height * 3)
                        .rotationEffect(.degrees(18))
                        .offset(x: -bandWidth * 2 + (geometry.size.width + bandWidth * 4) * progress,
                                y: -geometry.size.height)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StoreWelcomeExampleCard: View {
    let name: LocalizedStringKey
    let completed: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("Quantity · 1")
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected {
                VStack(spacing: 15) {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 0.5)
                    Text("Mark Added")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(StoreWelcomePalette.blue, in: Capsule())
                }
                .padding(.horizontal, -4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 25)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(completed ? Color.white : Color(red: 0.16, green: 0.18, blue: 0.19))
        .background(completed ? StoreWelcomePalette.blue : StoreWelcomePalette.cream,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
    }
}

private struct ListItemRevealGeometry {
    let target: CGRect
    let viewport: CGRect

    var isFullyVisible: Bool {
        target.minY >= viewport.minY - 0.5 && target.maxY <= viewport.maxY + 0.5
    }
}

@MainActor
private enum ListItemReveal {
    static func start(isCurrent: @escaping @MainActor () -> Bool,
                      geometry: @escaping @MainActor () -> ListItemRevealGeometry?,
                      scroll: @escaping @MainActor (UnitPoint, Bool) -> Void,
                      finished: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            defer { finished() }
            // Query insertion, keyboard layout and Return can restore offsets
            // in stages. Both scopes recheck the padded row, not just its text.
            for (index, delay) in [0.5, 0.4, 0.2].enumerated() {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard isCurrent() else { return }
                guard let frame = geometry(), frame.viewport.height > 0, !frame.isFullyVisible else { continue }
                scroll(frame.target.maxY > frame.viewport.maxY ? .bottom : .top, index == 0)
            }
        }
    }
}

private struct ProductEntryRevealGeometry {
    let editor: CGRect
    let actions: CGRect
    let viewport: CGRect
    var footerTop: CGFloat?
}

// Weak, editor-scoped access for explicit presentation actions. Never resign
// another scene's first responder through a global UIApplication action.
@MainActor
private final class ProductEntryFocus {
    weak var view: UITextView?

    func resignFirstResponder() {
        if let view, view.isFirstResponder { view.resignFirstResponder() }
    }

    func revealCard(geometry: @escaping @MainActor () -> ProductEntryRevealGeometry?,
                    onRevealing: @escaping @MainActor (Bool) -> Void,
                    onStatus: @escaping @MainActor (String) -> Void = { _ in }) -> Task<Void, Never> {
        Task { @MainActor in
            onRevealing(true)
            defer { onRevealing(false) }
            // Keyboard layout arrives in stages. Both page scopes use the same
            // measured, minimal correction and retain this editor's responder.
            for delay in [0.1, 0.3, 0.3] {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard let frame = geometry(), frame.viewport.height > 0,
                      frame.editor.height > 0, frame.actions.height > 0 else { return }
                let cardTop = frame.editor.minY - 19
                let cardBottom = frame.actions.maxY
                let bottom = frame.footerTop ?? frame.viewport.maxY
                onStatus("checked bottom=\(cardBottom) visibleBottom=\(bottom)")
                guard cardBottom - cardTop <= bottom - frame.viewport.minY else { continue }
                let adjustment: CGFloat
                if cardBottom > bottom + 0.5 { adjustment = cardBottom - bottom }
                else if cardTop < frame.viewport.minY - 0.5 { adjustment = cardTop - frame.viewport.minY }
                else { continue }
                onStatus("scroll adjustment=\(adjustment)")
                adjustListOffset(by: adjustment)
            }
        }
    }

    func adjustListOffset(by adjustment: CGFloat, animated: Bool = true, requiresFocus: Bool = true) {
        guard let view, !requiresFocus || view.isFirstResponder else { return }
        var ancestor = view.superview
        while let candidate = ancestor {
            if let list = candidate as? UICollectionView {
                guard !list.isDragging, !list.isDecelerating else { return }
                let minimum = -list.adjustedContentInset.top
                let maximum = max(minimum, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
                let offset = min(maximum, max(minimum, list.contentOffset.y + adjustment))
                list.setContentOffset(CGPoint(x: list.contentOffset.x, y: offset), animated: animated)
                return
            }
            ancestor = candidate.superview
        }
    }
}

// A vertical SwiftUI TextField inserts Return before onSubmit/onChange. Use the
// native editing delegate to reject that edit before UIKit lays out a new line.
private struct ProductEntryFieldStyle: ViewModifier {
    let tint: Color
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(tint.opacity(isFocused ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(isFocused ? 1 : 0.7), lineWidth: isFocused ? 2.5 : 1.5)
            }
            .contentShape(Rectangle())
    }
}

private struct ProductEntryEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusControl: ProductEntryFocus
    let onSubmit: () -> Void
    var accessibilityIdentifier = "grocery-input"
    var onManualScroll: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> EntryTextView {
        let view = EntryTextView()
        focusControl.view = view
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.returnKeyType = .continue
        view.accessibilityIdentifier = accessibilityIdentifier
        view.accessibilityLabel = String(localized: "Type or paste products")
        view.onWindowAttachment = { [weak coordinator = context.coordinator] view in
            coordinator?.observeListScroll(from: view)
            coordinator?.synchronizeFocus(for: view)
        }
        view.placeholder.text = String(localized: "Tap to add products…")
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: EntryTextView, context: Context) {
        focusControl.view = view
        context.coordinator.parent = self
        context.coordinator.observeListScroll(from: view)
        if view.text != text {
            view.text = text
            view.invalidateIntrinsicContentSize()
        }
        view.updatePlaceholder()
        context.coordinator.synchronizeFocus(for: view)
    }

    static func dismantleUIView(_ view: EntryTextView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.stopObservingListScroll()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EntryTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = uiView.font?.lineHeight ?? 22
        let fullHeight = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(max(lineHeight, fullHeight), lineHeight * 4))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ProductEntryEditor
        var isDismantled = false
        private var focusUpdateScheduled = false
        private weak var listPan: UIPanGestureRecognizer?
        private var dismissedKeyboardForPan = false
        init(parent: ProductEntryEditor) { self.parent = parent }

        func observeListScroll(from view: UIView) {
            guard !isDismantled, view.window != nil else {
                stopObservingListScroll()
                return
            }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let list = candidate as? UICollectionView {
                    let pan = list.panGestureRecognizer
                    guard listPan !== pan else { return }
                    stopObservingListScroll()
                    listPan = pan
                    // Observe the existing native pan; a competing full-page
                    // SwiftUI DragGesture can swallow the interactive Back edge.
                    pan.addTarget(self, action: #selector(listDidPan(_:)))
                    return
                }
                ancestor = candidate.superview
            }
            stopObservingListScroll()
        }

        func stopObservingListScroll() {
            listPan?.removeTarget(self, action: #selector(listDidPan(_:)))
            listPan = nil
        }

        @objc private func listDidPan(_ pan: UIPanGestureRecognizer) {
            guard !isDismantled else { return }
            if pan.state == .began {
                dismissedKeyboardForPan = false
                parent.onManualScroll()
                // Reveal can temporarily request .none. Restore native dismissal
                // before the next touch sample, without adding a pan recognizer.
                (pan.view as? UIScrollView)?.keyboardDismissMode = .interactive
            }
            guard pan.state == .changed, !dismissedKeyboardForPan, parent.isFocused else { return }
            let translation = pan.translation(in: pan.view)
            // Upward scrolling need not move an interactive keyboard downward.
            // Treat a deliberate vertical scroll as dismissal in both directions,
            // but preserve focus for small repositioning and horizontal edge Back.
            guard abs(translation.y) >= 44, abs(translation.y) > abs(translation.x) else { return }
            dismissedKeyboardForPan = true
            parent.isFocused = false
            parent.focusControl.resignFirstResponder()
        }

        func synchronizeFocus(for view: EntryTextView) {
            guard parent.isFocused != view.isFirstResponder, !focusUpdateScheduled else { return }
            focusUpdateScheduled = true
            #if DEBUG
            if ProcessInfo.processInfo.environment["LISTRUNNER_ENTRY_ANIMATION_TEST_FIXTURE"] == "enabled" {
                EntryTextView.lastFocusUpdateAnimationsEnabled = UIView.areAnimationsEnabled
            }
            #endif
            // SwiftUI can disable UIKit animations during updateUIView. Changing
            // first responder there also suppresses the system keyboard slide.
            // Leave that layout transaction, then read the latest binding so a
            // rapid retap cannot execute an obsolete dismissal/refocus request.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.focusUpdateScheduled = false
                guard !self.isDismantled, let view, view.window != nil,
                      self.parent.focusControl.view === view else { return }
                if self.parent.isFocused && !view.isFirstResponder { view.becomeFirstResponder() }
                else if !self.parent.isFocused && view.isFirstResponder { view.resignFirstResponder() }
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", textView.markedTextRange == nil else { return true }
            parent.onSubmit()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? EntryTextView)?.updatePlaceholder()
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard !isDismantled, parent.focusControl.view === textView else { return }
            if !parent.isFocused { parent.isFocused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            // A recycled editor must not clear the replacement editor's focus.
            guard !isDismantled, parent.focusControl.view === textView else { return }
            if parent.isFocused { parent.isFocused = false }
        }
    }

    final class EntryTextView: UITextView {
        let placeholder = UILabel()
        var onWindowAttachment: ((EntryTextView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // A lazy List can update the editor before attaching its cell. Retry
            // the desired focus on attachment instead of waiting for a scroll.
            onWindowAttachment?(self)
        }
        #if DEBUG
        static var lastFocusUpdateAnimationsEnabled: Bool?
        static var lastResignAnimationsEnabled: Bool?

        override func resignFirstResponder() -> Bool {
            if isFirstResponder,
               ProcessInfo.processInfo.environment["LISTRUNNER_ENTRY_ANIMATION_TEST_FIXTURE"] == "enabled",
               ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil {
                Self.lastResignAnimationsEnabled = UIView.areAnimationsEnabled
            }
            return super.resignFirstResponder()
        }
        #endif

        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholder.textColor = .placeholderText
            placeholder.isUserInteractionEnabled = false
            placeholder.isAccessibilityElement = false
            addSubview(placeholder)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func updatePlaceholder() {
            let hidden = !text.isEmpty
            guard placeholder.isHidden != hidden || placeholder.font != font else { return }
            placeholder.isHidden = hidden
            placeholder.font = font
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            placeholder.font = font
            placeholder.frame = CGRect(x: 0, y: 0, width: bounds.width, height: font?.lineHeight ?? 22)
            let needsScrolling = contentSize.height > bounds.height + 1
            if isScrollEnabled != needsScrolling { isScrollEnabled = needsScrolling }
        }
    }
}

private struct ItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: GroceryItem
    let onSave: (String, Double?, String?) -> Void
    @State private var name: String
    @State private var amount: String
    @State private var unit: String
    @State private var validationMessage: String?

    init(item: GroceryItem, onSave: @escaping (String, Double?, String?) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _amount = State(initialValue: item.quantityAmount.map { String($0) } ?? "")
        _unit = State(initialValue: item.quantityUnit ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                    if validationMessage == "Item name is required" { Text(validationMessage!).foregroundStyle(.red) }
                    TextField("Quantity", text: $amount).keyboardType(.decimalPad)
                    if validationMessage == "Enter a valid quantity" { Text(validationMessage!).foregroundStyle(.red) }
                    TextField("Unit (optional)", text: $unit)
                    HStack(spacing: 8) {
                        ForEach(["g", "kg", "mL", "L", "cans", "packs"], id: \.self) { suggestion in
                            Button(suggestion) { unit = suggestion }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                Section {
                    Text("Saving changes marks this item Pending. Quantity is guidance only and does not change any store basket.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !cleanedName.isEmpty else { validationMessage = "Item name is required"; return }
        let cleanedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAmount: Double?
        if cleanedAmount.isEmpty { parsedAmount = nil }
        else if let value = Double(cleanedAmount), value.isFinite, value >= 0 { parsedAmount = value }
        else { validationMessage = "Enter a valid quantity"; return }
        onSave(cleanedName, parsedAmount, unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct ClearListButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Label("Clear List", systemImage: "trash")
                Spacer(minLength: 0)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct StoreLaunchButtonStyle: ViewModifier {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .tint(tint)
        } else {
            content
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(Capsule().fill(tint.opacity(0.72)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                }
                .shadow(color: tint.opacity(0.18), radius: 8, y: 3)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}
