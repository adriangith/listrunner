import Foundation
import SwiftData
import WebKit

// Standalone native service checks: temporary files, isolated UserDefaults and a
// nonpersistent WebKit store only. Never resets the running app or a real login.
@main
struct RecoveryTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }

        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let configData = try Data(contentsOf: resources.appendingPathComponent("coles.json"))
        let coles = try JSONDecoder().decode(StoreDefinition.self, from: configData)
        let woolworths = try JSONDecoder().decode(StoreDefinition.self, from: Data(contentsOf: resources.appendingPathComponent("woolworths.json")))
        try coles.validate(); try woolworths.validate()
        let separatedGroceries = GroceryParser.parse("milk\tbread; eggs, butter\nyogurt")
        check(separatedGroceries.map(\.name) == ["milk", "bread", "eggs", "butter", "yogurt"],
              "grocery input accepts newline, tab, semicolon and comma separators")
        check(coles.addedColor.red == 224 && coles.addedColor.green == 26 && coles.addedColor.blue == 34,
              "Coles Added colour is explicitly configured as RGB(224, 26, 34)")
        check(woolworths.addedColor.red == 0 && woolworths.addedColor.green == 114 && woolworths.addedColor.blue == 61,
              "Woolworths Added colour is explicitly configured as RGB(0, 114, 61)")
        check(coles.capabilities.cartDetection && coles.capabilities.cartUndo, "Coles capabilities preserved")
        check(woolworths.capabilities.cartDetection && !woolworths.capabilities.cartUndo,
              "verified Woolworths add detection is enabled while cart Undo remains disabled")
        let woolworthsCart = woolworths.cart!
        let woolworthsProductPath = "/shop/productdetails/83273/so-good-barista-oat-long-life-milk"
        let woolworthsMatch = try NSRegularExpression(pattern: woolworthsCart.productURLPattern)
            .firstMatch(in: woolworthsProductPath, range: NSRange(woolworthsProductPath.startIndex..., in: woolworthsProductPath))
        let woolworthsIDRange = woolworthsMatch?.range(at: 1)
        let woolworthsProductID = woolworthsIDRange.flatMap { Range($0, in: woolworthsProductPath).map { String(woolworthsProductPath[$0]) } }
        check(woolworthsCart.tileSelector == "wc-product-tile" && woolworthsProductID == "83273",
              "Woolworths product tile and numeric stockcode identity match live product URLs")
        check(woolworthsCart.quantitySelector.contains("quantity-input") && woolworthsCart.emptyStatusText == "Add to cart",
              "Woolworths detection uses in-tile quantity or explicit empty-cart Add control")
        let query = "milk & tea / + # ? = café"
        let generated = URLComponents(url: woolworths.searchURL(for: query)!, resolvingAgainstBaseURL: false)!
        check(generated.queryItems?.first?.value == query && generated.fragment == nil, "search query safely percent-encoded")
        check(!coles.allows(woolworths.homepage) && !woolworths.allows(coles.homepage), "cross-store URL rejection")
        let colesLogin = URL(string: "https://auth.colesgroupprofile.com.au/login")!
        check(coles.allowsNavigation(colesLogin) && !coles.allows(colesLogin),
              "Coles login stays embedded but cannot use cart automation")
        check(!woolworths.allowsNavigation(colesLogin), "Coles authentication is not allowed in Woolworths")
        let colesIdentity = URL(string: "https://id.colesgroupprofile.com.au/?token=placeholder")!
        check(coles.allowsNavigation(colesIdentity) && !coles.allows(colesIdentity),
              "Coles post-MFA identity handoff stays embedded without cart automation")
        check(!woolworths.allowsNavigation(colesIdentity), "Coles identity handoff is not allowed in Woolworths")
        for loginURL in ["http://auth.colesgroupprofile.com.au/login",
                         "https://auth.colesgroupprofile.com.au.evil.test/login",
                         "https://evil.colesgroupprofile.com.au/login",
                         "https://auth.colesgroupprofile.com.au:444/login",
                         "https://user@auth.colesgroupprofile.com.au/login"] {
            check(!coles.allowsNavigation(URL(string: loginURL)!), "unsafe login URL rejected: \(loginURL)")
        }
        check(StoreID.coles.ownsDataDomain(".colesgroupprofile.com.au")
              && StoreID.coles.ownsDataDomain("auth.colesgroupprofile.com.au")
              && StoreID.coles.ownsDataDomain("id.colesgroupprofile.com.au")
              && !StoreID.woolworths.ownsDataDomain(".colesgroupprofile.com.au"),
              "Coles session reset owns authentication cookies without affecting Woolworths")
        check(!coles.allows(URL(string: "https://evil.coles.com.au")!), "exact-host allowlist")
        check(!coles.allows(URL(string: "https://www.coles.com.au:444")!), "unapproved port rejection")
        check(!coles.allows(URL(string: "http://www.coles.com.au")!), "HTTPS enforced")
        check(!coles.allows(URL(string: "https://user@www.coles.com.au")!), "credential URL rejection")
        check(StoreID.coles.listID != StoreID.woolworths.listID && StoreID.coles.websiteDataID != StoreID.woolworths.websiteDataID, "stable per-store identifiers are distinct")
        func rejects(_ mutate: (inout [String: Any]) -> Void) throws -> Bool {
            var object = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
            mutate(&object)
            do {
                let value = try JSONDecoder().decode(StoreDefinition.self, from: JSONSerialization.data(withJSONObject: object))
                try value.validate()
                return false
            } catch { return true }
        }
        let badVersion = try rejects { $0["schemaVersion"] = 99 }
        let badHome = try rejects { $0["homepage"] = "https://evil.test" }
        let badHosts = try rejects { $0["allowedHosts"] = ["evil.test"] }
        let badStrategy = try rejects { $0["search"] = ["strategy": "executeScript", "template": "https://www.coles.com.au?q={query}"] }
        let badTemplate = try rejects { $0["search"] = ["strategy": "urlTemplate", "template": "https://www.coles.com.au?q={query}{query}"] }
        let missingCart = try rejects { $0["cart"] = NSNull() }
        check(badVersion && badHome && badHosts && badStrategy && badTemplate && missingCart, "invalid configuration contracts rejected")
        let fallback = StoreDefinition.load(.woolworths)
        check(!fallback.capabilities.search && !fallback.capabilities.cartDetection && fallback.allows(StoreID.woolworths.home), "bad/missing configuration keeps safe manual browsing")

        let bridge: [String: Any] = ["schemaVersion": 1, "storeID": "coles", "sessionID": "session", "interactionID": "interaction",
            "itemID": UUID().uuidString, "documentGeneration": 1, "pageURL": "https://www.coles.com.au/search?q=milk",
            "type": "addDetected", "productID": "123", "confirmationID": "1", "beforeQuantity": 0, "resultingQuantity": 1]
        func bridgeRaw(_ object: [String: Any]) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        let validBridge = try bridgeRaw(bridge)
        check(StoreBridge.decode(validBridge, store: coles) != nil, "valid configured bridge schema")
        check(StoreBridge.decode(validBridge, store: woolworths) == nil, "native cross-store bridge rejection")
        for (key, value) in [("resultingQuantity", true as Any), ("resultingQuantity", 1.5 as Any),
                             ("resultingQuantity", 10_000 as Any), ("schemaVersion", true as Any),
                             ("documentGeneration", true as Any), ("documentGeneration", -1 as Any),
                             ("productID", "abc" as Any), ("itemID", "not-a-uuid" as Any),
                             ("type", "arbitraryCommand" as Any), ("injectedField", "not-allowed" as Any),
                             ("pageURL", "https://evil.coles.com.au" as Any)] {
            var invalid = bridge
            invalid[key] = value
            let raw = try bridgeRaw(invalid)
            check(StoreBridge.decode(raw, store: coles) == nil, "strict bridge rejection: \(key)")
        }
        check(StoreBridge.decode(String(repeating: "é", count: 4_097), store: coles) == nil, "UTF-8 bridge size bound")
        check(StoreBridge.decode("not json", store: coles) == nil, "malformed bridge rejected")

        var pacing = StoreNavigationPacing()
        check(pacing.delay(at: 100) == 0, "first storefront request can start immediately")
        pacing.requested(at: 100)
        check(pacing.delay(at: 100.5) == 1.5, "rapid app navigation waits for minimum interval")
        check(pacing.delay(at: 102) == 0 && pacing.delay(at: 200) == 0, "request interval ends without negative delays")
        pacing.blocked(at: 102)
        check(!pacing.canRetry(at: 131.9) && pacing.canRetry(at: 132), "verification retry requires deliberate cooldown")
        pacing.blocked(at: 132)
        check(!pacing.canRetry(at: 133), "failed verification retry starts another pause")
        pacing.clearBlock()
        check(pacing.canRetry(at: 133), "completed verification releases the pause")
        check(StoreNavigationPacing.isVerificationPage(title: "Pardon Our Interruption", heading: ""), "verification page detected by title")
        check(StoreNavigationPacing.isVerificationPage(title: "", heading: "  PARDON OUR INTERRUPTION\n"), "verification page detected by normalized heading")
        check(!StoreNavigationPacing.isVerificationPage(title: "Coles | Groceries", heading: "Results for eggs"), "normal search page is not a verification block")
        check(!StoreNavigationPacing.isVerificationPage(title: "Coles", heading: "Results for pardon our interruption"), "product search text cannot impersonate exact verification heading")

        let paprikaSnapshot = [
            PaprikaReminderSnapshot(id: "late", title: "bread", creationDate: Date(timeIntervalSince1970: 20)),
            PaprikaReminderSnapshot(id: "old", title: "2L milk", creationDate: Date(timeIntervalSince1970: 10)),
            PaprikaReminderSnapshot(id: "existing", title: "eggs", creationDate: Date(timeIntervalSince1970: 5)),
            PaprikaReminderSnapshot(id: "blank", title: " •  ", creationDate: nil),
            PaprikaReminderSnapshot(id: "late", title: "duplicate", creationDate: Date(timeIntervalSince1970: 30)),
            PaprikaReminderSnapshot(id: "undated", title: "apples", creationDate: nil)
        ]
        let paprikaStaged = PaprikaImportPlanner.stage(reminders: paprikaSnapshot, existingIDs: ["existing"])
        check(paprikaStaged.map(\.grocery.name) == ["milk", "bread", "apples"], "Paprika import is creation-ordered, duplicate-safe and ignores blank titles")
        check(paprikaStaged.first?.grocery.amount == 2 && paprikaStaged.first?.grocery.unit == "l", "Paprika title uses grocery quantity parser")
        let mayonnaise = PaprikaImportPlanner.stage(
            reminders: [PaprikaReminderSnapshot(id: "mayonnaise", title: "1 cup mayonnaise", creationDate: nil)],
            existingIDs: []
        )
        check(mayonnaise.count == 1 && mayonnaise[0].grocery.name == "mayonnaise"
              && mayonnaise[0].grocery.amount == 1 && mayonnaise[0].grocery.unit == "cup",
              "Paprika cup measure preserves amount and unit while parsing grocery name")
        check(paprikaStaged.map(\.reminderID) == ["old", "late", "undated"], "Paprika source identity remains linked to imported rows")
        let reimported = PaprikaImportPlanner.stage(reminders: paprikaSnapshot,
                                                    existingIDs: Set(paprikaStaged.compactMap(\.reminderID)).union(["existing"]))
        check(reimported.isEmpty,
              "re-import ignores already-linked Paprika reminder IDs: \(reimported.map { ($0.reminderID ?? "nil") + ":" + $0.grocery.name })")
        let multiTitle = PaprikaImportPlanner.stage(reminders: [PaprikaReminderSnapshot(id: "comma", title: "milk, bread", creationDate: nil)], existingIDs: [])
        check(multiTitle.map(\.grocery.name) == ["milk", "bread"] && multiTitle.map(\.reminderID) == ["comma", nil],
              "comma-separated reminder creates rows but only one reminder writeback owner")

        var queueStarted = false
        var unblockFirstWrite: CheckedContinuation<Void, Never>?
        var executedWrites: [ReminderWriteback] = []
        let writeQueue = ReminderWritebackQueue { write in
            executedWrites.append(write)
            if write.title == "Milk" {
                queueStarted = true
                await withCheckedContinuation { unblockFirstWrite = $0 }
            }
        }
        writeQueue.enqueue(ReminderWriteback(reminderID: "one", title: "Milk", isCompleted: false))
        while !queueStarted { await Task.yield() }
        writeQueue.enqueue(ReminderWriteback(reminderID: "one", title: "2 L Milk", isCompleted: false))
        writeQueue.enqueue(ReminderWriteback(reminderID: "one", title: "2 L Milk", isCompleted: true))
        unblockFirstWrite?.resume()
        while executedWrites.count < 2 { await Task.yield() }
        check(executedWrites.map(\.title) == ["Milk", "2 L Milk"] && executedWrites.last?.isCompleted == true,
              "Reminder writes serialize in-flight state then coalesce to newest desired state")
        writeQueue.enqueue(ReminderWriteback(reminderID: "two", title: "Bread", isCompleted: false))
        writeQueue.cancelQueued(reminderID: "two")
        await Task.yield()
        check(!executedWrites.contains { $0.reminderID == "two" }, "deleted reminder cancels queued write")

        check(StoreID.coles.ownsDataDomain(".coles.com.au"), "parent-domain cookie")
        check(StoreID.coles.ownsDataDomain("WWW.COLES.COM.AU"), "case-insensitive Coles host")
        check(!StoreID.coles.ownsDataDomain("notcoles.com.au"), "unrelated suffix")
        check(!StoreID.coles.ownsDataDomain("coles.com.au.evil.test"), "host suffix attack")

        var operation = SessionResetOperation()
        let first = operation.begin()!
        check(operation.phase == .resetting, "reset gates store")
        check(operation.begin() == nil, "double reset ignored")
        check(!operation.cancelFailure(), "cannot cancel in-flight WebKit deletion")
        check(!operation.complete(UUID(), verified: true), "stale completion rejected")
        check(operation.complete(first, verified: false), "verification failure accepted")
        check(operation.phase == .failed, "failure keeps store gated")
        let retry = operation.begin()!
        check(!operation.complete(first, verified: true), "old completion cannot finish retry")
        check(operation.complete(retry, verified: false), "retry can fail")
        check(operation.cancelFailure() && operation.phase == .ready, "Cancel permits fresh session")
        let success = operation.begin()!
        check(operation.complete(success, verified: true) && operation.phase == .ready, "verified reset enables store")
        check(!operation.complete(success, verified: false), "duplicate completion ignored")

        var now = Date(timeIntervalSince1970: 2_000_000)
        let memory = DiagnosticStore(fileURL: nil, clock: { now })
        memory.record(.store, .load, reason: .network, outcome: .failed, host: .www)
        memory.record(.store, .load, reason: .network, outcome: .failed, host: .www)
        check(memory.entries.count == 1, "identical diagnostics throttled")
        now += 59
        memory.record(.store, .load, reason: .network, outcome: .failed, host: .www)
        check(memory.entries.count == 1, "rolling throttle applies before 60 seconds")
        now += 1
        memory.record(.store, .load, reason: .network, outcome: .failed, host: .www)
        check(memory.entries.count == 2, "60-second boundary accepts entry")
        now += DiagnosticStore.lifetime - 60
        memory.purge()
        check(memory.entries.count == 1, "expiry includes exact 168-hour boundary")
        now += 60
        memory.purge()
        check(memory.entries.isEmpty, "all expired diagnostics purged")
        for _ in 0..<2_003 {
            now += 60
            memory.record(.automation, .cartUndo, outcome: .succeeded)
        }
        check(memory.entries.count == DiagnosticStore.countLimit, "diagnostic count cap")
        check(memory.byteCount <= DiagnosticStore.byteLimit, "diagnostic byte cap")
        check(memory.entries.first!.sequence < memory.entries.last!.sequence, "deterministic chronological eviction")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let exactBytes = try memory.entries.reduce(0) { try $0 + encoder.encode($1).count }
        check(memory.byteCount == exactBytes, "sorted-key UTF-8 byte accounting")
        let payload = try JSONSerialization.jsonObject(with: encoder.encode(memory.entries[0])) as! [String: Any]
        check(Set(payload.keys).isSubset(of: ["timestamp", "sequence", "category", "event", "reason", "outcome", "host"]), "diagnostic privacy whitelist")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ListRunnerRecoveryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnosticsURL = root.appendingPathComponent("diagnostics.json")
        let disk = DiagnosticStore(fileURL: diagnosticsURL, clock: { now })
        disk.record(.store, .load, outcome: .succeeded)
        check(DiagnosticStore(fileURL: diagnosticsURL, clock: { now }).entries.count == 1, "diagnostics survive relaunch")
        try disk.clear()
        try disk.clear()
        check(disk.entries.isEmpty && !FileManager.default.fileExists(atPath: diagnosticsURL.path), "clear is immediate and idempotent")
        disk.record(.store, .load, outcome: .succeeded, host: .www)
        disk.record(.store, .load, outcome: .succeeded, host: .woolworths)
        disk.record(.storage, .localSave, outcome: .failed)
        try disk.clear(storeID: .woolworths)
        check(disk.entries.count == 2 && !disk.entries.contains { $0.host == .woolworths }, "per-store diagnostics clear preserves other store and app records")

        let legacyURL = root.appendingPathComponent("legacy.store")
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: CommandLine.arguments[2])
        writer.arguments = [legacyURL.path]
        try writer.run(); writer.waitUntilExit()
        check(writer.terminationStatus == 0, "legacy database fixture written by original unversioned model")
        let migrated = try ShoppingLists.open(configuration: ModelConfiguration(url: legacyURL))
        let originalID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
        try ShoppingLists.prepare(migrated.mainContext, legacySelectedID: originalID)
        let migratedItems = try migrated.mainContext.fetch(FetchDescriptor<GroceryItem>())
        let migratedLists = try migrated.mainContext.fetch(FetchDescriptor<GroceryList>())
        check(migratedItems.count == 1 && migratedLists.count == 2, "legacy items retained with separate store lists")
        let original = migratedItems[0]
        check(original.id == originalID && original.listID == StoreID.coles.listID, "legacy UUID preserved in Coles list")
        check(original.name == "BBQ Sauce" && original.searchTerm == "BBQ Sauce" && original.quantityAmount == 2 && original.quantityUnit == "bottles", "legacy names and quantities preserved")
        check(original.status == .added && original.position == 7, "legacy status and position preserved")
        let colesList = migratedLists.first { $0.id == StoreID.coles.listID }!
        check(colesList.selectedItemID == originalID, "legacy selected item migrated")
        try ShoppingLists.prepare(migrated.mainContext, legacySelectedID: originalID)
        let listCount = try migrated.mainContext.fetchCount(FetchDescriptor<GroceryList>())
        check(listCount == 2, "list backfill is idempotent")
        let woolworthsItem = GroceryItem(name: "BBQ Sauce", position: 0, listID: StoreID.woolworths.listID)
        migrated.mainContext.insert(woolworthsItem)
        ShoppingLists.move(original, to: .woolworths, allItems: [original, woolworthsItem])
        check(original.id == originalID && original.status == .pending && original.position == 1, "explicit move preserves identity, marks Pending, appends")
        check(woolworthsItem.status == .pending && original.listID == StoreID.woolworths.listID, "move does not merge or edit existing destination item")
        try migrated.mainContext.save()

        let v2URL = root.appendingPathComponent("store-v2.store")
        let v2Writer = Process()
        v2Writer.executableURL = URL(fileURLWithPath: CommandLine.arguments[3])
        v2Writer.arguments = [v2URL.path]
        try v2Writer.run(); v2Writer.waitUntilExit()
        check(v2Writer.terminationStatus == 0, "multi-store v2 database fixture written")
        let v2Migrated = try ShoppingLists.open(configuration: ModelConfiguration(url: v2URL))
        let v2Items = try v2Migrated.mainContext.fetch(FetchDescriptor<GroceryItem>())
        let v2Lists = try v2Migrated.mainContext.fetch(FetchDescriptor<GroceryList>())
        check(v2Items.count == 1 && v2Lists.count == 1, "multi-store v2 database migrates to Paprika schema")
        check(v2Items[0].id == UUID(uuidString: "40000000-0000-4000-8000-000000000001")! && v2Items[0].paprikaReminderID == nil,
              "v2 item identity is retained and reminder link defaults to nil")
        check(v2Items[0].name == "2L milk" && v2Items[0].quantityAmount == 2 && v2Items[0].quantityUnit == "l" && v2Items[0].status == .added && v2Items[0].position == 4,
              "v2 grocery fields survive Paprika schema migration")
        check(v2Lists[0].selectedItemID == v2Items[0].id && v2Lists[0].lastActiveDay == "2026-10-21",
              "v2 store-list metadata survives Paprika schema migration")

        let suiteName = "ListRunnerRecoveryTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("saved-selection", forKey: "lastOverlaySelectedItemID")
        defaults.set("keep", forKey: "unrelated")
        let url = root.appendingPathComponent("test.store")
        let unrelatedFile = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelatedFile)
        let config = ModelConfiguration(url: url)
        let preserved = Data("unreadable-store-sentinel".utf8)
        try preserved.write(to: url)
        enum InjectedFailure: Error { case unavailable }
        var allowOpen = false
        let storage = LocalDataController(configuration: config, diagnostics: disk, defaults: defaults) { configuration in
            guard allowOpen else { throw InjectedFailure.unavailable }
            return try ShoppingLists.open(configuration: configuration)
        }
        check(storage.container == nil, "failed store open routes to recovery")
        let afterFailedOpen = try Data(contentsOf: url)
        check(afterFailedOpen == preserved, "failed open does not silently replace store")
        storage.open()
        let afterRetry = try Data(contentsOf: url)
        check(afterRetry == preserved, "Retry preserves unreadable data")
        try Data("old-wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("old-shm".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))
        allowOpen = true
        storage.resetAfterConfirmation()
        check(storage.container != nil, "confirmed local reset opens an empty store")
        let emptyCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(emptyCount == 0, "reset store contains no items")
        check(defaults.string(forKey: "lastOverlaySelectedItemID") == nil, "local reset clears app metadata")
        check(defaults.string(forKey: "unrelated") == "keep", "local reset preserves unrelated preferences")
        check(FileManager.default.fileExists(atPath: unrelatedFile.path), "local reset preserves neighboring files")
        check(disk.entries.isEmpty, "local reset clears diagnostics")
        let item = GroceryItem(name: "Test item", position: 0)
        storage.container!.mainContext.insert(item)
        try storage.container!.mainContext.save()
        storage.resetAfterConfirmation()
        let healthyCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(healthyCount == 1, "healthy open database cannot be reset through recovery")
        let fromItem = GroceryItem(name: "First", position: 0, listID: StoreID.coles.listID)
        let nextItem = GroceryItem(name: "Next", position: 1, listID: StoreID.coles.listID)
        check(ShoppingLists.selection(afterRemoving: fromItem.id, from: [fromItem, nextItem]) == nextItem.id, "deletion/move selection uses next Pending row")
        nextItem.status = .added
        check(ShoppingLists.selection(afterRemoving: nextItem.id, from: [fromItem, nextItem]) == fromItem.id, "selection fallback wraps to Pending")
        check(ShoppingLists.selection(afterRemoving: fromItem.id, from: [fromItem]) == nil, "empty-list selection cleared")

        var retryCanOpen = false
        let retryStorage = LocalDataController(configuration: ModelConfiguration(isStoredInMemoryOnly: true), diagnostics: memory, defaults: defaults) { configuration in
            guard retryCanOpen else { throw InjectedFailure.unavailable }
            return try ShoppingLists.open(configuration: configuration)
        }
        check(retryStorage.container == nil, "transient open failure shows recovery")
        retryCanOpen = true
        retryStorage.open()
        check(retryStorage.container != nil, "Retry can recover without resetting data")

        let website = WKWebsiteDataStore.nonPersistent()
        func cookie(_ domain: String, _ name: String) -> HTTPCookie {
            HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: "test"] )!
        }
        await website.httpCookieStore.setCookie(cookie(".coles.com.au", "coles-test"))
        await website.httpCookieStore.setCookie(cookie("example.com", "unrelated-test"))
        await website.httpCookieStore.setCookie(cookie(".woolworths.com.au", "woolworths-test"))
        let cleared = await StoreWebsiteData.clear(in: website, for: .coles)
        check(cleared, "real nonpersistent WebKit deletion verifies success")
        let remaining = await website.httpCookieStore.allCookies()
        check(!remaining.contains { StoreID.coles.ownsDataDomain($0.domain) }, "Coles cookies removed")
        check(remaining.contains { $0.name == "unrelated-test" }, "unrelated website cookies preserved")
        check(remaining.contains { $0.name == "woolworths-test" }, "Coles reset preserves Woolworths cookies")
        let clearedWoolworths = await StoreWebsiteData.clear(in: website, for: .woolworths)
        check(clearedWoolworths, "Woolworths reset verifies its own data scope")
        let afterWoolworths = await website.httpCookieStore.allCookies()
        check(afterWoolworths.contains { $0.name == "unrelated-test" } && !afterWoolworths.contains { $0.name == "woolworths-test" }, "Woolworths reset preserves unrelated domains")
        let finalCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(finalCount == 1, "Coles reset leaves groceries unchanged")
        check(defaults.string(forKey: "unrelated") == "keep", "Coles reset leaves app preferences unchanged")
        print("PASS: \(checks) native recovery, reset-boundary and diagnostics checks")
    }
}
