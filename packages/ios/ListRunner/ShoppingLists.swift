import Foundation
import SwiftData

enum ShoppingListNavigationPolicy {
    static func offersAllItems(enabledStoreIDs: Set<StoreID>, inboxEnabled: Bool = false, itemListIDs: [UUID?]) -> Bool {
        // The Inbox is a list: Inbox plus one store needs the overview.
        if enabledStoreIDs.count + (inboxEnabled ? 1 : 0) > 1 { return true }
        var accessibleLists = Set(enabledStoreIDs.map(\.listID))
        if inboxEnabled { accessibleLists.insert(ListOwner.inboxListID) }
        // nil and unrecognised owners are recovery items too. Never hide them
        // just because only one (or no) retailer can currently be shopped.
        return itemListIDs.contains { id in
            guard let id else { return true }
            return !accessibleLists.contains(id)
        }
    }
}

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

    // All items' list recency: the owner that just received items moves first.
    static func promotingList(_ owner: ListOwner, in rawValue: String) -> String {
        var order = rawValue.split(separator: ",")
            .compactMap { ListOwner(rawValue: String($0)) }.filter { $0 != owner }
        order.insert(owner, at: 0)
        return order.map(\.rawValue).joined(separator: ",")
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

    // `storeID` keeps its stored name for schema compatibility; the Inbox
    // record uses the reserved owner value "inbox".
    init(owner: ListOwner) {
        id = owner.listID
        storeID = owner.rawValue
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

// Version 3 froze the single-owner schema that shipped before memberships.
// Its models keep the exact stored shape so already-migrated stores match
// by entity name and fields, then step forward to version 4.
enum ShoppingSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [GroceryItem.self, GroceryList.self] }

    @Model final class GroceryItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var searchTerm: String
        var quantityAmount: Double?
        var quantityUnit: String?
        var statusRawValue: String
        var position: Int
        var listID: UUID?
        var paprikaReminderID: String? = nil

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

// Version 4 adds membership rows (one per item and list, holding that list's
// own position) plus the originating store for website products. Both are
// additive: existing rows upgrade in place without a custom stage. Existing
// items receive their first membership in the idempotent `prepare` backfill,
// keeping every UUID, status, quantity, position and Reminders link.
enum ShoppingSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [GroceryItem.self, GroceryList.self, GroceryMembership.self] }
}

enum ShoppingMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ShoppingSchemaV1.self, ShoppingSchemaV2.self, ShoppingSchemaV3.self, ShoppingSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: ShoppingSchemaV1.self, toVersion: ShoppingSchemaV2.self),
            .lightweight(fromVersion: ShoppingSchemaV2.self, toVersion: ShoppingSchemaV3.self),
            .lightweight(fromVersion: ShoppingSchemaV3.self, toVersion: ShoppingSchemaV4.self)
        ]
    }
}

enum ShoppingLists {
    static var schema: Schema { Schema(versionedSchema: ShoppingSchemaV4.self) }

    // Items on one list, ordered by that list's own positions. Rows written
    // before memberships exist (fixtures, a mid-upgrade writer) fall back to
    // their legacy list and position, so nothing is hidden or lost.
    static func orderedItems(in listID: UUID, from allItems: [GroceryItem]) -> [GroceryItem] {
        allItems.filter { $0.listIDs.contains(listID) }.sorted {
            let left = $0.sortPosition(in: listID), right = $1.sortPosition(in: listID)
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    static func reorderedIDs(_ current: [UUID], moving sources: [UUID], before destination: UUID?) -> [UUID]? {
        let moving = Set(sources)
        guard !moving.isEmpty, moving.isSubset(of: Set(current)) else { return nil }
        if let destination, !current.contains(destination) || moving.contains(destination) { return nil }
        let picked = current.filter { moving.contains($0) }
        var remaining = current.filter { !moving.contains($0) }
        let index = destination.flatMap { remaining.firstIndex(of: $0) } ?? remaining.endIndex
        remaining.insert(contentsOf: picked, at: index)
        return remaining
    }

    enum AdditionPosition: Equatable, Sendable { case start, end }

    // SwiftData rollback can leave already-held @Model references showing their
    // staged values. Restore those presentation objects too, so a retry cannot
    // add its quantity twice or retain the failed transaction's promoted order.
    struct AdditionSnapshot {
        private struct Row {
            let item: GroceryItem
            let listID: UUID
            let amount: Double?
            let unit: String?
            let status: String
            let position: Int
            let membershipPosition: Int?
        }
        private let rows: [Row]

        init(items: [GroceryItem], store: StoreID) {
            self.init(items: items, owner: .store(store))
        }

        init(items: [GroceryItem], owner: ListOwner) {
            rows = items.filter { $0.listIDs.contains(owner.listID) }.map {
                Row(item: $0, listID: owner.listID, amount: $0.quantityAmount, unit: $0.quantityUnit,
                    status: $0.statusRawValue, position: $0.position,
                    membershipPosition: $0.membership(in: owner.listID)?.position)
            }
        }

        func restoreAfterRollback() {
            for row in rows {
                if row.item.quantityAmount != row.amount { row.item.quantityAmount = row.amount }
                if row.item.quantityUnit != row.unit { row.item.quantityUnit = row.unit }
                if row.item.statusRawValue != row.status { row.item.statusRawValue = row.status }
                if let membershipPosition = row.membershipPosition {
                    row.item.membership(in: row.listID)?.position = membershipPosition
                }
                if row.item.listID == row.listID && row.item.position != row.position {
                    row.item.position = row.position
                }
            }
        }
    }

    @MainActor
    static func stageAdd(_ entries: [ParsedGrocery], to store: StoreID,
                         allItems: [GroceryItem], context: ModelContext,
                         insertion: AdditionPosition = .start) -> [GroceryItem] {
        stageAdd(entries, to: .store(store), allItems: allItems, context: context, insertion: insertion)
    }

    @MainActor
    static func stageAdd(_ entries: [ParsedGrocery], to owner: ListOwner,
                         allItems: [GroceryItem], context: ModelContext,
                         insertion: AdditionPosition = .start) -> [GroceryItem] {
        var staged = orderedItems(in: owner.listID, from: allItems)
        var promoted: [GroceryItem] = []
        func unit(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }
        for entry in entries {
            guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
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
                                       position: staged.count, listID: owner.listID)
                context.insert(item)
                context.insert(GroceryMembership(item: item, listID: owner.listID, position: staged.count))
                staged.append(item)
                promoted.append(item)
            }
        }
        let ids = Set(promoted.map(\.id))
        let untouched = staged.filter { !ids.contains($0.id) }
        let ordered = insertion == .start ? promoted + untouched : untouched + promoted
        for (index, item) in ordered.enumerated() {
            setPosition(index, of: item, in: owner.listID, context: context)
        }
        return promoted
    }

