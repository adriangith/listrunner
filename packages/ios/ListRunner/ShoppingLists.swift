import Foundation
import SwiftData

// Sidecar preference metadata uses immutable item UUIDs; existing SwiftData
// records and their migration contract remain untouched. Unknown historical
// rows have no fabricated addition time and use their deterministic list order.
enum ItemPromotionOrder {
    static func ranks(_ rawValue: String) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for part in rawValue.split(separator: ",") {
            guard let id = UUID(uuidString: String(part)), result[id] == nil else { continue }
            result[id] = result.count
        }
        return result
    }

    static func promoting(_ ids: [UUID], in rawValue: String, existing: Set<UUID>) -> String {
        var seen = Set<UUID>()
        let previous = ranks(rawValue).sorted { $0.value < $1.value }.map(\.key)
        return (ids + previous).filter { existing.contains($0) && seen.insert($0).inserted }
            .map(\.uuidString).joined(separator: ",")
    }
}

@Model
final class GroceryList {
    @Attribute(.unique) var id: UUID
    var storeID: String
    var selectedItemID: UUID?
    var lastActiveDay: String?

    init(store: StoreID) {
        id = store.listID
        storeID = store.rawValue
    }
}

// Matches the previously shipped, unversioned GroceryItem entity exactly.
enum ShoppingSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [GroceryItem.self] }
    @Model final class GroceryItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var searchTerm: String
        var quantityAmount: Double?
        var quantityUnit: String?
        var statusRawValue: String
        var position: Int

        init(id: UUID = UUID(), name: String, amount: Double? = nil, unit: String? = nil, status: String = "Pending", position: Int = 0) {
            self.id = id; self.name = name; searchTerm = name
            quantityAmount = amount; quantityUnit = unit; statusRawValue = status; self.position = position
        }
    }
}

enum ShoppingSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [GroceryItem.self, GroceryList.self] }

    // Preserve the exact multi-store schema shipped before Paprika linkage.
    @Model final class GroceryItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var searchTerm: String
        var quantityAmount: Double?
        var quantityUnit: String?
        var statusRawValue: String
        var position: Int
        var listID: UUID?

        init(id: UUID = UUID(), name: String, searchTerm: String, quantityAmount: Double? = nil,
             quantityUnit: String? = nil, statusRawValue: String = "Pending", position: Int, listID: UUID? = nil) {
            self.id = id; self.name = name; self.searchTerm = searchTerm
            self.quantityAmount = quantityAmount; self.quantityUnit = quantityUnit
            self.statusRawValue = statusRawValue; self.position = position; self.listID = listID
        }
    }

    @Model final class GroceryList {
        @Attribute(.unique) var id: UUID
        var storeID: String
        var selectedItemID: UUID?
        var lastActiveDay: String?

        init(id: UUID, storeID: String, selectedItemID: UUID? = nil, lastActiveDay: String? = nil) {
            self.id = id; self.storeID = storeID; self.selectedItemID = selectedItemID; self.lastActiveDay = lastActiveDay
        }
    }
}

enum ShoppingSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [GroceryItem.self, GroceryList.self] }
}

enum ShoppingMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ShoppingSchemaV1.self, ShoppingSchemaV2.self, ShoppingSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: ShoppingSchemaV1.self, toVersion: ShoppingSchemaV2.self),
            .lightweight(fromVersion: ShoppingSchemaV2.self, toVersion: ShoppingSchemaV3.self)
        ]
    }
}

enum ShoppingLists {
    static var schema: Schema { Schema(versionedSchema: ShoppingSchemaV3.self) }

    @MainActor
    static func stageAdd(_ entries: [ParsedGrocery], to store: StoreID,
                         allItems: [GroceryItem], context: ModelContext) -> [GroceryItem] {
        var staged = allItems.filter { $0.listID == store.listID }.sorted {
            $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position
        }
        var promoted: [GroceryItem] = []
        func unit(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }
        for entry in entries {
            if let existing = staged.first(where: {
                GroceryParser.normalizedName($0.name) == GroceryParser.normalizedName(entry.name)
                    && (unit($0.quantityUnit) == unit(entry.unit) || $0.quantityAmount == nil || entry.amount == nil)
            }) {
                if let amount = entry.amount {
                    if existing.quantityAmount == nil { existing.quantityUnit = entry.unit }
                    existing.quantityAmount = (existing.quantityAmount ?? 0) + amount
                }
                existing.status = .pending
                if !promoted.contains(where: { $0.id == existing.id }) { promoted.append(existing) }
            } else {
                let item = GroceryItem(name: entry.name, amount: entry.amount, unit: entry.unit,
                                       position: staged.count, listID: store.listID)
                context.insert(item)
                staged.append(item)
                promoted.append(item)
            }
        }
        let ids = Set(promoted.map(\.id))
        for (index, item) in (promoted + staged.filter { !ids.contains($0.id) }).enumerated() { item.position = index }
        return promoted
    }

    static func open(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: ShoppingMigration.self, configurations: configuration)
    }

    @MainActor
    static func prepare(_ context: ModelContext, legacySelectedID: UUID?) throws {
        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        var byID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        for store in StoreID.allCases where byID[store.listID] == nil {
            let list = GroceryList(store: store)
            context.insert(list)
            byID[list.id] = list
        }
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        for item in items where item.listID == nil { item.listID = StoreID.coles.listID }
        if let legacySelectedID, byID[StoreID.coles.listID]?.selectedItemID == nil,
           items.contains(where: { $0.id == legacySelectedID && $0.listID == StoreID.coles.listID }) {
            byID[StoreID.coles.listID]?.selectedItemID = legacySelectedID
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    static func selection(afterRemoving id: UUID, from ordered: [GroceryItem]) -> UUID? {
        let index = ordered.firstIndex { $0.id == id } ?? -1
        let remaining = ordered.filter { $0.id != id }
        return ordered.dropFirst(max(0, index + 1)).first { $0.id != id && $0.status == .pending }?.id ??
            remaining.first { $0.status == .pending }?.id ??
            ordered.dropFirst(max(0, index + 1)).first { $0.id != id }?.id ?? remaining.last?.id
    }

    @MainActor
    static func move(_ item: GroceryItem, to destination: StoreID, allItems: [GroceryItem]) {
        // Moving an existing row is deliberately not an implicit merge or cart action.
        // Typed/pasted duplicates still merge only within the selected list.
        item.listID = destination.listID
        item.position = (allItems.filter { $0.listID == destination.listID && $0.id != item.id }.map(\.position).max() ?? -1) + 1
        item.status = .pending
    }
}
