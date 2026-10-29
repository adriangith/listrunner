import SwiftData
import SwiftUI

struct ShoppingRootScreen: View {
    @StateObject private var sessions: StoreSessions
    @StateObject private var visibility: StoreVisibilityPreferences
    @StateObject private var paprikaReminders = PaprikaReminders()
    @AppStorage("activeStoreID") private var activeStoreID = StoreID.coles.rawValue
    @State private var drafts: [StoreID: String] = [:]

    init(diagnostics: DiagnosticStore) {
        let preferences = StoreVisibilityPreferences()
        _visibility = StateObject(wrappedValue: preferences)
        _sessions = StateObject(wrappedValue: StoreSessions(diagnostics: diagnostics, preferences: preferences))
    }

    var body: some View {
        let storeID = StoreID(rawValue: activeStoreID) ?? .coles
        GroceryListScreen(storeID: storeID, sessions: sessions, visibility: visibility, paprikaReminders: paprikaReminders,
                           rawInput: Binding(get: { drafts[storeID] ?? "" }, set: { drafts[storeID] = $0 }),
                           onSelectStore: { id in
                              sessions.endAllInteractions()
                              activeStoreID = id.rawValue
                          })
            .id(storeID)
    }
}

struct GroceryListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \GroceryItem.position) private var allItems: [GroceryItem]
    @Query private var lists: [GroceryList]
    @StateObject private var browser: StoreBrowser
    @ObservedObject var visibility: StoreVisibilityPreferences
    @ObservedObject var paprikaReminders: PaprikaReminders
    let storeID: StoreID
    let sessions: StoreSessions
    let onSelectStore: (StoreID) -> Void
    @Binding private var rawInput: String
    @State private var routedLaunch = false
    @State private var itemToMove: GroceryItem?
    @State private var editingItem: GroceryItem?
    @State private var showingStore = false
    @State private var showingStoreManagement = false
    @State private var showingClearConfirmation = false
    @State private var notice: String?
    @State private var saveFailed = false
    @State private var pendingReminderWrites: [UUID: ReminderWriteback] = [:]
    @FocusState private var groceryInputFocused: Bool
    @State private var recentlyAddedItemIDs = Set<UUID>()
    @State private var scrollTargetItemID: UUID?
    @State private var addedItemScrollTask: Task<Void, Never>?
    @State private var listViewportFrame: CGRect = .zero

    init(storeID: StoreID, sessions: StoreSessions, visibility: StoreVisibilityPreferences, paprikaReminders: PaprikaReminders, rawInput: Binding<String>,
         onSelectStore: @escaping (StoreID) -> Void) {
        self.storeID = storeID; self.sessions = sessions
        self.visibility = visibility
        self.paprikaReminders = paprikaReminders
        self.onSelectStore = onSelectStore; self._rawInput = rawInput
        _browser = StateObject(wrappedValue: sessions.browser(for: storeID))
    }

    private var items: [GroceryItem] { allItems.filter { $0.listID == storeID.listID } }
    private var selectedList: GroceryList? { lists.first { $0.id == storeID.listID } }

    private var pendingCount: Int { items.filter { $0.status == .pending }.count }
    private var addedCount: Int { items.filter { $0.status == .added }.count }
    private var skippedCount: Int { items.filter { $0.status == .skipped }.count }
    // The storefront configuration is the single source of truth for the
    // selected store's visual identity, including all list-screen accents.
    private var storePrimaryColor: Color {
        guard !visibility.visibleIDs.isEmpty else { return .primary }
        let color = browser.store.brandColors?.primary ?? browser.store.addedColor
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }
    private var storeHighlightColor: Color {
        guard !visibility.visibleIDs.isEmpty else { return .primary }
        guard let color = browser.store.brandColors?.highlight else { return storePrimaryColor }
        return Color(red: Double(color.red) / 255,
                     green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        NavigationStack {
            List {
                if visibility.visibleIDs.isEmpty {
                    ContentUnavailableView {
                        Label("No stores enabled", systemImage: "basket")
                    } description: {
                        Text("Enable a store to see its grocery list. Your saved lists and logins are kept.")
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
                        if let notice { messageBanner(notice) }
                        if saveFailed { PersistenceWarning() }
                        if browser.cartUndoWarning {
                            CartUndoWarning(storeName: storeID.displayName) { browser.dismissCartUndoWarning() }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

                    Section("Add grocery items") {
                        TextField("Milk, bread, eggs", text: $rawInput, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($groceryInputFocused)
                            .submitLabel(.continue)
                            .onSubmit(addItems)
                            .onChange(of: rawInput) { _, value in
                                // In a vertically-growing TextField, Return can
                                // arrive as a newline rather than a submit event.
                                // Treat that newline as submission; a multiline
                                // paste still enters in one edit and is parsed
                                // into multiple items by IngredientParser.
                                if value.contains(where: { $0.isNewline }) {
                                    addItems()
                                } else if !value.isEmpty {
                                    addedItemScrollTask?.cancel()
                                    scrollTargetItemID = nil
                                }
                            }
                            .accessibilityLabel("Type or paste groceries")
                            .accessibilityIdentifier("grocery-input")

                        HStack {
                            Button(action: importPaprika) {
                                Label(paprikaReminders.importing ? "Importing…" : "Import from Paprika",
                                      systemImage: paprikaReminders.importing ? "hourglass" : "checklist")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .disabled(paprikaReminders.importing)
                            .accessibilityIdentifier("import-from-paprika")
                            .accessibilityHint("Imports incomplete reminders from the Paprika list in Apple Reminders")

                            Spacer(minLength: 8)

                            Button("Add Items", action: addItems)
                                .buttonStyle(.borderedProminent)
                                .disabled(IngredientParser.application.parseGroceries(rawInput).isEmpty)
                        }
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
                                Button("Clear List", role: .destructive) { deleteAllItems() }
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
                if let selected = visibility.selectionForList(current: storeID, definitions: sessions.definitions),
                   selected != storeID {
                    onSelectStore(selected)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                // A deliberate manual scroll takes precedence over positioning
                // the most recently submitted item.
                addedItemScrollTask?.cancel()
                scrollTargetItemID = nil
            })
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .global)
                let insets = geometry.safeAreaInsets
                return CGRect(x: frame.minX + insets.leading, y: frame.minY + insets.top,
                              width: max(0, frame.width - insets.leading - insets.trailing),
                              height: max(0, frame.height - insets.top - insets.bottom))
            } action: { frame in
                listViewportFrame = frame
                // The first item also introduces the bottom action inset. Scroll
                // against the resulting viewport, not the old empty-list size.
                guard let itemID = scrollTargetItemID else { return }
                scrollToAddedItem(itemID, using: scrollProxy)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Your list")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !visibility.visibleIDs.isEmpty {
                        Menu {
                            ForEach(StoreCatalogue.ordered(sessions.definitions, countryCode: nil,
                                                           enabledIDs: visibility.visibleIDs), id: \.id) { store in
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
                if !visibility.visibleIDs.isEmpty && !items.isEmpty {
                    Button {
                        showingStore = true
                    } label: {
                        Label("Show Store", systemImage: "cart.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .modifier(StoreLaunchButtonStyle(tint: storePrimaryColor))
                     .disabled(!browser.canPresentStore || !visibility.visibleIDs.contains(storeID))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    // Keep the action inside the adjusted safe area so it stays
                    // above the keyboard while the grocery field is focused.
                    .padding(.bottom, groceryInputFocused ? 16 : 0)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingStoreManagement) {
                StoreVisibilityScreen(sessions: sessions, visibility: visibility)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !visibility.visibleIDs.isEmpty && !items.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                         SettingsOverviewScreen(sessions: sessions, visibility: visibility)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
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
                    ForEach(StoreID.allCases.filter { $0 != storeID }) { destination in
                        Button("Move to \(destination.displayName)") { moveItem(item, to: destination); itemToMove = nil }
                    }
                }
                Button("Cancel", role: .cancel) { itemToMove = nil }
            } message: {
                Text("The item moves to the other list as Pending. Neither store basket is changed. Existing items in the other list are not merged.")
            }
        }
        .tint(storePrimaryColor)
        .onAppear {
            guard !routedLaunch else { return }
            routedLaunch = true
            let today = Self.localDay()
            selectedList?.lastActiveDay = today
            saveChanges()
        }
        .onChange(of: visibility.visibleIDs) { _, visibleIDs in
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
        .onChange(of: items.map(\.id)) { _, itemIDs in
            // When adding the first row, SwiftUI replaces the empty-state row
            // and may not have registered the new row when the target changes.
            // Retry after the query reflects the inserted row.
            guard let itemID = scrollTargetItemID, itemIDs.contains(itemID) else { return }
            scrollToAddedItem(itemID, using: scrollProxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            // Return can briefly change the field's focus while UIKit keeps the
            // keyboard open. Only retire the target on an actual dismissal.
            addedItemScrollTask?.cancel()
            scrollTargetItemID = nil
        }
        .onDisappear {
            addedItemScrollTask?.cancel()
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
                    guard browser.canPresentStore, visibility.visibleIDs.contains(storeID) else { return }
                    selectedList?.selectedItemID = item.id
                    saveChanges()
                    showingStore = true
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
            .id(item.id)
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .global)
            } action: { frame in
                guard scrollTargetItemID == item.id, listViewportFrame.height > 0,
                      frame.maxY > listViewportFrame.maxY - 16 else { return }
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
        }
        .onMove(perform: moveItems)
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Button("Dismiss") { notice = nil }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dismiss notice")
        }
    }

    private func statusColor(_ status: GroceryStatus) -> Color {
        switch status {
        case .pending, .added: storePrimaryColor
        case .skipped: .secondary
        }
    }

    private func addItems() {
        let parsed = IngredientParser.application.parseGroceries(rawInput)
        guard !parsed.isEmpty else { return }
        var newlyAddedIDs = Set<UUID>()
        // Do not animate the empty-state replacement and new bottom inset while
        // trying to position the first row. Later additions keep their animation;
        // the first row still gets the added-item highlight and animated scroll.
        withAnimation(items.isEmpty ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            var stagedItems = items
            var promotedItems: [GroceryItem] = []
            for entry in parsed {
                if let existing = stagedItems.first(where: {
                    let sameName = GroceryParser.normalizedName($0.name) == GroceryParser.normalizedName(entry.name)
                    let sameUnit = Self.normalizedUnit($0.quantityUnit) == Self.normalizedUnit(entry.unit)
                    let oneUnspecified = $0.quantityAmount == nil || entry.amount == nil
                    return sameName && (sameUnit || oneUnspecified)
                }) {
                    switch (existing.quantityAmount, entry.amount) {
                    case let (old?, new?): existing.quantityAmount = old + new
                    case (nil, let new?): existing.quantityAmount = new
                    default: break
                    }
                    existing.status = .pending
                    if !promotedItems.contains(where: { $0.id == existing.id }) {
                        promotedItems.append(existing)
                    }
                    stageReminderWriteback(for: existing)
                } else {
                    let item = GroceryItem(name: entry.name, amount: entry.amount, unit: entry.unit, position: stagedItems.count, listID: storeID.listID)
                    modelContext.insert(item)
                    stagedItems.append(item)
                    promotedItems.append(item)
                    newlyAddedIDs.insert(item.id)
                }
            }
            // New and reactivated items go to the front in the same order they
            // appeared in the input. Existing untouched items retain their order.
            let promotedIDs = Set(promotedItems.map(\.id))
            let reorderedItems = promotedItems + stagedItems.filter { !promotedIDs.contains($0.id) }
            for (position, item) in reorderedItems.enumerated() {
                item.position = position
            }
            recentlyAddedItemIDs.formUnion(newlyAddedIDs)
            scrollTargetItemID = promotedItems.first?.id
            rawInput = ""
            groceryInputFocused = true
            saveChanges()
        }

        guard !newlyAddedIDs.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            withAnimation(.easeOut(duration: 0.45)) {
                recentlyAddedItemIDs.subtract(newlyAddedIDs)
            }
        }
    }

    private func scrollToAddedItem(_ itemID: UUID, using proxy: ScrollViewProxy, animated: Bool = true) {
        addedItemScrollTask?.cancel()
        addedItemScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, scrollTargetItemID == itemID,
                  items.contains(where: { $0.id == itemID }) else { return }
            withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
                proxy.scrollTo(itemID, anchor: .bottom)
            }
        }
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
        if pendingCount > 0 { showingClearConfirmation = true }
        else { deleteAllItems() }
    }

    private func deleteAllItems() {
        for item in items { paprikaReminders.cancelQueuedWriteback(for: item) }
        pendingReminderWrites.removeAll()
        for item in items { modelContext.delete(item) }
        notice = nil
        selectedList?.selectedItemID = nil
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
        guard item.listID == storeID.listID, destination != storeID else { return }
        if selectedList?.selectedItemID == item.id {
            selectedList?.selectedItemID = ShoppingLists.selection(afterRemoving: item.id, from: items)
        }
        browser.endInteraction()
        ShoppingLists.move(item, to: destination, allItems: allItems)
        stageReminderWriteback(for: item)
        saveChanges()
    }

    private func stageReminderWriteback(for item: GroceryItem) {
        if let write = paprikaReminders.desiredWriteback(for: item) {
            pendingReminderWrites[item.id] = write
        }
    }

    private func importPaprika() {
        guard !paprikaReminders.importing else { return }
        notice = nil
        Task { @MainActor in
            do {
                // Keep the import transaction isolated from any earlier failed
                // save. The existing local list must be durable before staging
                // a second, all-or-nothing transaction.
                saveChanges()
                guard !saveFailed else { throw PaprikaImportError.transaction }
                let snapshot = try await paprikaReminders.fetchPaprikaSnapshot()
                let linkedIDs = Set(items.compactMap(\.paprikaReminderID))
                let staged = PaprikaImportPlanner.stage(reminders: snapshot, existingIDs: linkedIDs)
                guard !staged.isEmpty else { throw PaprikaImportError.noNewItems }

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
                            position += 1
                        }
                    }
                    saveFailed = false
                } catch {
                    modelContext.rollback()
                    throw PaprikaImportError.transaction
                }
                // Successful imports are shown in the list without a toast.
            } catch let error as PaprikaImportError {
                switch error {
                case .access: notice = "Could not access Paprika reminders"
                case .listNotFound: notice = "Paprika list not found"
                case .multipleLists: notice = "Multiple Paprika lists found"
                case .noNewItems: notice = "No new Paprika items"
                case .transaction: notice = "Could not import Paprika reminders"
                }
            } catch {
                notice = "Could not import Paprika reminders"
            }
            paprikaReminders.finishImport()
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