    // Set one list's own position for an item, creating the membership when a
    // legacy fallback row is promoted for the first time, and keeping the
    // legacy mirror truthful when it points at this list.
    @MainActor
    private static func setPosition(_ position: Int, of item: GroceryItem, in listID: UUID, context: ModelContext) {
        if let membership = item.membership(in: listID) {
            membership.position = position
        } else {
            context.insert(GroceryMembership(item: item, listID: listID, position: position))
        }
        if item.listID == listID { item.position = position }
    }

    static func open(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: ShoppingMigration.self, configurations: configuration)
    }

    @MainActor
    static func prepare(_ context: ModelContext, legacySelectedID: UUID?) throws {
        let lists = try context.fetch(FetchDescriptor<GroceryList>())
        var byID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        // Inbox's record is created like a retailer's; the setting only controls
        // whether the list is offered. No schema change is involved.
        for owner in ListOwner.all where byID[owner.listID] == nil {
            let list = GroceryList(owner: owner)
            context.insert(list)
            byID[list.id] = list
        }
        let items = try context.fetch(FetchDescriptor<GroceryItem>())
        for item in items where item.listID == nil { item.listID = StoreID.coles.listID }
        // Idempotent membership backfill: one row per saved item, at its
        // stored legacy position. Runs only when no membership exists yet.
        for item in items where item.memberships.isEmpty {
            guard let listID = item.listID else { continue }
            context.insert(GroceryMembership(item: item, listID: listID, position: item.position))
        }
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

    // The Lists… checklist. `owners` is either Inbox alone, or one or more
    // stores. Newly ticked lists receive the item at their end; unticked
    // memberships are removed. An item that leaves every list it was on is a
    // move, and moves set Pending, as the old Move action did. Everything else
    // (name, quantity, status, Reminders link) is shared and untouched here.
    @MainActor
    static func setLists(_ item: GroceryItem, to requested: [ListOwner],
                         allItems: [GroceryItem], context: ModelContext) {
        // Inbox is exclusive with stores: a mixed request keeps the stores,
        // exactly as the sheet's ticking rules already enforce.
        let owners = requested.contains { $0.store != nil }
            ? requested.filter { $0.store != nil }
            : requested.filter { $0 == .inbox }
        let targets = owners.map(\.listID)
        guard !targets.isEmpty else { return }
        let previous = Set(item.listIDs)
        // A fallback row (legacy fields, no membership yet) must not lose its
        // first list when a second is ticked: materialize it first.
        for listID in previous where item.membership(in: listID) == nil {
            context.insert(GroceryMembership(item: item, listID: listID, position: item.sortPosition(in: listID)))
        }
        let target = Set(targets)
        for listID in target.subtracting(previous) where item.membership(in: listID) == nil {
            let position = orderedItems(in: listID, from: allItems.filter { $0.id != item.id }).count
            context.insert(GroceryMembership(item: item, listID: listID, position: position))
        }
        for membership in item.liveMemberships where !target.contains(membership.listID) {
            context.delete(membership)
        }
        if previous.isDisjoint(with: target) { item.status = .pending }
        normalizeLegacyMirror(item)
    }

    // Remove one list's membership (the ⋯ menu's "Remove from [store]"). The
    // item itself stays with its other lists; a single-list item cannot reach
    // this path (its menu offers Delete instead).
    @MainActor
    static func removeList(_ listID: UUID, from item: GroceryItem) {
        guard item.listIDs.count > 1, let membership = item.membership(in: listID) else { return }
        item.modelContext?.delete(membership)
        normalizeLegacyMirror(item)
    }

    // Re-compact positions after rows leave a list. Callers repair selections
    // first; this only rewrites each affected list's own ordering.
    @MainActor
    static func repairOrder(removedIDs: Set<UUID>, affectedListIDs: Set<UUID>, allItems: [GroceryItem]) {
        for listID in affectedListIDs {
            let remaining = orderedItems(in: listID, from: allItems.filter { !removedIDs.contains($0.id) })
            for (position, item) in remaining.enumerated() {
                if let membership = item.membership(in: listID) { membership.position = position }
                if item.listID == listID { item.position = position }
            }
        }
    }

    // The legacy single-owner fields mirror the first remaining membership so
    // fallback reads (and an older recovery view) stay truthful. Rows with no
    // membership at all keep their stored values untouched.
    static func normalizeLegacyMirror(_ item: GroceryItem) {
        let live = item.liveMemberships
        guard !live.isEmpty else { return }
        let membership = live.min { $0.listID.uuidString < $1.listID.uuidString }!
        item.listID = membership.listID
        item.position = membership.position
    }
}
