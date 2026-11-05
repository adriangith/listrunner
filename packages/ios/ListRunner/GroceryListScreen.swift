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
    @State private var allItemsDraft = ""
    @AppStorage("allItemsAddDestination.v1") private var allItemsAddDestination = ""
    @State private var welcomeCompletion = 0
    @State private var welcomeTransition = WelcomeCompletionTransition()
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

    var body: some View {
        let storeID = StoreID(rawValue: activeStoreID) ?? .coles
        ZStack {
        Group {
        if showingAllItems {
            NavigationStack {
            AllItemsScreen(sessions: sessions, visibility: visibility, paprikaReminders: paprikaReminders,
                           draft: $allItemsDraft, destinationRawValue: $allItemsAddDestination,
                           onChooseStoreList: { id in
                               sessions.endAllInteractions()
                               activeStoreID = id.rawValue
                               showingAllItems = false
                            }, onImportToStore: { id in
                                sessions.endAllInteractions()
                                activeStoreID = id.rawValue
                                importLaunchRequested = true
                                showingAllItems = false
                           }, onPromoteStore: promote)
            }
        } else {
        GroceryListScreen(storeID: storeID, sessions: sessions, visibility: visibility, paprikaReminders: paprikaReminders,
                           previewingStoreWelcome: $previewingStoreWelcome,
                           rawInput: Binding(get: { drafts[storeID] ?? "" }, set: { drafts[storeID] = $0 }),
                           onWelcomeStoreEnabled: { id in
                               sessions.endAllInteractions()
                               _ = visibility.selectionForList(current: id, definitions: sessions.definitions)
                               // Lay out the new navigation stack without animating
                               // its safe areas/header. Fade the captured outgoing
                               // screen instead of interpolating live stack layout.
                               welcomeTransition.perform(reduceMotion: reduceMotion) {
                                   previewingStoreWelcome = false
                                   activeStoreID = id.rawValue
                                   welcomeCompletion += 1
                               }
                           }, onSelectStore: { id in
                               sessions.endAllInteractions()
                               activeStoreID = id.rawValue
                           }, onSelectAllItems: {
                               if allItemsAddDestination.isEmpty { allItemsAddDestination = storeID.rawValue }
                               showingAllItems = true
                           }, storeLaunchRequested: $storeLaunchRequested,
                           importLaunchRequested: $importLaunchRequested,
                           onPromoteStore: promote)
        }
        }
            .id("\(storeID.rawValue)-\(welcomeCompletion)")
        }
            .background(WelcomeTransitionAnchor(transition: welcomeTransition))
            .sensoryFeedback(.success, trigger: welcomeCompletion)
             .onChange(of: shoppingVisibleIDs) { previous, current in
                // Opening management is not a choice. Keep the one-run welcome
                // preview when backing out, and finish only on an enable action.
                if !current.subtracting(previous).isEmpty {
                    previewingStoreWelcome = false
                }
            }
            .onAppear {
                visibility.updateNonEmptyListIDs(nonEmptyListIDs)
                visibility.listItemCountsProvider = {
                    // Do not disable a destination while a local mutation has
                    // not been saved, or when the saved rows cannot be read.
                    guard !modelContext.hasChanges else { throw StoreDefinition.ConfigurationError.invalid }
                    let rows = try modelContext.fetch(FetchDescriptor<GroceryItem>())
                    return Dictionary(grouping: rows.compactMap(\.listID), by: { $0 }).mapValues(\.count)
                }
            }
            .onChange(of: nonEmptyListIDs) { _, ids in visibility.updateNonEmptyListIDs(ids) }
    }

    private func promote(_ store: StoreID, _ itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else { return }
        var order = allItemsRecentStoreOrder.split(separator: ",")
            .compactMap { StoreID(rawValue: String($0)) }.filter { $0 != store }
        order.insert(store, at: 0)
        allItemsRecentStoreOrder = order.map(\.rawValue).joined(separator: ",")
        allItemsRecentItemOrder = ItemPromotionOrder.promoting(itemIDs, in: allItemsRecentItemOrder,
                                                               existing: Set(allItems.map(\.id)))
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

private enum AllItemsGrouping: String {
    case store
    case category
}

private struct AllItemsGroup: Identifiable {
    let id: String
    let title: String
    let storeIDs: [StoreID]
    let items: [GroceryItem]
}

private struct AllItemsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryItem.position) private var allItems: [GroceryItem]
    @Query private var lists: [GroceryList]
    @ObservedObject var sessions: StoreSessions
    @ObservedObject var visibility: StoreVisibilityPreferences
    @ObservedObject var paprikaReminders: PaprikaReminders
    @Binding var draft: String
    @Binding var destinationRawValue: String
    let onChooseStoreList: (StoreID) -> Void
    let onImportToStore: (StoreID) -> Void
    let onPromoteStore: (StoreID, [UUID]) -> Void
    @AppStorage("allItemsGrouping.v1") private var groupingRawValue = AllItemsGrouping.store.rawValue
    @AppStorage("allItemsRecentStoreOrder.v1") private var recentStoreOrderRawValue = ""
    @AppStorage("allItemsRecentItemOrder.v1") private var recentItemOrderRawValue = ""
    @State private var notice: String?
    @State private var showingStoreManagement = false
    @State private var itemToDelete: GroceryItem?
    @State private var editingItem: GroceryItem?
    @State private var shoppingDestination: StoreID?
    @State private var pendingReminderWrites: [UUID: ReminderWriteback] = [:]
    @FocusState private var entryFocused: Bool
    @AppStorage(GroceryImportSource.removeRemindersKey) private var removeRemindersAfterImport = true

    private var grouping: AllItemsGrouping {
        AllItemsGrouping(rawValue: groupingRawValue) ?? .store
    }
    private var destinationID: StoreID? {
        let id = StoreID(rawValue: destinationRawValue)
        return id.flatMap { visibility.shoppingVisibleIDs(in: sessions.definitions).contains($0) ? $0 : nil }
    }
    private var visibleStores: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                               enabledIDs: visibility.shoppingVisibleIDs(in: sessions.definitions))
    }
    private var pendingCount: Int { allItems.filter { $0.status == .pending }.count }
    private var addedCount: Int { allItems.filter { $0.status == .added }.count }
    private var skippedCount: Int { allItems.filter { $0.status == .skipped }.count }
    private var recency: [StoreID] {
        recentStoreOrderRawValue.split(separator: ",").compactMap { StoreID(rawValue: String($0)) }
    }

    private var groups: [AllItemsGroup] {
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
            let known = StoreID.allCases.compactMap { id -> AllItemsGroup? in
                let values = owned.filter { $0.0 == id }.map(\.1).sorted { $0.position < $1.position }
                guard !values.isEmpty else { return nil }
                return AllItemsGroup(id: "store-\(id.rawValue)", title: id.displayName, storeIDs: [id], items: values)
            }.sorted { lhs, rhs in
                let left = lhs.storeIDs[0], right = rhs.storeIDs[0]
                let li = recency.firstIndex(of: left) ?? Int.max, ri = recency.firstIndex(of: right) ?? Int.max
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
            let ranks = ItemPromotionOrder.ranks(recentItemOrderRawValue)
            let sortedItems = historicalItems.enumerated().sorted { lhs, rhs in
                let left = ranks[lhs.element.id] ?? Int.max, right = ranks[rhs.element.id] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
            return AllItemsGroup(id: "category-\(category.rawValue)", title: category.displayName,
                                 storeIDs: storeIDs, items: sortedItems)
        }.sorted { lhs, rhs in
            let left = lhs.storeIDs.first, right = rhs.storeIDs.first
            let li = left.flatMap { recency.firstIndex(of: $0) } ?? Int.max
            let ri = right.flatMap { recency.firstIndex(of: $0) } ?? Int.max
            return li == ri ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : li < ri
        }
        let orphaned = byCategory[.none] ?? []
        guard !orphaned.isEmpty else { return categorized }
        return categorized + [AllItemsGroup(id: "uncategorised", title: "Uncategorised", storeIDs: [],
                                             items: orphaned.map(\.1).sorted { $0.position < $1.position })]
    }

    private var composer: some View {
        VStack(spacing: 12) {
            Section {
                HStack {
                    countLabel(pendingCount, title: "Pending", tint: .blue)
                    Spacer()
                    countLabel(addedCount, title: "Added", tint: .blue)
                    Spacer()
                    countLabel(skippedCount, title: "Skipped", tint: .secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            GroupBox("Add products") {
                VStack(spacing: 12) {
                    TextField("Milk, bread, eggs", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .submitLabel(.done)
                        .onSubmit(addItems)
                        .focused($entryFocused)
                        .accessibilityIdentifier("all-items-entry")
                    Divider()
                    HStack(spacing: 8) {
                        Button("Import") { importItems() }
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .accessibilityHint("Import items into the selected destination store")
                        Spacer(minLength: 4)
                        if let destinationID {
                            HStack(spacing: 0) {
                                Button("Add to \(destinationID.displayName)", action: addItems)
                                    .buttonStyle(.plain)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                                    .padding(.leading, 14)
                                    .disabled(IngredientParser.application.parseProductEntry(draft).isEmpty)
                                    .accessibilityIdentifier("all-items-add")
                                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 26)
                                Menu {
                                    ForEach(visibleStores, id: \.id) { store in
                                        Button {
                                            destinationRawValue = store.id.rawValue
                                        } label: {
                                            if store.id == destinationID {
                                                Label(store.displayName, systemImage: "checkmark")
                                            } else {
                                                Text(store.displayName)
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Choose add destination")
                                .accessibilityValue(destinationID.displayName)
                                .accessibilityIdentifier("all-items-add-destination")
                            }
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                        } else {
                            Menu {
                                if visibleStores.isEmpty {
                                    Button("Manage Stores") { showingStoreManagement = true }
                                } else {
                                    ForEach(visibleStores, id: \.id) { store in
                                        Button(store.displayName) { destinationRawValue = store.id.rawValue }
                                    }
                                }
                            } label: {
                                Label("Choose Store", systemImage: "chevron.down")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Picker("Group items", selection: $groupingRawValue) {
                    Text("By store").tag(AllItemsGrouping.store.rawValue)
                    Text("By category").tag(AllItemsGrouping.category.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("all-items-grouping")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    var body: some View {
        VStack(spacing: 0) {
        composer
        List {
            if groups.isEmpty {
                ContentUnavailableView("Your lists are empty", systemImage: "basket",
                                       description: Text("Add products above, or choose a store list."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items, id: \.id) { item in
                            allItemRow(item)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text("\(group.items.count)").foregroundStyle(.secondary)
                        }
                        .foregroundStyle(grouping == .store && !group.storeIDs.isEmpty ? storeTint(group.storeIDs[0]) : .secondary)
                    }
                }
            }
            if let notice {
                Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $showingStoreManagement) {
            StoreVisibilityScreen(sessions: sessions, visibility: visibility,
                onOpenStoreList: { id in
                    showingStoreManagement = false
                    onChooseStoreList(id)
                })
        }
        .confirmationDialog("Delete this item?", isPresented: Binding(
            get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Item", role: .destructive) {
                guard let itemToDelete else { return }
                delete(itemToDelete)
                self.itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("This removes the row from its ListRunner store list only. It does not change a retailer cart or Apple Reminders.")
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
                saveFailed: false,
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Your list").font(.largeTitle.weight(.bold))
                Spacer(minLength: 8)
                Menu {
                    Label("All items", systemImage: "checkmark")
                    Divider()
                    ForEach(visibleStores, id: \.id) { store in
                        Button(store.displayName) { onChooseStoreList(store.id) }
                    }
                    Divider()
                    Button("Manage Stores") { showingStoreManagement = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("All items").font(.title3.weight(.heavy)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.black))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                }
                .accessibilityIdentifier("all-items-scope-picker")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !allItems.isEmpty {
                Menu {
                    ForEach(visibleStores, id: \.id) { store in
                        Button("Shop at \(store.displayName)") { shoppingDestination = store.id }
                    }
                } label: {
                    Label("Choose Store", systemImage: "cart.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor.opacity(0.28))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .onAppear {
            if destinationRawValue.isEmpty, !visibleStores.isEmpty {
                let previouslyViewed = StoreID(rawValue: UserDefaults.standard.string(forKey: "activeStoreID") ?? "")
                destinationRawValue = previouslyViewed.flatMap { id in
                    visibleStores.contains(where: { $0.id == id }) ? id.rawValue : nil
                } ?? visibleStores[0].id.rawValue
            }
        }
    }

    private func countLabel(_ count: Int, title: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)").font(.title3.weight(.semibold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 68)
        .accessibilityElement(children: .combine)
    }

    private func allItemRow(_ item: GroceryItem) -> some View {
        let owner = StoreID.allCases.first { $0.listID == item.listID }
        return HStack(spacing: 10) {
            Button {
                guard let owner else {
                    notice = "This saved item has no recognized store list. It remains visible and has not been moved or deleted."
                    return
                }
                guard visibility.shoppingVisibleIDs(in: sessions.definitions).contains(owner) else {
                    notice = "This item belongs to the disabled \(owner.displayName) list. It remains visible here; enable that store to open its list."
                    return
                }
                let list = lists.first { $0.id == owner.listID }
                list?.selectedItemID = item.id
                try? modelContext.save()
                shoppingDestination = owner
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text("\(owner?.displayName ?? "Uncategorised") · \(item.displayQuantity)\(owner.map { visibility.shoppingVisibleIDs(in: sessions.definitions).contains($0) ? "" : " · Unavailable" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue)\(owner.map { ", \($0.displayName)" } ?? ", Uncategorised")")
            Spacer(minLength: 4)
            Text(item.status.rawValue)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(statusTint(item.status).opacity(0.14), in: Capsule())
                .foregroundStyle(statusTint(item.status))
            Menu {
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
                Button("Delete Item", systemImage: "trash", role: .destructive) { itemToDelete = item }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Actions for \(item.name)")
        }
        .frame(minHeight: 48)
        .accessibilityIdentifier("all-item-\(item.id.uuidString)")
    }

    private func setStatus(_ status: GroceryStatus, for item: GroceryItem) {
        item.status = status
        stageReminderWriteback(for: item)
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

    private func stageReminderWriteback(for item: GroceryItem) {
        guard !removeRemindersAfterImport else { return }
        if let write = paprikaReminders.desiredWriteback(for: item) { pendingReminderWrites[item.id] = write }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            let writes = Array(pendingReminderWrites.values)
            pendingReminderWrites.removeAll()
            for write in writes { paprikaReminders.queueWriteback(write) }
            return true
        } catch {
            notice = "Changes may not be saved. Try again."
            return false
        }
    }

    private func importItems() {
        guard let destinationID else {
            notice = "Choose an enabled store before importing."
            return
        }
        onImportToStore(destinationID)
    }

    private func addItems() {
        guard let destinationID, !IngredientParser.application.parseProductEntry(draft).isEmpty else { return }
        let parsed = IngredientParser.application.parseProductEntry(draft)
        let promoted = ShoppingLists.stageAdd(parsed, to: destinationID, allItems: allItems, context: modelContext)
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
            draft = ""
            entryFocused = true
            notice = "Added \(promoted.count) \(promoted.count == 1 ? "item" : "items") to \(destinationID.displayName)."
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

    private func statusTint(_ status: GroceryStatus) -> Color {
        switch status {
        case .pending: .accentColor
        case .added: .green
        case .skipped: .secondary
        }
    }

    private static func normalizedUnit(_ unit: String?) -> String? {
        unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    let onWelcomeStoreEnabled: (StoreID) -> Void
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
    @GestureState private var isDraggingList = false
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
          onPromoteStore: @escaping (StoreID, [UUID]) -> Void) {
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
        _browser = StateObject(wrappedValue: sessions.browser(for: storeID))
    }

    private var items: [GroceryItem] { allItems.filter { $0.listID == storeID.listID } }
    private var selectedList: GroceryList? { lists.first { $0.id == storeID.listID } }
    private var shoppingVisibleIDs: Set<StoreID> { sessions.shoppingAvailability.visibleIDs(in: visibility.visibleIDs) }
    private var moveDestinations: [StoreDefinition] {
        StoreCatalogue.ordered(sessions.definitions, countryCode: nil).filter { $0.id != storeID }
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
        NavigationStack {
            List {
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
                        Text("Enable a store to see its grocery list.")
                    } actions: {
                        Button("Manage Stores") { showingStoreManagement = true }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("no-stores-manage")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        summary
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

                    Section("Add products") {
                        ProductEntryEditor(text: $rawInput,
                                           isFocused: $groceryInputFocused,
                                           focusControl: productEntryFocus,
                                           onSubmit: addItems)
                            .onChange(of: rawInput) { _, value in
                                // Return can submit and clear the binding before
                                // SwiftUI delivers the preceding typing change.
                                // That obsolete edit must not cancel its reveal.
                                guard value == rawInput else { return }
                                // Multiline paste is parsed in a single edit.
                                // Keyboard Return is intercepted before insertion.
                                if value.contains(where: { $0.isNewline }) {
                                    addItems()
                                 } else if !value.isEmpty {
                                     cancelAddedItemScroll()
                                     scrollTargetItemID = nil
                                     revealFocusedProductEntry()
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .background(storePrimaryColor.opacity(groceryInputFocused ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(storePrimaryColor.opacity(groceryInputFocused ? 1 : 0.7), lineWidth: groceryInputFocused ? 2.5 : 1.5)
                            }
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded { groceryInputFocused = true })
                            .onGeometryChange(for: CGRect?.self) { geometry in
                                groceryInputFocused ? geometry.frame(in: .global) : nil
                             } action: { frame in
                                 guard let frame else { return }
                                 let heightChanged = abs(groceryInputFrame.height - frame.height) > 0.5
                                 groceryInputFrame = frame
                                 if heightChanged { revealFocusedProductEntry() }
                            }
                            .padding(.vertical, 4)

                        HStack {
                            Button {
                                groceryInputFocused = false
                                if GroceryImportSource(rawValue: importSourceID) == .paprika {
                                    importPaprika()
                                } else {
                                    showingImportSetup = true
                                }
                            } label: {
                                Label(paprikaReminders.importing ? "Importing…" :
                                        GroceryImportSource(rawValue: importSourceID) == .paprika ? "Import from Paprika" : "Import items...",
                                      systemImage: paprikaReminders.importing ? "hourglass" : "checklist")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .disabled(paprikaReminders.importing)
                            .accessibilityIdentifier(GroceryImportSource(rawValue: importSourceID) == .paprika ? "import-from-paprika" : "set-import-source")
                            .accessibilityHint(GroceryImportSource(rawValue: importSourceID) == .paprika ?
                                (removeRemindersAfterImport ? "Imports unchecked Paprika reminders and removes them after saving groceries" : "Imports unchecked Paprika reminders and keeps them linked") : "Choose your grocery import source")

                            Spacer(minLength: 8)

                            Button("Add Items") {
                                addItems(keepingInputFocused: true)
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(IngredientParser.application.parseProductEntry(rawInput).isEmpty)
                                .onGeometryChange(for: CGRect?.self) { geometry in
                                    groceryInputFocused ? geometry.frame(in: .global) : nil
                                } action: { frame in
                                    guard let frame else { return }
                                    addItemsButtonFrame = frame
                                }
                        }
                        .padding(.vertical, 4)
                        .id("product-entry-actions")
                        .onGeometryChange(for: CGRect?.self) { geometry in
                            groceryInputFocused ? geometry.frame(in: .global) : nil
                        } action: { frame in
                            guard let frame else { return }
                            productActionsFrame = frame
                        }
                        // Trim List's default 15 pt vertical insets without
                        // shrinking the import action's 44 pt hit area.
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }

                    Section {
                        if items.isEmpty {
                            ContentUnavailableView("Your list is empty", systemImage: "basket",
                                                   description: Text("Add products above, then shop though them with ListRunner"))
                                .padding(.vertical, 12)
                        } else {
                            groceryList(using: scrollProxy)
                            Button(action: clearList) {
                                HStack(spacing: 8) {
                                    Spacer(minLength: 0)
                                    Label("Clear List", systemImage: "trash")
                                    Spacer(minLength: 0)
                                }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
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
                        if !items.isEmpty { Text("Groceries") }
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
            }
            .onDisappear {
                groceryInputFocused = false
                isListScreenVisible = false
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(isRevealingProductEntry ? .never : .interactively)
            .simultaneousGesture(DragGesture(minimumDistance: 10).updating($isDraggingList) { _, dragging, _ in
                if !dragging { dragging = true }
            })
            .onChange(of: isDraggingList) { _, dragging in
                guard dragging else { return }
                // A deliberate manual scroll takes precedence over positioning
                // the most recently submitted item. Cancel once at drag start,
                // not on every finger movement; GestureState also resets on cancel.
                cancelAddedItemScroll()
                productEntryRevealTask?.cancel()
                scrollTargetItemID = nil
                itemFrames.removeAll(keepingCapacity: true)
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                // The surrounding safeAreaInsets already reduce this layout
                // frame for the header, Show Store and keyboard. Subtracting
                // geometry.safeAreaInsets again can produce a zero-height area.
                geometry.frame(in: .global)
            } action: { frame in
                listViewportFrame = frame
                revealFocusedProductEntry()
                // The first item also introduces the bottom action inset. Scroll
                // against the resulting viewport, not the old empty-list size.
                guard let itemID = scrollTargetItemID else { return }
                scrollToAddedItem(itemID, using: scrollProxy)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center) {
                    Text(showingStoreWelcome ? "ListRunner" : "Your list")
                        .font(showingStoreWelcome ? .title3.weight(.bold) : .largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !showingStoreWelcome && !shoppingVisibleIDs.isEmpty {
                        Menu {
                            Button {
                                onSelectAllItems()
                            } label: {
                                Label("All items", systemImage: "square.grid.2x2")
                            }
                            Divider()
                            ForEach(StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                                                            enabledIDs: shoppingVisibleIDs), id: \.id) { store in
                                Button(store.displayName) { onSelectStore(store.id) }
                            }
                            Divider()
                            Button("Manage Stores") { showingStoreManagement = true }
                                .accessibilityIdentifier("store-picker-manage-stores")
                        } label: {
                            HStack(spacing: 6) {
                                Text(storeID.displayName)
                                    .font(.system(.title3, design: .default, weight: .heavy))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.black))
                            }
                            .foregroundStyle(storePrimaryColor)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        }
                        .accessibilityIdentifier("store-picker")
                        .accessibilityHint("Each store has its own grocery list and basket")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !showingStoreWelcome && !shoppingVisibleIDs.isEmpty && !items.isEmpty {
                    Button {
                        presentStore()
                    } label: {
                        Label("Show Store", systemImage: "cart.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .modifier(StoreLaunchButtonStyle(tint: storePrimaryColor))
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .global)
                    } action: { frame in
                        showStoreFrame = frame
                        revealFocusedProductEntry()
                    }
                     .disabled(!browser.canPresentStore || !shoppingVisibleIDs.contains(storeID))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    // Keep the action inside the adjusted safe area so it stays
                    // above the keyboard while the grocery field is focused.
                    .padding(.bottom, groceryInputFocused ? 16 : 0)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Keep the root's layout stable during interactive Back. The pushed
            // screen owns its visible navigation bar, not this presentation flag.
            .toolbar(showingStoreWelcome ? .hidden : .visible, for: .navigationBar)
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
                ToolbarItem(placement: .topBarLeading) {
                    if !showingStoreWelcome && !shoppingVisibleIDs.isEmpty && !items.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !showingStoreWelcome {
                        Button {
                            groceryInputFocused = false
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
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
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.environment["LISTRUNNER_REVEAL_TEST_FIXTURE"] == "enabled" {
                Text(verbatim: "target=\(scrollTargetItemID?.uuidString ?? "none"); trackedRows=\(itemFrames.count); frame=\(scrollTargetItemID.flatMap { itemFrames[$0] }.debugDescription); viewport=\(listViewportFrame); pending=\(addedItemScrollTask != nil); editor=\(groceryInputFrame); actions=\(productActionsFrame); focused=\(groceryInputFocused); entryReveal=\(productEntryRevealStatus)")
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
            SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                guard groceryInputFocused,
                      !groceryInputFrame.contains(value.location),
                      !addItemsButtonFrame.contains(value.location) else { return }
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

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(items.isEmpty ? "Ready when you are" : pendingCount == 0 ? "Complete" : "Ready when you are")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                summaryMetric(count: pendingCount, label: "Pending", color: storePrimaryColor)
                Divider().frame(height: 32)
                summaryMetric(count: addedCount, label: "Added", color: storePrimaryColor)
                Divider().frame(height: 32)
                summaryMetric(count: skippedCount, label: "Skipped", color: .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pendingCount) pending, \(addedCount) added, \(skippedCount) skipped")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryMetric(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(count, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func groceryList(using scrollProxy: ScrollViewProxy) -> some View {
        ForEach(items) { item in
            HStack(spacing: 12) {
                Button {
                    guard browser.canPresentStore, shoppingVisibleIDs.contains(storeID) else { return }
                    selectedList?.selectedItemID = item.id
                    saveChanges()
                    presentStore()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sentenceCase(item.name)).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text("Quantity \(item.displayQuantity)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(item.status.rawValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor(item.status))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(statusColor(item.status).opacity(0.11), in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue). Find in \(storeID.displayName)")

                Menu {
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
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(item.name)")
            }
            .frame(minHeight: 48)
            // Include the entire cell in the scroll identity/geometry. Native
            // List row insets otherwise sit outside the scrollTo target, leaving
            // the cell's bottom padding clipped even after a successful scroll.
            .padding(.vertical, 15)
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
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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

    private func statusColor(_ status: GroceryStatus) -> Color {
        switch status {
        case .pending, .added: storePrimaryColor
        case .skipped: .secondary
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
        let parsed = IngredientParser.application.parseProductEntry(rawInput)
        guard !parsed.isEmpty else { return }
        cancelAddedItemScroll()
        var newlyAddedIDs = Set<UUID>()
        // Do not animate the empty-state replacement and new bottom inset while
        // trying to position the first row. Later additions keep their animation;
        // the first row still gets the added-item highlight and animated scroll.
        withAnimation(items.isEmpty ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            let existingIDs = Set(items.map(\.id))
            let promotedItems = ShoppingLists.stageAdd(parsed, to: storeID, allItems: allItems, context: modelContext)
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
            if !saveFailed { onPromoteStore(storeID, promotedItems.map(\.id)) }
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
        productEntryRevealTask = Task { @MainActor in
            isRevealingProductEntry = true
            defer { isRevealingProductEntry = false }
            // Keyboard layout can arrive in stages. Re-measure each time rather
            // than forcing alignment when the complete card already fits.
            for delay in [0.1, 0.3, 0.3] {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard groceryInputFocused, scrollTargetItemID == nil,
                      listViewportFrame.height > 0,
                      groceryInputFrame.height > 0, productActionsFrame.height > 0 else { return }
                // The editor geometry excludes its List row's 15 pt native
                // insets and 4 pt explicit padding. The actions target includes
                // its explicit padding so scrollTo reveals the full native cell.
                let cardTop = groceryInputFrame.minY - 19
                let cardBottom = productActionsFrame.maxY
                // The inset's top spacing is unobscured. A card touching the
                // actual Show Store button already fits and must not move.
                let visibleBottom = items.isEmpty || showStoreFrame.height == 0
                    ? listViewportFrame.maxY : showStoreFrame.minY
                productEntryRevealStatus = "checked bottom=\(cardBottom) visibleBottom=\(visibleBottom)"
                guard cardBottom - cardTop <= visibleBottom - listViewportFrame.minY else { continue }
                let adjustment: CGFloat
                if cardBottom > visibleBottom + 0.5 {
                    adjustment = cardBottom - visibleBottom
                } else if cardTop < listViewportFrame.minY - 0.5 {
                    adjustment = cardTop - listViewportFrame.minY
                } else { continue }
                // Static List cells do not reliably register with scrollTo.
                // Move only the measured clipping distance in the editor's own
                // enclosing list, retaining its responder and compact geometry.
                productEntryRevealStatus = "scroll adjustment=\(adjustment)"
                productEntryFocus.adjustListOffset(by: adjustment)
            }
        }
    }

    private func scrollToAddedItem(_ itemID: UUID, using proxy: ScrollViewProxy, animated: Bool = true) {
        // Geometry, query and onAppear callbacks can arrive in the same layout
        // pass. Coalesce them instead of repeatedly cancelling the queued scroll.
        guard !isAddedItemFullyVisible(itemID) else { return }
        guard addedItemScrollTask == nil else { return }
        let requestID = UUID()
        addedItemScrollRequestID = requestID
        addedItemScrollTask = Task { @MainActor in
            defer {
                if addedItemScrollRequestID == requestID {
                    addedItemScrollTask = nil
                }
            }
            // The insertion spring and UITextView's Return handling can both
            // restore the content offset after the initial geometry callback.
            // Wait past the insertion, then recheck after the reveal animation.
            // Keep the request alive even when an intermediate frame fits.
            for (index, delay) in [0.5, 0.4, 0.2].enumerated() {
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                guard scrollTargetItemID == itemID,
                      items.contains(where: { $0.id == itemID }) else { return }
                guard let target = itemFrames[itemID],
                      listViewportFrame.height > 0,
                      !isAddedItemFullyVisible(itemID) else { continue }
                // Explicit edge alignment respects List's safe-area insets.
                // Only request it for a measured, clipped row; a visible row
                // never gets repositioned just because it was inserted.
                let anchor: UnitPoint = target.maxY > listViewportFrame.maxY ? .bottom : .top
                withAnimation(animated && index == 0 ? .easeInOut(duration: 0.35) : nil) {
                    proxy.scrollTo(itemID, anchor: anchor)
                }
            }
        }
    }

    private func isAddedItemFullyVisible(_ itemID: UUID) -> Bool {
        guard let target = itemFrames[itemID],
              listViewportFrame.height > 0 else { return false }
        // Subpixel rounding must not keep requesting the same scroll forever.
        return target.minY >= listViewportFrame.minY - 0.5
            && target.maxY <= listViewportFrame.maxY + 0.5
    }

    private func cancelAddedItemScroll() {
        guard addedItemScrollTask != nil else { return }
        addedItemScrollTask?.cancel()
        addedItemScrollTask = nil
        addedItemScrollRequestID = UUID()
    }

    private static func normalizedUnit(_ unit: String?) -> String { unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }

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
              sessions.definitions.first(where: { $0.id == destination })?.isAvailableForShopping == true else { return }
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
                do {
                    try modelContext.transaction {
                        var position = (items.map(\.position).max() ?? -1) + 1
                        for entry in staged {
                            let item = GroceryItem(name: entry.grocery.name,
                                                   amount: entry.grocery.amount,
                                                   unit: entry.grocery.unit,
                                                   position: position,
                                                   listID: storeID.listID)
                            item.paprikaReminderID = entry.reminderID
                            modelContext.insert(item)
                            importedItemIDs.append(item.id)
                            position += 1
                        }
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
            StoreWelcomeSteps()

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
                Text("You can add more stores later.")
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
            Text("Your lists.\nStreamlined.")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Bring your shopping lists to your favourite stores’ websites and work through them with ListRunner.")
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

private struct StoreWelcomeSteps: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                StoreWelcomeStep(number: 1, title: "Choose a store")
                Image(systemName: "chevron.right").accessibilityHidden(true)
                StoreWelcomeStep(number: 2, title: "Add your list")
                Image(systemName: "chevron.right").accessibilityHidden(true)
                StoreWelcomeStep(number: 3, title: "Shop")
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 10) {
                StoreWelcomeStep(number: 1, title: "Choose a store")
                StoreWelcomeStep(number: 2, title: "Add your list")
                StoreWelcomeStep(number: 3, title: "Shop")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoreWelcomeStep: View {
    let number: Int
    let title: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(number, format: .number)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

// Weak, editor-scoped access for explicit presentation actions. Never resign
// another scene's first responder through a global UIApplication action.
@MainActor
private final class ProductEntryFocus {
    weak var view: UITextView?

    func resignFirstResponder() {
        if let view, view.isFirstResponder { view.resignFirstResponder() }
    }

    func adjustListOffset(by adjustment: CGFloat) {
        guard let view, view.isFirstResponder else { return }
        var ancestor = view.superview
        while let candidate = ancestor {
            if let list = candidate as? UICollectionView {
                guard !list.isDragging, !list.isDecelerating else { return }
                let minimum = -list.adjustedContentInset.top
                let maximum = max(minimum, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
                let offset = min(maximum, max(minimum, list.contentOffset.y + adjustment))
                list.setContentOffset(CGPoint(x: list.contentOffset.x, y: offset), animated: true)
                return
            }
            ancestor = candidate.superview
        }
    }
}

// A vertical SwiftUI TextField inserts Return before onSubmit/onChange. Use the
// native editing delegate to reject that edit before UIKit lays out a new line.
private struct ProductEntryEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let focusControl: ProductEntryFocus
    let onSubmit: () -> Void

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
        view.accessibilityIdentifier = "grocery-input"
        view.accessibilityLabel = String(localized: "Type or paste groceries")
        view.placeholder.text = String(localized: "Tap to add products…")
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: EntryTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
            view.invalidateIntrinsicContentSize()
        }
        view.updatePlaceholder()
        context.coordinator.synchronizeFocus(for: view)
    }

    static func dismantleUIView(_ view: EntryTextView, coordinator: Coordinator) {
        coordinator.isDismantled = true
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
        init(parent: ProductEntryEditor) { self.parent = parent }

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
                guard !self.isDismantled, let view, view.window != nil else { return }
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
            if !parent.isFocused { parent.isFocused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }
    }

    final class EntryTextView: UITextView {
        let placeholder = UILabel()
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
