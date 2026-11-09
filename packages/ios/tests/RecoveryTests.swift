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
        let addData = try ShoppingLists.open(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let addContext = addData.mainContext
        addContext.autosaveEnabled = false
        let otherStoreItem = GroceryItem(name: "milk", amount: 9, position: 0, listID: StoreID.woolworths.listID)
        addContext.insert(otherStoreItem)
        try addContext.save()
        let addedRows = ShoppingLists.stageAdd([ParsedGrocery(name: "milk", amount: 2, unit: nil),
                                               ParsedGrocery(name: "bread", amount: nil, unit: nil),
                                               ParsedGrocery(name: "milk", amount: 3, unit: nil)],
                                               to: .coles, allItems: [otherStoreItem], context: addContext)
        check(addedRows.count == 2 && addedRows[0].name.lowercased() == "milk" && addedRows[0].quantityAmount == 5
              && addedRows[1].position == 1 && otherStoreItem.quantityAmount == 9,
              "shared manual add merges only within destination, preserves batch order and does not duplicate promoted rows")
        let measuredRows = ShoppingLists.stageAdd([ParsedGrocery(name: "bread", amount: 2, unit: "kg")],
                                                  to: .coles, allItems: addedRows + [otherStoreItem], context: addContext)
        check(measuredRows.count == 1 && measuredRows[0].quantityAmount == 2 && measuredRows[0].quantityUnit == "kg",
              "reactivating an unspecified quantity preserves the newly parsed unit")
        addContext.rollback()
        let remainingAddRows = try addContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(remainingAddRows == 1,
              "failed manual-add transaction can roll back without changing another store")
        let manualNames = ["500 g penne pasta", "Firm tofu thinly sliced", "2 eggs"]
        let manualRows = ShoppingLists.stageAdd(ParsedGrocery.productEntries(in: manualNames.joined(separator: "; ")),
                                                to: .coles, allItems: [otherStoreItem], context: addContext)
        check(manualRows.map(\.name) == manualNames && manualRows.map(\.searchTerm) == manualNames,
              "manual additions retain complete literal names and search terms in input order")
        check(manualRows.allSatisfy { $0.quantityAmount == nil && $0.quantityUnit == nil && $0.displayQuantity == "1" },
              "manual additions do not infer amounts or units from product wording")
        manualRows[0].status = .added
        let repeatedRows = ShoppingLists.stageAdd(ParsedGrocery.productEntries(in: "500 g penne pasta"),
                                                  to: .coles, allItems: manualRows + [otherStoreItem], context: addContext)
        check(repeatedRows.count == 1 && repeatedRows[0].id == manualRows[0].id && repeatedRows[0].status == .pending,
              "literal manual duplicates still reactivate the destination's existing row")
        try addContext.save()
        let savedManualRows = try addContext.fetch(FetchDescriptor<GroceryItem>()).filter { $0.listID == StoreID.coles.listID }
        check(savedManualRows.count == 3 && savedManualRows.allSatisfy { manualNames.contains($0.name) && $0.searchTerm == $0.name },
              "saved manual names and search terms are not rewritten by persistence")
        check(otherStoreItem.quantityAmount == 9 && otherStoreItem.name == "milk",
              "literal manual additions leave other stores unchanged")
        let firstID = UUID(), secondID = UUID(), thirdID = UUID()
        let initialOrder = ItemPromotionOrder.promoting([firstID, secondID], in: "", existing: [firstID, secondID, thirdID])
        let updatedOrder = ItemPromotionOrder.promoting([thirdID, firstID], in: initialOrder,
                                                       existing: [firstID, secondID, thirdID])
        check(ItemPromotionOrder.ranks(updatedOrder) == [thirdID: 0, firstID: 1, secondID: 2],
              "cross-store promotion retains actual recent batch order and deduplicates existing rows")
        check(ItemPromotionOrder.ranks(ItemPromotionOrder.promoting([], in: updatedOrder, existing: [secondID])) == [secondID: 0],
              "deleted rows are pruned from sidecar ranks without assigning historical dates")
        check(ShoppingCountry.validated("au") == "AU", "country preferences normalize ISO codes")
        for code in [nil, "", "ZZ", "Australia", "123"] as [String?] {
            check(ShoppingCountry.validated(code) == nil, "invalid/missing region suggestions do not guess a country")
        }
        let configData = try Data(contentsOf: resources.appendingPathComponent("coles.json"))
        let coles = try JSONDecoder().decode(StoreDefinition.self, from: configData)
        func resultsConfig(_ fields: [String: Any]) throws -> StoreDefinition {
            var root = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
            var search = root["search"] as! [String: Any]
            search.removeValue(forKey: "resultsSelector")
            search.removeValue(forKey: "resultsTopOffset")
            search.merge(fields) { _, new in new }
            root["search"] = search
            return try StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: root))
        }
        let legacyResultsConfig = try resultsConfig([:])
        check(legacyResultsConfig.search.resultsSelector == nil && legacyResultsConfig.isConfigurationValid,
              "old definitions need no results targeting or version bump")
        for fields in [
            ["resultsSelector": ".grid"],
            ["resultsSelector": ".grid", "resultsTopOffset": 0],
            ["resultsSelector": ".grid", "resultsTopOffset": 120.5],
            ["resultsSelector": ".grid", "resultsTopOffset": 500]
        ] as [[String: Any]] {
            let definition = try resultsConfig(fields)
            check(definition.isConfigurationValid, "optional results target passes strict native decoding")
        }
        for fields in [
            ["resultsSelector": ""], ["resultsSelector": "  "],
            ["resultsSelector": String(repeating: "é", count: 513)],
            ["resultsSelector": true], ["resultsTopOffset": 12],
            ["resultsSelector": ".grid", "resultsTopOffset": -1],
            ["resultsSelector": ".grid", "resultsTopOffset": 501],
            ["resultsSelector": ".grid", "resultsTopOffset": true],
            ["resultsSelector": ".grid", "resultsTopOffset": "120"],
            ["unknownResultsField": ".grid"]
        ] as [[String: Any]] {
            do { _ = try resultsConfig(fields); check(false, "invalid results config must throw") }
            catch { check(true, "invalid results config rejected") }
        }
        let woolworths = try JSONDecoder().decode(StoreDefinition.self, from: Data(contentsOf: resources.appendingPathComponent("woolworths.json")))
        let bunnings = try JSONDecoder().decode(StoreDefinition.self, from: Data(contentsOf: resources.appendingPathComponent("bunnings.json")))
        check(coles.schemaVersion == 7 && coles.category == .grocery && coles.categories.isEmpty,
              "Coles schema-7 single category decodes as typed metadata")
        var schema6Object = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
        schema6Object["schemaVersion"] = 6
        schema6Object.removeValue(forKey: "category")
        schema6Object["categories"] = ["grocery", "pharmacyBeauty", "petSupplies"]
        let schema6Data = try JSONSerialization.data(withJSONObject: schema6Object)
        let schema6 = try StoreDefinition.decodeConfiguration(from: schema6Data)
        for invalidCategory in ["departmentStore", "warehouseClub"] {
            var invalid = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
            invalid["category"] = invalidCategory
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: invalid))) == nil,
                  "schema 7 rejects legacy-only categories just like the onboarding validator")
        }
        for futureCategory in ["groceryHome", "clothingHome", "homeFurniture"] {
            var invalid = schema6Object
            invalid["categories"] = [futureCategory]
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: invalid))) == nil,
                  "schema 6 retains its original category vocabulary")
        }
        check(schema6.schemaVersion == 6 && schema6.category == nil && schema6.categories.count == 3,
              "legacy schema-6 category arrays remain readable without choosing an implicit primary category")
        var missingCategory = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
        missingCategory.removeValue(forKey: "category")
        check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: missingCategory))) == nil,
              "schema 7 requires one category")
        var missingCategories = schema6Object
        missingCategories.removeValue(forKey: "categories")
        check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: missingCategories))) == nil,
              "schema 6 requires categories")
        var missingAutomationVersion = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
        missingAutomationVersion.removeValue(forKey: "automationSchemaVersion")
        check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: missingAutomationVersion))) == nil,
              "schema 6 requires its compatibility automation version")
        for version in [1, 6, 99] {
            var object = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
            object["automationSchemaVersion"] = version
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "schema 6 rejects unsupported automation version \(version)")
        }
        let invalidCategories: [Any] = [NSNull(), [], ["grocery", "grocery"], ["unknown"], ["Grocery"], [" grocery"], [1], ["grocery", NSNull()]]
        for categories in invalidCategories {
            var object = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
            object["category"] = categories
            let invalid = try JSONSerialization.data(withJSONObject: object)
            check((try? StoreDefinition.decodeConfiguration(from: invalid)) == nil,
                  "schema-7 rejects malformed category values")
            check((try? JSONDecoder().decode(StoreDefinition.self, from: invalid)) == nil,
                  "direct Codable decoding also rejects malformed category values")
        }
        let legacyDefinitions: [(StoreDefinition, Int)] = [(bunnings, 2),
            (try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("kmart.json"))), 3),
            (try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("waitrose.json"))), 4),
            (try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("ikeaAU.json"))), 5)]
        for (current, legacyVersion) in legacyDefinitions {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as! [String: Any]
            object["schemaVersion"] = legacyVersion
            object.removeValue(forKey: "categories")
            object.removeValue(forKey: "category")
            object.removeValue(forKey: "automationSchemaVersion")
            let legacyData = try JSONSerialization.data(withJSONObject: object)
            let legacy = try StoreDefinition.decodeConfiguration(from: legacyData)
            check(legacy.schemaVersion == legacyVersion && legacy.categories.isEmpty && legacy.isConfigurationValid,
                  "legacy schema \(legacyVersion) remains valid with unknown categories")
            let encoded = try JSONEncoder().encode(legacy)
            let encodedObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            check(encodedObject["categories"] == nil,
                  "legacy schema \(legacyVersion) encoding preserves the old wire contract")
            var forbidden = encodedObject
            forbidden["categories"] = ["grocery"]
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: forbidden))) == nil,
                  "legacy schema \(legacyVersion) cannot smuggle schema-6 categories")
            var forbiddenAutomation = encodedObject
            forbiddenAutomation["automationSchemaVersion"] = legacyVersion
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: forbiddenAutomation))) == nil,
                  "legacy schema \(legacyVersion) cannot add a schema-6 compatibility field")
        }
        let bunningsAuthorization = URL(string: "https://authorisation.api.bunnings.com.au/connect/authorize")!
        check(bunnings.allowsNavigation(bunningsAuthorization), "Bunnings silent authorization frame can establish its website cart session")
        check(!bunnings.allows(bunningsAuthorization)
              && !bunnings.allowedHosts.contains("authorisation.api.bunnings.com.au"),
              "Bunnings authorization is browsing-only, never an automation/bridge origin")
        check(!coles.allowsNavigation(bunningsAuthorization) && !woolworths.allowsNavigation(bunningsAuthorization),
              "other retailers cannot inherit Bunnings authentication navigation")
        for raw in ["http://authorisation.api.bunnings.com.au/connect/authorize",
                    "https://authorisation.api.bunnings.com.au:444/connect/authorize",
                    "https://user:secret@authorisation.api.bunnings.com.au/connect/authorize",
                    "https://authorisation.api.bunnings.com.au.attacker.example/connect/authorize",
                    "https://other.api.bunnings.com.au/connect/authorize",
                    "https://8847090.fls.doubleclick.net/activityi"] {
            check(!bunnings.allowsNavigation(URL(string: raw)!), "Bunnings auth exception stays exact, HTTPS-only and credential-free")
        }
        check(StoreID.bunnings.ownsDataDomain("authorisation.api.bunnings.com.au")
              && !StoreID.coles.ownsDataDomain("authorisation.api.bunnings.com.au"),
              "Bunnings authorization website data remains in the existing Bunnings reset boundary")
        let costco = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("costco.json")))
        let tesco = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("tesco.json")))
        let walmart = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("walmart.json")))
        let kmart = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("kmart.json")))
        let bigW = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("bigW.json")))
        let costcoUS = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("costcoUS.json")))
        check(costcoUS.serviceArea.countryCodes == ["US"] && !costcoUS.capabilities.search
              && !costcoUS.capabilities.cartDetection && !costcoUS.capabilities.cartUndo && costcoUS.cart == nil,
              "Costco US is browsing-only, independent of Australia's search support")
        var widenedUS = costcoUS
        widenedUS.capabilities.search = true
        check(!widenedUS.isConfigurationValid, "US Costco JSON cannot inherit Australia's automatic search capability")
        check(!costcoUS.allowsNavigation(URL(string: "https://auth.colesgroupprofile.com.au")!)
              && !costcoUS.allows(URL(string: "https://login.costco.com")!), "US Costco cannot inherit unrelated or unreviewed login exceptions")
        check(!StoreID.costcoUS.permitsSearch && !StoreID.costcoUS.permitsCartDetection && !StoreID.costcoUS.permitsCartUndo,
              "Costco US native automation ceilings remain closed")
        check(!costcoUS.allows(costco.homepage) && !costco.allows(costcoUS.homepage)
              && costcoUS.id.listID != costco.id.listID && costcoUS.id.websiteDataID != costco.id.websiteDataID,
              "Costco regions cannot share hosts, lists or website-data identities")
        let brandDefinitions = [coles, woolworths, bunnings, costco, costcoUS, tesco, walmart, kmart, bigW]
        let amazon = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("amazon.json")))
        let kroger = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("kroger.json")))
        let target = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("target.json")))
        let usDefinitions = [amazon, costcoUS, kroger, target, walmart]
        let expandedDefinitions = brandDefinitions + [amazon, kroger, target]
        let expansionIDs: [StoreID] = [.chemistWarehouse, .priceline, .officeworks, .jbHiFi, .targetAU,
            .petbarn, .supercheapAuto, .bcf, .bunningsNZ, .theWarehouse, .newWorld, .paknsave,
            .sainsburys, .asda, .morrisons, .ocado, .waitrose, .boots, .walgreens, .cvs]
        let expansionDefinitions = try expansionIDs.map {
            try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent($0.rawValue + ".json")))
        }
        let ikea = try StoreDefinition.decodeConfiguration(from: Data(contentsOf: resources.appendingPathComponent("ikeaAU.json")))
        let allProductionDefinitions = expandedDefinitions + expansionDefinitions + [ikea]
        check(ikea.isConfigurationValid && ikea.serviceArea.countryCodes == ["AU"] && ikea.id == .ikeaAU,
              "IKEA AU has its own reviewed registration")
        check(ikea.capabilities.search && ikea.capabilities.cartDetection && ikea.capabilities.cartUndo
              && StoreID.ikeaAU.permitsSearch && StoreID.ikeaAU.permitsCartDetection && StoreID.ikeaAU.permitsCartUndo,
              "IKEA independently verified search, exact-article detection and retailer Undo are enabled in JSON and native policy")
        check(ikea.id.home == ikea.homepage && ikea.id.listID.uuidString.hasSuffix("000033")
              && ikea.id.websiteDataID.uuidString.hasSuffix("000033"), "IKEA fallback and stable identities stay Australian")
        check(ikea.cart?.strategy == .verifiedCartSnapshot && ikea.cart?.profiles?.count == 2,
              "IKEA grid and detail opt into the separately bundled cart snapshot engine")
        check(ikea.acceptsProductIdentity("00428484") && !ikea.acceptsProductIdentity("428484")
              && !ikea.acceptsProductIdentity("004.284.84"), "IKEA keeps exact eight-digit article IDs, including leading zeroes")
        check(ikea.allows(URL(string: "https://www.ikea.com/au/en/search/?q=spoon")!)
              && ikea.allows(URL(string: "https://ikea.com/au/en/p/dragon-spoon-40515525/")!), "IKEA accepts exact Australian HTTPS URLs")
        for raw in ["https://www.ikea.com/us/en/", "https://www.ikea.com/au/enough/", "https://www.ikea.com/",
                    "http://www.ikea.com/au/en/", "https://www.ikea.com:444/au/en/",
                    "https://user:password@www.ikea.com/au/en/", "https://www.ikea.com.evil.test/au/en/",
                    "https://login.ikea.com/au/en/", "https://www.ikea.com/au/en/../../us/en/",
                    "https://www.ikea.com/au/en/%2e%2e/us/en/", "https://www.ikea.com/au/en/%252e%252e/us/en/",
                    "https://www.ikea.com/au/en/%2f..%2fus/en/"] {
            check(!ikea.allows(URL(string: raw)!) && !ikea.allowsNavigation(URL(string: raw)!), "IKEA locale and origin boundaries fail closed")
        }
        check(ikea.searchURL(for: "table & café + #?")?.query?.contains("q=table") == true
              && ikea.searchURL(for: "table & café + #?")?.fragment == nil, "IKEA searches encode query values safely")
        for change in ["strategy", "path", "unknown"] {
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("ikeaAU.json"))) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            if change == "strategy" { cart["strategy"] = "profiled" }
            else {
                var snapshot = cart["snapshot"] as! [String: Any]
                snapshot[change == "path" ? "path" : "script"] = "/us/en/shoppingcart/"
                cart["snapshot"] = snapshot
            }
            object["cart"] = cart
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "IKEA snapshot contract rejects incompatible engines, foreign locales and unknown keys")
        }
        check(allProductionDefinitions.count == 33
              && allProductionDefinitions.allSatisfy { $0.schemaVersion == 7 && $0.category != nil && $0.isConfigurationValid },
              "all 33 production destinations use valid schema-7 categories")
        for definition in allProductionDefinitions {
            let roundTrip = try StoreDefinition.decodeConfiguration(from: JSONEncoder().encode(definition))
            check(roundTrip.id == definition.id && roundTrip.categories == definition.categories
                  && roundTrip.category == definition.category
                   && roundTrip.automationSchemaVersion == definition.automationSchemaVersion,
                   "every definition round-trips, including stores with a null cart")
        }
        let persistentProbeID = UUID(uuidString: "0BDE339A-A800-4D62-B5BC-17838D7B3823")!
        let persistentProbeEnvironment = ["LISTRUNNER_UI_TEST_SESSION": persistentProbeID.uuidString,
            "LISTRUNNER_LIVE_CART_PROBE": "officeworks", "LISTRUNNER_LIVE_PERSISTENT_PROBE": "officeworks"]
        check(StoreProbeIsolation.persistentIdentifier(for: .officeworks, environment: persistentProbeEnvironment) == persistentProbeID,
              "Officeworks persistent probe resolves only its isolated test namespace")
        check(StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: true, identifier: persistentProbeID,
                                                  environment: persistentProbeEnvironment), "exact isolated persistent probe can observe its prospective profile")
        check(!StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: true, identifier: nil,
                                                   environment: persistentProbeEnvironment), "default persistent store cannot receive probe capabilities")
        check(!StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: true, identifier: UUID(),
                                                   environment: persistentProbeEnvironment), "unrelated named store cannot receive probe capabilities")
        for key in persistentProbeEnvironment.keys {
            var environment = persistentProbeEnvironment; environment.removeValue(forKey: key)
            check(StoreProbeIsolation.persistentIdentifier(for: .officeworks, environment: environment) == nil
                  && !StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: true, identifier: persistentProbeID, environment: environment),
                  "persistent probe requires every explicit gate: \(key)")
        }
        for raw in ["invalid", "00000000-0000-0000-0000-000000000000"] {
            var environment = persistentProbeEnvironment; environment["LISTRUNNER_UI_TEST_SESSION"] = raw
            check(StoreProbeIsolation.persistentIdentifier(for: .officeworks, environment: environment) == nil,
                  "persistent probe rejects invalid or zero identifiers")
        }
        for id in StoreID.allCases {
            if id != .officeworks {
                var environment = persistentProbeEnvironment
                environment["LISTRUNNER_LIVE_CART_PROBE"] = id.rawValue
                environment["LISTRUNNER_LIVE_PERSISTENT_PROBE"] = id.rawValue
                check(StoreProbeIsolation.persistentIdentifier(for: id, environment: environment) == nil
                      && !StoreProbeIsolation.permitsCartProbe(for: id, isPersistent: true, identifier: persistentProbeID, environment: environment),
                      "persistent experiment cannot silently expand to another retailer")
            }
            for identifier in [id.websiteDataID, id.listID] {
                var environment = persistentProbeEnvironment; environment["LISTRUNNER_UI_TEST_SESSION"] = identifier.uuidString
                check(StoreProbeIsolation.persistentIdentifier(for: .officeworks, environment: environment) == nil
                      && !StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: true, identifier: identifier, environment: environment),
                      "persistent experiment rejects every canonical website/list identifier")
            }
        }
        var ephemeralProbeEnvironment = persistentProbeEnvironment; ephemeralProbeEnvironment.removeValue(forKey: "LISTRUNNER_LIVE_PERSISTENT_PROBE")
        check(StoreProbeIsolation.permitsCartProbe(for: .officeworks, isPersistent: false, identifier: nil, environment: ephemeralProbeEnvironment),
              "ordinary live probes remain nonpersistent with their original two explicit gates")
        let bunningsNZ = expansionDefinitions.first { $0.id == .bunningsNZ }!
        let nzAuthorization = URL(string: "https://authorisation.api.bunnings.co.nz/connect/authorize")!
        check(bunningsNZ.allowsNavigation(nzAuthorization)
              && bunningsNZ.allowsNavigation(URL(string: "https://authorisation.api.bunnings.co.nz:443/connect/authorize")!),
              "Bunnings NZ observed silent authorization frame permits HTTPS/default port browsing")
        check(!bunningsNZ.allows(nzAuthorization)
              && !bunningsNZ.allowedHosts.contains("authorisation.api.bunnings.co.nz"),
              "Bunnings NZ auth is never an automation or bridge origin")
        check(!bunnings.allowsNavigation(nzAuthorization) && !bunningsNZ.allowsNavigation(bunningsAuthorization),
              "AU and NZ authentication exceptions stay region-isolated")
        for definition in allProductionDefinitions where definition.id != .bunningsNZ {
            check(!definition.allowsNavigation(nzAuthorization), "NZ auth does not extend another retailer's browsing trust")
        }
        for raw in ["http://authorisation.api.bunnings.co.nz/connect/authorize",
                    "https://authorisation.api.bunnings.co.nz:444/connect/authorize",
                    "https://user:secret@authorisation.api.bunnings.co.nz/connect/authorize",
                    "https://authorisation.api.bunnings.co.nz.evil.test/connect/authorize",
                    "https://login.bunnings.co.nz/connect/authorize"] {
            check(!bunningsNZ.allowsNavigation(URL(string: raw)!), "NZ auth exception rejects insecure and unreviewed navigation")
        }
        check(StoreID.bunningsNZ.ownsDataDomain("authorisation.api.bunnings.co.nz")
              && !StoreID.bunnings.ownsDataDomain("authorisation.api.bunnings.co.nz"),
              "NZ authorization data belongs only to the NZ session reset boundary")
        check(expansionDefinitions.count == 20 && Set(allProductionDefinitions.map(\.id)) == Set(StoreID.allCases),
              "all twenty additions and every legacy store have a canonical validated resource")
        check(StoreBrand.catalogue(allProductionDefinitions).count == 31,
               "33 regional destinations form 31 brands with isolated Costco and Bunnings regions")
        let hiddenShoppingIDs: Set<StoreID> = [.amazon, .costcoUS, .newWorld, .paknsave, .boots, .cvs]
        check(Set(allProductionDefinitions.filter { !$0.isAvailableForShopping }.map(\.id)) == hiddenShoppingIDs,
               "only destinations without verified search are hidden, without deleting registrations")
        let shoppingAvailability = StoreShoppingAvailability(definitions: allProductionDefinitions)
        check(shoppingAvailability.availableIDs == Set(StoreID.allCases).subtracting(hiddenShoppingIDs),
              "one immutable registry snapshot preserves fully validated shopping eligibility")
        for enabled in [Set<StoreID>(), [.coles], [.coles, .amazon, .costcoUS], Set(StoreID.allCases)] {
            check(shoppingAvailability.visibleIDs(in: enabled)
                  == Set(allProductionDefinitions.filter(\.isAvailableForShopping).map(\.id)).intersection(enabled),
                  "cached eligibility follows every current enabled set without changing saved visibility")
        }
        var disabledColes = coles
        disabledColes.capabilities.search = false
        let replacedAvailability = StoreShoppingAvailability(definitions: [disabledColes])
        check(replacedAvailability.availableIDs.isEmpty && shoppingAvailability.availableIDs.contains(.coles),
              "a replacement registry is revalidated without mutating the original snapshot")
        var malformedColes = coles
        malformedColes.capabilities.cartDetection = false
        malformedColes.capabilities.cartUndo = true
        check(StoreShoppingAvailability(definitions: [malformedColes]).availableIDs.isEmpty,
              "availability snapshots never bypass malformed configuration or native capability policy")
        check(StoreCatalogue.ordered(allProductionDefinitions, countryCode: nil).count == 27
               && StoreBrand.sections(allProductionDefinitions, countryCode: nil, search: "").flatMap(\.brands).count == 26,
                "shopping catalogue has 27 verified destinations grouped into 26 brands")
        for country in [nil, "AU", "US", "NZ", "GB"] as [String?] {
            let stores = StoreCatalogue.sections(allProductionDefinitions, countryCode: country).flatMap(\.stores)
            let brands = StoreBrand.sections(allProductionDefinitions, countryCode: country, search: "",
                                             enabledIDs: Set(StoreID.allCases)).flatMap(\.brands)
            check(Set(stores.map(\.id)).isDisjoint(with: hiddenShoppingIDs)
                  && Set(brands.flatMap(\.regions).map(\.id)).isDisjoint(with: hiddenShoppingIDs),
                  "hidden stores cannot reappear via enabled or country groups")
            for id in hiddenShoppingIDs {
                let name = allProductionDefinitions.first { $0.id == id }!.displayName
                check(StoreCatalogue.sections(allProductionDefinitions, countryCode: country, search: name).isEmpty
                      && StoreBrand.sections(allProductionDefinitions, countryCode: country, search: name).isEmpty,
                      "hidden destinations cannot reappear through exact-name search")
            }
        }
        let availabilitySuite = "ListRunner.Availability.\(UUID().uuidString)"
        let availabilityDefaults = UserDefaults(suiteName: availabilitySuite)!
        defer { availabilityDefaults.removePersistentDomain(forName: availabilitySuite) }
        let previouslyEnabled = hiddenShoppingIDs.union([.coles])
        availabilityDefaults.set(StoreID.allCases.map(\.rawValue), forKey: "knownStoreIDs.v1")
        availabilityDefaults.set(previouslyEnabled.map(\.rawValue).sorted(), forKey: "visibleStoreIDs.v1")
        availabilityDefaults.set(["costco": "costcoUS"], forKey: "storeRegionalChoices.v1")
        availabilityDefaults.set("costcoUS", forKey: "activeStoreID")
        let retainedData = try ShoppingLists.open(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        let retainedItem = GroceryItem(name: "Saved Tesco item", amount: 2, position: 3, listID: StoreID.tesco.listID)
        retainedItem.status = .added
        retainedData.mainContext.insert(retainedItem); try retainedData.mainContext.save()
        let availability = StoreVisibilityPreferences(defaults: availabilityDefaults, suggestedCountryCode: "US")
        check(availability.shoppingVisibleIDs(in: allProductionDefinitions) == [.coles] && availability.visibleIDs == previouslyEnabled,
              "effective visibility hides unsupported enabled stores without rewriting saved visibility")
        var disabledSearchConfiguration = coles
        disabledSearchConfiguration.capabilities.search = false
        check(availability.shoppingVisibleIDs(in: [disabledSearchConfiguration]).isEmpty
              && availability.selectionForList(current: .coles, definitions: [disabledSearchConfiguration]) == nil,
              "a native search ceiling alone cannot expose a loaded definition with search disabled")
        check(availability.selectionForList(current: .costcoUS, definitions: allProductionDefinitions) == .coles,
              "a hidden active region falls back to an available enabled store, never its sibling")
        check(availability.regionalChoices["costco"] == "costcoUS"
              && availabilityDefaults.string(forKey: "activeStoreID") == "costcoUS"
              && Set(availabilityDefaults.stringArray(forKey: "visibleStoreIDs.v1") ?? []) == Set(previouslyEnabled.map(\.rawValue)),
              "selection resolution preserves stored region, active preference and enabled flags until the UI explicitly changes selection")
        let disableGuardSuite = "ListRunner.StoreDisableGuard.\(UUID().uuidString)"
        let disableGuardDefaults = UserDefaults(suiteName: disableGuardSuite)!
        defer { disableGuardDefaults.removePersistentDomain(forName: disableGuardSuite) }
        disableGuardDefaults.set(StoreID.allCases.map(\.rawValue), forKey: "knownStoreIDs.v1")
        disableGuardDefaults.set([StoreID.coles.rawValue, StoreID.costco.rawValue], forKey: "visibleStoreIDs.v1")
        disableGuardDefaults.set(["costco": StoreID.costco.rawValue], forKey: "storeRegionalChoices.v1")
        let disableGuard = StoreVisibilityPreferences(defaults: disableGuardDefaults)
        disableGuard.updateNonEmptyListIDs(Set([StoreID.coles.listID, StoreID.costco.listID]))
        check(!disableGuard.setVisible(false, for: .coles) && disableGuard.visibleIDs.contains(.coles),
              "a nonempty store list blocks direct destination disabling without changing visibility")
        let guardCostco = StoreBrand.catalogue(allProductionDefinitions).first { $0.id == "costco" }!
        check(!disableGuard.setBrandVisible(false, brand: guardCostco)
              && disableGuard.visibleIDs.contains(.costco)
              && !disableGuard.chooseRegion(.costcoUS, for: guardCostco)
              && disableGuard.visibleIDs.contains(.costco)
              && disableGuard.regionalChoices["costco"] == StoreID.costco.rawValue,
              "nonempty regional list blocks brand disable and region replacement without rewriting the saved choice")
        check(disableGuard.chooseRegion(.costco, for: guardCostco),
              "reselecting the enabled region does not disable its nonempty list")
        disableGuard.listItemCountsProvider = { throw StoreDefinition.ConfigurationError.invalid }
        check(!disableGuard.setVisible(false, for: .coles) && disableGuard.visibleIDs.contains(.coles)
              && disableGuard.listLookupFailed,
              "failed saved-row lookup fails closed instead of disabling a store")
        disableGuard.listItemCountsProvider = { [StoreID.coles.listID: 1] }
        check(!disableGuard.setVisible(false, for: .coles), "fresh saved-row lookup overrides an earlier empty snapshot")
        disableGuard.listItemCountsProvider = { [:] }
        check(disableGuard.setVisible(false, for: .coles) && !disableGuard.visibleIDs.contains(.coles),
              "explicit disable succeeds after all affected rows are successfully removed")
        let availableCostco = StoreBrand.sections(allProductionDefinitions, countryCode: "US", search: "Costco").flatMap(\.brands).first!
        disableGuardDefaults.set([StoreID.costcoUS.rawValue], forKey: "visibleStoreIDs.v1")
        disableGuardDefaults.set(["costco": StoreID.costco.rawValue], forKey: "storeRegionalChoices.v1")
        let hiddenRegionGuard = StoreVisibilityPreferences(defaults: disableGuardDefaults)
        hiddenRegionGuard.updateNonEmptyListIDs([StoreID.costcoUS.listID])
        check(!hiddenRegionGuard.setBrandVisible(true, brand: availableCostco)
              && !hiddenRegionGuard.chooseRegion(.costco, for: availableCostco)
              && hiddenRegionGuard.visibleIDs.contains(.costcoUS),
              "enabling/replacing an available region cannot silently disable a populated hidden sibling")
        check(availableCostco.regions.map(\.id) == [.costco] && !availableCostco.isRegional
              && availability.selectedRegion(for: availableCostco).id == .costco
              && availability.regionalChoices["costco"] == "costcoUS",
              "Costco AU is offered without exposing US or silently changing the saved regional preference")
        availability.setVisible(false, for: .coles)
        let hiddenOnly = StoreVisibilityPreferences(defaults: availabilityDefaults)
        check(hiddenOnly.shoppingVisibleIDs(in: allProductionDefinitions).isEmpty && hiddenOnly.hasCompletedStoreSetup
              && hiddenOnly.visibleIDs == hiddenShoppingIDs
              && hiddenOnly.selectionForList(current: .tesco, definitions: allProductionDefinitions) == nil,
              "hidden-only installs show the returning-user no-stores state and retain every saved enable flag")
        let retainedItems = try retainedData.mainContext.fetch(FetchDescriptor<GroceryItem>())
        check(retainedItems.contains { $0.id == retainedItem.id && $0.listID == StoreID.tesco.listID
              && $0.name == "Saved Tesco item" && $0.quantityAmount == 2 && $0.status == .added && $0.position == 3 },
              "hiding a destination leaves its saved row identity, quantity, status and position intact")
        hiddenOnly.setBrandVisible(true, brand: availableCostco)
        check(hiddenOnly.shoppingVisibleIDs(in: allProductionDefinitions) == [.costco] && !hiddenOnly.visibleIDs.contains(.costcoUS)
              && hiddenOnly.regionalChoices["costco"] == "costco",
              "only an explicit AU enable replaces the hidden US region's saved enable flag")
        for definition in expansionDefinitions {
            let id = definition.id
            check(definition.isConfigurationValid && definition.allows(id.home), "new store has a trusted fallback homepage")
            check(definition.capabilities.search == id.permitsSearch,
                  "new search configuration matches the independently reviewed native ceiling")
            check(!definition.capabilities.cartUndo && !id.permitsCartUndo,
                  "expansion never inherits retailer-cart Undo")
            check(definition.capabilities.cartDetection == id.permitsCartDetection,
                  "new detector configuration matches independent native certification")
            let query = "tea & coffee + 50% / café #?"
            let url = definition.searchURL(for: query)!
            check(definition.allows(url) && url.fragment == nil && !url.absoluteString.contains(" "),
                  "new store search query stays encoded on its exact approved host")
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
            check(components.queryItems?.filter { $0.value == query }.count == 1
                  || (components.queryItems == nil && components.percentEncodedPath.hasSuffix(encodedQuery)),
                  "expansion queries stay one complete parameter or one percent-encoded path segment")
            for raw in ["http://\(id.home.host!)", "https://\(id.home.host!):444", "https://user:secret@\(id.home.host!)",
                        "https://\(id.home.host!).evil.test", "https://login.\(id.dataDomain)"] {
                check(!definition.allowsNavigation(URL(string: raw)!), "new browsing trust rejects unreviewed origins")
            }
            for other in allProductionDefinitions where other.id != id {
                check(!definition.allows(other.homepage) && !id.ownsDataDomain(other.id.dataDomain),
                      "new store and regional browsing/reset scopes cannot leak across destinations")
            }
            for host in id.hosts {
                check(DiagnosticEntry.Host(rawValue: host) != nil, "new hosts use the closed diagnostic allowlist")
            }
            for capability in ["cartDetection", "cartUndo"] where capability == "cartUndo" || !id.permitsCartDetection {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as! [String: Any]
                var capabilities = object["capabilities"] as! [String: Any]
                capabilities[capability] = true
                object["capabilities"] = capabilities
                check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                      "new JSON cannot enable unreviewed cart capabilities")
            }
        }
        check(StoreBrand.sections(allProductionDefinitions, countryCode: "AU", search: "Target").flatMap(\.brands).map(\.id) == ["targetAU", "target"],
              "Australian Target and unrelated US Target remain separate brands and sessions")
        check(StoreBrand.catalogue(allProductionDefinitions).first(where: { $0.id == "bunnings" })?.regions.map(\.id).sorted(by: { $0.rawValue < $1.rawValue }) == [.bunnings, .bunningsNZ],
              "Bunnings has explicit independently isolated AU/NZ destinations")
        check(StoreID.morrisons.ownsDataDomain("morrisons.com") && StoreID.asda.ownsDataDomain("asda.com")
              && !StoreID.morrisons.hosts.contains("www.morrisons.com"),
              "root-domain website data resets do not widen subdomain-only browsing trust")
        let prospectivePriceline = expansionDefinitions.first { $0.id == .priceline }!
        let sainsburys = expansionDefinitions.first { $0.id == .sainsburys }!
        let sainsburysLogin = URL(string: "https://account.sainsburys.co.uk/login-ui/gol/login")!
        check(sainsburys.allowsNavigation(sainsburysLogin) && !sainsburys.allows(sainsburysLogin),
              "Sainsbury's reviewed login origin is browsing-only, never cart-bridge trusted")
        for value in ["https://evil.account.sainsburys.co.uk/login", "https://account.sainsburys.co.uk.evil.test/login",
                      "https://account.sainsburys.co.uk:444/login", "http://account.sainsburys.co.uk/login",
                      "https://user@account.sainsburys.co.uk/login"] {
            check(!sainsburys.allowsNavigation(URL(string: value)!), "Sainsbury's authentication exceptions remain exact and HTTPS-only")
        }
        let waitrose = expansionDefinitions.first { $0.id == .waitrose }!
        check(waitrose.schemaVersion == 7 && waitrose.acceptsProductIdentity("053457-26759-26760")
              && waitrose.cart?.profiles?.first?.quantityDraftSelector == "button[data-testid='trolleyUpdateButton']",
              "Waitrose uses observed composite identity and rejects unapplied quantity drafts")
        for value in ["", "053457", "053457-26759", "abc-def-ghi", "053457-26759-", "-1-2",
                      "053457-26759-26760\n", String(repeating: "1", count: 17) + "-2-3"] {
            check(!waitrose.acceptsProductIdentity(value), "Waitrose native identities require three bounded numeric components")
        }
        for mutation in ["legacyDraft", "emptyDraftSelector", "oversizedDraftSelector", "undoWithDraft", "receiptWithDraft"] {
            let source = mutation == "legacyDraft" ? expansionDefinitions.first { $0.id == .morrisons }! : waitrose
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            profiles[0]["quantityDraftSelector"] = "button[data-testid='trolleyUpdateButton']"
            switch mutation {
            case "legacyDraft": object["schemaVersion"] = 3; object.removeValue(forKey: "categories"); object.removeValue(forKey: "automationSchemaVersion")
            case "emptyDraftSelector": profiles[0]["quantityDraftSelector"] = ""
            case "oversizedDraftSelector": profiles[0]["quantityDraftSelector"] = String(repeating: "x", count: 1_025)
            case "undoWithDraft": profiles[0]["undo"] = ["decrementSelector": "button", "decrementLabelPattern": "^remove$"]
            default: profiles[0]["confirmation"] = "productReceipt"
            }
            cart["profiles"] = profiles; object["cart"] = cart
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "quantity-draft validation rejects \(mutation)")
        }
        let waitroseLogin = URL(string: "https://auth.waitrose.com/oauth2/authorize")!
        check(waitrose.allowsNavigation(waitroseLogin) && !waitrose.allows(waitroseLogin),
              "Waitrose's observed OAuth redirect is browsing-only, not cart-bridge trusted")
        for value in ["https://evil.auth.waitrose.com/login", "https://auth.waitrose.com.evil.test/login",
                      "https://auth.waitrose.com:444/login", "http://auth.waitrose.com/login",
                      "https://user@auth.waitrose.com/login"] {
            check(!waitrose.allowsNavigation(URL(string: value)!), "Waitrose authentication remains exact-host HTTPS without credentials or custom ports")
        }
        let prospectiveSupercheap = expansionDefinitions.first { $0.id == .supercheapAuto }!
        check(prospectivePriceline.schemaVersion == 7 && prospectivePriceline.cart?.profiles?.first?.receipt?.imageIdentity?.allowedHosts == ["api.priceline.com.au"],
              "Priceline's linkless receipt has an explicitly bounded image-identity source")
        for mutation in ["oldSchema", "foreignImage", "missingRow", "missingQuantity", "mixedQuantityModes", "unknownImageKey"] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(prospectivePriceline)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            var receipt = profiles[0]["receipt"] as! [String: Any]
            var image = receipt["imageIdentity"] as! [String: Any]
            switch mutation {
            case "oldSchema": object["schemaVersion"] = 3; object.removeValue(forKey: "categories"); object.removeValue(forKey: "automationSchemaVersion")
            case "foreignImage": image["allowedHosts"] = ["evil.test"]
            case "missingRow": receipt.removeValue(forKey: "productSelector")
            case "missingQuantity": receipt.removeValue(forKey: "quantitySelector")
            case "mixedQuantityModes": receipt["quantityPattern"] = "qty ([0-9]+)"
            default: image["script"] = "arbitrary code"
            }
            receipt["imageIdentity"] = image; profiles[0]["receipt"] = receipt
            cart["profiles"] = profiles; object["cart"] = cart
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "schema-6 advanced receipt rejects \(mutation)")
        }
        var componentObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expansionDefinitions.first { $0.id == .officeworks }!)) as! [String: Any]
        componentObject["schemaVersion"] = 4
        componentObject.removeValue(forKey: "category")
        componentObject.removeValue(forKey: "categories")
        componentObject.removeValue(forKey: "automationSchemaVersion")
        var componentCart = try JSONSerialization.jsonObject(with: JSONEncoder().encode(prospectiveSupercheap.cart!)) as! [String: Any]
        componentCart["identityStrategy"] = "capturedURLComponent"
        componentCart["productURLPattern"] = "^/shop/officeworks/p/([A-Za-z0-9_-]{1,256})$"
        componentObject["cart"] = componentCart
        let componentDefinition = try StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: componentObject))
        check(componentDefinition.acceptsProductIdentity("keji-ballpoint-pens-keka1271as")
              && componentDefinition.acceptsProductIdentity(String(repeating: "x", count: 256)), "reviewed schema-4 identities support bounded nonnumeric SKUs")
        for value in ["", "-sku", "_sku", "../sku", "sku/path", "sku%2Fpath", "café", "sku\n", String(repeating: "x", count: 257)] {
            check(!componentDefinition.acceptsProductIdentity(value), "native bridge refuses unsafe captured product identity")
        }
        check(!prospectiveSupercheap.acceptsProductIdentity("sku") && prospectiveSupercheap.acceptsProductIdentity("733022"),
              "numeric stores do not inherit captured SKU identity validation")
        check(Set(StoreID.allCases.map(\.listID)).count == StoreID.allCases.count
              && Set(StoreID.allCases.map(\.websiteDataID)).count == StoreID.allCases.count,
              "all store and regional list/session identities remain unique")
        let searchContracts: [StoreID: (String, String)] = [
            .amazon: ("/s", "k"), .costcoUS: ("/s", "keyword"), .kroger: ("/search", "query"),
            .target: ("/s", "searchTerm"), .walmart: ("/search", "q")
        ]
        for definition in usDefinitions {
            let id = definition.id
            let expectedSearch = [StoreID.walmart, .kroger, .target].contains(id)
            check(definition.capabilities.search == expectedSearch && id.permitsSearch == expectedSearch,
                  "only US routes with matching live iOS WebKit product evidence enable automatic search")
            check(definition.serviceArea.countryCodes == ["US"] && definition.isConfigurationValid,
                  "US registrations have valid US-only coverage")
            check(!definition.capabilities.cartDetection && !definition.capabilities.cartUndo && definition.cart == nil
                  && !id.permitsCartDetection && !id.permitsCartUndo,
                  "US cart automation stays disabled until separately verified")
            for capability in ["cartDetection", "cartUndo"] {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as! [String: Any]
                var capabilities = object["capabilities"] as! [String: Any]
                capabilities[capability] = true
                object["capabilities"] = capabilities
                check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                      "US JSON cannot enable unreviewed cart capabilities")
            }
            let query = "milk & bread + 50% / café #?"
            let url = definition.searchURL(for: query)!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let contract = searchContracts[id]!
            check(components.path == contract.0 && components.queryItems?.count == 1
                  && components.queryItems?.first?.name == contract.1 && components.queryItems?.first?.value == query
                  && components.fragment == nil && definition.allows(url), "US query encoding preserves one retailer-specific parameter")
            for raw in ["http://www.\(id.dataDomain)", "https://www.\(id.dataDomain):444",
                        "https://user:secret@www.\(id.dataDomain)", "https://www.\(id.dataDomain).evil.test",
                        "https://login.\(id.dataDomain)"] {
                check(!definition.allowsNavigation(URL(string: raw)!), "US browsing trust cannot widen to unreviewed origins")
            }
            for other in expandedDefinitions where other.id != id {
                check(!definition.allows(other.homepage) && !id.ownsDataDomain(other.id.dataDomain),
                      "US browsing and reset scopes cannot leak across stores or regions")
            }
            for host in id.hosts {
                check(DiagnosticEntry.Host(rawValue: host) != nil, "US hosts use the closed diagnostic allowlist")
            }
        }
        let usBrands = StoreBrand.sections(expandedDefinitions, countryCode: "US", search: "")
        check(usBrands.first?.brands.map(\.id) == ["kroger", "target", "walmart"],
              "only verified-search US destinations appear in the local group")
        check(usBrands.flatMap(\.brands).count == 10, "unverified destinations stay registered but are absent from discovery")
        check(StoreBrand.sections(expandedDefinitions, countryCode: "AU", search: "Target").flatMap(\.brands).map(\.id) == ["target"],
              "US Target is searchable without inventing an Australian Target integration")
        let usSuite = "ListRunner.USStores.\(UUID().uuidString)"
        let usDefaults = UserDefaults(suiteName: usSuite)!
        defer { usDefaults.removePersistentDomain(forName: usSuite) }
        usDefaults.set(brandDefinitions.map { $0.id.rawValue }, forKey: "knownStoreIDs.v1")
        usDefaults.set(["coles", "walmart"], forKey: "visibleStoreIDs.v1")
        let usPreferences = StoreVisibilityPreferences(defaults: usDefaults, suggestedCountryCode: "US")
        check(usPreferences.visibleIDs == [.coles, .walmart], "adding US retailers preserves old visibility and starts new stores disabled")
        usPreferences.setVisible(true, for: .target)
        usPreferences.setShoppingCountry("AU")
        let usRestored = StoreVisibilityPreferences(defaults: usDefaults)
        check(usRestored.visibleIDs == [.coles, .walmart, .target]
              && usRestored.selectionForList(current: .coles, definitions: expandedDefinitions) == .target,
              "US enabling and pending selection persist without country changes switching a website")
        let emptySuite = "ListRunner.EmptyStoreTests.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        emptyDefaults.set("bunnings", forKey: "activeStoreID")
        let emptyPreferences = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(emptyPreferences.visibleIDs.isEmpty
              && emptyPreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == nil,
              "fresh installs start with every store disabled and no enabled destination")
        check(!emptyPreferences.hasCompletedStoreSetup
              && !StoreVisibilityPreferences(defaults: emptyDefaults).hasCompletedStoreSetup,
              "first-store welcome survives relaunch before choosing a store")
        for id in StoreID.allCases { emptyPreferences.setVisible(false, for: id) }
        check(emptyPreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == nil,
              "all-disabled state has no enabled destination")
        emptyPreferences.setVisible(true, for: .coles)
        let emptyRestored = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(emptyRestored.hasCompletedStoreSetup,
              "enabling the first store permanently completes welcome setup")
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == .coles,
              "all-disabled then Coles-only selects Coles even after relaunch")
        check(emptyDefaults.string(forKey: "activeStoreID") == "bunnings",
              "visibility recovery waits for the list screen to apply the selection")
        check(emptyRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .coles,
              "list reconciliation preserves an explicit enabled store choice")
        emptyRestored.setVisible(false, for: .coles)
        check(StoreVisibilityPreferences(defaults: emptyDefaults).hasCompletedStoreSetup,
              "disabling every store does not show first-time welcome again")
        emptyRestored.setVisible(true, for: .woolworths)
        emptyRestored.setVisible(true, for: .coles)
        check(emptyRestored.selectionForList(current: .woolworths, definitions: brandDefinitions) == .coles,
               "the most recently enabled store wins even when the current store is enabled")
        for id in StoreID.allCases { emptyRestored.setVisible(false, for: id) }
        emptyRestored.setVisible(true, for: .woolworths)
        emptyRestored.setVisible(true, for: .coles)
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions.reversed()) == .coles,
               "multiple re-enabled stores select the latest enabled store, independent of catalogue order")
        let recoveryCostco = StoreBrand.catalogue(brandDefinitions).first { $0.id == "costco" }!
        for id in StoreID.allCases { emptyRestored.setVisible(false, for: id) }
        emptyRestored.chooseRegion(.costcoUS, for: recoveryCostco)
        emptyRestored.setBrandVisible(true, brand: recoveryCostco)
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == nil,
               "a saved unverified regional destination cannot become the active shopping list")
        emptyRestored.chooseRegion(.costco, for: recoveryCostco)
        check(emptyRestored.selectionForList(current: .costcoUS, definitions: brandDefinitions) == .costco,
              "a disabled regional destination also resolves to an enabled list on return")
        let activePreferences = StoreVisibilityPreferences(defaults: UserDefaults(suiteName: emptySuite)!)
        activePreferences.setVisible(true, for: .coles)
        activePreferences.setVisible(true, for: .woolworths)
        activePreferences.setVisible(true, for: .bunnings)
        activePreferences.setVisible(false, for: .bunnings)
        check(activePreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == .woolworths,
               "disabling the newest enabled store selects the previous pending enable")
        let activeRestored = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(activeRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == .coles,
              "relaunch repairs a previously persisted disabled active store")
        activeRestored.setShoppingCountry("US")
        check(activeRestored.selectionForList(current: .woolworths, definitions: brandDefinitions) == .woolworths,
               "country changes never switch an active store that remains enabled")
        activeRestored.setVisible(true, for: .bigW)
        activeRestored.setVisible(true, for: .kmart)
        check(emptyDefaults.string(forKey: "activeStoreID") == "bunnings", "enabling never changes activeStoreID before returning")
        let pendingRestored = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(pendingRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .kmart,
              "latest enable order survives relaunch until list reconciliation")
        check(pendingRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .coles,
              "enable selection is consumed once and preserves subsequent manual choices")
        pendingRestored.setVisible(true, for: .bigW)
        check(pendingRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .coles,
              "repeated already-enabled assignments do not requeue selection")
        pendingRestored.setVisible(false, for: .bigW)
        pendingRestored.setVisible(true, for: .bigW)
        pendingRestored.setVisible(false, for: .bigW)
        check(pendingRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .coles,
              "enabling then disabling before returning cannot activate a hidden store")
        let costcoBrand = StoreBrand.catalogue(brandDefinitions).first { $0.id == "costco" }!
        check(costcoBrand.regions.map(\.id) == [.costco, .costcoUS], "reviewed Costco regions share one brand entry")
        check(StoreBrand.catalogue(brandDefinitions).count == 8, "nine regional stores have eight brand rows")
        for country in ["AU", "US", "GB", "NZ", nil] as [String?] {
            let enabled: Set<StoreID> = [.coles, .costcoUS, .tesco]
            let groups = StoreBrand.sections(brandDefinitions, countryCode: country, search: "", enabledIDs: enabled)
            check(groups.first?.title == "Enabled stores"
                  && groups.first?.brands.map(\.id) == ["coles", "tesco"],
                   "only verified enabled destinations lead the shopping catalogue")
            check(groups.dropFirst().flatMap(\.brands).allSatisfy { brand in
                !brand.regions.contains { enabled.contains($0.id) }
            }, "enabled brands never appear in local or other stores")
            check(groups.flatMap(\.brands).count == 8,
                   "enabled-first grouping preserves every available brand exactly once")
            check(groups.compactMap(\.indexTitle).allSatisfy { letter in
                groups.contains { $0.indexTitle == letter && !$0.brands.isEmpty }
            }, "enabled-first grouping has no empty index entries")
        }
        let enabledSearch = StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "Costco US", enabledIDs: [.costcoUS])
        check(enabledSearch.isEmpty, "search cannot reveal a saved but unverified Costco US destination")
        let allEnabled = StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "", enabledIDs: Set(brandDefinitions.map(\.id)))
        check(allEnabled.count == 1 && allEnabled.first?.title == "Enabled stores",
              "all enabled hides empty country and other groups")
        for country in ["AU", "US"] {
            let groups = StoreBrand.sections(brandDefinitions, countryCode: country, search: "")
            check(groups.flatMap(\.brands).filter { $0.id == "costco" }.count == 1
                  && groups.flatMap(\.brands).first { $0.id == "costco" }?.regions.map(\.id) == [.costco],
                   "Costco AU remains available once; its unverified US region is not offered")
        }
        check(StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "Costco US").isEmpty,
               "searching an unavailable regional name cannot reveal the hidden region")
        check(!StoreBrand.sections(brandDefinitions, countryCode: "GB", search: "United States").flatMap(\.brands).contains { $0.id == "costco" },
               "country search matches only available regional destinations")
        let outsideRegions = StoreBrand.sections(brandDefinitions, countryCode: "GB", search: "")
        check(outsideRegions.flatMap(\.brands).filter { $0.id == "costco" }.count == 1
              && outsideRegions.first(where: { $0.indexTitle == "C" })?.brands.map(\.id) == ["coles", "costco"],
              "a brand with no local region is indexed once, not repeated by website")
        check(StoreBrand.catalogue(brandDefinitions).first { $0.id == "kmart" }?.regions.count == 1,
              "unrelated Kmart businesses are not inferred into a shared brand")
        let regionalSuite = "ListRunner.RegionalTests.\(UUID().uuidString)"
        let regionalDefaults = UserDefaults(suiteName: regionalSuite)!
        defer { regionalDefaults.removePersistentDomain(forName: regionalSuite) }
        regionalDefaults.set(["costco", "coles"], forKey: "visibleStoreIDs.v1")
        regionalDefaults.set(["costco", "coles"], forKey: "knownStoreIDs.v1")
        regionalDefaults.set("costco", forKey: "activeStoreID")
        let regionalPreferences = StoreVisibilityPreferences(defaults: regionalDefaults, suggestedCountryCode: "US")
        check(regionalPreferences.selectedRegion(for: costcoBrand).id == .costco
              && regionalPreferences.visibleIDs == [.costco, .coles],
              "migration retains enabled Australia even with a US shopping country")
        regionalPreferences.setShoppingCountry("AU")
        regionalPreferences.setShoppingCountry("US")
        check(regionalPreferences.selectedRegion(for: costcoBrand).id == .costco
              && !regionalPreferences.visibleIDs.contains(.costcoUS), "country changes never switch an enabled region")
        regionalPreferences.chooseRegion(.costcoUS, for: costcoBrand)
        check(regionalPreferences.visibleIDs == [.costcoUS, .coles]
              && regionalDefaults.string(forKey: "activeStoreID") == "costco",
              "explicit regional choice replaces chooser visibility, never the active list")
        regionalPreferences.setShoppingCountry("AU")
        let regionalRestored = StoreVisibilityPreferences(defaults: regionalDefaults, suggestedCountryCode: "AU")
        check(regionalRestored.selectedRegion(for: costcoBrand).id == .costcoUS,
              "explicit regional destination persists despite later country changes and relaunch")
        regionalRestored.setBrandVisible(false, brand: costcoBrand)
        check(!regionalRestored.visibleIDs.contains(.costco) && !regionalRestored.visibleIDs.contains(.costcoUS)
              && regionalRestored.visibleIDs.contains(.coles), "one brand switch hides regional destinations without affecting other brands")
        regionalRestored.chooseRegion(.costco, for: costcoBrand)
        check(!regionalRestored.visibleIDs.contains(.costco), "choosing a disabled brand's region does not enable it")
        regionalRestored.setBrandVisible(true, brand: costcoBrand)
        check(regionalRestored.visibleIDs == [.coles, .costco], "enabling brand restores only explicitly chosen region")
        regionalRestored.chooseRegion(.tesco, for: costcoBrand)
        check(regionalRestored.selectedRegion(for: costcoBrand).id == .costco, "unrelated retailer cannot become a Costco region")
        regionalRestored.setBrandVisible(false, brand: costcoBrand)
        regionalDefaults.removeObject(forKey: "storeRegionalChoices.v1")
        let newUSChoice = StoreVisibilityPreferences(defaults: regionalDefaults, suggestedCountryCode: "US")
        newUSChoice.setShoppingCountry("US")
        check(newUSChoice.selectedRegion(for: costcoBrand).id == .costcoUS, "disabled unchosen brand suggests shopping-country region")
        regionalDefaults.set(["costco": "tesco"], forKey: "storeRegionalChoices.v1")
        let malformedChoice = StoreVisibilityPreferences(defaults: regionalDefaults, suggestedCountryCode: "US")
        check(malformedChoice.selectedRegion(for: costcoBrand).id == .costcoUS,
              "malformed regional choice cannot redirect a brand to another retailer")
        check(kmart.isConfigurationValid && kmart.serviceArea.countryCodes == ["AU"]
               && kmart.capabilities.search && kmart.capabilities.cartDetection && !kmart.capabilities.cartUndo
               && kmart.cart?.productURLPattern == "/product/[^/?#]+-(\\d{1,32})(?:[/?#]|$)",
              "Kmart Australia enables search and product-scoped detection but keeps unverified cart Undo disabled")
        check(StoreID.kmart.permitsSearch && StoreID.kmart.permitsCartDetection && !StoreID.kmart.permitsCartUndo,
               "native Kmart policy keeps retailer-cart Undo disabled until its bag-page reversal is verified")
        check(kmart.schemaVersion == 7 && kmart.cart?.strategy == .profiled
              && kmart.cart?.profiles?.map(\.scope) == [.productCard, .productPage]
              && kmart.cart?.profiles?.map(\.identity) == [.cardLink, .pageURL]
              && kmart.cart?.profiles?.allSatisfy({ $0.confirmation == .productReceipt }) == true,
              "Kmart declares independent grid/detail identities using a shared receipt engine")
        check(coles.schemaVersion == 7 && coles.cart?.profiles == nil
              && woolworths.cart?.profiles == nil && bunnings.cart?.profiles == nil,
              "legacy version-2 stores keep their existing detector rules")
        func rejectsProfile(_ mutate: (inout [String: Any]) -> Void) -> Bool {
            var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(kmart)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            mutate(&cart)
            object["cart"] = cart
            do {
                _ = try StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))
                return false
            } catch { return true }
        }
        check(rejectsProfile { $0.removeValue(forKey: "profiles") }, "profile strategy cannot silently fall back to legacy rules")
        check(rejectsProfile { $0["profiles"] = [] }, "profile strategy requires at least one profile")
        for (key, value) in [("identity", "pageURL" as Any), ("confirmation", "executeScript" as Any),
                             ("confirmationWindowMS", 60_000 as Any), ("containerSelector", "" as Any),
                             ("executableScript", "unexpected" as Any)] {
            check(rejectsProfile { cart in
                var profiles = cart["profiles"] as! [[String: Any]]
                profiles[0][key] = value
                cart["profiles"] = profiles
            }, "invalid or unknown profile field rejected: \(key)")
        }
        check(rejectsProfile { cart in
            var profiles = cart["profiles"] as! [[String: Any]]
            profiles[1]["id"] = profiles[0]["id"]
            cart["profiles"] = profiles
        }, "duplicate profile IDs rejected")
        check(rejectsProfile { cart in
            var profiles = cart["profiles"] as! [[String: Any]]
            var receipt = profiles[0]["receipt"] as! [String: Any]
            receipt["quantityPattern"] = "(qty) ([0-9]+)"
            profiles[0]["receipt"] = receipt
            cart["profiles"] = profiles
        }, "receipt quantity regex requires exactly one capture")
        check(bigW.isConfigurationValid && bigW.serviceArea.countryCodes == ["AU"]
              && bigW.capabilities.search && bigW.capabilities.cartDetection && bigW.capabilities.cartUndo
              && bigW.cart?.strategy == .profiled,
              "BIG W enables reviewed profile-based search/detection and scoped quantity Undo")
        check(StoreID.bigW.permitsSearch && StoreID.bigW.permitsCartDetection && StoreID.bigW.permitsCartUndo,
              "native BIG W policy permits reviewed automation")
        check(bigW.cart?.profiles?.count == 2 && bigW.cart?.profiles?.allSatisfy({
            $0.confirmation == .quantityIncrease && $0.emptyStatusText == "Add to cart" && $0.undo != nil
        }) == true, "BIG W card/detail profiles require explicit empty-state and decrement provenance")
        check(bigW.cart?.profiles?.allSatisfy({ $0.setupPrompt?.maximumWaitMS == 300_000 }) == true,
              "BIG W first-use postcode/store setup has a bounded human-interaction window")
        for field in ["maximumWaitMS", "selector", "textPattern", "unexpected"] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bigW)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            var setup = profiles[0]["setupPrompt"] as! [String: Any]
            if field == "maximumWaitMS" { setup[field] = 900_000 }
            else { setup[field] = field == "textPattern" ? "[" : "" }
            profiles[0]["setupPrompt"] = setup
            cart["profiles"] = profiles; object["cart"] = cart
            let malformed = try JSONSerialization.data(withJSONObject: object)
            check((try? StoreDefinition.decodeConfiguration(from: malformed)) == nil,
                  "invalid setup-prompt contract rejected: \(field)")
        }
        let bigWSearch = URLComponents(url: bigW.searchURL(for: "toaster & kettle")!, resolvingAgainstBaseURL: false)!
        check(bigWSearch.path == "/search" && bigWSearch.queryItems?.first?.name == "text"
              && bigWSearch.queryItems?.first?.value == "toaster & kettle", "BIG W search uses its verified encoded text route")
        for (field, value) in [("undo", NSNull() as Any), ("emptyStatusText", "" as Any),
                               ("confirmation", "productReceipt" as Any)] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bigW)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            profiles[0][field] = value
            cart["profiles"] = profiles
            object["cart"] = cart
            let malformed = try JSONSerialization.data(withJSONObject: object)
            check((try? StoreDefinition.decodeConfiguration(from: malformed)) == nil,
                  "profiled Undo rejects unsafe confirmation/control contracts: \(field)")
        }
        check(bigW.allows(bigW.homepage) && bigW.allows(URL(string: "https://bigw.com.au")!)
              && !bigW.allows(URL(string: "https://www.bigw.co.nz")!)
              && !bigW.allows(URL(string: "https://www.bigw.com.au.evil.test")!), "BIG W hosts are exact and Australia-only")
        var invalidKmart = kmart
        invalidKmart.capabilities.cartUndo = true
        check(!invalidKmart.isConfigurationValid, "Kmart cart Undo remains prohibited for profiled detection")
        check(kmart.allows(kmart.homepage) && kmart.allows(URL(string: "https://kmart.com.au")!)
              && !kmart.allows(URL(string: "https://www.kmart.co.nz")!)
              && !kmart.allows(URL(string: "https://www.kmart.com.au.evil.test")!)
              && !kmart.allows(URL(string: "https://login.kmart.com.au")!), "Kmart hosts are exact and Australia-only")
        let kmartCatalogue = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco, walmart, kmart], countryCode: "AU")
        check(kmartCatalogue.first?.stores.map(\.id) == [.bunnings, .coles, .costco, .kmart, .woolworths]
              && kmartCatalogue.dropFirst().map(\.indexTitle) == ["T", "W"]
              && kmartCatalogue[1].stores.map(\.id) == [.tesco],
               "Kmart joins Australia while Tesco appears in its verified other-store group")
        try coles.validate(); try woolworths.validate(); try bunnings.validate(); try costco.validate()
        for store in [woolworths, bunnings, costco] {
            var widened = store
            widened.capabilities.cartUndo = true
            check(!widened.isConfigurationValid, "JSON cannot widen the native cart-Undo ceiling")
        }
        _ = try StoreDefinition.decodeConfiguration(from: configData)
        let validJSON = String(decoding: configData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        for raw in [
            "{\"schemaVersion\":2," + validJSON.dropFirst(),
            validJSON.replacingOccurrences(of: "\"countryCodes\":", with: "\"countryCodes\":[\"AU\"],\"countryCodes\":"),
            "{\"\\u0069d\":\"coles\"," + validJSON.dropFirst()
        ] {
            check((try? StoreDefinition.decodeConfiguration(from: Data(raw.utf8))) == nil,
                  "duplicate JSON object keys fail closed, including nested and escaped keys")
        }
        check([coles, woolworths, bunnings, costco].allSatisfy { $0.serviceArea.countryCodes == ["AU"] },
              "all bundled retailers declare the approved Australia service area")
        check(StoreCatalogue.ordered([coles, woolworths, bunnings], countryCode: "AU").map(\.id) == [.bunnings, .coles, .woolworths],
              "service-area matches sort first and alphabetically within the matching group")
        check(StoreCatalogue.ordered([coles, woolworths, bunnings], countryCode: "NZ").map(\.id) == [.bunnings, .coles, .woolworths],
              "nonmatching stores remain available in deterministic alphabetical order")
        check(costco.capabilities.search && !costco.capabilities.cartDetection && !costco.capabilities.cartUndo && costco.cart == nil,
              "Costco supports configured search and manual progression without unverified cart automation")
        var widenedCostco = costco
        widenedCostco.capabilities.cartDetection = true
        check(!widenedCostco.isConfigurationValid && !StoreID.costco.permitsCartDetection && !StoreID.costco.permitsCartUndo,
              "Costco native ceilings prohibit unverified detection and Undo")
        let costcoQuery = URLComponents(url: costco.searchURL(for: "milk & coffee / #?")!, resolvingAgainstBaseURL: false)!
        check(costcoQuery.path == "/search" && costcoQuery.queryItems == [URLQueryItem(name: "text", value: "milk & coffee / #?")],
              "Costco search uses one safely encoded text parameter")
        check(costco.allows(URL(string: "https://www.costco.com.au/search?text=milk")!)
              && costco.allows(URL(string: "https://costco.com.au")!)
              && !costco.allows(URL(string: "https://www.costco.com")!)
              && !costco.allows(URL(string: "https://www.costco.co.nz")!)
              && !costco.allows(URL(string: "https://www.costco.com.au.evil.test")!)
              && !costco.allows(URL(string: "https://evil.costco.com.au")!),
              "Costco Australia trusts only its exact reviewed Australian hosts, not other markets or subdomains")
        check(Set(StoreID.allCases.map(\.listID)).count == StoreID.allCases.count
              && Set(StoreID.allCases.map(\.websiteDataID)).count == StoreID.allCases.count,
              "all retailer list and website-data IDs remain unique after adding Costco")
        let fourStores = StoreCatalogue.sections([coles, woolworths, bunnings, costco], countryCode: "AU")
        check(fourStores.count == 1 && fourStores[0].stores.map(\.id) == [.bunnings, .coles, .costco, .woolworths],
              "Costco joins the Australian group once, alphabetically, even while disabled")
        check(tesco.isConfigurationValid && tesco.serviceArea.countryCodes == ["GB"]
               && tesco.capabilities.search && tesco.capabilities.cartDetection && tesco.capabilities.cartUndo
               && tesco.cart?.profiles?.first?.quantityText == true,
               "Tesco UK supports verified search, text-quantity detection and normal signed-in cart Undo")
        check(StoreID.tesco.permitsSearch && StoreID.tesco.permitsCartDetection && StoreID.tesco.permitsCartUndo,
               "native Tesco policy matches independently verified search, detection and reversal")
        let replayStore = tesco
        let replaySource = URL(string: "https://www.tesco.com/shop/en-GB/search?query=milk")!
        let replayLogin = URL(string: "https://www.tesco.com/account/auth/en-GB/login")!
        let replayReceipt: [String: Any] = ["nonce": "test-nonce", "productID": "254656543", "successful": true,
                                           "requestedQuantity": 4, "resultingQuantity": 4]
        var replay = StoreLoginReplay(store: replayStore, productID: "254656543", context: "selected-item",
                                      nonce: "test-nonce", sourceURL: replaySource, now: 100)!
        check(replay.accepts(replayReceipt, url: replaySource, context: "selected-item", now: 101) == nil,
              "basket acknowledgements cannot create a login continuation without authentication navigation")
        check(replay.visit(replayLogin, store: replayStore, context: "selected-item", now: 101),
              "a retained trusted product intent can enter the exact reviewed authentication route")
        check(replay.visit(URL(string: "https://www.tesco.com/account/auth/en-GB/authorize")!,
                           store: replayStore, context: "selected-item", now: 101)
              && replay.visit(URL(string: "https://www.tesco.com/account/login/en-GB/continue")!,
                              store: replayStore, context: "selected-item", now: 101),
              "observed auth-to-login continuation keeps the original trusted intent before returning")
        for path in ["/account/auth/en-GB", "/account/login/en-GB", "/account/login/en-GB/"] {
            var copy = replay
            check(copy.visit(URL(string: "https://www.tesco.com" + path)!, store: replayStore,
                             context: "selected-item", now: 101),
                  "reviewed authentication roots accept their optional trailing slash")
        }
        check(replay.visit(replaySource, store: replayStore, context: "selected-item", now: 102)
              && replay.accepts(replayReceipt, url: replaySource, context: "selected-item", now: 102) == 4,
              "post-auth product acknowledgement is accepted without inventing a pre-auth account baseline")
        for (field, value) in [("nonce", "foreign" as Any), ("productID", "111111" as Any),
                               ("successful", "true" as Any), ("successful", 1 as Any), ("successful", false as Any),
                               ("requestedQuantity", 3 as Any), ("resultingQuantity", 0 as Any),
                               ("resultingQuantity", true as Any), ("resultingQuantity", 1.5 as Any),
                               ("extra", "unrecognized" as Any)] {
            var object = replayReceipt; object[field] = value
            check(replay.accepts(object, url: replaySource, context: "selected-item", now: 103) == nil,
                  "login continuation rejects forged, ambiguous and malformed acknowledgement: \(field)")
        }
        check(replay.accepts(replayReceipt, url: replaySource, context: "other-item", now: 103) == nil
              && replay.accepts(replayReceipt, url: replaySource, context: "selected-item", now: 401) == nil,
              "login acknowledgement cannot cross item/session context or outlive its bounded deadline")
        for raw in ["https://www.tesco.com/shop/en-GB/search?query=bread", "https://www.tesco.com/shop/en-GB/trolley",
                    "https://www.tesco.com/account/profile", "http://www.tesco.com/account/auth/en-GB/login",
                    "https://www.tesco.com/account/login/en-IE/continue", "https://www.tesco.com/account/login/en-GB-evil/continue",
                    "https://www.tesco.com/account/auth/en-GB-evil/login", "https://www.tesco.com/account/settings/en-GB",
                    "https://www.tesco.com:444/account/auth/en-GB/login", "https://tesco.com/account/auth/en-GB/login",
                    "https://www.tesco.com.evil.test/account/auth/en-GB/login"] {
            var copy = replay
            check(!copy.visit(URL(string: raw)!, store: replayStore, context: "selected-item", now: 103),
                  "login continuation refuses unrelated search/cart/account pages and unreviewed origins")
        }
        check(StoreLoginReplay(store: coles, productID: "254656543", context: "selected-item", nonce: "n",
                               sourceURL: replaySource, now: 100) == nil,
              "login continuation cannot be enabled for an unreviewed retailer")
        for (field, value) in [("quantityText", false as Any), ("confirmation", "productReceipt" as Any),
                               ("quantitySelector", NSNull() as Any)] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tesco)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            profiles[0][field] = value
            cart["profiles"] = profiles
            object["cart"] = cart
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "text quantity contracts reject invalid configuration: \(field)")
        }
        var widenedTesco = tesco
        widenedTesco.capabilities.cartDetection = false
        check(!widenedTesco.isConfigurationValid, "Tesco cart Undo cannot be enabled without detection")
        let fiveStores = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco], countryCode: "AU")
        check(fiveStores.count == 2 && fiveStores[0].stores.count == 4
               && fiveStores[1].stores.map(\.id) == [.tesco],
               "Tesco appears in the other-store group when search is verified")
        let britishStores = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco], countryCode: "GB")
        check(britishStores.first?.stores.map(\.id) == [.tesco]
               && britishStores.dropFirst().flatMap(\.stores).count == 4,
               "changing country promotes Tesco to the local store group")
        check(tesco.allows(tesco.homepage) && !tesco.allows(URL(string: "https://www.tesco.ie")!)
              && !tesco.allows(URL(string: "https://www.tesco.com.evil.test")!)
              && !tesco.allows(coles.homepage), "Tesco UK browsing hosts remain exact and isolated")
        check(walmart.isConfigurationValid && walmart.serviceArea.countryCodes == ["US"]
              && walmart.capabilities.search && !walmart.capabilities.cartDetection && !walmart.capabilities.cartUndo && walmart.cart == nil,
              "Walmart US supports verified search without claiming cart automation")
        check(StoreID.walmart.permitsSearch && !StoreID.walmart.permitsCartDetection && !StoreID.walmart.permitsCartUndo,
              "native Walmart policy permits search but prohibits unreviewed cart automation")
        var widenedWalmart = walmart
        widenedWalmart.capabilities.cartDetection = true
        check(!widenedWalmart.isConfigurationValid, "JSON cannot enable Walmart cart detection")
        let allStores = [coles, woolworths, bunnings, costco, tesco, walmart]
        let auWithUS = StoreCatalogue.sections(allStores, countryCode: "AU")
        check(auWithUS.count == 3 && auWithUS[0].stores.count == 4
               && auWithUS.dropFirst().map(\.indexTitle) == ["T", "W"]
               && auWithUS[1].stores.map(\.id) == [.tesco]
               && auWithUS.last?.stores.map(\.id) == [.walmart],
               "Australia offers verified-search Tesco and Walmart in separate other-store groups")
        let usStores = StoreCatalogue.sections(allStores, countryCode: "US")
        check(usStores.first?.stores.map(\.id) == [.walmart]
               && usStores.dropFirst().flatMap(\.stores).map(\.id).contains(.walmart) == false
               && usStores.dropFirst().flatMap(\.stores).count == 5,
               "Walmart moves to the US local group without duplicating or hiding other stores")
        check(walmart.allows(walmart.homepage) && walmart.allows(URL(string: "https://walmart.com")!)
              && !walmart.allows(URL(string: "https://www.walmart.ca")!)
              && !walmart.allows(URL(string: "https://www.walmart.com.evil.test")!)
              && !walmart.allows(URL(string: "https://identity.walmart.com")!),
              "Walmart US permits only the exact browsing hosts, not another market or unreviewed authentication")
        let separatedGroceries = GroceryParser.parse("milk\tbread; eggs, butter\nyogurt")
        check(separatedGroceries.map(\.name) == ["milk", "bread", "eggs", "butter", "yogurt"],
              "grocery input accepts newline, tab, semicolon and comma separators")
        let dictionary = try IngredientDictionary(data: Data(contentsOf: resources.appendingPathComponent("ingredients.json")))
        let ingredientParser = IngredientParser(dictionary: dictionary)
        // Exercise the ingredient-first parser used by the app, not the legacy
        // fallback parser. A unit or plural package does not invent a count.
        let recipeGroceries = ingredientParser.parseGroceries("Tbs lime juice\n(15 ounce) cans cannellini beans drained and rinsed\n(28 ounce) can diced tomatoes\n3 cups low-sodium vegetable stock\n3 tablespoons butter divided\n2 eggs whisked\nFirm tofu thinly sliced\n1/3 cup freshly grated romano cheese")
        check(recipeGroceries.map(\.name) == ["Lime juice", "Cannellini beans", "Diced tomatoes", "Low-sodium vegetable stock", "Butter", "Eggs", "Firm tofu", "Romano cheese"],
              "recipe imports omit preparation notes and retain clean ingredient names")
        check(recipeGroceries[0].amount == nil && recipeGroceries[0].unit == "tbsp"
              && recipeGroceries[1].amount == nil && recipeGroceries[1].unit == "15 oz can"
              && recipeGroceries[2].amount == nil && recipeGroceries[2].unit == "28 oz can"
              && recipeGroceries[4].amount == 3 && recipeGroceries[4].unit == "tbsp"
              && recipeGroceries[7].amount == 1.0 / 3.0 && recipeGroceries[7].unit == "cup",
              "recipe quantities, abbreviated measures and can sizes are retained")
        let chilledRice = ingredientParser.parseGroceries("4 cups cooked and chilled rice(I prefer short-grain white rice)")
        check(chilledRice.count == 1
              && chilledRice[0].name == "Rice (I prefer short-grain white rice)"
              && chilledRice[0].amount == 4 && chilledRice[0].unit == "cups",
              "quantity survives an intervening cooked-and-chilled note and parenthetical preference is preserved")
        let cashews = ingredientParser.parseRecord("¼ cup (40g) roasted salted cashews")
        check(cashews?.disposition == .recognized
              && cashews?.grocery.name == "Roasted salted cashews"
              && cashews?.grocery.amount == 0.25 && cashews?.grocery.unit == "cup",
              "cashews resolve to the ingredient while the primary volume quantity and clean name are retained")
        check(coles.addedColor.red == 224 && coles.addedColor.green == 26 && coles.addedColor.blue == 34,
              "Coles Added colour is explicitly configured as RGB(224, 26, 34)")
        check(woolworths.addedColor.red == 0 && woolworths.addedColor.green == 114 && woolworths.addedColor.blue == 61,
              "Woolworths Added colour is explicitly configured as RGB(0, 114, 61)")
        check(bunnings.addedColor.red == 218 && bunnings.addedColor.green == 41 && bunnings.addedColor.blue == 28
              && bunnings.brandColors?.primary.red == 13 && bunnings.brandColors?.primary.green == 82 && bunnings.brandColors?.primary.blue == 87
              && bunnings.brandColors?.highlight.red == 255 && bunnings.brandColors?.highlight.green == 171 && bunnings.brandColors?.highlight.blue == 0,
              "Bunnings red, teal and gold palette is configured")
        check(bunnings.capabilities.search && bunnings.capabilities.cartDetection && !bunnings.capabilities.cartUndo,
              "Bunnings enables verified search and product-specific cart detection but keeps cart Undo disabled")
        let bunningsCart = bunnings.cart!
        let bunningsPath = "/esky-26l-chilla-hard-cooler_p0138506"
        let bunningsMatch = try NSRegularExpression(pattern: bunningsCart.productURLPattern)
            .firstMatch(in: bunningsPath, range: NSRange(bunningsPath.startIndex..., in: bunningsPath))
        let bunningsID = bunningsMatch.flatMap { Range($0.range(at: 1), in: bunningsPath).map { String(bunningsPath[$0]) } }
        check(bunningsID == "0138506" && bunningsCart.quantitySelector.contains("aria-label")
              && bunningsCart.addLabelPatterns.contains("^add to cart$"),
              "Bunnings cart identity and controls match its verified product page")
        let bunningsSearch = URLComponents(url: bunnings.searchURL(for: "Esky 26L Chilla Hard Cooler")!, resolvingAgainstBaseURL: false)!
        check(bunningsSearch.path == "/search/products" && bunningsSearch.queryItems?.first?.value == "Esky 26L Chilla Hard Cooler",
              "Bunnings search uses its verified product-search route and safely encoded query")
        check(bunnings.allows(bunnings.homepage) && bunnings.homepage.host == "www.bunnings.com.au"
              && StoreID.bunnings.listID != StoreID.coles.listID && StoreID.bunnings.websiteDataID != StoreID.woolworths.websiteDataID,
              "Bunnings has an allowlisted homepage and isolated list/session identifiers")
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
        check(!bunnings.allows(colesLogin), "Bunnings rejects cross-store navigation")
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
        check(StoreID.bunnings.ownsDataDomain("www.bunnings.com.au")
              && !StoreID.bunnings.ownsDataDomain("bunnings.com.au.evil.test"),
              "Bunnings session reset is scoped to its own domain")
        check(!coles.allows(URL(string: "https://evil.coles.com.au")!), "exact-host allowlist")
        check(!coles.allows(URL(string: "https://www.coles.com.au:444")!), "unapproved port rejection")
        check(!coles.allows(URL(string: "http://www.coles.com.au")!), "HTTPS enforced")
        check(!coles.allows(URL(string: "https://user@www.coles.com.au")!), "credential URL rejection")
        check(StoreID.coles.listID != StoreID.woolworths.listID && StoreID.coles.websiteDataID != StoreID.woolworths.websiteDataID, "stable per-store identifiers are distinct")
        func rejects(_ mutate: (inout [String: Any]) -> Void) throws -> Bool {
             var object = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
             mutate(&object)
             do {
                 _ = try StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))
                 return false
             } catch { return true }
        }
         let badVersion = try rejects { $0["schemaVersion"] = 99 }
          let badArea = try rejects { $0["serviceArea"] = ["countryCodes": ["Australia"]] }
          let unsupportedArea = try rejects { $0["serviceArea"] = ["countryCodes": ["ZZ"]] }
         let missingArea = try rejects { $0.removeValue(forKey: "serviceArea") }
         let duplicateArea = try rejects { $0["serviceArea"] = ["countryCodes": ["AU", "AU"]] }
         let unknownField = try rejects { $0["futureAutomation"] = true }
         let unknownNestedField = try rejects {
             var cart = $0["cart"] as! [String: Any]
             cart["executableScript"] = "unexpected"
             $0["cart"] = cart
         }
         let badHome = try rejects { $0["homepage"] = "https://evil.test" }
         let badHosts = try rejects { $0["allowedHosts"] = ["evil.test"] }
        let badStrategy = try rejects { $0["search"] = ["strategy": "executeScript", "template": "https://www.coles.com.au?q={query}"] }
        let badTemplate = try rejects { $0["search"] = ["strategy": "urlTemplate", "template": "https://www.coles.com.au?q={query}{query}"] }
        let missingCart = try rejects { $0["cart"] = NSNull() }
         let badCapabilities = try rejects { $0["capabilities"] = ["search": true, "cartDetection": false, "cartUndo": true] }
          check(badVersion && badArea && unsupportedArea && missingArea && duplicateArea && unknownField && unknownNestedField && badHome && badHosts
               && badStrategy && badTemplate && missingCart && badCapabilities,
               "invalid configuration contracts, unknown keys and capability dependencies are rejected")
         for id in StoreID.allCases {
             let fallback = StoreDefinition.load(id)
             check(!fallback.isConfigurationValid && !fallback.capabilities.search
                   && !fallback.capabilities.cartDetection && !fallback.capabilities.cartUndo
                   && fallback.cart == nil && fallback.serviceArea.countryCodes.isEmpty
                   && fallback.allows(id.home), "bad/missing configuration closes all automation and retains safe browsing for \(id)")
         }

         let preferenceSuite = "ListRunner.RecoveryTests.\(UUID().uuidString)"
         let preferenceDefaults = UserDefaults(suiteName: preferenceSuite)!
         defer { preferenceDefaults.removePersistentDomain(forName: preferenceSuite) }
          preferenceDefaults.set("nearby", forKey: "storeSortMode.v1")
          let migratedPreferences = StoreVisibilityPreferences(defaults: preferenceDefaults, suggestedCountryCode: "au")
          check(migratedPreferences.useLocalIngredientNames
                && migratedPreferences.ingredientSearchContext == IngredientSearchContext(countryCode: "AU", enabled: true),
                "regional names default on using the existing country")
          migratedPreferences.setUseLocalIngredientNames(false)
          let restoredNaming = StoreVisibilityPreferences(defaults: preferenceDefaults, suggestedCountryCode: "US")
          check(!restoredNaming.useLocalIngredientNames && restoredNaming.ingredientSearchContext.countryCode == "AU",
                "explicit naming opt-out and country persist independently of device region")
          restoredNaming.setShoppingCountry("NZ")
          check(restoredNaming.ingredientSearchContext == IngredientSearchContext(countryCode: "NZ", enabled: false),
                "country changes do not enable naming")
          restoredNaming.setUseLocalIngredientNames(true)
          check(restoredNaming.ingredientSearchContext == IngredientSearchContext(countryCode: "NZ", enabled: true),
                "enabling naming uses current country atomically")
          restoredNaming.setShoppingCountry("AU")
          let namingDictionary = try IngredientDictionary(data: Data(contentsOf: resources.appendingPathComponent("ingredients.json")))
          let namingCatalogue = try RegionalIngredientNames(data: Data(contentsOf: resources.appendingPathComponent("ingredient-regional-names.json")), dictionary: namingDictionary)
          let namingResolver = RegionalIngredientSearchResolver(dictionary: namingDictionary, catalogue: namingCatalogue)
          let savedIngredient = GroceryItem(name: "Zucchini", amount: 2, unit: "kg", position: 9, listID: StoreID.coles.listID)
          savedIngredient.status = .added
          savedIngredient.paprikaReminderID = "unchanged-reminder"
          let savedID = savedIngredient.id
          check(namingResolver.resolve(savedIngredient.searchTerm, context: IngredientSearchContext(countryCode: "NZ", enabled: true)).query == "courgette",
                "existing saved search terms resolve without an import or migration")
          check(savedIngredient.id == savedID && savedIngredient.name == "Zucchini" && savedIngredient.searchTerm == "Zucchini"
                && savedIngredient.quantityAmount == 2 && savedIngredient.quantityUnit == "kg" && savedIngredient.position == 9
                && savedIngredient.status == .added && savedIngredient.listID == StoreID.coles.listID
                && savedIngredient.paprikaReminderID == "unchanged-reminder", "regional resolution never mutates saved ingredient fields")
          check(migratedPreferences.visibleIDs == Set([.coles, .woolworths, .bunnings])
                && !migratedPreferences.visibleIDs.contains(.costco) && !migratedPreferences.visibleIDs.contains(.tesco)
                && !migratedPreferences.visibleIDs.contains(.walmart) && !migratedPreferences.visibleIDs.contains(.kmart),
                 "existing stores remain visible while newly introduced stores start hidden")
          check(migratedPreferences.hasCompletedStoreSetup, "legacy installs do not receive first-time welcome")
          migratedPreferences.setVisible(true, for: .costco)
          check(StoreVisibilityPreferences(defaults: preferenceDefaults).visibleIDs.contains(.costco),
                "enabling Costco persists without enabling another store")
         for store in StoreID.allCases { migratedPreferences.setVisible(false, for: store) }
          check(migratedPreferences.shoppingCountryCode == "AU" && preferenceDefaults.object(forKey: "storeSortMode.v1") == nil,
                "legacy Nearby migrates to device-region country suggestion without retaining a location mode")
          migratedPreferences.setShoppingCountry("NZ")
          let restoredPreferences = StoreVisibilityPreferences(defaults: preferenceDefaults, suggestedCountryCode: "US")
          check(restoredPreferences.visibleIDs.isEmpty && restoredPreferences.shoppingCountryCode == "NZ",
                "intentional all-hidden visibility and explicit country persist despite a changed device region")
          restoredPreferences.setShoppingCountry("ZZ")
          check(restoredPreferences.shoppingCountryCode == "NZ", "invalid country changes cannot overwrite an explicit choice")
          restoredPreferences.setShoppingCountry(nil)
          check(StoreVisibilityPreferences(defaults: preferenceDefaults, suggestedCountryCode: "AU").shoppingCountryCode == nil,
                "an explicitly unset country does not pick a new region on relaunch")
          for legacy in ["alphabetical", "nearby"] {
              preferenceDefaults.removePersistentDomain(forName: preferenceSuite)
              preferenceDefaults.set(legacy, forKey: "storeSortMode.v1")
              preferenceDefaults.set([String](), forKey: "visibleStoreIDs.v1")
              preferenceDefaults.set(StoreID.allCases.map(\.rawValue), forKey: "knownStoreIDs.v1")
              let migrated = StoreVisibilityPreferences(defaults: preferenceDefaults, suggestedCountryCode: "ZZ")
              check(migrated.visibleIDs.isEmpty && migrated.shoppingCountryCode == nil
                    && preferenceDefaults.object(forKey: "storeSortMode.v1") == nil,
                    "both old sort modes preserve all-hidden visibility and allow an unset country")
          }
          restoredPreferences.setVisible(true, for: .coles)
         check(StoreCatalogue.ordered([coles, woolworths, bunnings], countryCode: "AU",
                                      enabledIDs: restoredPreferences.visibleIDs).map(\.id) == [.coles],
                "enabled-store filtering does not alter the persisted store-owned catalogue")

          let australian = StoreCatalogue.sections([coles, woolworths, bunnings], countryCode: "AU", locale: Locale(identifier: "en_AU"))
          check(australian.count == 1 && australian[0].stores.map(\.id) == [.bunnings, .coles, .woolworths]
                && australian[0].indexTitle == nil && !australian[0].beginsOtherStores,
                "AU-only production catalogue hides empty Other Stores and the letter index")
          let overseas = StoreCatalogue.sections([coles, woolworths, bunnings], countryCode: "NZ")
          check(overseas.map(\.indexTitle) == ["B", "C", "W"] && overseas.first?.beginsOtherStores == true,
                "no-local-match catalogue retains all stores with only real index targets")
          let unset = StoreCatalogue.sections([coles, woolworths, bunnings], countryCode: nil)
          check(unset.map(\.indexTitle) == ["B", "C", "W"] && unset.allSatisfy { !$0.beginsOtherStores },
                "unset country provides plain alphabetical discovery without implying foreign stores")
          func withCountries(_ original: StoreDefinition, _ codes: [String]) -> StoreDefinition {
              StoreDefinition(schemaVersion: original.schemaVersion, id: original.id, displayName: original.displayName,
                              serviceArea: .init(countryCodes: codes), homepage: original.homepage, allowedHosts: original.allowedHosts,
                               search: original.search, addedColor: original.addedColor, brandColors: original.brandColors,
                               automationSchemaVersion: original.automationSchemaVersion,
                               categories: original.categories,
                               category: original.category,
                               capabilities: original.capabilities, cart: original.cart)
          }
          let multiCountry = withCountries(woolworths, ["AU", "NZ"])
          let mixed = StoreCatalogue.sections([coles, multiCountry, bunnings], countryCode: "NZ")
          check(mixed.count == 3 && mixed[0].stores.map(\.id) == [.woolworths]
                && mixed[1].beginsOtherStores && mixed.dropFirst().map(\.indexTitle) == ["B", "C"],
                "multi-country retailer appears once in local group and never in foreign letter groups")
          let matches = StoreCatalogue.sections([coles, multiCountry, bunnings], countryCode: "NZ", search: "CoLeS")
          check(matches.count == 1 && matches[0].stores.map(\.id) == [.coles] && matches[0].indexTitle == nil,
                "search is case-insensitive and flat, independent of country and visibility")
          check(StoreCatalogue.sections([coles], countryCode: "AU", search: "unknown").isEmpty,
                "no matching store names return an empty result")
          let badCountry = withCountries(coles, [])
          let invalidSections = StoreCatalogue.sections([badCountry, bunnings], countryCode: "AU")
          check(invalidSections.count == 1 && invalidSections[0].stores.map(\.id) == [.bunnings],
                 "invalid setup cannot appear as an available shopping destination")
          check(StoreCatalogue.sections([], countryCode: "AU").isEmpty, "empty catalogues contain no empty sections")
          check(StoreCatalogue.indexTitle(for: "Épicerie", locale: Locale(identifier: "en_AU")) == "E",
                "accented initial letters map to a usable index target")
          for name in ["123 Foods", "🍎 Market", ""] {
              check(StoreCatalogue.indexTitle(for: name) == "#", "non-letter initials use the final # index target")
          }

        let bridge: [String: Any] = ["schemaVersion": 1, "storeID": "coles", "sessionID": "session", "interactionID": "interaction",
            "itemID": UUID().uuidString, "documentGeneration": 1, "pageURL": "https://www.coles.com.au/search?q=milk",
            "type": "addDetected", "productID": "123", "confirmationID": "1", "beforeQuantity": 0, "resultingQuantity": 1]
        func bridgeRaw(_ object: [String: Any]) throws -> String {
            String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        let validBridge = try bridgeRaw(bridge)
        check(StoreBridge.decode(validBridge, store: coles) != nil, "valid configured bridge schema")
        check(StoreBridge.decode(validBridge, store: woolworths) == nil, "native cross-store bridge rejection")
        check(StoreBridge.decode(validBridge, store: costco) == nil, "Costco rejects another retailer's bridge events")
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
        var ikeaBridge = bridge
        ikeaBridge["storeID"] = "ikeaAU"
        ikeaBridge["pageURL"] = "https://www.ikea.com/au/en/search/?q=spoon"
        ikeaBridge["productID"] = "40515525"
        let ikeaBridgeRaw = try bridgeRaw(ikeaBridge)
        check(StoreBridge.decode(ikeaBridgeRaw, store: ikea) != nil,
              "IKEA exact article quantity confirmation uses the existing bounded native bridge")
        for (field, value) in [("productID", "405.155.25" as Any), ("productID", "4051552" as Any),
                               ("beforeQuantity", false as Any), ("resultingQuantity", true as Any),
                               ("pageURL", "https://www.ikea.com/us/en/search/?q=spoon" as Any)] {
            var invalid = ikeaBridge; invalid[field] = value
            let raw = try bridgeRaw(invalid)
            check(StoreBridge.decode(raw, store: ikea) == nil, "IKEA bridge rejects non-article, coercible or foreign-locale evidence")
        }
        var preflight = ikeaBridge
        for field in ["productID", "confirmationID", "beforeQuantity", "resultingQuantity"] { preflight.removeValue(forKey: field) }
        preflight["type"] = "automationUnavailable"
        preflight["capability"] = "cartDetection"
        preflight["scope"] = "interaction"
        preflight["reason"] = "cartPreflightUnavailable"
        let ikeaPreflightRaw = try bridgeRaw(preflight)
        check(StoreBridge.decode(ikeaPreflightRaw, store: ikea) != nil, "IKEA distinguishes an unsent Add from an unconfirmed Add")
        preflight["storeID"] = "coles"; preflight["pageURL"] = "https://www.coles.com.au/search?q=milk"
        let passivePreflightRaw = try bridgeRaw(preflight)
        check(StoreBridge.decode(passivePreflightRaw, store: coles) == nil,
              "passive retailers cannot claim that their original Add was intercepted")
        let prospectiveJB = expansionDefinitions.first { $0.id == .jbHiFi }!
        var acknowledgementBridge = bridge
        acknowledgementBridge["storeID"] = "jbHiFi"
        acknowledgementBridge["pageURL"] = "https://www.jbhifi.com.au/search?query=usb"
        acknowledgementBridge["type"] = "addAcknowledged"
        acknowledgementBridge["productID"] = "belkin-hi-speed-usb-cable-1-8-metres"
        acknowledgementBridge["profileID"] = "product-card"
        acknowledgementBridge.removeValue(forKey: "beforeQuantity")
        acknowledgementBridge.removeValue(forKey: "resultingQuantity")
        let validAcknowledgementBridge = try bridgeRaw(acknowledgementBridge)
        check(StoreBridge.decode(validAcknowledgementBridge, store: prospectiveJB) != nil,
              "acknowledgement bridge supports reviewed nonnumeric identity without fabricated quantities")
        for (key, value) in [("productID", "unsafe/sku" as Any), ("profileID", "other" as Any),
                             ("beforeQuantity", 0 as Any), ("resultingQuantity", 1 as Any),
                             ("confirmationID", true as Any), ("injected", "field" as Any)] {
            var invalid = acknowledgementBridge
            invalid[key] = value
            let raw = try bridgeRaw(invalid)
            check(StoreBridge.decode(raw, store: prospectiveJB) == nil,
                  "acknowledgement bridge rejects invalid \(key)")
        }
        for mutation in ["schema", "quantity", "undo", "emptySuccess", "unknownKey"] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(prospectiveJB)) as! [String: Any]
            var cart = object["cart"] as! [String: Any]
            var profiles = cart["profiles"] as! [[String: Any]]
            var acknowledgement = profiles[0]["acknowledgement"] as! [String: Any]
            switch mutation {
            case "schema": object["schemaVersion"] = 3; object.removeValue(forKey: "categories"); object.removeValue(forKey: "automationSchemaVersion")
            case "quantity": profiles[0]["quantitySelector"] = "input"
            case "undo": object["capabilities"] = ["search": true, "cartDetection": true, "cartUndo": true]
            case "emptySuccess": acknowledgement["successText"] = " "
            default: acknowledgement["script"] = "arbitrary code"
            }
            profiles[0]["acknowledgement"] = acknowledgement
            cart["profiles"] = profiles; object["cart"] = cart
            check((try? StoreDefinition.decodeConfiguration(from: JSONSerialization.data(withJSONObject: object))) == nil,
                  "acknowledgement configuration rejects \(mutation)")
        }

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
        let paprikaStaged = PaprikaImportPlanner.stage(reminders: paprikaSnapshot, existingIDs: ["existing"], parser: ingredientParser)
        check(PaprikaImportPlanner.canRemove(calendarID: "named-list", selectedCalendarID: "named-list", title: "milk", originalTitle: "milk", isCompleted: false),
              "named Reminders list can be cleaned up by stable identity")
        check(!PaprikaImportPlanner.canRemove(calendarID: "other-list", selectedCalendarID: "named-list", title: "milk", originalTitle: "milk", isCompleted: false),
              "same-title reminder moved to another list cannot be removed")
        check(!PaprikaImportPlanner.canRemove(calendarID: "named-list", selectedCalendarID: "named-list", title: "changed", originalTitle: "milk", isCompleted: false),
              "externally changed reminder cannot be removed")
        check(!PaprikaImportPlanner.canRemove(calendarID: "named-list", selectedCalendarID: "named-list", title: "milk", originalTitle: "milk", isCompleted: true),
              "externally completed reminder cannot be removed")
        check(PaprikaImportPlanner.removalCandidates(reminders: paprikaSnapshot, savedIDs: [], parser: ingredientParser).isEmpty,
              "no committed reminder identities means no destructive cleanup")
        let removalIDs = PaprikaImportPlanner.removalCandidates(reminders: paprikaSnapshot, savedIDs: ["late", "blank", "existing"], parser: ingredientParser).map(\.id)
        check(removalIDs == ["late", "existing"], "cleanup only targets saved, readable, unique reminders")
        check(PaprikaImportPlanner.emptyImportError(reminders: [], existingIDs: [], parser: ingredientParser) == .noUncheckedItems,
              "empty Paprika snapshot explains unchecked groceries rather than duplicates")
        check(PaprikaImportPlanner.emptyImportError(reminders: [paprikaSnapshot[0]], existingIDs: ["late"], parser: ingredientParser) == .noNewItems,
              "already imported Paprika snapshot explains duplicate reminder identities")
        check(PaprikaImportPlanner.emptyImportError(reminders: [paprikaSnapshot[0], paprikaSnapshot[3]], existingIDs: ["late"], parser: ingredientParser) == .noNewItems,
              "ignored blank reminders do not obscure an already-imported outcome")
        check(PaprikaImportPlanner.emptyImportError(reminders: [paprikaSnapshot[3]], existingIDs: ["existing"], parser: ingredientParser) == .noReadableItems,
              "blank titles have a distinct no-readable-groceries outcome")
        check(paprikaStaged.map(\.grocery.name) == ["Milk", "Bread", "Apples"], "Paprika import is creation-ordered, duplicate-safe and ignores blank titles: \(paprikaStaged.map(\.grocery.name))")
        check(paprikaStaged.first?.grocery.amount == 2 && paprikaStaged.first?.grocery.unit == "l", "Paprika title uses grocery quantity parser")
        let mayonnaise = PaprikaImportPlanner.stage(
            reminders: [PaprikaReminderSnapshot(id: "mayonnaise", title: "1 cup mayonnaise", creationDate: nil)],
            existingIDs: [], parser: ingredientParser
        )
        check(mayonnaise.count == 1 && mayonnaise[0].grocery.name == "Mayonnaise"
              && mayonnaise[0].grocery.amount == 1 && mayonnaise[0].grocery.unit == "cup",
              "Paprika cup measure preserves amount and unit while parsing grocery name")
        check(paprikaStaged.map(\.reminderID) == ["old", "late", "undated"], "Paprika source identity remains linked to imported rows")
        let reimported = PaprikaImportPlanner.stage(reminders: paprikaSnapshot,
                                                    existingIDs: Set(paprikaStaged.compactMap(\.reminderID)).union(["existing"]), parser: ingredientParser)
        check(reimported.isEmpty,
              "re-import ignores already-linked Paprika reminder IDs: \(reimported.map { ($0.reminderID ?? "nil") + ":" + $0.grocery.name })")
        let multiTitle = PaprikaImportPlanner.stage(reminders: [PaprikaReminderSnapshot(id: "comma", title: "milk, bread", creationDate: nil)], existingIDs: [], parser: ingredientParser)
        check(multiTitle.map(\.grocery.name) == ["Milk", "Bread"] && multiTitle.map(\.reminderID) == ["comma", nil],
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
        let legacyDiagnostic = try JSONDecoder().decode(DiagnosticEntry.self, from: encoder.encode(memory.entries[0]))
        check(legacyDiagnostic.failureDomain == nil && legacyDiagnostic.failureCode == nil
              && legacyDiagnostic.httpStatus == nil && legacyDiagnostic.browsingActive == nil,
              "older diagnostics decode without new failure metadata")
        let failureRecords = DiagnosticStore(fileURL: nil, clock: { now })
        for code in [NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet] {
            failureRecords.record(.store, .load, reason: .network, outcome: .failed, host: .bunnings,
                                  failureDomain: .url, failureCode: DiagnosticEntry.FailureCode(rawValue: code), browsingActive: false)
        }
        failureRecords.record(.store, .load, reason: .httpResponse, outcome: .failed, host: .bunnings,
                              httpStatus: 503, browsingActive: true)
        check(failureRecords.entries.count == 3, "distinct failure codes/statuses are not throttled together")
        let failureData = try encoder.encode(failureRecords.entries)
        let decodedFailures = try JSONDecoder().decode([DiagnosticEntry].self, from: failureData)
        check(decodedFailures == failureRecords.entries,
              "safe failure metadata round-trips")
        let failurePayloads = try JSONSerialization.jsonObject(with: failureData) as! [[String: Any]]
        let failureKeys: Set<String> = ["timestamp", "sequence", "category", "event", "reason", "outcome", "host",
                                        "failureDomain", "failureCode", "httpStatus", "browsingActive"]
        check(failurePayloads.allSatisfy { Set($0.keys).isSubset(of: failureKeys) },
              "failure diagnostics contain only closed metadata, no descriptions or URLs")
        check(DiagnosticEntry.FailureCode(rawValue: 987654) == nil,
              "unreviewed numeric error codes cannot enter persistent diagnostics")

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
        disk.record(.store, .load, outcome: .succeeded, host: .costco)
        disk.record(.store, .load, outcome: .succeeded, host: .costcoBare)
        disk.record(.store, .load, outcome: .succeeded, host: .costcoUS)
        try disk.clear(storeID: .costco)
        check(disk.entries.count == 3 && disk.entries.contains { $0.host == .www } && disk.entries.contains { $0.host == .costcoUS },
              "Costco diagnostics clearing removes both exact Costco hosts and preserves Coles/app records")
        try disk.clear(storeID: .costcoUS)
        check(disk.entries.count == 2 && disk.entries.contains { $0.host == .www }, "US Costco diagnostic reset is independent of Australia's")

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
        check(migratedItems.count == 1 && Set(migratedLists.map(\.id)) == Set(StoreID.allCases.map(\.listID)),
              "legacy items retained with a separate list for every bundled store")
        let original = migratedItems[0]
        check(original.id == originalID && original.listID == StoreID.coles.listID, "legacy UUID preserved in Coles list")
        check(original.name == "BBQ Sauce" && original.searchTerm == "BBQ Sauce" && original.quantityAmount == 2 && original.quantityUnit == "bottles", "legacy names and quantities preserved")
        check(original.status == .added && original.position == 7, "legacy status and position preserved")
        let colesList = migratedLists.first { $0.id == StoreID.coles.listID }!
        check(colesList.selectedItemID == originalID, "legacy selected item migrated")
        try ShoppingLists.prepare(migrated.mainContext, legacySelectedID: originalID)
        let listCount = try migrated.mainContext.fetchCount(FetchDescriptor<GroceryList>())
        check(listCount == StoreID.allCases.count, "list backfill is idempotent")
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
        let scrollPreferences = StoreVisibilityPreferences(defaults: defaults)
        check(scrollPreferences.autoScrollToResults, "auto-scroll defaults on")
        scrollPreferences.setAutoScrollToResults(false)
        check(!StoreVisibilityPreferences(defaults: defaults).autoScrollToResults, "auto-scroll opt-out persists")
        scrollPreferences.setAutoScrollToResults(true)
        check(StoreVisibilityPreferences(defaults: defaults).autoScrollToResults, "auto-scroll opt-in persists")
        scrollPreferences.setAutoScrollToResults(false)
        check(GroceryImportSource(rawValue: defaults.string(forKey: GroceryImportSource.preferenceKey) ?? "") == nil,
              "unset import source requires explicit setup")
        check(GroceryImportSource(rawValue: "future-source") == nil,
              "unknown import source returns to setup rather than importing Paprika")
        defaults.set("paprika", forKey: GroceryImportSource.preferenceKey)
        defaults.set(false, forKey: GroceryImportSource.removeRemindersKey)
        defaults.set("weekly-list-id", forKey: GroceryImportSource.remindersListIDKey)
        defaults.set("Weekly Shopping", forKey: GroceryImportSource.remindersListNameKey)
        defaults.set("preserve", forKey: "unrelated-import-reset-test")
        GroceryImportSource.resetSetup(in: defaults)
        check([GroceryImportSource.preferenceKey, GroceryImportSource.removeRemindersKey,
               GroceryImportSource.remindersListIDKey, GroceryImportSource.remindersListNameKey]
            .allSatisfy { defaults.object(forKey: $0) == nil }, "import setup reset clears only its four preferences")
        check(defaults.string(forKey: "unrelated-import-reset-test") == "preserve",
              "import setup reset preserves unrelated preferences")
        defaults.set(GroceryImportSource.paprika.rawValue, forKey: GroceryImportSource.preferenceKey)
        check(GroceryImportSource(rawValue: UserDefaults(suiteName: suiteName)!.string(forKey: GroceryImportSource.preferenceKey)!) == .paprika,
              "explicit Paprika selection survives preferences reload")
         defaults.set("saved-selection", forKey: "lastOverlaySelectedItemID")
         defaults.set(["coles"], forKey: "visibleStoreIDs.v1")
         defaults.set(["coles", "woolworths", "bunnings"], forKey: "knownStoreIDs.v1")
         defaults.set("nearby", forKey: "storeSortMode.v1")
         defaults.set("NZ", forKey: "shoppingCountry.v1")
         defaults.set(true, forKey: "shoppingCountryInitialized.v1")
         defaults.set(false, forKey: "useLocalIngredientNames.v1")
         defaults.set(["costco": "costcoUS"], forKey: "storeRegionalChoices.v1")
          defaults.set(true, forKey: "selectEnabledStoreAfterEmpty.v1")
          defaults.set("dark", forKey: "appearance.v1")
           try disk.clear()
          check(defaults.string(forKey: GroceryImportSource.preferenceKey) == "paprika",
                "diagnostics clearing preserves import source")
           check(defaults.object(forKey: "useLocalIngredientNames.v1") as? Bool == false, "diagnostics clearing preserves naming opt-out")
           check(defaults.object(forKey: "autoScrollToResults.v1") as? Bool == false, "diagnostics clearing preserves auto-scroll opt-out")
         check(defaults.string(forKey: "shoppingCountry.v1") == "NZ"
               && defaults.array(forKey: "visibleStoreIDs.v1") as? [String] == ["coles"],
               "clearing diagnostics preserves country and visibility preferences")
         check(defaults.string(forKey: "appearance.v1") == "dark", "clearing diagnostics preserves appearance")
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
        defaults.set(["bigW"], forKey: "pendingEnabledStoreSelection.v1")
        let allItemsPreferenceKeys = ["allItemsScope.v1", "allItemsGrouping.v1", "allItemsDraft.v1",
                                      "allItemsAddDestination.v1", "allItemsRecentStoreOrder.v1", "allItemsRecentItemOrder.v1"]
        for key in allItemsPreferenceKeys { defaults.set("test", forKey: key) }
        allowOpen = true
        storage.resetAfterConfirmation()
        check(storage.container != nil, "confirmed local reset opens an empty store")
        let emptyCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(emptyCount == 0, "reset store contains no items")
        check(allItemsPreferenceKeys.allSatisfy { defaults.object(forKey: $0) == nil },
              "confirmed local reset clears all aggregate preferences and sidecar ordering only with the database")
        check(defaults.object(forKey: GroceryImportSource.preferenceKey) == nil,
              "confirmed local reset clears import source and restores setup")
        check(defaults.object(forKey: "useLocalIngredientNames.v1") == nil,
              "local reset removes naming preference")
        check(defaults.object(forKey: "autoScrollToResults.v1") == nil,
              "local reset removes auto-scroll preference")
        check(defaults.object(forKey: "appearance.v1") == nil,
              "local reset restores system appearance")
         check(defaults.string(forKey: "lastOverlaySelectedItemID") == nil, "local reset clears app metadata")
         check(defaults.object(forKey: "visibleStoreIDs.v1") == nil
               && defaults.object(forKey: "knownStoreIDs.v1") == nil
                && defaults.object(forKey: "storeSortMode.v1") == nil
                && defaults.object(forKey: "shoppingCountry.v1") == nil
                 && defaults.object(forKey: "shoppingCountryInitialized.v1") == nil
                 && defaults.object(forKey: "storeRegionalChoices.v1") == nil
                  && defaults.object(forKey: "selectEnabledStoreAfterEmpty.v1") == nil
                  && defaults.object(forKey: "pendingEnabledStoreSelection.v1") == nil,
                "local reset clears store visibility, legacy ordering and shopping-country preferences")
        check(defaults.string(forKey: "unrelated") == "keep", "local reset preserves unrelated preferences")
        check(FileManager.default.fileExists(atPath: unrelatedFile.path), "local reset preserves neighboring files")
        check(disk.entries.isEmpty, "local reset clears diagnostics")
        check(StoreVisibilityPreferences(defaults: defaults, suggestedCountryCode: "NZ").useLocalIngredientNames,
              "local reset restores regional naming default on")
        check(StoreVisibilityPreferences(defaults: defaults).autoScrollToResults,
              "local reset restores auto-scroll default on")
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
        await website.httpCookieStore.setCookie(cookie(".bunnings.com.au", "bunnings-test"))
        await website.httpCookieStore.setCookie(cookie(".costco.com.au", "costco-test"))
        await website.httpCookieStore.setCookie(cookie(".costco.com", "costco-us-test"))
        await website.httpCookieStore.setCookie(cookie(".tesco.com", "tesco-test"))
        await website.httpCookieStore.setCookie(cookie(".walmart.com", "walmart-test"))
        for id in [StoreID.amazon, .kroger, .target] {
            await website.httpCookieStore.setCookie(cookie("." + id.dataDomain, id.rawValue + "-test"))
        }
        let cleared = await StoreWebsiteData.clear(in: website, for: .coles)
        check(cleared, "real nonpersistent WebKit deletion verifies success")
        let remaining = await website.httpCookieStore.allCookies()
        check(!remaining.contains { StoreID.coles.ownsDataDomain($0.domain) }, "Coles cookies removed")
        check(remaining.contains { $0.name == "unrelated-test" }, "unrelated website cookies preserved")
        check(remaining.contains { $0.name == "woolworths-test" }, "Coles reset preserves Woolworths cookies")
        check(remaining.contains { $0.name == "bunnings-test" }, "Coles reset preserves Bunnings cookies")
        check(remaining.contains { $0.name == "costco-test" }, "Coles reset preserves Costco cookies")
        let clearedWoolworths = await StoreWebsiteData.clear(in: website, for: .woolworths)
        check(clearedWoolworths, "Woolworths reset verifies its own data scope")
        let afterWoolworths = await website.httpCookieStore.allCookies()
        check(afterWoolworths.contains { $0.name == "unrelated-test" } && !afterWoolworths.contains { $0.name == "woolworths-test" }, "Woolworths reset preserves unrelated domains")
        check(afterWoolworths.contains { $0.name == "bunnings-test" }, "Woolworths reset preserves Bunnings cookies")
        let clearedBunnings = await StoreWebsiteData.clear(in: website, for: .bunnings)
        check(clearedBunnings, "Bunnings reset verifies its own data scope")
        let afterBunnings = await website.httpCookieStore.allCookies()
        check(afterBunnings.contains { $0.name == "unrelated-test" } && !afterBunnings.contains { $0.name == "bunnings-test" },
              "Bunnings reset preserves unrelated website cookies")
        check(afterBunnings.contains { $0.name == "costco-test" }, "other retailer resets preserve Costco cookies")
        await website.httpCookieStore.setCookie(cookie(".coles.com.au", "coles-kept-for-costco-reset"))
        let clearedCostco = await StoreWebsiteData.clear(in: website, for: .costco)
        check(clearedCostco, "Costco reset verifies its own website-data scope")
        let afterCostco = await website.httpCookieStore.allCookies()
        check(!afterCostco.contains { $0.name == "costco-test" }
              && afterCostco.contains { $0.name == "unrelated-test" }
              && afterCostco.contains { $0.name == "coles-kept-for-costco-reset" },
              "Costco reset removes only Costco cookies and preserves other retailer/unrelated data")
        check(afterCostco.contains { $0.name == "costco-us-test" }, "Australian Costco reset preserves US Costco cookies")
        await website.httpCookieStore.setCookie(cookie(".costco.com.au", "costco-au-preserved"))
        let clearedUS = await StoreWebsiteData.clear(in: website, for: .costcoUS)
        let afterUS = await website.httpCookieStore.allCookies()
        check(clearedUS && !afterUS.contains { $0.name == "costco-us-test" }
              && afterUS.contains { $0.name == "costco-au-preserved" }, "US Costco reset preserves Australian Costco cookies")
        check(afterCostco.contains { $0.name == "tesco-test" }, "Australian retailer resets preserve Tesco cookies")
        let clearedTesco = await StoreWebsiteData.clear(in: website, for: .tesco)
        let afterTesco = await website.httpCookieStore.allCookies()
        check(clearedTesco && !afterTesco.contains { $0.name == "tesco-test" }
              && afterTesco.contains { $0.name == "coles-kept-for-costco-reset" }
              && afterTesco.contains { $0.name == "unrelated-test" }, "Tesco reset preserves Australian and unrelated website data")
        check(afterTesco.contains { $0.name == "walmart-test" }, "other retailer resets preserve Walmart cookies")
        let clearedWalmart = await StoreWebsiteData.clear(in: website, for: .walmart)
        let afterWalmart = await website.httpCookieStore.allCookies()
        check(clearedWalmart && !afterWalmart.contains { $0.name == "walmart-test" }
              && afterWalmart.contains { $0.name == "coles-kept-for-costco-reset" }
               && afterWalmart.contains { $0.name == "unrelated-test" }, "Walmart reset preserves other store data")
        for id in [StoreID.amazon, .kroger, .target] {
            let before = await website.httpCookieStore.allCookies()
            check(before.contains { $0.name == id.rawValue + "-test" }, "other resets preserve each new US retailer's cookies")
            let result = await StoreWebsiteData.clear(in: website, for: id)
            let after = await website.httpCookieStore.allCookies()
            check(result && !after.contains { id.ownsDataDomain($0.domain) }, "each US reset clears its own website data")
            check(Set(after.map(\.name)) == Set(before.filter { !id.ownsDataDomain($0.domain) }.map(\.name)),
                  "each US reset preserves every other retailer and unrelated cookie")
        }
        let finalCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(finalCount == 1, "Coles reset leaves groceries unchanged")
        check(defaults.string(forKey: "unrelated") == "keep", "Coles reset leaves app preferences unchanged")
        print("PASS: \(checks) native recovery, reset-boundary and diagnostics checks")
    }
}
