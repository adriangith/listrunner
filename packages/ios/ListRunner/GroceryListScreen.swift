import Combine
import SwiftData
import SwiftUI
import UIKit

struct ShoppingRootScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allItems: [GroceryItem]
    @StateObject private var sessions: StoreSessions
    @StateObject private var visibility: StoreVisibilityPreferences
    @StateObject private var paprikaReminders = PaprikaReminders.shared
    @ObservedObject private var siriNavigation = SiriNavigation.shared
    @AppStorage("activeStoreID") private var activeStoreID = StoreID.coles.rawValue
    @State private var drafts: [ListOwner: String] = [:]
    @AppStorage("allItemsScope.v1") private var showingAllItems = false
    @State private var storeLaunchRequested = false
    @State private var importLaunchRequested = false
    @AppStorage("allItemsRecentStoreOrder.v1") private var allItemsRecentStoreOrder = ""
    @AppStorage("allItemsRecentItemOrder.v1") private var allItemsRecentItemOrder = ""
    @AppStorage("allItemsDraft.v1") private var allItemsDraft = ""
    @AppStorage("allItemsAddDestination.v1") private var allItemsAddDestination = ""
    @State private var welcomeCompletion = 0
    @State private var welcomeTransition = WelcomeCompletionTransition()
    // A list is one level below All items, never a growing list-to-list history.
    // nil lets the first render restore the saved scope without a launch animation.
    // `activeStoreID` keeps its key; it now holds a list owner's raw value.
    @State private var listPath: [ListOwner]?
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
        Set(allItems.flatMap { item in
            item.listIDs.filter { ListOwner(listID: $0) != nil }
        })
    }
    private var activeOwner: ListOwner { ListOwner(rawValue: activeStoreID) ?? .store(.coles) }
    private var availableOwners: [ListOwner] {
        (visibility.inboxEnabled ? [.inbox] : []) + StoreCatalogue.ordered(sessions.definitions,
            countryCode: nil, enabledIDs: shoppingVisibleIDs).map { .store($0.id) }
    }

    private var overviewAvailable: Bool {
        ShoppingListNavigationPolicy.offersAllItems(enabledStoreIDs: shoppingVisibleIDs,
                                                    inboxEnabled: visibility.inboxEnabled,
                                                    itemListIDs: allItems.flatMap { item in item.listIDs.map(Optional.init) })
    }

    private var usesOverview: Bool {
        !previewingStoreWelcome && (overviewEnabled ?? overviewAvailable)
    }

    private var navigationPath: Binding<[ListOwner]> {
        Binding(get: {
            listPath ?? (usesOverview && !showingAllItems ? [activeOwner] : [])
        }, set: { path in
            // SwiftUI writes this only when the native Back action/edge pop commits.
            // A cancelled interactive swipe must not change the remembered scope.
            sessions.endAllInteractions()
            listPath = path
            if let owner = path.last { activeStoreID = owner.rawValue }
            showingAllItems = usesOverview && path.isEmpty
        })
    }

    var body: some View {
        let owner = activeOwner
        NavigationStack(path: navigationPath) {
                // A one-launch preview takes precedence without changing the saved scope.
                Group {
                    if usesOverview {
                        AllItemsScreen(sessions: sessions, visibility: visibility, paprikaReminders: paprikaReminders,
                            draft: $allItemsDraft, destinationRawValue: $allItemsAddDestination,
                            onChooseStoreList: { selectStore($0) }, onPromoteStore: promote,
                            onListVisibilityChange: listVisibilityChanged)
                    } else {
                        storeList(owner)
                    }
                }
                .navigationDestination(for: ListOwner.self) { id in
                    storeList(id)
                        // Keep the system Back button and interactive edge gesture, with
                        // a compact chevron alongside the existing leading scope chooser.
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
            .onChange(of: visibility.inboxEnabled) { _, enabled in
                if enabled { previewingStoreWelcome = false }
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
                    return Dictionary(grouping: rows.flatMap(\.listIDs), by: { $0 }).mapValues(\.count)
                }
                // A cold launch from Siri's Open List arrives before this view.
                openSiriRequestedList(siriNavigation.requestedList)
                ListRunnerShortcuts.updateAppShortcutParameters()
            }
            .onChange(of: nonEmptyListIDs) { _, ids in visibility.updateNonEmptyListIDs(ids) }
            .onChange(of: siriNavigation.requestedList) { _, owner in openSiriRequestedList(owner) }
            .onChange(of: availableOwners) { _, _ in
                // Siri's spoken list names come from the enabled lists.
                ListRunnerShortcuts.updateAppShortcutParameters()
            }
    }

    private func openSiriRequestedList(_ owner: ListOwner?) {
        guard let owner else { return }
        siriNavigation.requestedList = nil
        guard !previewingStoreWelcome else { return }
        selectStore(owner)
    }

    // Shared route construction for a direct single-list root and a list detail.
    private func storeList(_ owner: ListOwner) -> some View {
        GroceryListScreen(owner: owner, sessions: sessions, visibility: visibility,
            paprikaReminders: paprikaReminders, previewingStoreWelcome: $previewingStoreWelcome,
            rawInput: Binding(get: { drafts[owner] ?? "" }, set: { drafts[owner] = $0 }),
            onWelcomeStoreEnabled: completeWelcome,
            onSelectStore: { selectStore($0) }, onSelectAllItems: selectAllItems,
            storeLaunchRequested: $storeLaunchRequested, importLaunchRequested: $importLaunchRequested,
            onPromoteStore: promote, ownsNavigationStack: false,
            offersAllItems: usesOverview, onListVisibilityChange: listVisibilityChanged)
            .id(owner)
    }

    private func selectStore(_ store: ListOwner) {
        guard visibility.isListAvailable(store, definitions: sessions.definitions) else { return }
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
                if let onlyList = availableOwners.first, availableOwners.count == 1 {
                    activeStoreID = onlyList.rawValue
                }
                showingAllItems = false
            }
            listPath = available && !showingAllItems ? [activeOwner] : []
        }
    }

    private func completeWelcome(_ store: ListOwner) {
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

    private func promote(_ store: ListOwner, _ itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else { return }
        allItemsRecentStoreOrder = ItemPromotionOrder.promotingList(store, in: allItemsRecentStoreOrder)
        allItemsRecentItemOrder = ItemPromotionOrder.promoting(itemIDs, in: allItemsRecentItemOrder,
                                                               existing: Set(allItems.map(\.id)).union(itemIDs))
    }
}

// Lets a list screen own an optional retailer browser as a StateObject and
// still re-render when that browser changes. The Inbox holds nil.
@MainActor
private final class OptionalStoreBrowser: ObservableObject {
    let browser: StoreBrowser?
    private var subscription: AnyCancellable?

    init(_ browser: StoreBrowser?) {
        self.browser = browser
        subscription = browser?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
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
                ToolbarItem(placement: .topBarLeading) {
                    if !isWelcome { scope() }
                }
            }
            .toolbar(isWelcome ? .hidden : .visible, for: .navigationBar)
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

// Tint only the native Back item. Keep its system glyph, background, hit target
// and interactive navigation; never extend the chooser's decoration over it.
private struct StoreListBackTint: UIViewControllerRepresentable {
    let tint: Color

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.storeTint = UIColor(tint)
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.storeTint = UIColor(tint)
        controller.apply()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore()
    }

    final class Controller: UIViewController {
        var storeTint = UIColor.label
        private weak var previousItem: UINavigationItem?
        private var originalBack: UIBarButtonItem?
        private let storeBack = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        override func loadView() {
            let anchor = UIView()
            anchor.isUserInteractionEnabled = false
            view = anchor
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { apply() }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // Configure before the navigation bar's visible transition, rather
            // than waiting for viewDidAppear or a queued main-thread update.
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restore()
        }

        func apply() {
            // During viewWillAppear the destination need not be in a window yet.
            // Stack ownership, not window attachment, makes this safe to style.
            guard let navigationController else { return }
            var host = parent
            while let candidate = host, !navigationController.viewControllers.contains(where: { $0 === candidate }) {
                host = candidate.parent
            }
            guard let host, navigationController.topViewController === host,
                  let index = navigationController.viewControllers.firstIndex(where: { $0 === host }), index > 0 else { return }
            let previous = navigationController.viewControllers[index - 1].navigationItem
            if previousItem !== previous {
                restore()
                previousItem = previous
                originalBack = previous.backBarButtonItem
            }
            storeBack.tintColor = storeTint
            storeBack.accessibilityLabel = String(localized: "Back to All items")
            if previous.backBarButtonItem !== storeBack { previous.backBarButtonItem = storeBack }
        }

        func restore() {
            if previousItem?.backBarButtonItem === storeBack { previousItem?.backBarButtonItem = originalBack }
            previousItem = nil
            originalBack = nil
        }
    }
}

