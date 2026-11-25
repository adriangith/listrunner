import CloudKit
import CryptoKit
import Foundation

// iCloud sync model: the values, record format and merge rules shared by the
// sync engine and its tests. SwiftData stays the app's only store and the
// UI's only source; these types are what crosses into and out of CloudKit.
// Nothing here talks to the network. See plan.md, "iCloud sync and list
// sharing".

// MARK: - Zones

// Where a record lives. Each unshared list has its own zone in its owner's
// private database. Each share group (lists shared with the same people) is
// one zone with a zone-wide CKShare. Zones owned by someone else are reached
// through the shared database and carry that owner's record name.
struct SyncZone: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case list(UUID)
        case group(UUID)
    }

    static let listPrefix = "list-"
    static let groupPrefix = "group-"

    let kind: Kind
    // `CKCurrentUserDefaultName` for this person's own zones.
    let ownerName: String

    init(_ kind: Kind, ownerName: String = CKCurrentUserDefaultName) {
        self.kind = kind
        self.ownerName = ownerName
    }

    init?(zoneID: CKRecordZone.ID) {
        guard let kind = Self.kind(named: zoneID.zoneName) else { return nil }
        self.init(kind, ownerName: zoneID.ownerName)
    }

    static func kind(named name: String) -> Kind? {
        if name.hasPrefix(listPrefix), let id = UUID(uuidString: String(name.dropFirst(listPrefix.count))) {
            return .list(id)
        }
        if name.hasPrefix(groupPrefix), let id = UUID(uuidString: String(name.dropFirst(groupPrefix.count))) {
            return .group(id)
        }
        return nil
    }

    var name: String {
        switch kind {
        case .list(let id): Self.listPrefix + id.uuidString
        case .group(let id): Self.groupPrefix + id.uuidString
        }
    }

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: name, ownerName: ownerName) }
    var isOwnedByCurrentUser: Bool { ownerName == CKCurrentUserDefaultName }
    // Only share groups are ever shared; a list zone is always private.
    var isShareGroup: Bool {
        if case .group = kind { return true }
        return false
    }
}

// Which zone each list and item belongs to.
struct SyncZonePlan: Sendable {
    struct ItemLists: Sendable {
        let id: UUID
        let listIDs: [UUID]
    }

    // Local list ID → the share group holding it, this person's own or
    // someone else's. Lists not named here are unshared.
    var sharedLists: [UUID: SyncZone] = [:]

    func zone(forList listID: UUID) -> SyncZone {
        sharedLists[listID] ?? SyncZone(.list(listID))
    }

    func shareGroups(forItemOn listIDs: [UUID]) -> Set<SyncZone> {
        Set(listIDs.compactMap { sharedLists[$0] })
    }

    // An item's record lives in its share group when it is on a shared list,
    // otherwise in the zone of its first list by ID (the same list the legacy
    // mirror uses, so every device picks the same one). Nil when the lists
    // span two share groups or there are none: the app never allows the
    // first (it copies the item instead), and an item with no list is gone.
    func zone(forItemOn listIDs: [UUID]) -> SyncZone? {
        let groups = shareGroups(forItemOn: listIDs)
        if groups.count > 1 { return nil }
        if let group = groups.first { return group }
        guard let first = listIDs.min(by: { $0.uuidString < $1.uuidString }) else { return nil }
        return zone(forList: first)
    }

    // Items to copy before `listID` joins `group`: those on that list that
    // are also on a list in a different share group. Lists already in
    // `group` never force a copy, so a list joining its own group never
    // splits anything.
    func itemsNeedingCopies(beforeMoving listID: UUID, into group: SyncZone, items: [ItemLists]) -> [UUID] {
        items.filter { item in
            item.listIDs.contains(listID) && item.listIDs.contains { other in
                other != listID && sharedLists[other].map { $0 != group } == true
            }
        }.map(\.id)
    }
}

// MARK: - Record names

enum SyncRecordType {
    static let list = "List"
    static let item = "Item"
    static let membership = "Membership"
}

// Record names hold the IDs as they are stored in that zone. For someone
// else's list added separately, the membership names the owner's list ID,
// not the local alias.
enum SyncRecordName {
    enum Parsed: Equatable, Sendable {
        case list(UUID)
        case item(UUID)
        case membership(item: UUID, list: UUID)
    }

    static func list(_ id: UUID) -> String { "list.\(id.uuidString)" }
    static func item(_ id: UUID) -> String { "item.\(id.uuidString)" }
    static func membership(item: UUID, list: UUID) -> String { "membership.\(item.uuidString).\(list.uuidString)" }

    static func parse(_ name: String) -> Parsed? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("list", 2): return UUID(uuidString: parts[1]).map(Parsed.list)
        case ("item", 2): return UUID(uuidString: parts[1]).map(Parsed.item)
        case ("membership", 3):
            guard let item = UUID(uuidString: parts[1]), let list = UUID(uuidString: parts[2]) else { return nil }
            return .membership(item: item, list: list)
        default: return nil
        }
    }
}

