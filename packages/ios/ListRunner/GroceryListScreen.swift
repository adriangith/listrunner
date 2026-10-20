import SwiftData
import SwiftUI

struct GroceryListScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryItem.position) private var items: [GroceryItem]
    @StateObject private var browser = ColesBrowser()
    @AppStorage("lastOverlaySelectedItemID") private var lastSelectedItemID = ""
    @State private var rawInput = ""
    @State private var editingItem: GroceryItem?
    @State private var showingStore = false
    @State private var showingClearConfirmation = false
    @State private var notice: String?

    private var pendingCount: Int { items.filter { $0.status == .pending }.count }
    private var addedCount: Int { items.filter { $0.status == .added }.count }
    private var skippedCount: Int { items.filter { $0.status == .skipped }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summary
                        if let notice { messageBanner(notice) }
                        entryCard
                        if items.isEmpty {
                            ContentUnavailableView("Your list is empty", systemImage: "basket",
                                                   description: Text("Add groceries here, then shop through them with ListRunner."))
                                .padding(.vertical, 12)
                        } else {
                            groceryList
                            Button("Clear List", role: .destructive) { clearList() }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }

                if !items.isEmpty {
                    Button {
                        showingStore = true
                    } label: {
                        Label("Show Store", systemImage: "cart.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.listRunnerGreen)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Your list")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { notice = "Settings and session controls are being built next." } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingStore) {
                StoreShoppingView(items: items, browser: browser, initialSelectedID: UUID(uuidString: lastSelectedItemID), onSelectionChange: { id in
                    lastSelectedItemID = id.uuidString
                }, onStatusChange: saveChanges)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(item: item) { name, amount, unit in
                    item.name = name
                    item.searchTerm = name
                    item.quantityAmount = amount
                    item.quantityUnit = amount == nil ? nil : unit
                    item.status = .pending
                    saveChanges()
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Clear your list?", isPresented: $showingClearConfirmation,
                                titleVisibility: .visible) {
                Button("Clear List", role: .destructive) { deleteAllItems() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the list from ListRunner. It does not change Coles or Apple Reminders.")
            }
        }
        .tint(Color.listRunnerGreen)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(items.isEmpty ? "Ready when you are" : pendingCount == 0 ? "Complete" : "Ready when you are")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                countPill("\(pendingCount) Pending", color: .listRunnerGreen)
                countPill("\(addedCount) Added", color: .green)
                countPill("\(skippedCount) Skipped", color: .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pendingCount) pending, \(addedCount) added, \(skippedCount) skipped")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.1), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add grocery items").font(.subheadline.weight(.semibold))
            TextField("Milk, bread, eggs", text: $rawInput, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Type or paste groceries")
            HStack {
                Button {
                    notice = "Paprika import will be added in a later implementation step."
                } label: {
                    Label("Import from Paprika", systemImage: "checklist")
                }
                .font(.footnote.weight(.semibold))
                .accessibilityHint("Apple Reminders import is not available yet")
                Spacer(minLength: 8)
                Button("Add Items", action: addItems)
                    .buttonStyle(.borderedProminent)
                    .disabled(GroceryParser.parse(rawInput).isEmpty)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var groceryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GROCERIES").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Text("Edit items").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                    HStack(spacing: 12) {
                        Button {
                            lastSelectedItemID = item.id.uuidString
                            showingStore = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.name), quantity \(item.displayQuantity), \(item.status.rawValue). Find in Coles")
                        .accessibilityHint("Opens Coles and selects this item")

                        Menu {
                            Button("Edit Item", systemImage: "pencil") { editingItem = item }
                            Button("Delete Item", systemImage: "trash", role: .destructive) { delete(item) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Actions for \(item.name)")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .frame(minHeight: 60)
                    if index < items.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Text("Tap an item to edit it. Show Store opens Coles.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 4)
            Button("Dismiss") { notice = nil }.frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Dismiss notice")
        }
        .padding(.leading, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func statusColor(_ status: GroceryStatus) -> Color {
        switch status {
        case .pending: Color.listRunnerGreen
        case .added: .green
        case .skipped: .secondary
        }
    }

    private func addItems() {
        let parsed = GroceryParser.parse(rawInput)
        guard !parsed.isEmpty else { return }
        var stagedItems = items
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
            } else {
                let item = GroceryItem(name: entry.name, amount: entry.amount, unit: entry.unit, position: stagedItems.count)
                modelContext.insert(item)
                stagedItems.append(item)
            }
        }
        rawInput = ""
        saveChanges()
    }

    private static func normalizedUnit(_ unit: String?) -> String { unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }

    private func delete(_ item: GroceryItem) {
        modelContext.delete(item)
        normalizePositions()
        saveChanges()
    }

    private func clearList() {
        if pendingCount > 0 { showingClearConfirmation = true }
        else { deleteAllItems() }
    }

    private func deleteAllItems() {
        for item in items { modelContext.delete(item) }
        notice = nil
        saveChanges()
    }

    private func normalizePositions() {
        for (index, item) in items.enumerated() { item.position = index }
    }

    private func saveChanges() {
        do { try modelContext.save() }
        catch { notice = "Changes may not be saved" }
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
                    Text("Saving changes marks this item Pending. Quantity is guidance only and does not change Coles.")
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

private extension Color {
    static let listRunnerGreen = Color(red: 0.10, green: 0.52, blue: 0.37)
}