private struct ListScopePicker: View {
    let stores: [StoreDefinition]
    var includesInbox = false
    let selectedOwner: ListOwner?
    let tint: Color
    let onChooseAllItems: () -> Void
    let onChooseStore: (ListOwner) -> Void
    let onManageStores: () -> Void
    var offersAllItems = true

    var body: some View {
        Menu {
            if offersAllItems {
                if selectedOwner == nil {
                    Label("All items", systemImage: "checkmark")
                } else {
                    Button(action: onChooseAllItems) { Label("All items", systemImage: "square.grid.2x2") }
                }
                Divider()
            }
            if includesInbox {
                Button { onChooseStore(.inbox) } label: { Label("Inbox", systemImage: "tray") }
                    .accessibilityIdentifier("store-picker-inbox")
                Divider()
            }
            ForEach(stores, id: \.id) { store in
                Button(store.displayName) { onChooseStore(.store(store.id)) }
            }
            Divider()
            Button("Manage Stores", action: onManageStores)
                .accessibilityIdentifier("store-picker-manage-stores")
        } label: {
            HStack(spacing: 6) {
                Text(selectedOwner?.displayName ?? "All items")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.black))
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(selectedOwner == nil ? "all-items-scope-picker" : "store-picker")
        .accessibilityHint("Each store has its own shopping list and basket")
    }
}

private struct ListPageToolbar: ToolbarContent {
    var showSettings = true
    var grouping: Binding<AllItemsGrouping>?
    var groupingDisabled = false
    let onSettings: () -> Void

