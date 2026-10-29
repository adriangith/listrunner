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
        check(ShoppingCountry.validated("au") == "AU", "country preferences normalize ISO codes")
        for code in [nil, "", "ZZ", "Australia", "123"] as [String?] {
            check(ShoppingCountry.validated(code) == nil, "invalid/missing region suggestions do not guess a country")
        }
        let configData = try Data(contentsOf: resources.appendingPathComponent("coles.json"))
        let coles = try JSONDecoder().decode(StoreDefinition.self, from: configData)
        let woolworths = try JSONDecoder().decode(StoreDefinition.self, from: Data(contentsOf: resources.appendingPathComponent("woolworths.json")))
        let bunnings = try JSONDecoder().decode(StoreDefinition.self, from: Data(contentsOf: resources.appendingPathComponent("bunnings.json")))
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
        let brandDefinitions = [coles, woolworths, bunnings, costco, costcoUS, tesco, walmart, kmart]
        let emptySuite = "ListRunner.EmptyStoreTests.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        emptyDefaults.set("bunnings", forKey: "activeStoreID")
        let emptyPreferences = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(emptyPreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == .bunnings,
              "ordinary store management does not change the active store")
        for id in StoreID.allCases { emptyPreferences.setVisible(false, for: id) }
        check(emptyPreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == nil,
              "all-disabled state has no enabled destination")
        emptyPreferences.setVisible(true, for: .coles)
        let emptyRestored = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == .coles,
              "all-disabled then Coles-only selects Coles even after relaunch")
        check(emptyDefaults.string(forKey: "activeStoreID") == "bunnings",
              "visibility recovery waits for the list screen to apply the selection")
        check(emptyRestored.selectionForList(current: .coles, definitions: brandDefinitions) == .coles,
              "list reconciliation preserves an explicit enabled store choice")
        emptyRestored.setVisible(false, for: .coles)
        emptyRestored.setVisible(true, for: .woolworths)
        emptyRestored.setVisible(true, for: .coles)
        check(emptyRestored.selectionForList(current: .woolworths, definitions: brandDefinitions) == .woolworths,
              "recovery retains the previous active store if it is enabled again")
        for id in StoreID.allCases { emptyRestored.setVisible(false, for: id) }
        emptyRestored.setVisible(true, for: .woolworths)
        emptyRestored.setVisible(true, for: .coles)
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions.reversed()) == .coles,
              "multiple re-enabled stores use stable alphabetical selection, never a disabled list")
        let recoveryCostco = StoreBrand.catalogue(brandDefinitions).first { $0.id == "costco" }!
        for id in StoreID.allCases { emptyRestored.setVisible(false, for: id) }
        emptyRestored.chooseRegion(.costcoUS, for: recoveryCostco)
        emptyRestored.setBrandVisible(true, brand: recoveryCostco)
        check(emptyRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == .costcoUS,
              "brand switches recover to the explicitly selected enabled regional site")
        emptyRestored.chooseRegion(.costco, for: recoveryCostco)
        check(emptyRestored.selectionForList(current: .costcoUS, definitions: brandDefinitions) == .costco,
              "a disabled regional destination also resolves to an enabled list on return")
        let activePreferences = StoreVisibilityPreferences(defaults: UserDefaults(suiteName: emptySuite)!)
        activePreferences.setVisible(true, for: .coles)
        activePreferences.setVisible(true, for: .woolworths)
        activePreferences.setVisible(true, for: .bunnings)
        activePreferences.setVisible(false, for: .bunnings)
        check(activePreferences.selectionForList(current: .bunnings, definitions: brandDefinitions) == .coles,
              "disabling only active Bunnings selects enabled Coles without an all-disabled transition")
        let activeRestored = StoreVisibilityPreferences(defaults: emptyDefaults)
        check(activeRestored.selectionForList(current: .bunnings, definitions: brandDefinitions) == .coles,
              "relaunch repairs a previously persisted disabled active store")
        activeRestored.setShoppingCountry("US")
        check(activeRestored.selectionForList(current: .woolworths, definitions: brandDefinitions) == .woolworths,
              "country changes never switch an active store that remains enabled")
        let costcoBrand = StoreBrand.catalogue(brandDefinitions).first { $0.id == "costco" }!
        check(costcoBrand.regions.map(\.id) == [.costco, .costcoUS], "reviewed Costco regions share one brand entry")
        check(StoreBrand.catalogue(brandDefinitions).count == 7, "eight regional stores have seven brand rows")
        for country in ["AU", "US", "GB", "NZ", nil] as [String?] {
            let enabled: Set<StoreID> = [.coles, .costcoUS, .tesco]
            let groups = StoreBrand.sections(brandDefinitions, countryCode: country, search: "", enabledIDs: enabled)
            check(groups.first?.title == "Enabled stores"
                  && groups.first?.brands.map(\.id) == ["coles", "costco", "tesco"],
                  "enabled brands are first and alphabetical regardless of country")
            check(groups.dropFirst().flatMap(\.brands).allSatisfy { brand in
                !brand.regions.contains { enabled.contains($0.id) }
            }, "enabled brands never appear in local or other stores")
            check(groups.flatMap(\.brands).count == 7,
                  "enabled-first grouping preserves every brand exactly once")
            check(groups.compactMap(\.indexTitle).allSatisfy { letter in
                groups.contains { $0.indexTitle == letter && !$0.brands.isEmpty }
            }, "enabled-first grouping has no empty index entries")
        }
        let enabledSearch = StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "Costco US", enabledIDs: [.costcoUS])
        check(enabledSearch.count == 1 && enabledSearch.first?.title == "Matching stores"
              && enabledSearch.first?.brands.map(\.id) == ["costco"] && enabledSearch.first?.indexTitle == nil,
              "search finds enabled regional brands once without section index")
        let allEnabled = StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "", enabledIDs: Set(brandDefinitions.map(\.id)))
        check(allEnabled.count == 1 && allEnabled.first?.title == "Enabled stores",
              "all enabled hides empty country and other groups")
        for country in ["AU", "US"] {
            let groups = StoreBrand.sections(brandDefinitions, countryCode: country, search: "")
            check(groups.first?.brands.contains { $0.id == "costco" } == true
                  && groups.flatMap(\.brands).filter { $0.id == "costco" }.count == 1,
                  "Costco brand is local once in either supported region without duplicate switches")
        }
        check(StoreBrand.sections(brandDefinitions, countryCode: "AU", search: "Costco US").flatMap(\.brands).map(\.id) == ["costco"],
              "searching a regional name finds the single brand row")
        check(StoreBrand.sections(brandDefinitions, countryCode: "GB", search: "United States").flatMap(\.brands).contains { $0.id == "costco" },
              "searching a country finds a brand with that regional destination")
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
              && !kmart.capabilities.search && !kmart.capabilities.cartDetection && !kmart.capabilities.cartUndo && kmart.cart == nil,
              "Kmart Australia is browsing-only with all automation disabled")
        check(!StoreID.kmart.permitsSearch && !StoreID.kmart.permitsCartDetection && !StoreID.kmart.permitsCartUndo,
              "native Kmart policy prohibits unreviewed automation")
        check(bigW.isConfigurationValid && bigW.serviceArea.countryCodes == ["AU"]
              && !bigW.capabilities.search && !bigW.capabilities.cartDetection && !bigW.capabilities.cartUndo && bigW.cart == nil,
              "BIG W is browsing-only with all automation disabled")
        check(!StoreID.bigW.permitsSearch && !StoreID.bigW.permitsCartDetection && !StoreID.bigW.permitsCartUndo,
              "native BIG W policy prohibits unreviewed automation")
        check(bigW.allows(bigW.homepage) && bigW.allows(URL(string: "https://bigw.com.au")!)
              && !bigW.allows(URL(string: "https://www.bigw.co.nz")!)
              && !bigW.allows(URL(string: "https://www.bigw.com.au.evil.test")!), "BIG W hosts are exact and Australia-only")
        var widenedKmart = kmart
        widenedKmart.capabilities.search = true
        check(!widenedKmart.isConfigurationValid, "JSON cannot enable Kmart automatic search")
        check(kmart.allows(kmart.homepage) && kmart.allows(URL(string: "https://kmart.com.au")!)
              && !kmart.allows(URL(string: "https://www.kmart.co.nz")!)
              && !kmart.allows(URL(string: "https://www.kmart.com.au.evil.test")!)
              && !kmart.allows(URL(string: "https://login.kmart.com.au")!), "Kmart hosts are exact and Australia-only")
        let kmartCatalogue = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco, walmart, kmart], countryCode: "AU")
        check(kmartCatalogue.first?.stores.map(\.id) == [.bunnings, .coles, .costco, .kmart, .woolworths]
              && kmartCatalogue.dropFirst().map(\.indexTitle) == ["T", "W"],
              "Kmart joins Australia alphabetically without changing international groups")
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
              && !tesco.capabilities.search && !tesco.capabilities.cartDetection && !tesco.capabilities.cartUndo && tesco.cart == nil,
              "Tesco UK is a valid browsing-only definition with all automation off")
        check(!StoreID.tesco.permitsSearch && !StoreID.tesco.permitsCartDetection && !StoreID.tesco.permitsCartUndo,
              "native Tesco policy disallows all store automation")
        var widenedTesco = tesco
        widenedTesco.capabilities.search = true
        check(!widenedTesco.isConfigurationValid, "JSON cannot turn on Tesco search automation")
        let fiveStores = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco], countryCode: "AU")
        check(fiveStores.count == 2 && fiveStores[0].stores.count == 4
              && fiveStores[1].indexTitle == "T" && fiveStores[1].beginsOtherStores
              && fiveStores[1].stores.map(\.id) == [.tesco],
              "Tesco appears in Other Stores under T for an Australian shopping country")
        let britishStores = StoreCatalogue.sections([coles, woolworths, bunnings, costco, tesco], countryCode: "GB")
        check(britishStores.first?.stores.map(\.id) == [.tesco]
              && britishStores.dropFirst().flatMap(\.stores).count == 4,
              "choosing the UK moves Tesco to the local group without hiding Australian stores")
        check(tesco.allows(tesco.homepage) && !tesco.allows(URL(string: "https://www.tesco.ie")!)
              && !tesco.allows(URL(string: "https://www.tesco.com.evil.test")!)
              && !tesco.allows(coles.homepage), "Tesco UK browsing hosts remain exact and isolated")
        check(walmart.isConfigurationValid && walmart.serviceArea.countryCodes == ["US"]
              && !walmart.capabilities.search && !walmart.capabilities.cartDetection && !walmart.capabilities.cartUndo && walmart.cart == nil,
              "Walmart US is a valid browsing-only definition with no automation")
        check(!StoreID.walmart.permitsSearch && !StoreID.walmart.permitsCartDetection && !StoreID.walmart.permitsCartUndo,
              "native Walmart policy prohibits unreviewed store automation")
        var widenedWalmart = walmart
        widenedWalmart.capabilities.search = true
        check(!widenedWalmart.isConfigurationValid, "JSON cannot enable Walmart automatic searches")
        let allStores = [coles, woolworths, bunnings, costco, tesco, walmart]
        let auWithUS = StoreCatalogue.sections(allStores, countryCode: "AU")
        check(auWithUS.count == 3 && auWithUS[0].stores.count == 4
              && auWithUS.dropFirst().map(\.indexTitle) == ["T", "W"]
              && auWithUS.last?.stores.map(\.id) == [.walmart],
              "Australia groups Tesco and Walmart under real T/W nonlocal sections")
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
          check(migratedPreferences.visibleIDs == Set([.coles, .woolworths, .bunnings])
                && !migratedPreferences.visibleIDs.contains(.costco) && !migratedPreferences.visibleIDs.contains(.tesco)
                && !migratedPreferences.visibleIDs.contains(.walmart) && !migratedPreferences.visibleIDs.contains(.kmart),
                "existing stores remain visible while newly introduced stores start hidden")
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
          check(invalidSections.count == 2 && invalidSections[0].stores.map(\.id) == [.bunnings]
                && invalidSections[1].title == "Setup unavailable" && invalidSections[1].indexTitle == nil,
                "invalid setup stays accessible but never claims a validated country match")
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
         defaults.set("saved-selection", forKey: "lastOverlaySelectedItemID")
         defaults.set(["coles"], forKey: "visibleStoreIDs.v1")
         defaults.set(["coles", "woolworths", "bunnings"], forKey: "knownStoreIDs.v1")
         defaults.set("nearby", forKey: "storeSortMode.v1")
         defaults.set("NZ", forKey: "shoppingCountry.v1")
         defaults.set(true, forKey: "shoppingCountryInitialized.v1")
         defaults.set(["costco": "costcoUS"], forKey: "storeRegionalChoices.v1")
         defaults.set(true, forKey: "selectEnabledStoreAfterEmpty.v1")
         try disk.clear()
         check(defaults.string(forKey: "shoppingCountry.v1") == "NZ"
               && defaults.array(forKey: "visibleStoreIDs.v1") as? [String] == ["coles"],
               "clearing diagnostics preserves country and visibility preferences")
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
         check(defaults.object(forKey: "visibleStoreIDs.v1") == nil
               && defaults.object(forKey: "knownStoreIDs.v1") == nil
                && defaults.object(forKey: "storeSortMode.v1") == nil
                && defaults.object(forKey: "shoppingCountry.v1") == nil
                 && defaults.object(forKey: "shoppingCountryInitialized.v1") == nil
                 && defaults.object(forKey: "storeRegionalChoices.v1") == nil
                 && defaults.object(forKey: "selectEnabledStoreAfterEmpty.v1") == nil,
                "local reset clears store visibility, legacy ordering and shopping-country preferences")
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
        await website.httpCookieStore.setCookie(cookie(".bunnings.com.au", "bunnings-test"))
        await website.httpCookieStore.setCookie(cookie(".costco.com.au", "costco-test"))
        await website.httpCookieStore.setCookie(cookie(".costco.com", "costco-us-test"))
        await website.httpCookieStore.setCookie(cookie(".tesco.com", "tesco-test"))
        await website.httpCookieStore.setCookie(cookie(".walmart.com", "walmart-test"))
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
        let finalCount = try storage.container!.mainContext.fetchCount(FetchDescriptor<GroceryItem>())
        check(finalCount == 1, "Coles reset leaves groceries unchanged")
        check(defaults.string(forKey: "unrelated") == "keep", "Coles reset leaves app preferences unchanged")
        print("PASS: \(checks) native recovery, reset-boundary and diagnostics checks")
    }
}
