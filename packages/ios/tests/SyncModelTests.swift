import CloudKit
import Foundation

// Offline checks for the iCloud sync model: zones, record names, list
// aliases, merge rules and the record format. No iCloud account or network.
@main
struct SyncModelTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }

        let coles = StoreID.coles.listID, woolworths = StoreID.woolworths.listID, bunnings = StoreID.bunnings.listID
        let groupA = SyncZone(.group(UUID())), groupB = SyncZone(.group(UUID()))
        let samsGroup = SyncZone(.group(UUID()), ownerName: "_sam")

        // Zones
        for zone in [SyncZone(.list(coles)), groupA, samsGroup] {
            check(SyncZone(zoneID: zone.zoneID) == zone, "zone \(zone.name) round-trips through its CloudKit ID")
        }
        check(SyncZone(.list(coles)).name == "list-\(coles.uuidString)" && groupA.name.hasPrefix("group-"),
              "zone names say whether they hold one list or a share group")
        for bad in ["", "list-", "list-nope", "group-\(UUID().uuidString)x", "other-\(UUID().uuidString)", "_defaultZone"] {
            check(SyncZone(zoneID: CKRecordZone.ID(zoneName: bad, ownerName: CKCurrentUserDefaultName)) == nil,
                  "unrecognised zone name \(bad) is ignored")
        }
        check(SyncZone(.list(coles)).isOwnedByCurrentUser && !samsGroup.isOwnedByCurrentUser,
              "own zones and someone else's are told apart")
        check(groupA.isShareGroup && !SyncZone(.list(coles)).isShareGroup, "only share groups are shared")

        // Record names
        let itemID = UUID()
        for parsed in [SyncRecordName.Parsed.list(coles), .item(itemID), .membership(item: itemID, list: woolworths)] {
            let name: String
            switch parsed {
            case .list(let id): name = SyncRecordName.list(id)
            case .item(let id): name = SyncRecordName.item(id)
            case .membership(let item, let list): name = SyncRecordName.membership(item: item, list: list)
            }
            check(SyncRecordName.parse(name) == parsed, "record name \(name) round-trips")
        }
        for bad in ["", "item", "item.", "item.x", "list.\(coles).extra", "membership.\(itemID)", "group.\(coles)",
                    "membership.\(itemID).nope", "ITEM.\(itemID)"] {
            check(SyncRecordName.parse(bad) == nil, "malformed record name \(bad) is rejected")
        }

        // List aliases for separate shared lists
        let alias = SyncListAlias.localID(forRemoteList: coles, in: samsGroup)
        check(alias == SyncListAlias.localID(forRemoteList: coles, in: samsGroup),
              "every device of a participant derives the same alias")
        check(alias != coles && alias != SyncListAlias.localID(forRemoteList: woolworths, in: samsGroup)
              && alias != SyncListAlias.localID(forRemoteList: coles, in: SyncZone(samsGroup.kind, ownerName: "_pat"))
              && alias != SyncListAlias.localID(forRemoteList: coles, in: SyncZone(.group(UUID()), ownerName: "_sam")),
              "aliases differ by list, owner and group")
        check(!StoreID.allCases.contains { $0.listID == alias || $0.websiteDataID == alias } && alias != ListOwner.inboxListID,
              "an alias never collides with a store's or Inbox's permanent ID")
        check(alias.uuidString.dropFirst(14).first == "5", "aliases are well-formed name-based UUIDs")

        // Zone plan
        var plan = SyncZonePlan()
        check(plan.zone(forList: coles) == SyncZone(.list(coles)), "an unshared list lives in its own zone")
        let firstByID = [coles, woolworths].min { $0.uuidString < $1.uuidString }!
        check(plan.zone(forItemOn: [woolworths, coles]) == SyncZone(.list(firstByID)),
              "an unshared multi-store item lives with its first list by ID, whatever the order")
        check(plan.zone(forItemOn: []) == nil, "an item on no list has no zone")
        plan.sharedLists[coles] = groupA
        check(plan.zone(forList: coles) == groupA && plan.zone(forList: woolworths) == SyncZone(.list(woolworths)),
              "a shared list lives in its group")
        check(plan.zone(forItemOn: [woolworths, coles]) == groupA,
              "an item on a shared and a private list lives in the share group (Case 1: still one item)")
        plan.sharedLists[woolworths] = groupA
        check(plan.zone(forItemOn: [coles, woolworths]) == groupA, "lists shared with the same people share one zone")
        plan.sharedLists[woolworths] = groupB
        check(plan.zone(forItemOn: [coles, woolworths]) == nil, "an item cannot span two share groups")
        plan.sharedLists[woolworths] = nil

        let milk = UUID(), bread = UUID(), nails = UUID(), eggs = UUID()
        let items = [SyncZonePlan.ItemLists(id: milk, listIDs: [coles, woolworths]),
                     .init(id: bread, listIDs: [woolworths]),
                     .init(id: nails, listIDs: [woolworths, bunnings]),
                     .init(id: eggs, listIDs: [coles])]
        check(plan.itemsNeedingCopies(beforeMoving: woolworths, into: groupB, items: items) == [milk],
              "sharing Woolworths with different people copies only items also in Coles' group")
        check(plan.itemsNeedingCopies(beforeMoving: woolworths, into: groupA, items: items).isEmpty,
              "adding Woolworths to Coles' group never copies")
        check(plan.itemsNeedingCopies(beforeMoving: woolworths, into: samsGroup, items: items) == [milk],
              "merging Woolworths into someone else's list copies items in this person's own group")
        check(plan.itemsNeedingCopies(beforeMoving: bunnings, into: groupB, items: items).isEmpty,
              "items shared only with private lists never need copies")

        // Merge
        let early = SyncStamp(date: Date(timeIntervalSince1970: 1_000), device: "a")
        let late = SyncStamp(date: Date(timeIntervalSince1970: 2_000), device: "a")
        let tieB = SyncStamp(date: early.date, device: "b")
        let base = SyncItem(id: itemID, name: "Milk", searchTerm: "Milk", quantityAmount: 1, quantityUnit: "L",
                            status: .pending, originStoreID: nil)
        var mine = base, theirs = base
        mine.name = "Oat milk"; mine.stampChanges(since: base, at: late)
        theirs.status = .added; theirs.stampChanges(since: base, at: early)
        check(mine.stamps.keys.sorted { $0.rawValue < $1.rawValue } == [.name] && theirs.stamps.keys.first == .status
              && theirs.stamps.count == 1, "a local edit stamps only the fields it changed")
        let both = SyncMerge.item(local: mine, remote: theirs)
        check(both.merged.name == "Oat milk" && both.merged.status == .added,
              "edits to different fields by different people both survive")
        check(both.changesLocal && both.needsUpload, "a two-sided merge updates both copies")

        var a = base, b = base
        a.quantityAmount = 2; a.stampChanges(since: base, at: early)
        b.quantityUnit = "kg"; b.stampChanges(since: base, at: late)
        let quantity = SyncMerge.item(local: a, remote: b).merged
        check(quantity.quantityAmount == 1 && quantity.quantityUnit == "kg",
              "amount and unit merge together, never mixing two people's quantities")

        var x = base, y = base
        x.name = "Milk A"; x.stampChanges(since: base, at: early)
        y.name = "Milk B"; y.stampChanges(since: base, at: tieB)
        check(SyncMerge.item(local: x, remote: y).merged.name == "Milk B"
              && SyncMerge.item(local: y, remote: x).merged.name == "Milk B",
              "a same-instant conflict resolves the same way on every device")

        let samples: [SyncItem] = [base, mine, theirs, a, b, x, y]
        for left in samples {
            for right in samples {
                let one = SyncMerge.item(local: left, remote: right).merged
                let two = SyncMerge.item(local: right, remote: left).merged
                check(SyncItem.Field.allCases.allSatisfy { one.hasSameValue($0, as: two) && one.stamp($0) == two.stamp($0) },
                      "merging is order-independent")
                check(SyncMerge.item(local: one, remote: one) == .init(merged: one, changesLocal: false, needsUpload: false),
                      "merging a record with itself changes nothing")
            }
        }
        var unstamped = base
        unstamped.name = "Old"
        check(SyncMerge.item(local: unstamped, remote: mine).merged.name == "Oat milk"
              && SyncMerge.item(local: mine, remote: unstamped).merged.name == "Oat milk",
              "a stamped edit beats a value with no stamp either way round")
        var fresh = base
        fresh.stampChanges(since: nil, at: early)
        check(fresh.stamps.count == SyncItem.Field.allCases.count, "a new item stamps every field")
        var unchanged = base
        unchanged.stampChanges(since: base, at: late)
        check(unchanged.stamps.isEmpty, "an unchanged item is not stamped")

        let m1 = SyncMembership(itemID: itemID, listID: coles, position: 3, positionStamp: early)
        let m2 = SyncMembership(itemID: itemID, listID: coles, position: 0, positionStamp: late)
        check(SyncMerge.membership(local: m1, remote: m2).merged.position == 0
              && SyncMerge.membership(local: m2, remote: m1).merged.position == 0, "the later reorder wins")
        check(SyncMerge.membership(local: m2, remote: m1).needsUpload && !SyncMerge.membership(local: m2, remote: m1).changesLocal,
              "a newer local position is sent back up")

        let pending: Set<String> = [SyncRecordName.item(itemID)]
        check(!SyncMerge.appliesIncomingUpdate(to: SyncRecordName.item(itemID), pendingDeletes: pending)
              && SyncMerge.appliesIncomingUpdate(to: SyncRecordName.item(UUID()), pendingDeletes: pending),
              "a pending local delete wins over an incoming edit of that record only")

        // Record format
        let zone = groupA.zoneID
        var full = mine
        full.originStoreID = "coles"
        let itemRecord = SyncRecordCoder.record(for: full, in: zone)
        check(itemRecord.recordType == "Item" && itemRecord.recordID.zoneID == zone
              && itemRecord.recordID.recordName == SyncRecordName.item(itemID), "an item record is named and placed")
        check(SyncRecordCoder.item(from: itemRecord) == full, "an item round-trips with its stamps")
        var bare = base
        bare.quantityAmount = nil; bare.quantityUnit = nil
        check(SyncRecordCoder.item(from: SyncRecordCoder.record(for: bare, in: zone)) == bare,
              "an item without a quantity round-trips")
        let cleared = SyncRecordCoder.record(for: bare, in: zone, reusing: itemRecord)
        check(cleared === itemRecord && cleared["quantityAmount"] == nil && cleared["originStoreID"] == nil,
              "re-encoding into the stored record keeps its change tag and clears removed values")
        let moved = SyncRecordCoder.record(for: bare, in: groupB.zoneID, reusing: itemRecord)
        check(moved !== itemRecord && moved.recordID.zoneID == groupB.zoneID,
              "a record moving zones is created fresh, never reusing the old zone's record")

        let odd = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: SyncRecordName.item(itemID), zoneID: zone))
        odd["name"] = "Eggs" as NSString
        odd["status"] = "Bought" as NSString
        odd["stamps"] = Data("not json".utf8) as NSData
        odd["quantityAmount"] = Double.nan as NSNumber
        let decoded = SyncRecordCoder.item(from: odd)
        check(decoded?.status == .pending && decoded?.stamps.isEmpty == true && decoded?.searchTerm == "Eggs"
              && decoded?.quantityAmount == nil,
              "unknown status, unreadable stamps and invalid amounts fall back without dropping the item")
        odd["name"] = "  " as NSString
        check(SyncRecordCoder.item(from: odd) == nil, "an item without a name is rejected")
        let wrongName = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: "item.nope", zoneID: zone))
        wrongName["name"] = "Eggs" as NSString
        check(SyncRecordCoder.item(from: wrongName) == nil, "an item record with a malformed name is rejected")
        check(SyncRecordCoder.membership(from: itemRecord) == nil && SyncRecordCoder.list(from: itemRecord) == nil,
              "records are only decoded as their own type")

        let membershipRecord = SyncRecordCoder.record(for: m2, in: zone)
        check(SyncRecordCoder.membership(from: membershipRecord) == m2, "a membership round-trips")
        membershipRecord["position"] = Int64(-4) as NSNumber
        membershipRecord["positionStamp"] = nil
        check(SyncRecordCoder.membership(from: membershipRecord)?.position == 0
              && SyncRecordCoder.membership(from: membershipRecord)?.positionStamp == .unknown,
              "a negative position or missing stamp is repaired, not trusted")

        for list in [SyncList(id: coles, ownerRawValue: "coles"), SyncList(id: UUID(), ownerRawValue: "futureStore")] {
            check(SyncRecordCoder.list(from: SyncRecordCoder.record(for: list, in: zone)) == list,
                  "list \(list.ownerRawValue) round-trips, including owners this build does not know")
        }
        let emptyOwner = SyncRecordCoder.record(for: SyncList(id: coles, ownerRawValue: "coles"), in: zone)
        emptyOwner["owner"] = "" as NSString
        check(SyncRecordCoder.list(from: emptyOwner) == nil, "a list without an owner is rejected")

        print("PASS: \(checks) sync model checks")
    }
}