    var body: some ToolbarContent {
        // Adjacent native controls share one system Liquid Glass capsule on
        // iOS 26+. Earlier versions retain their standard toolbar appearance.
        ToolbarItemGroup(placement: .topBarTrailing) {
            if showSettings {
                if let grouping {
                    AllItemsGroupingMenu(selection: grouping)
                        .disabled(groupingDisabled)
                }
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
    var showsImport = true
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
                if showsImport {
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
                }
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
    // Other lists the item also belongs to, e.g. "Also in Woolworths".
    var alsoIn: String?
    let status: GroceryStatus
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentenceCase(name)).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let ownerName {
                    Text("\(ownerName) · Quantity \(quantity)\(unavailable ? " · Unavailable" : "")\(alsoIn.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Quantity \(quantity)\(alsoIn.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
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
    var alsoIn: String?
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
                        unavailable: unavailable, alsoIn: alsoIn, status: status,
                        tint: status == .skipped ? .secondary : tint)
    }
}

private struct AllItemsAddButton: View {
    @ScaledMetric(relativeTo: .body) private var verticalPadding = 7.0
    let destinations: [ListOwner]
    let stores: [ListOwner]
    let onChooseDestination: (ListOwner) -> Void
    let onChooseDestinations: () -> Void
    let canAdd: Bool
    let onAdd: () -> Void
    let onManageStores: () -> Void

    var body: some View {
        if !destinations.isEmpty {
            HStack(spacing: 0) {
                Button(action: onAdd) {
                    Text(destinations.count == 1
                        ? "Add to \(destinations[0].displayName)"
                        : "Add to \(destinations.count) Stores")
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
                    ForEach(stores) { store in
                        Button { onChooseDestination(store) } label: {
                            if destinations.contains(store) { Label(store.displayName, systemImage: "checkmark") }
                            else { Text(store.displayName) }
                        }
                    }
                    Divider()
                    Button("Choose Lists…", action: onChooseDestinations)
                } label: {
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Choose add destinations")
                .accessibilityValue(Text(destinations.map(\.displayName).joined(separator: ", ")))
                .accessibilityIdentifier("all-items-add-destination")
            }
            .modifier(ProductAddButtonChrome())
        } else {
            Menu {
                if stores.isEmpty { Button("Manage Stores", action: onManageStores) }
                else {
                    ForEach(stores) { store in
                        Button(store.displayName) { onChooseDestination(store) }
                    }
                    Divider()
                    Button("Choose Lists…", action: onChooseDestinations)
                }
            } label: {
                Label("Choose Lists", systemImage: "chevron.down")
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

private struct AllItemsGroupingMenu: View {
    @Binding var selection: AllItemsGrouping

    var body: some View {
        Menu {
            Picker("Group items", selection: $selection) {
                Text("By store").tag(AllItemsGrouping.store)
                    .accessibilityIdentifier("all-items-grouping-store")
                Text("By category").tag(AllItemsGrouping.category)
                    .accessibilityIdentifier("all-items-grouping-category")
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .labelStyle(.iconOnly)
        // Native toolbar menus can discard accessibilityValue; keep the current
        // grouping in the label so it is still announced before opening the menu.
        .accessibilityLabel(selection == .store
            ? Text("Filter, grouped by store") : Text("Filter, grouped by category"))
        .accessibilityHint("Choose how to group all items")
        .accessibilityIdentifier("all-items-filter")
    }
}

private struct AllItemsGroup: Identifiable {
    let id: String
    let title: String
    let owners: [ListOwner]
    let items: [GroceryItem]
}

private struct AllItemsClearRequest {
    let groupID: String
    let itemIDs: Set<UUID>
}

private struct AllItemsGroupHeader: View {
    let group: AllItemsGroup
    let tint: Color
    let addStore: ListOwner?
    let openStore: ListOwner?
    let onOpenStore: (ListOwner) -> Void
    let onAdd: (ListOwner) -> Void
    var onAddFrame: (ListOwner, CGRect) -> Void = { _, _ in }

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
    var groupAddButtons: [ListOwner: CGRect] = [:]
}

private struct AllItemsGroupRegion<Content: View>: View {
    let nativeRows: Bool
    let order: [ListOwner]
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
    let onChooseStoreList: (ListOwner) -> Void
    let onPromoteStore: (ListOwner, [UUID]) -> Void
    var onListVisibilityChange: (Bool) -> Void = { _ in }
    @AppStorage("allItemsGrouping.v1") private var groupingRawValue = AllItemsGrouping.store.rawValue
    @AppStorage("allItemsRecentStoreOrder.v1") private var recentStoreOrderRawValue = ""
    @AppStorage("allItemsRecentItemOrder.v1") private var recentItemOrderRawValue = ""
    @State private var notice: String?
    @State private var showingStoreManagement = false
    @State private var showingSettings = false
    @State private var editMode = EditMode.inactive
    @State private var workingStoreID: ListOwner?
    @State private var workingStoreOrder: [ListOwner] = []
    @State private var groupAddRequest: UUID?
    @State private var groupAddFocusRequest: UUID?
    @State private var clearRequest: AllItemsClearRequest?
    @State private var showingDestinationPicker = false
    @State private var editingListsItem: GroceryItem?
    @State private var shoppingChooserItem: GroceryItem?
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
    private func isAvailable(_ owner: ListOwner) -> Bool {
        switch owner {
        case .inbox: visibility.inboxEnabled
        case .store(let store): shoppingVisibleIDs.contains(store)
        }
    }
    private var destinationOwners: [ListOwner] {
        destinationRawValue.split(separator: ",").compactMap { ListOwner(rawValue: String($0)) }.filter { isAvailable($0) }
    }
    private var destinationID: ListOwner? { destinationOwners.first }
    private var visibleStores: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                               enabledIDs: shoppingVisibleIDs)
    }
    // Add and move destinations: Inbox first when on, then enabled stores.
    private var availableOwners: [ListOwner] {
        (visibility.inboxEnabled ? [.inbox] : []) + visibleStores.map { .store($0.id) }
    }
    private var shoppingStores: [StoreDefinition] {
        let populatedListIDs = Set(allItems.flatMap(\.listIDs))
        return visibleStores.filter { populatedListIDs.contains($0.id.listID) }
    }
    private var pendingCount: Int { allItems.filter { $0.status == .pending }.count }
    private var addedCount: Int { allItems.filter { $0.status == .added }.count }
    private var skippedCount: Int { allItems.filter { $0.status == .skipped }.count }
    private var recency: [ListOwner] {
        recentStoreOrderRawValue.split(separator: ",").compactMap { ListOwner(rawValue: String($0)) }
    }

    private var groups: [AllItemsGroup] {
        let itemRanks = ItemPromotionOrder.ranks(recentItemOrderRawValue)
        func groupRank(_ group: AllItemsGroup) -> Int {
            group.items.compactMap { itemRanks[$0.id] }.min() ?? Int.max
        }
        // One pair per (item, list): a shared item appears in each of its
        // store groups; an unknown or missing owner appears once as
        // Uncategorised, never silently dropped.
        let owned: [(ListOwner?, GroceryItem)] = allItems.flatMap { item in
            var pairs: [(ListOwner?, GroceryItem)] = []
            var orphaned = false
            for listID in item.listIDs {
                if let owner = ListOwner(listID: listID) {
                    pairs.append((owner, item))
                } else if !orphaned {
                    orphaned = true
                    pairs.append((nil, item))
                }
            }
            if pairs.isEmpty { pairs.append((nil, item)) }
            return pairs
        }
        let definitions = Dictionary(uniqueKeysWithValues: sessions.definitions.map { ($0.id, $0) })
        func storeOrder(_ ids: [ListOwner]) -> [ListOwner] {
            let ranked = ids.sorted { lhs, rhs in
                let li = recency.firstIndex(of: lhs) ?? Int.max
                let ri = recency.firstIndex(of: rhs) ?? Int.max
                return li == ri ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending : li < ri
            }
            return ranked
        }
        // Each store group orders by that list's own membership positions.
        func byListPosition(_ items: [GroceryItem], in listID: UUID) -> [GroceryItem] {
            items.sorted { left, right in
                let lhs = left.sortPosition(in: listID), rhs = right.sortPosition(in: listID)
                return lhs == rhs ? left.id.uuidString < right.id.uuidString : lhs < rhs
            }
        }
        if grouping == .store {
            var known: [AllItemsGroup] = []
            for id in ListOwner.all {
                let values = byListPosition(owned.filter { $0.0 == id }.map(\.1), in: id.listID)
                if !values.isEmpty || (!editMode.isEditing && workingStoreID == id && isAvailable(id)) {
                    known.append(AllItemsGroup(id: "store-\(id.rawValue)", title: id.displayName, owners: [id], items: values))
                }
            }
            known.sort { lhs, rhs in
                if workingStoreID != nil {
                    let left = lhs.owners.first.flatMap { workingStoreOrder.firstIndex(of: $0) } ?? Int.max
                    let right = rhs.owners.first.flatMap { workingStoreOrder.firstIndex(of: $0) } ?? Int.max
                    if left != right { return left < right }
                }
                let li = groupRank(lhs), ri = groupRank(rhs)
                return li == ri ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : li < ri
            }
            let orphaned = owned.filter { $0.0 == nil }.map(\.1).sorted { $0.position < $1.position }
            return known + (orphaned.isEmpty ? [] : [AllItemsGroup(id: "uncategorised", title: "Uncategorised", owners: [], items: orphaned)])
        }
        // Inbox items have no retailer category. They form their own group,
        // never Uncategorised (which means an unrecognised owner).
        let inboxItems = owned.filter { $0.0 == .inbox }.map(\.1)
        let storeOwned = owned.filter { $0.0 != .inbox }
        let byCategory: [StoreCategory?: [(ListOwner?, GroceryItem)]] = Dictionary(grouping: storeOwned) { pair in
            pair.0?.store.flatMap { definitions[$0]?.category ?? $0.defaultCategory }
        }
        func promoted(_ items: [GroceryItem]) -> [GroceryItem] {
            items.enumerated().sorted { lhs, rhs in
                let left = itemRanks[lhs.element.id] ?? Int.max, right = itemRanks[rhs.element.id] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }
        var categorized = StoreCategory.allCases.compactMap { category -> AllItemsGroup? in
            let values = byCategory[.some(category)] ?? []
            guard !values.isEmpty else { return nil }
            let owners = storeOrder(Array(Set(values.compactMap(\.0))))
            let order = Dictionary(uniqueKeysWithValues: owners.enumerated().map { ($1, $0) })
            let historicalItems = values.sorted { lhs, rhs in
                let li = lhs.0.flatMap { order[$0] } ?? Int.max, ri = rhs.0.flatMap { order[$0] } ?? Int.max
                if li != ri { return li < ri }
                let lp = lhs.0.map { lhs.1.sortPosition(in: $0.listID) } ?? lhs.1.position
                let rp = rhs.0.map { rhs.1.sortPosition(in: $0.listID) } ?? rhs.1.position
                return lp == rp ? lhs.1.id.uuidString < rhs.1.id.uuidString : lp < rp
            }
            // A shared item whose stores share a category appears once in
            // that category group, at its best-ranked occurrence.
            var seen = Set<UUID>()
            let unique = historicalItems.filter { seen.insert($0.1.id).inserted }
            return AllItemsGroup(id: "category-\(category.rawValue)", title: category.displayName,
                                 owners: owners, items: promoted(unique.map(\.1)))
        }
        if !inboxItems.isEmpty {
            categorized.append(AllItemsGroup(id: "category-inbox", title: ListOwner.inbox.displayName,
                                             owners: [.inbox], items: promoted(byListPosition(inboxItems, in: ListOwner.inbox.listID))))
        }
        categorized.sort { lhs, rhs in
            let li = groupRank(lhs), ri = groupRank(rhs)
            return li == ri ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : li < ri
        }
        let orphaned = byCategory[.none] ?? []
        guard !orphaned.isEmpty else { return categorized }
        return categorized + [AllItemsGroup(id: "uncategorised", title: "Uncategorised", owners: [],
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
                ListScopePicker(stores: visibleStores, includesInbox: visibility.inboxEnabled,
                    selectedOwner: nil, tint: .accentColor,
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
                importDisabled: destinationID?.store == nil, compactImport: true,
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
                    AllItemsAddButton(destinations: destinationOwners, stores: availableOwners,
                         onChooseDestination: selectAddDestination,
                         onChooseDestinations: { showingDestinationPicker = true },
                         canAdd: !ParsedGrocery.productEntries(in: draft).isEmpty,
                         onAdd: addItems, onManageStores: { showingStoreManagement = true })
                }
            if groups.isEmpty {
                ContentUnavailableView("Your lists are empty", systemImage: "basket",
                                       description: Text("Add products above, or choose a store list."))
                    .listRowBackground(Color.clear)
            } else {
                AllItemsGroupRegion(nativeRows: usesNativeGroupRows, order: workingStoreOrder, reduceMotion: reduceMotion) {
                ForEach(groups) { group in
                    AllItemsGroupCard(nativeRows: usesNativeGroupRows) {
                        AllItemsGroupHeader(group: group,
                            tint: grouping == .store && !group.owners.isEmpty ? storeTint(group.owners[0]) : .secondary,
                            addStore: grouping == .store
                                ? group.owners.first.flatMap { isAvailable($0) ? $0 : nil } : nil,
                            openStore: grouping == .store
                                ? group.owners.first.flatMap { isAvailable($0) ? $0 : nil } : nil,
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
                        // Browse cards use a VStack, so supply the vertical
                        // insets that native List rows already add in edit/store lists.
                        .padding(.vertical, usesNativeGroupRows ? 0 : 11)
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
                            if grouping == .store || group.owners == [.inbox] {
                                if group.items.contains(where: \.isShared) {
                                    Text("This clears only your \(group.title) list in ListRunner. Items also on other lists stay on them. It does not change any store cart or Apple Reminders.")
                                } else {
                                    Text("This clears only your \(group.title) list in ListRunner. It does not change any store cart or Apple Reminders.")
                                }
                            } else if group.items.contains(where: \.isShared) {
                                Text("This clears only items shown in the \(group.title) category in ListRunner, across its store lists. Items also on other lists stay on them. It does not change any store cart or Apple Reminders.")
                            } else {
                                Text("This clears only items shown in the \(group.title) category in ListRunner, across its store lists. It does not change any store cart or Apple Reminders.")
                            }
                        }
                        }
                    }
                    .id(group.id)
                    .zIndex(!editMode.isEditing && group.owners.first == workingStoreID ? 1 : 0)
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
        .onChange(of: availableOwners) { _, owners in
            if let workingStoreID, !owners.contains(workingStoreID) {
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
            ListPageToolbar(grouping: Binding(get: { grouping }, set: { value in
                guard !editMode.isEditing else { return }
                groupAddRequest = nil
                entryFocused = false
                entryFocus.resignFirstResponder()
                groupingRawValue = value.rawValue
            }), groupingDisabled: editMode.isEditing) {
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
                importDestinationName: destinationID?.store?.displayName ?? "selected store",
                onOpenStoreList: { id in
                    showingSettings = false
                    onChooseStoreList(.store(id))
                }, onOpenInbox: {
                    showingSettings = false
                    onChooseStoreList(.inbox)
                }) {
                    showingSettings = false
                    importItems()
                }
        }
        .navigationDestination(isPresented: $showingStoreManagement) {
            StoreVisibilityScreen(sessions: sessions, visibility: visibility,
                onOpenStoreList: { id in
                    showingStoreManagement = false
                    onChooseStoreList(.store(id))
                })
        }
        .sheet(item: $editingItem) { item in
            ItemEditorSheet(item: item, listOptions: editorListOptions(for: item)) { name, amount, unit, lists in
                item.name = name
                item.searchTerm = name
                item.quantityAmount = amount
                item.quantityUnit = amount == nil ? nil : unit
                item.status = .pending
                if !lists.isEmpty { applyLists(lists, to: item) }
                stageReminderWriteback(for: item)
                saveChanges()
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingDestinationPicker) {
            AddDestinationSheet(options: availableOwners, initialSelection: Set(destinationOwners.map(\.rawValue))) { chosen in
                destinationRawValue = chosen.map(\.rawValue).joined(separator: ",")
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingListsItem) { item in
            ListsEditorSheet(item: item, options: editorListOptions(for: item)) { lists in
                applyLists(lists, to: item)
                stageReminderWriteback(for: item)
                if saveChanges() {
                    notice = lists.count == 1
                        ? "Item is now on \(lists[0].displayName)."
                        : "Item is now on \(joinedNames(lists.map(\.displayName)))."
                }
            }
            .presentationDetents([.large])
        }
        .confirmationDialog("Open which store?", isPresented: Binding(
            get: { shoppingChooserItem != nil }, set: { if !$0 { shoppingChooserItem = nil } }),
            titleVisibility: .visible) {
            if let item = shoppingChooserItem {
                ForEach(shoppingChoices(for: item), id: \.rawValue) { owner in
                    Button(owner.displayName) {
                        openAllItem(item, at: owner)
                        shoppingChooserItem = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { shoppingChooserItem = nil }
        } message: {
            if let item = shoppingChooserItem {
                Text("\(item.name) is on more than one list. Choose which store to shop.")
            }
        }
        .sheet(item: $shoppingDestination) { store in
            StoreShoppingView(items: ShoppingLists.orderedItems(in: store.listID, from: allItems),
                browser: sessions.browser(for: store),
                initialSelectedID: lists.first { $0.id == store.listID }?.selectedItemID,
                saveFailed: saveFailed,
                onSelectionChange: { id in
                    lists.first { $0.id == store.listID }?.selectedItemID = id
                    saveChanges()
                }, onStatusChange: { item in
                    stageReminderWriteback(for: item)
                    saveChanges()
                }, onAddStoreProduct: { name, quantity, insertion in
                    addStoreProduct(name, quantity: quantity, to: .store(store), insertion: insertion)
                }, onDeleteItem: { item in delete(item) })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $importDestination) { store in
            GroceryListScreen(owner: .store(store), sessions: sessions, visibility: visibility,
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
            if destinationRawValue.isEmpty, let first = visibleStores.first.map({ ListOwner.store($0.id) }) ?? availableOwners.first {
                // The root supplies the previously viewed list on first entry.
                // Do not reach into a different defaults suite here (UI tests
                // and recovery use their own isolated app preferences).
                destinationRawValue = first.rawValue
            }
        }
        .onDisappear {
            onListVisibilityChange(false)
            entryFocused = false
            entryFocus.resignFirstResponder()
            if let workingStoreID, !allItems.contains(where: { $0.listIDs.contains(workingStoreID.listID) }) {
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
                groupItemRow(item, in: group, using: proxy)
            }
            .onMove(perform: grouping == .store && group.owners.count == 1 ? { source, destination in
                moveItems(in: group, from: source, to: destination)
            } : nil)
        } else {
            AllItemsItemRows(groupID: group.id, items: group.items,
                canReorder: grouping == .store && group.owners.count == 1,
                onReorder: { reorderItems($0, before: $1, in: group) }, onDelete: delete,
                onSelect: { openAllItem($0, choosingFrom: displayOwner(of: $0, in: group)) }) { item in
                    groupItemRow(item, in: group, using: proxy)
                }
        }
    }

    // Which of the group's lists a row speaks for: the group's own owner in
    // By store, or the item's best-ranked list among the category's owners.
    private func displayOwner(of item: GroceryItem, in group: AllItemsGroup) -> ListOwner? {
        group.owners.first { item.listIDs.contains($0.listID) } ?? group.owners.first
    }

    @ViewBuilder
    private func groupItemRow(_ item: GroceryItem, in group: AllItemsGroup, using proxy: ScrollViewProxy) -> some View {
        let row = allItemRow(item, displayOwner: displayOwner(of: item, in: group), nativeSelection: !usesNativeGroupRows)
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

    // Choosing a store in the menu replaces the single destination and
    // promotes its group, preserving the draft and keyboard/focus state.
    // Multi-list sets are chosen through the Lists… sheet.
    private func selectAddDestination(_ store: ListOwner) {
        guard isAvailable(store) else { return }
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

    private func workingOrder(promoting store: ListOwner) -> [ListOwner] {
        [store] + groups.compactMap { $0.owners.first }.filter { $0 != store }
    }

    private func beginAdding(to store: ListOwner, using proxy: ScrollViewProxy) {
        guard grouping == .store, !editMode.isEditing, isAvailable(store) else { return }
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

    private func finishGroupAdd(_ request: UUID, to store: ListOwner) {
        guard groupAddRequest == request, workingStoreID == store,
              destinationID == store, !editMode.isEditing,
              isAvailable(store) else { return }
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

    private func allItemRow(_ item: GroceryItem, displayOwner: ListOwner?, nativeSelection: Bool = false) -> some View {
        let available = displayOwner.map(isAvailable) ?? false
        let alsoIn = joinedAlsoIn(item, excluding: displayOwner?.listID)
        return ShoppingListItemRow(name: item.name, quantity: item.displayQuantity,
            ownerName: displayOwner?.displayName ?? "Uncategorised", unavailable: !available,
            alsoIn: alsoIn,
            status: item.status, tint: displayOwner.map(storeTint) ?? .accentColor,
            accessibilityLabel: "\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)\(displayOwner.map { ", \($0.displayName)" } ?? ", Uncategorised")\(alsoIn.map { ", \($0)" } ?? "")\(available ? "" : ", Unavailable")",
            nativeSelection: nativeSelection, onOpen: {
                if grouping == .category { openAllItem(item, choosingFrom: displayOwner) }
                else { openAllItem(item, at: displayOwner) }
            }) {
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
                Button("Lists…", systemImage: "arrow.right.arrow.left") { editingListsItem = item }
                if let displayOwner, item.listIDs.count > 1 {
                    Button("Remove from \(displayOwner.displayName)", systemImage: "minus.circle") {
                        removeItem(item, from: displayOwner)
                    }
                }
                Button(item.listIDs.count > 1 ? "Delete from All Lists" : "Delete Item",
                       systemImage: "trash", role: .destructive) { delete(item) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("all-item-\(item.id.uuidString)")
    }

    // "Also in Woolworths" / "Also in Woolworths and Bunnings" for the row's
    // secondary caption, in the ordinary grey colour of that caption.
    private func joinedAlsoIn(_ item: GroceryItem, excluding listID: UUID?) -> String? {
        let names = item.otherListNames(excluding: listID)
        guard !names.isEmpty else { return nil }
        return "Also in \(joinedNames(names))"
    }

    // The list options offered by Edit Item and Lists…: Inbox when on, then
    // the available stores, always including a current owner that is not
    // currently available so an item can be moved off a disabled list.
    private func editorListOptions(for item: GroceryItem) -> [ListOwner] {
        var options = availableOwners
        for listID in item.listIDs {
            if let owner = ListOwner(listID: listID), !options.contains(owner) {
                options.append(owner)
            }
        }
        return options
    }

    private func applyLists(_ lists: [ListOwner], to item: GroceryItem) {
        let previous = Set(item.listIDs)
        for listID in previous.subtracting(Set(lists.map(\.listID))) {
            if let store = ListOwner(listID: listID)?.store { sessions.browser(for: store).endInteraction() }
            repairSelection(afterRemoving: item.id, from: listID)
        }
        ShoppingLists.setLists(item, to: lists, allItems: allItems, context: modelContext)
        ShoppingLists.repairOrder(removedIDs: [item.id],
                                  affectedListIDs: previous.subtracting(Set(lists.map(\.listID))),
                                  allItems: allItems)
    }

    private func removeItem(_ item: GroceryItem, from owner: ListOwner) {
        repairSelection(afterRemoving: item.id, from: owner.listID)
        if let store = owner.store { sessions.browser(for: store).endInteraction() }
        ShoppingLists.removeList(owner.listID, from: item)
        ShoppingLists.repairOrder(removedIDs: [item.id], affectedListIDs: [owner.listID], allItems: allItems)
        if saveChanges() {
            notice = "Removed from \(owner.displayName). It stays on its other lists."
        }
    }

    private func repairSelection(afterRemoving id: UUID, from listID: UUID) {
        guard let list = lists.first(where: { $0.id == listID }),
              list.selectedItemID == id else { return }
        list.selectedItemID = ShoppingLists.selection(afterRemoving: id,
            from: ShoppingLists.orderedItems(in: listID, from: allItems))
    }

    private func shoppingChoices(for item: GroceryItem) -> [ListOwner] {
        item.listIDs.compactMap { ListOwner(listID: $0) }.filter { owner in
            guard case .store(let store) = owner else { return false }
            return shoppingVisibleIDs.contains(store)
        }
    }

    private func openAllItem(_ item: GroceryItem, at owner: ListOwner?) {
        guard !editMode.isEditing else { editingItem = item; return }
        guard case .store(let storeOwner) = owner else {
            if owner == .inbox { editingItem = item; return }
            notice = "This saved item has no recognized store list. It remains visible and has not been moved or deleted."
            return
        }
        guard shoppingVisibleIDs.contains(storeOwner) else {
            notice = "Shopping with \(storeOwner.displayName) is unavailable. This saved item remains editable here; use its Actions menu to edit or move it."
            return
        }
        let list = lists.first { $0.id == owner?.listID }
        list?.selectedItemID = item.id
        if saveChanges() { shoppingDestination = storeOwner }
    }

    private func openAllItem(_ item: GroceryItem, choosingFrom displayOwner: ListOwner?) {
        guard !editMode.isEditing else { editingItem = item; return }
        if case .inbox = displayOwner { editingItem = item; return }
        if displayOwner == nil {
            notice = "This saved item has no recognized store list. It remains visible and has not been moved or deleted."
            return
        }
        let choices = shoppingChoices(for: item)
        guard !choices.isEmpty else {
            openAllItem(item, at: displayOwner)
            return
        }
        if choices.count == 1, let only = choices.first {
            openAllItem(item, at: only)
        } else {
            shoppingChooserItem = item
        }
    }

    private func setStatus(_ status: GroceryStatus, for item: GroceryItem) {
        item.status = status
        stageReminderWriteback(for: item)
        saveChanges()
    }

    private func moveItems(in group: AllItemsGroup, from source: IndexSet, to destination: Int) {
        guard grouping == .store, group.owners.count == 1, let owner = group.owners.first else { return }
        var orderedItems = group.items
        orderedItems.move(fromOffsets: source, toOffset: destination)
        // Reordering changes only this list's own positions, never another
        // list's copy of a shared item.
        for (position, item) in orderedItems.enumerated() {
            if let membership = item.membership(in: owner.listID) { membership.position = position }
            if item.listID == owner.listID { item.position = position }
        }
        saveChanges()
    }

    private func reorderItems(_ sources: [UUID], before destination: UUID?, in group: AllItemsGroup) {
        guard grouping == .store, group.owners.count == 1, let store = group.owners.first else { return }
        let current = ShoppingLists.orderedItems(in: store.listID, from: allItems)
        // A drag from another card must never become a cross-store transfer.
        guard let order = ShoppingLists.reorderedIDs(current.map(\.id), moving: sources, before: destination),
              order != current.map(\.id) else { return }
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for (position, id) in order.enumerated() {
            guard let item = byID[id] else { continue }
            if let membership = item.membership(in: store.listID) { membership.position = position }
            if item.listID == store.listID { item.position = position }
        }
        saveChanges()
    }

    private func delete(_ item: GroceryItem) {
        // One item, so Delete removes it from every list it is on, repairing
        // each affected list's selection and order. No second confirmation.
        let affected = Set(item.listIDs)
        for listID in affected {
            if let store = ListOwner(listID: listID)?.store { sessions.browser(for: store).endInteraction() }
            repairSelection(afterRemoving: item.id, from: listID)
        }
        for membership in item.memberships { modelContext.delete(membership) }
        modelContext.delete(item)
        ShoppingLists.repairOrder(removedIDs: [item.id], affectedListIDs: affected, allItems: allItems)
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
        // Capture the confirmed group before dismissing; a concurrent change
        // must not expand or shift the destructive scope.
        guard let request = clearRequest, let group = groups.first(where: { $0.id == request.groupID }) else { return }
        let candidates = group.items.filter { request.itemIDs.contains($0.id) }
        let removed = candidates.filter { !addedOnly || $0.status == .added }
        clearRequest = nil
        guard !removed.isEmpty else { return }
        clear(removed, from: group)
    }

    // Clearing one list removes shared items from that list only; an item whose
    // only list was cleared is deleted. In By category the affected lists are
    // the group's owners, matching the existing "across its store lists" scope.
    private func clear(_ removed: [GroceryItem], from group: AllItemsGroup) {
        let removedIDs = Set(removed.map(\.id))
        let affectedLists = Set(group.owners.map(\.listID))
        guard !removed.isEmpty else { return }
        for listID in affectedLists {
            if let store = ListOwner(listID: listID)?.store {
                sessions.browser(for: store).endInteraction()
            }
            repairSelection(afterRemovingMultiple: removedIDs, from: listID)
        }
        var fullyRemoved: [GroceryItem] = []
        for item in removed {
            // Uncategorised has no recognised owner: clearing it removes the
            // item's unrecognised lists, as the pre-membership clear did.
            let cleared: (UUID) -> Bool = group.owners.isEmpty
                ? { ListOwner(listID: $0) == nil }
                : { affectedLists.contains($0) }
            let unaffectedOthers = item.listIDs.filter { !cleared($0) }
            if unaffectedOthers.isEmpty {
                fullyRemoved.append(item)
                for membership in item.memberships { modelContext.delete(membership) }
                modelContext.delete(item)
            } else {
                for membership in item.liveMemberships where cleared(membership.listID) {
                    modelContext.delete(membership)
                }
                ShoppingLists.normalizeLegacyMirror(item)
            }
        }
        ShoppingLists.repairOrder(removedIDs: removedIDs, affectedListIDs: affectedLists, allItems: allItems)
        for item in fullyRemoved {
            pendingReminderWrites.removeValue(forKey: item.id)
            paprikaReminders.cancelQueuedWriteback(for: item)
        }
        highlightedItemIDs.subtract(removedIDs)
        notice = nil
        saveChanges()
    }

    // Selection repair for a whole cleared batch, on one list's own order.
    private func repairSelection(afterRemovingMultiple removedIDs: Set<UUID>, from listID: UUID) {
        guard let list = lists.first(where: { $0.id == listID }) else { return }
        let remaining = ShoppingLists.orderedItems(in: listID, from: allItems.filter { !removedIDs.contains($0.id) })
        if remaining.isEmpty {
            list.selectedItemID = nil
        } else if let selectedID = list.selectedItemID, removedIDs.contains(selectedID) {
            list.selectedItemID = remaining.first { $0.status == .pending }?.id ?? remaining.first?.id
        }
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
        guard let destinationID = destinationID?.store else {
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
        let destinations = destinationOwners
        guard !destinations.isEmpty, !entries.isEmpty else { return }
        guard !modelContext.hasChanges else {
            notice = "Save or retry your pending list changes before adding more items. Your text is still here."
            return
        }
        // One add can reach several lists. Duplicate merging stays list-local,
        // so the same name on two destinations stays two separate items.
        var promoted: [GroceryItem] = []
        for destination in destinations {
            promoted += ShoppingLists.stageAdd(entries, to: destination, allItems: allItems, context: modelContext)
        }
        for item in promoted { stageReminderWriteback(for: item) }
        do {
            try modelContext.save()
            let writes = Array(pendingReminderWrites.values)
            pendingReminderWrites.removeAll()
            for write in writes { paprikaReminders.queueWriteback(write) }
            var order = recency.filter { !destinations.contains($0) }
            order.insert(contentsOf: destinations.reversed(), at: 0)
            recentStoreOrderRawValue = order.map(\.rawValue).joined(separator: ",")
            for destination in destinations {
                onPromoteStore(destination, promoted.map(\.id))
            }
            highlightedItemIDs = Set(promoted.map(\.id))
            draft = ""
            entryFocused = true
            let names = joinedNames(destinations.map(\.displayName))
            notice = "Added \(promoted.count) \(promoted.count == 1 ? "item" : "items") to \(names)."
            UIAccessibility.post(notification: .announcement, argument: notice)
        } catch {
            modelContext.rollback()
            pendingReminderWrites.removeAll()
            notice = "Could not save the items. Your text is still here; try again."
        }
    }

    private func addStoreProduct(_ name: String, quantity: Int, to store: ListOwner,
                                 insertion: ShoppingLists.AdditionPosition) -> UUID? {
        guard !paprikaReminders.importing, !name.isEmpty, name.utf8.count <= 512,
              (1...999).contains(quantity) else { return nil }
        if modelContext.hasChanges, !saveChanges() { return nil }
        let existingIDs = Set(allItems.map(\.id))
        let entry = ParsedGrocery(name: name, amount: Double(quantity), unit: nil)
        let snapshot = ShoppingLists.AdditionSnapshot(items: allItems, owner: store)
        let promoted = ShoppingLists.stageAdd([entry], to: store, allItems: allItems, context: modelContext, insertion: insertion)
        // Website products belong to that store's list only.
        for item in promoted where !existingIDs.contains(item.id) {
            item.originStoreID = store.store?.rawValue
        }
        for item in promoted { stageReminderWriteback(for: item) }
        guard saveChanges() else {
            modelContext.rollback()
            snapshot.restoreAfterRollback()
            pendingReminderWrites.removeAll()
            return nil
        }
        onPromoteStore(store, promoted.map(\.id))
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Added to your \(store.displayName) list"))
        return promoted.first?.id
    }

    private func storeTint(_ owner: ListOwner) -> Color {
        guard let id = owner.store else { return .accentColor }
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
    // The Inbox has no retailer, so it never creates a browser or website session.
    @StateObject private var browserHolder: OptionalStoreBrowser
    @ObservedObject var visibility: StoreVisibilityPreferences
    @ObservedObject var paprikaReminders: PaprikaReminders
    let owner: ListOwner
    let sessions: StoreSessions
    let onSelectStore: (ListOwner) -> Void
    let onSelectAllItems: () -> Void
    @Binding var storeLaunchRequested: Bool
    @Binding var importLaunchRequested: Bool
    let onPromoteStore: (ListOwner, [UUID]) -> Void
    let onImportCompleted: ((String) -> Void)?
    let onWelcomeStoreEnabled: (ListOwner) -> Void
    let ownsNavigationStack: Bool
    let offersAllItems: Bool
    let onListVisibilityChange: (Bool) -> Void
    @Binding private var rawInput: String
    @State private var routedLaunch = false
    @State private var editingListsItem: GroceryItem?
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

    init(owner: ListOwner, sessions: StoreSessions, visibility: StoreVisibilityPreferences, paprikaReminders: PaprikaReminders,
         previewingStoreWelcome: Binding<Bool>, rawInput: Binding<String>,
          onWelcomeStoreEnabled: @escaping (ListOwner) -> Void,
          onSelectStore: @escaping (ListOwner) -> Void,
          onSelectAllItems: @escaping () -> Void,
          storeLaunchRequested: Binding<Bool>,
          importLaunchRequested: Binding<Bool>,
          onPromoteStore: @escaping (ListOwner, [UUID]) -> Void,
          onImportCompleted: ((String) -> Void)? = nil,
          ownsNavigationStack: Bool = true, offersAllItems: Bool = true,
          onListVisibilityChange: @escaping (Bool) -> Void = { _ in }) {
        self.owner = owner; self.sessions = sessions
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
        _browserHolder = StateObject(wrappedValue: OptionalStoreBrowser(owner.store.map { sessions.browser(for: $0) }))
    }

    private var browser: StoreBrowser? { browserHolder.browser }
    private var storeID: StoreID? { owner.store }
    private var diagnostics: DiagnosticStore { browser?.diagnostics ?? sessions.diagnostics }
    private var items: [GroceryItem] { ShoppingLists.orderedItems(in: owner.listID, from: allItems) }
    private var selectedList: GroceryList? { lists.first { $0.id == owner.listID } }
    private var shoppingVisibleIDs: Set<StoreID> { sessions.shoppingAvailability.visibleIDs(in: visibility.visibleIDs) }
    private var orderedStores: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil, enabledIDs: shoppingVisibleIDs)
    }
    // Neither an enabled store nor an enabled Inbox: show welcome/no-stores.
    private var hasNoLists: Bool {
        switch owner {
        case .inbox: !visibility.inboxEnabled && shoppingVisibleIDs.isEmpty
        case .store: shoppingVisibleIDs.isEmpty
        }
    }
    private var canShopHere: Bool {
        guard let storeID, let browser else { return false }
        return browser.canPresentStore && shoppingVisibleIDs.contains(storeID)
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
        return shoppingVisibleIDs.isEmpty && !visibility.inboxEnabled && !visibility.hasCompletedStoreSetup
    }
    // The storefront configuration is the single source of truth for the
    // selected store's visual identity, including all list-screen accents.
    private var storePrimaryColor: Color {
        guard !hasNoLists else { return .primary }
        guard let browser else { return .accentColor }
        let color = browser.store.brandColors?.primary ?? browser.store.addedColor
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }
    private var storeHighlightColor: Color {
        guard !hasNoLists else { return .primary }
        guard let color = browser?.store.brandColors?.highlight else { return storePrimaryColor }
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ListNavigationContainer(standalone: ownsNavigationStack) {
            ShoppingListPage(isWelcome: showingStoreWelcome,
                keyboardDismissMode: isRevealingProductEntry ? .never : .interactively,
                onViewportChange: { frame in
                    listViewportFrame = frame
                    revealFocusedProductEntry()
                    if let itemID = scrollTargetItemID { scrollToAddedItem(itemID, using: scrollProxy) }
                }, scope: {
                    if !showingStoreWelcome && !hasNoLists {
                        ListScopePicker(stores: orderedStores, includesInbox: visibility.inboxEnabled,
                            selectedOwner: owner, tint: storePrimaryColor,
                            onChooseAllItems: onSelectAllItems, onChooseStore: onSelectStore,
                            onManageStores: { showingStoreManagement = true }, offersAllItems: offersAllItems)
                    }
                }, footer: {
                    if !showingStoreWelcome && !hasNoLists && storeID != nil && !items.isEmpty {
                        Button(action: presentStore) {
                            Label("Show Store", systemImage: "cart.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .modifier(StoreLaunchButtonStyle(tint: storePrimaryColor))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            showStoreFrame = frame
                            revealFocusedProductEntry()
                        }
                        .disabled(!canShopHere)
                        .padding(.horizontal, 20).padding(.top, 8)
                        // Tuck the fixed action closer to the home indicator, but
                        // retain its comfortable keyboard clearance while editing.
                        .padding(.bottom, groceryInputFocused ? 16 : -12)
                    }
                }) {
                if showingStoreWelcome {
                    StoreWelcomeContent(chooseStore: {
                        managingWelcomeStores = true
                        showingStoreManagement = true
                    }, startWithInbox: startWithInbox)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if hasNoLists {
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
                        if let browser, browser.cartUndoWarning {
                            CartUndoWarning(storeName: owner.displayName) { browser.dismissCartUndoWarning() }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
                    // Animate only notice visibility, not typing, item statuses,
                    // or the rest of the grocery list's frequent updates.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: notice != nil)

                    ProductEntrySection(text: $rawInput, isFocused: $groceryInputFocused,
                        focusControl: productEntryFocus, tint: storePrimaryColor,
                        showsImport: storeID != nil,
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
                            ContentUnavailableView("Your list is empty", systemImage: owner == .inbox ? "tray" : "basket",
                                                   description: owner == .inbox
                                                    ? Text("Add items above. Move them to a store list when you know where to buy them.")
                                                    : Text("Add products above, then shop though them with ListRunner"))
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
                                Text(storeClearConfirmationMessage)
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
                    if storeID != nil { presentStore() }
                }
                if importLaunchRequested, storeID != nil {
                    importLaunchRequested = false
                    if GroceryImportSource(rawValue: importSourceID) == .paprika {
                        importPaprika()
                    } else {
                        showingImportSetup = true
                    }
                }
                if let selected = visibility.selectionForList(current: owner, definitions: sessions.definitions),
                   selected != owner {
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
                        onWelcomeStoreEnabled(.store(id))
                    } : nil,
                    onOpenStoreList: { id in
                        showingStoreManagement = false
                        onSelectStore(.store(id))
                    })
            }
            .onChange(of: showingStoreManagement) { _, presented in
                if !presented { managingWelcomeStores = false }
            }
            .navigationDestination(isPresented: $showingImportSetup) {
                ImportSourceSelectionScreen(selectedSourceID: importSourceID, destinationName: owner.displayName) { _ in
                    showingImportSetup = false
                    importPaprika()
                }
            }
            .navigationDestination(isPresented: $showingPaprikaInstructions) {
                PaprikaImportInstructionsScreen(destinationName: owner.displayName) {
                    showingPaprikaInstructions = false
                    importPaprika()
                }
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsOverviewScreen(sessions: sessions, visibility: visibility,
                                        importInProgress: paprikaReminders.importing,
                                        importDestinationName: owner.displayName,
                                        onOpenStoreList: { id in
                                            showingSettings = false
                                            onSelectStore(.store(id))
                                        }, onOpenInbox: {
                                            showingSettings = false
                                            onSelectStore(.inbox)
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
                if let browser {
                StoreShoppingView(items: items, browser: browser, initialSelectedID: selectedList?.selectedItemID, saveFailed: saveFailed, onSelectionChange: { id in
                    selectedList?.selectedItemID = id
                    saveChanges()
                }, onStatusChange: { item in
                    stageReminderWriteback(for: item)
                    saveChanges()
                }, onAddStoreProduct: addStoreProduct, onDeleteItem: { item in delete(item) })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(32)
                }
            }
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(item: item, listOptions: editorListOptions()) { name, amount, unit, lists in
                    item.name = name
                    item.searchTerm = name
                    item.quantityAmount = amount
                    item.quantityUnit = amount == nil ? nil : unit
                    item.status = .pending
                    if !lists.isEmpty { applyLists(lists, to: item) }
                    stageReminderWriteback(for: item)
                    saveChanges()
                }
                .presentationDetents([.large])
            }
            .sheet(item: $editingListsItem) { item in
                ListsEditorSheet(item: item, options: editorListOptions()) { lists in
                    applyLists(lists, to: item)
                    stageReminderWriteback(for: item)
                    if saveChanges() {
                        notice = lists.count == 1
                            ? "Item is now on \(lists[0].displayName)."
                            : "Item is now on \(joinedNames(lists.map(\.displayName)))."
                    }
                }
                .presentationDetents([.large])
            }
        }
        .tint(storePrimaryColor)
        .background {
            if offersAllItems && !ownsNavigationStack && !showingStoreWelcome {
                StoreListBackTint(tint: storePrimaryColor)
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
            guard let storeID, !visibleIDs.contains(storeID) else { return }
            browser?.endInteraction()
            showingStore = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                diagnostics.purge()
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
                alsoIn: joinedAlsoIn(item),
                status: item.status, tint: storePrimaryColor,
                accessibilityLabel: storeID.map { "\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue). Find in \($0.displayName)" }
                    ?? "\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)",
                onOpen: {
                    // Inbox rows have no store to open; a tap edits the item.
                    guard storeID != nil else { editingItem = item; return }
                    guard canShopHere else { return }
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
                    Button("Lists…", systemImage: "arrow.right.arrow.left") { editingListsItem = item }
                    if item.listIDs.count > 1 {
                        Button("Remove from \(owner.displayName)", systemImage: "minus.circle") { removeItem(item) }
                    }
                    Button(item.listIDs.count > 1 ? "Delete from All Lists" : "Delete Item",
                           systemImage: "trash", role: .destructive) { delete(item) }
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
            let promotedItems = ShoppingLists.stageAdd(entries, to: owner, allItems: allItems, context: modelContext)
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
                onPromoteStore(owner, promotedItems.map(\.id))
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

    private func addStoreProduct(_ name: String, quantity: Int, insertion: ShoppingLists.AdditionPosition) -> UUID? {
        guard !paprikaReminders.importing, !name.isEmpty, name.utf8.count <= 512,
              (1...999).contains(quantity) else { return nil }
        if modelContext.hasChanges {
            saveChanges()
            guard !saveFailed else { return nil }
        }
        // This is one literal product title, not a comma-separated ingredient input.
        let entry = ParsedGrocery(name: name, amount: Double(quantity), unit: nil)
        let existingIDs = Set(allItems.map(\.id))
        let snapshot = ShoppingLists.AdditionSnapshot(items: allItems, owner: owner)
        let promoted = ShoppingLists.stageAdd([entry], to: owner, allItems: allItems, context: modelContext, insertion: insertion)
        // Website products belong to this store's list only.
        for item in promoted where !existingIDs.contains(item.id) {
            item.originStoreID = storeID?.rawValue
        }
        for item in promoted { stageReminderWriteback(for: item) }
        saveChanges()
        guard !saveFailed else {
            modelContext.rollback()
            snapshot.restoreAfterRollback()
            pendingReminderWrites.removeAll()
            return nil
        }
        onPromoteStore(owner, promoted.map(\.id))
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Added to your \(owner.displayName) list"))
        return promoted.first?.id
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
        // One item: Delete removes it from every list it is on, repairing each
        // affected list's selection and order. No second confirmation.
        let affected = Set(item.listIDs)
        for listID in affected {
            if let store = ListOwner(listID: listID)?.store, store != storeID {
                sessions.browser(for: store).endInteraction()
            }
            if let list = lists.first(where: { $0.id == listID }), list.selectedItemID == item.id {
                list.selectedItemID = ShoppingLists.selection(afterRemoving: item.id,
                    from: ShoppingLists.orderedItems(in: listID, from: allItems))
            }
        }
        pendingReminderWrites.removeValue(forKey: item.id)
        paprikaReminders.cancelQueuedWriteback(for: item)
        for membership in item.memberships { modelContext.delete(membership) }
        modelContext.delete(item)
        ShoppingLists.repairOrder(removedIDs: [item.id], affectedListIDs: affected, allItems: allItems)
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
        // Reordering changes only this list's own positions.
        for (position, item) in orderedItems.enumerated() {
            if let membership = item.membership(in: owner.listID) { membership.position = position }
            if item.listID == owner.listID { item.position = position }
        }
        saveChanges()
    }

    private func startWithInbox() {
        // Turning Inbox on cannot be blocked; only turning it off checks rows.
        visibility.setInboxEnabled(true)
        onWelcomeStoreEnabled(.inbox)
    }

    private var storeClearConfirmationMessage: String {
        items.contains(where: \.isShared)
            ? "This clears only your \(owner.displayName) list in ListRunner. Items also on other lists stay on them. It does not change any store cart or Apple Reminders."
            : "This clears only your \(owner.displayName) list in ListRunner. It does not change any store cart or Apple Reminders."
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
        browser?.endInteraction()
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
        // Clearing this list removes shared items from here only; items whose
        // only list was this one are deleted.
        for item in removed {
            let otherLists = item.listIDs.filter { $0 != owner.listID }
            if otherLists.isEmpty {
                pendingReminderWrites.removeValue(forKey: item.id)
                paprikaReminders.cancelQueuedWriteback(for: item)
                for membership in item.memberships { modelContext.delete(membership) }
                modelContext.delete(item)
            } else {
                for membership in item.memberships where membership.listID == owner.listID {
                    modelContext.delete(membership)
                }
                ShoppingLists.normalizeLegacyMirror(item)
            }
        }
        ShoppingLists.repairOrder(removedIDs: removedIDs, affectedListIDs: [owner.listID], allItems: allItems)
        notice = nil
        saveChanges()
    }

    private func normalizePositions() {
        for (index, item) in items.enumerated() {
            if let membership = item.membership(in: owner.listID) { membership.position = index }
            if item.listID == owner.listID { item.position = index }
        }
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
            if !saveFailed {
                UIAccessibility.post(notification: .announcement, argument: "Changes may not be saved")
            }
            saveFailed = true
            diagnostics.record(.storage, .localSave, reason: .storageFailure, outcome: .failed)
            return false
        }
    }

    // "Also in Woolworths" for this list's rows, in the ordinary caption grey.
    private func joinedAlsoIn(_ item: GroceryItem) -> String? {
        let names = item.otherListNames(excluding: owner.listID)
        guard !names.isEmpty else { return nil }
        return "Also in \(joinedNames(names))"
    }

    // Inbox when on, then available stores; a current owner that is not
    // currently available stays in the list so items can be moved off it.
    private func editorListOptions() -> [ListOwner] {
        var options = (visibility.inboxEnabled ? [.inbox] : [])
            + orderedStores.map { ListOwner.store($0.id) }
        for item in [editingItem, editingListsItem].compactMap({ $0 }) {
            for listID in item.listIDs {
                if let current = ListOwner(listID: listID), !options.contains(current) {
                    options.append(current)
                }
            }
        }
        if !options.contains(owner) { options.append(owner) }
        return options
    }

    // Apply a Lists… or Edit Item selection: repair the lists the item left,
    // then hand the change to the shared mutation helper.
    private func applyLists(_ selected: [ListOwner], to item: GroceryItem) {
        let target = Set(selected.map(\.listID))
        let previous = Set(item.listIDs)
        let removedLists = previous.subtracting(target)
        for listID in removedLists {
            if let store = ListOwner(listID: listID)?.store, store != storeID {
                sessions.browser(for: store).endInteraction()
            }
            if let list = lists.first(where: { $0.id == listID }), list.selectedItemID == item.id {
                list.selectedItemID = ShoppingLists.selection(afterRemoving: item.id,
                    from: ShoppingLists.orderedItems(in: listID, from: allItems))
            }
        }
        ShoppingLists.setLists(item, to: selected, allItems: allItems, context: modelContext)
        ShoppingLists.repairOrder(removedIDs: [item.id], affectedListIDs: removedLists, allItems: allItems)
    }

    // The ⋯ menu's "Remove from [store]": the item stays on its other lists.
    private func removeItem(_ item: GroceryItem) {
        guard item.listIDs.count > 1 else { return }
        if selectedList?.selectedItemID == item.id {
            selectedList?.selectedItemID = ShoppingLists.selection(afterRemoving: item.id, from: items)
        }
        browser?.endInteraction()
        ShoppingLists.removeList(owner.listID, from: item)
        ShoppingLists.repairOrder(removedIDs: [item.id], affectedListIDs: [owner.listID], allItems: allItems)
        if saveChanges() {
            notice = "Removed from \(owner.displayName). It stays on its other lists."
        }
    }

    private func stageReminderWriteback(for item: GroceryItem) {
        guard !removeRemindersAfterImport else { return }
        if let write = paprikaReminders.desiredWriteback(for: item) {
            pendingReminderWrites[item.id] = write
        }
    }

    private func importPaprika() {
        // Importing into the Inbox is out of scope; its page offers no Import.
        guard storeID != nil, !paprikaReminders.importing else { return }
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
                        let positionBase = (items.map { $0.sortPosition(in: owner.listID) }.max() ?? -1) + 1
                        var importedItems: [GroceryItem] = []
                        for (offset, entry) in staged.enumerated() {
                            let item = GroceryItem(name: entry.grocery.name,
                                                   amount: entry.grocery.amount,
                                                   unit: entry.grocery.unit,
                                                   position: positionBase + offset,
                                                   listID: owner.listID)
                            item.paprikaReminderID = entry.reminderID
                            modelContext.insert(item)
                            modelContext.insert(GroceryMembership(item: item, listID: owner.listID, position: positionBase + offset))
                            importedItemIDs.append(item.id)
                            importedItems.append(item)
                        }
                        for (index, item) in (importedItems + previousItems).enumerated() {
                            if let membership = item.membership(in: owner.listID) { membership.position = index }
                            if item.listID == owner.listID { item.position = index }
                        }
                    }
                    saveFailed = false
                } catch {
                    modelContext.rollback()
                    throw PaprikaImportError.transaction
                }
                importSourceID = GroceryImportSource.paprika.rawValue
                onPromoteStore(owner, importedItemIDs)
                if removeAfterImport {
                    let savedIDs = linkedIDs.union(staged.compactMap(\.reminderID))
                    let failed = paprikaReminders.removeImportedReminders(PaprikaImportPlanner.removalCandidates(reminders: snapshot, savedIDs: savedIDs), calendarID: sourceListID)
                    notice = failed == 0
                        ? String(localized: "Groceries added to your \(owner.displayName) list: \(staged.count). Removed their reminders from ‘\(sourceListName)’. Paprika is unchanged.")
                        : String(localized: "Added \(staged.count) groceries to your \(owner.displayName) list. Some Apple reminders could not be removed. Import again to retry; your saved groceries won’t be duplicated.")
                    return
                }
                if alreadyImportedCount > 0 && staged.count == 1 {
                    notice = String(localized: "Added 1 item to your \(owner.displayName) list. Already-imported reminders skipped: \(alreadyImportedCount).")
                } else if alreadyImportedCount > 0 {
                    notice = String(localized: "Added \(staged.count) items to your \(owner.displayName) list. Already-imported reminders skipped: \(alreadyImportedCount).")
                } else if staged.count == 1 {
                    notice = String(localized: "Added 1 item to your \(owner.displayName) list.")
                } else {
                    notice = String(localized: "Added \(staged.count) items to your \(owner.displayName) list.")
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
    let startWithInbox: () -> Void

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
                Button(action: startWithInbox) {
                    Text("Start with an Inbox")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityHint("Turns on a list that is not tied to any store")
                .accessibilityIdentifier("welcome-start-inbox")
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

// Selection rows shared by the Add-destination picker, the Lists… sheet and
// the Lists section of Edit Item: full-row buttons with a checkmark, as in
// the OpenPencil design. Whole rows are tappable; Inbox is exclusive: ticking
// it clears every store, and ticking a store clears Inbox.
private struct ListsSelectionRows: View {
    let options: [ListOwner]
    var lockedTo: ListOwner? = nil
    @Binding var selection: Set<String>

    var body: some View {
        ForEach(options) { option in
            let selected = selection.contains(option.rawValue)
            Button {
                if option == .inbox {
                    if selected { selection.remove(option.rawValue) } else { selection = [option.rawValue] }
                } else if selected {
                    selection.remove(option.rawValue)
                } else {
                    selection.remove(ListOwner.inbox.rawValue)
                    selection.insert(option.rawValue)
                }
            } label: {
                HStack {
                    Text(option.displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected { Image(systemName: "checkmark") }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(lockedTo != nil && option != lockedTo)
            .accessibilityIdentifier("lists-row-\(option.rawValue)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}

private func joinedNames(_ names: [String]) -> String {
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + names.last!
}

// The Add button's destination checklist on All items: Inbox first when on,
// then the available stores. One or more stores, or Inbox alone, may be
// chosen; Done applies the remembered set.
private struct AddDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let options: [ListOwner]
    let onDone: ([ListOwner]) -> Void
    @State private var selection: Set<String>

    init(options: [ListOwner], initialSelection: Set<String>, onDone: @escaping ([ListOwner]) -> Void) {
        self.options = options
        self.onDone = onDone
        _selection = State(initialValue: initialSelection)
    }

    private var chosen: [ListOwner] { options.filter { selection.contains($0.rawValue) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add to") {
                    ListsSelectionRows(options: options, selection: $selection)
                    if selection.isEmpty {
                        Text("Choose at least one list.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Adding to Inbox alone notes the item without a store. Ticking a store clears Inbox, and Inbox clears the stores.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(chosen); dismiss() }
                        .disabled(selection.isEmpty)
                }
            }
        }
    }
}

// Lists… : the checklist that replaces Move to Another List. Ticking a store
// puts the item on that list (at its end); unticking removes it from there.
// Unticking the last list sends the item to Inbox when Inbox is on; with
// Inbox off, Save stays disabled. Website products stay locked to their store.
private struct ListsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: GroceryItem
    let options: [ListOwner]
    let inboxAvailable: Bool
    let onSave: ([ListOwner]) -> Void
    @State private var selection: Set<String>

    private var lockedTo: ListOwner? {
        guard let origin = item.originStoreID, let store = StoreID(rawValue: origin) else { return nil }
        return .store(store)
    }

    init(item: GroceryItem, options: [ListOwner], onSave: @escaping ([ListOwner]) -> Void) {
        self.item = item
        self.options = options
        self.inboxAvailable = options.contains(.inbox)
        self.onSave = onSave
        let locked = item.originStoreID.flatMap { origin in options.first { $0.store?.rawValue == origin } }
        _selection = State(initialValue: locked.map { Set([$0.rawValue]) }
            ?? Set(item.listIDs.compactMap { ListOwner(listID: $0)?.rawValue }))
    }

    private var chosen: [ListOwner] { options.filter { selection.contains($0.rawValue) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lists") {
                    ListsSelectionRows(options: options, lockedTo: lockedTo, selection: $selection)
                    if selection.isEmpty {
                        Text("Choose at least one list.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if let lockedTo {
                        Text("Products chosen on \(lockedTo.displayName)'s website stay on its list.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("An item is in Inbox on its own, or on one or more stores. Unticking its last store moves it to Inbox\(inboxAvailable ? "" : " when Inbox is on").")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("This changes where the item is kept in ListRunner. It never changes any store cart or Apple Reminders.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(chosen)
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}

private struct ItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: GroceryItem
    // List options shown in the Lists section; empty hides the section.
    let listOptions: [ListOwner]
    let onSave: (String, Double?, String?, [ListOwner]) -> Void
    @State private var name: String
    @State private var amount: String
    @State private var unit: String
    @State private var listSelection: Set<String>
    @State private var validationMessage: String?

    private var lockedTo: ListOwner? {
        guard let origin = item.originStoreID, let store = StoreID(rawValue: origin) else { return nil }
        return .store(store)
    }

    init(item: GroceryItem, listOptions: [ListOwner],
         onSave: @escaping (String, Double?, String?, [ListOwner]) -> Void) {
        self.item = item
        self.listOptions = listOptions
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _amount = State(initialValue: item.quantityAmount.map { String($0) } ?? "")
        _unit = State(initialValue: item.quantityUnit ?? "")
        let locked = item.originStoreID.flatMap { origin in listOptions.first { $0.store?.rawValue == origin } }
        _listSelection = State(initialValue: locked.map { Set([$0.rawValue]) }
            ?? Set(item.listIDs.compactMap { ListOwner(listID: $0)?.rawValue }))
    }

    private var chosenLists: [ListOwner] { listOptions.filter { listSelection.contains($0.rawValue) } }

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
                if !listOptions.isEmpty {
                    Section("Lists") {
                        ListsSelectionRows(options: listOptions, lockedTo: lockedTo, selection: $listSelection)
                        if let lockedTo {
                            Text("Products chosen on \(lockedTo.displayName)'s website stay on its list.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if listSelection.isEmpty {
                            Text("Choose at least one list.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Ticking a store adds it to that list; unticking removes it from there. An item is in Inbox on its own, or on one or more stores.")
                                .font(.footnote).foregroundStyle(.secondary)
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
        onSave(cleanedName, parsedAmount, unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, chosenLists)
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