// Someone else's list added as a separate list ("Coles · Sam") needs a local
// ID of its own: their Coles list has the same permanent ID as this person's.
// The alias is derived, so every device of this person agrees on it without
// coordination.
enum SyncListAlias {
    static func localID(forRemoteList remoteID: UUID, in zone: SyncZone) -> UUID {
        let seed = Data("listrunner-shared-list/\(zone.ownerName)/\(zone.name)/\(remoteID.uuidString)".utf8)
        var bytes = Array(SHA256.hash(data: seed).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // name-based UUID version
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - Values and merge

// When a field last changed and on which device. The device breaks ties, so
// every device resolves the same conflict the same way.
struct SyncStamp: Hashable, Codable, Comparable, Sendable {
    var date: Date
    var device: String

    static let unknown = SyncStamp(date: .distantPast, device: "")

    static func < (lhs: SyncStamp, rhs: SyncStamp) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.device < rhs.device
    }
}

// The synced part of an item. Never: Reminders links, selection, cart state.
struct SyncItem: Equatable, Sendable {
    // Amount and unit change together, so a merge never pairs one person's
    // amount with another's unit.
    enum Field: String, CaseIterable, Sendable {
        case name, searchTerm, quantity, status, originStoreID
    }

    var id: UUID
    var name: String
    var searchTerm: String
    var quantityAmount: Double?
    var quantityUnit: String?
    var status: GroceryStatus
    var originStoreID: String?
    var stamps: [Field: SyncStamp] = [:]

    func stamp(_ field: Field) -> SyncStamp { stamps[field] ?? .unknown }

    func hasSameValue(_ field: Field, as other: SyncItem) -> Bool {
        switch field {
        case .name: name == other.name
        case .searchTerm: searchTerm == other.searchTerm
        case .quantity: quantityAmount == other.quantityAmount && quantityUnit == other.quantityUnit
        case .status: status == other.status
        case .originStoreID: originStoreID == other.originStoreID
        }
    }

    mutating func take(_ field: Field, from other: SyncItem) {
        switch field {
        case .name: name = other.name
        case .searchTerm: searchTerm = other.searchTerm
        case .quantity:
            quantityAmount = other.quantityAmount
            quantityUnit = other.quantityUnit
        case .status: status = other.status
        case .originStoreID: originStoreID = other.originStoreID
        }
        stamps[field] = other.stamps[field]
    }

    // A local edit: stamp each field whose value differs from the last synced
    // state. A new item (no previous state) stamps every field.
    mutating func stampChanges(since previous: SyncItem?, at stamp: SyncStamp) {
        for field in Field.allCases where previous.map({ !hasSameValue(field, as: $0) }) ?? true {
            stamps[field] = stamp
        }
    }
}

// One list's membership: the item is on the list, at that list's position.
struct SyncMembership: Equatable, Sendable {
    var itemID: UUID
    var listID: UUID
    var position: Int
    var positionStamp: SyncStamp = .unknown
}

// A list record. Its ID is the one stored in its zone; separate lists map it
// to a local alias.
struct SyncList: Equatable, Sendable {
    var id: UUID
    // A `ListOwner` raw value. Unknown values (a newer build's store) are
    // kept, so the existing unknown-owner recovery shows the rows.
    var ownerRawValue: String
}

enum SyncMerge {
    struct Outcome<Value: Equatable & Sendable>: Equatable, Sendable {
        var merged: Value
        // The local copy must be updated to `merged`.
        var changesLocal: Bool
        // The server copy is older than `merged`; send it back up.
        var needsUpload: Bool
    }

    // Field by field, the later stamp wins. Commutative: merging either way
    // round gives the same values.
    static func item(local: SyncItem, remote: SyncItem) -> Outcome<SyncItem> {
        precondition(local.id == remote.id, "merging two different items")
        var merged = remote
        for field in SyncItem.Field.allCases where local.stamp(field) > remote.stamp(field) {
            merged.take(field, from: local)
        }
        return Outcome(merged: merged, changesLocal: merged != local, needsUpload: merged != remote)
    }

    static func membership(local: SyncMembership, remote: SyncMembership) -> Outcome<SyncMembership> {
        precondition(local.itemID == remote.itemID && local.listID == remote.listID, "merging two different memberships")
        let merged = local.positionStamp > remote.positionStamp ? local : remote
        return Outcome(merged: merged, changesLocal: merged != local, needsUpload: merged != remote)
    }

    // Deletes win over edits. An incoming delete always applies, even over
    // unsent local edits. While a local delete waits to upload, an incoming
    // edit of that record is ignored.
    static func appliesIncomingUpdate(to recordName: String, pendingDeletes: Set<String>) -> Bool {
        !pendingDeletes.contains(recordName)
    }
}

// MARK: - Record format

enum SyncRecordCoder {
    static let formatVersion: Int64 = 1

    private enum Key {
        static let version = "formatVersion"
        static let name = "name"
        static let searchTerm = "searchTerm"
        static let quantityAmount = "quantityAmount"
        static let quantityUnit = "quantityUnit"
        static let status = "status"
        static let originStoreID = "originStoreID"
        static let stamps = "stamps"
        static let position = "position"
        static let positionStamp = "positionStamp"
        static let owner = "owner"
    }

    // Reuse the stored server record (it carries CloudKit's change tag) only
    // when it is the same record in the same zone.
    private static func base(_ type: String, name: String, zone: CKRecordZone.ID, reusing existing: CKRecord?) -> CKRecord {
        let id = CKRecord.ID(recordName: name, zoneID: zone)
        if let existing, existing.recordID == id, existing.recordType == type { return existing }
        return CKRecord(recordType: type, recordID: id)
    }

    static func record(for item: SyncItem, in zone: CKRecordZone.ID, reusing existing: CKRecord? = nil) -> CKRecord {
        let record = base(SyncRecordType.item, name: SyncRecordName.item(item.id), zone: zone, reusing: existing)
        record[Key.version] = formatVersion as NSNumber
        record[Key.name] = item.name as NSString
        record[Key.searchTerm] = item.searchTerm as NSString
        record[Key.quantityAmount] = item.quantityAmount.map { $0 as NSNumber }
        record[Key.quantityUnit] = item.quantityUnit.map { $0 as NSString }
        record[Key.status] = item.status.rawValue as NSString
        record[Key.originStoreID] = item.originStoreID.map { $0 as NSString }
        let stamps = Dictionary(uniqueKeysWithValues: item.stamps.map { ($0.key.rawValue, $0.value) })
        record[Key.stamps] = (try? JSONEncoder().encode(stamps)).map { $0 as NSData }
        return record
    }

    static func item(from record: CKRecord) -> SyncItem? {
        guard record.recordType == SyncRecordType.item,
              case .item(let id)? = SyncRecordName.parse(record.recordID.recordName),
              let name = record[Key.name] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let searchTerm = (record[Key.searchTerm] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        // Unreadable stamps lose every conflict rather than dropping the record.
        let decoded = (record[Key.stamps] as? Data).flatMap { try? JSONDecoder().decode([String: SyncStamp].self, from: $0) } ?? [:]
        var stamps: [SyncItem.Field: SyncStamp] = [:]
        for (key, stamp) in decoded {
            if let field = SyncItem.Field(rawValue: key) { stamps[field] = stamp }
        }
        let amount = (record[Key.quantityAmount] as? NSNumber)?.doubleValue
        return SyncItem(id: id, name: name, searchTerm: searchTerm,
                        quantityAmount: amount.flatMap { $0.isFinite ? $0 : nil },
                        quantityUnit: record[Key.quantityUnit] as? String,
                        status: (record[Key.status] as? String).flatMap(GroceryStatus.init(rawValue:)) ?? .pending,
                        originStoreID: record[Key.originStoreID] as? String,
                        stamps: stamps)
    }

    static func record(for membership: SyncMembership, in zone: CKRecordZone.ID, reusing existing: CKRecord? = nil) -> CKRecord {
        let name = SyncRecordName.membership(item: membership.itemID, list: membership.listID)
        let record = base(SyncRecordType.membership, name: name, zone: zone, reusing: existing)
        record[Key.version] = formatVersion as NSNumber
        record[Key.position] = Int64(membership.position) as NSNumber
        record[Key.positionStamp] = (try? JSONEncoder().encode(membership.positionStamp)).map { $0 as NSData }
        return record
    }

    static func membership(from record: CKRecord) -> SyncMembership? {
        guard record.recordType == SyncRecordType.membership,
              case .membership(let itemID, let listID)? = SyncRecordName.parse(record.recordID.recordName) else { return nil }
        let position = (record[Key.position] as? NSNumber)?.int64Value ?? 0
        let stamp = (record[Key.positionStamp] as? Data).flatMap { try? JSONDecoder().decode(SyncStamp.self, from: $0) } ?? .unknown
        return SyncMembership(itemID: itemID, listID: listID,
                              position: Int(clamping: max(0, position)), positionStamp: stamp)
    }

    static func record(for list: SyncList, in zone: CKRecordZone.ID, reusing existing: CKRecord? = nil) -> CKRecord {
        let record = base(SyncRecordType.list, name: SyncRecordName.list(list.id), zone: zone, reusing: existing)
        record[Key.version] = formatVersion as NSNumber
        record[Key.owner] = list.ownerRawValue as NSString
        return record
    }

    static func list(from record: CKRecord) -> SyncList? {
        guard record.recordType == SyncRecordType.list,
              case .list(let id)? = SyncRecordName.parse(record.recordID.recordName),
              let owner = record[Key.owner] as? String, !owner.isEmpty else { return nil }
        return SyncList(id: id, ownerRawValue: owner)
    }
}
