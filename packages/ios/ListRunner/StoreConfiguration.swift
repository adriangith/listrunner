import Foundation
import CoreFoundation
import Combine

enum StoreID: String, Codable, CaseIterable, Identifiable {
    case coles, woolworths, bunnings, costco, tesco, walmart, kmart, costcoUS, bigW, amazon, kroger, target
    case chemistWarehouse, priceline, officeworks, jbHiFi, targetAU, petbarn, supercheapAuto, bcf
    case bunningsNZ, theWarehouse, newWorld, paknsave, sainsburys, asda, morrisons, ocado, waitrose, boots, walgreens, cvs
    case ikeaAU
    #if STORE_REGISTRY_PROOF
    // Only compiled by the standalone extensibility proof, never the app.
    case synthetic
    #endif
    var id: String { rawValue }
    // Reviewed native ceilings: bundled data cannot enable unreviewed store automation.
    var permitsSearch: Bool {
        #if STORE_REGISTRY_PROOF
        if self == .synthetic { return true }
        #endif
        return [.coles, .woolworths, .bunnings, .costco, .tesco, .walmart, .kmart, .bigW, .kroger, .target,
         .chemistWarehouse, .priceline, .officeworks, .jbHiFi, .targetAU, .petbarn, .supercheapAuto, .bcf,
         .bunningsNZ, .theWarehouse, .sainsburys, .asda, .morrisons, .ocado, .waitrose, .walgreens, .ikeaAU].contains(self)
    }
    // Brand grouping is reviewed native identity, never inferred from a name or host.
    var brandID: String {
        switch self {
        case .costcoUS: StoreID.costco.rawValue
        case .bunningsNZ: StoreID.bunnings.rawValue
        default: rawValue
        }
    }
    var brandName: String {
        switch self {
        case .costcoUS: "Costco"
        case .bunningsNZ: "Bunnings"
        default: displayName
        }
    }
    var regionalCountryCode: String? {
        switch self {
        case .costco: "AU"
        case .costcoUS: "US"
        case .bunnings: "AU"
        case .bunningsNZ: "NZ"
        default: nil
        }
    }
    var permitsCartUndo: Bool { [.coles, .bigW, .tesco, .ikeaAU].contains(self) }
    var permitsCartDetection: Bool { [.coles, .woolworths, .bunnings, .tesco, .kmart, .bigW, .priceline, .supercheapAuto, .ocado, .chemistWarehouse, .waitrose, .jbHiFi, .bunningsNZ, .officeworks, .ikeaAU].contains(self) }
    var displayName: String {
        switch self {
        case .coles: "Coles"
        case .woolworths: "Woolworths"
        case .bunnings: "Bunnings"
        case .costco: "Costco"
        case .tesco: "Tesco"
        case .walmart: "Walmart"
        case .kmart: "Kmart"
        case .costcoUS: "Costco US"
        case .bigW: "BIG W"
        case .amazon: "Amazon US"
        case .kroger: "Kroger"
        case .target: "Target US"
        case .chemistWarehouse: "Chemist Warehouse"
        case .priceline: "Priceline"
        case .officeworks: "Officeworks"
        case .jbHiFi: "JB Hi-Fi"
        case .targetAU: "Target Australia"
        case .petbarn: "Petbarn"
        case .supercheapAuto: "Supercheap Auto"
        case .bcf: "BCF"
        case .bunningsNZ: "Bunnings New Zealand"
        case .theWarehouse: "The Warehouse"
        case .newWorld: "New World"
        case .paknsave: "PAK’nSAVE"
        case .sainsburys: "Sainsbury’s"
        case .asda: "Asda"
        case .morrisons: "Morrisons"
        case .ocado: "Ocado"
        case .waitrose: "Waitrose"
        case .boots: "Boots"
        case .walgreens: "Walgreens"
        case .cvs: "CVS"
        case .ikeaAU: "IKEA"
        #if STORE_REGISTRY_PROOF
        case .synthetic: "Example Hardware"
        #endif
        }
    }
    var defaultCategory: StoreCategory? {
        switch self {
        case .coles, .woolworths, .kroger, .morrisons, .newWorld, .ocado, .paknsave, .sainsburys, .tesco, .waitrose:
            .grocery
        case .costco, .costcoUS, .walmart, .asda, .target:
            .groceryHome
        case .kmart, .targetAU, .bigW, .theWarehouse:
            .clothingHome
        case .ikeaAU:
            .homeFurniture
        case .amazon:
            .onlineMarketplace
        case .bunnings, .bunningsNZ:
            .hardwareGarden
        case .chemistWarehouse, .priceline, .boots, .cvs, .walgreens:
            .pharmacyBeauty
        case .jbHiFi:
            .electronics
        case .officeworks:
            .officeSupplies
        case .petbarn:
            .petSupplies
        case .supercheapAuto:
            .automotive
        case .bcf:
            .outdoorCamping
        #if STORE_REGISTRY_PROOF
        case .synthetic:
            .grocery
        #endif
        // Unreviewed disabled onboarding drafts have no compatibility mapping.
        // Do not guess a category for a newly generated registration.
        default: nil
        }
    }
    var hosts: Set<String> {
        switch self {
        case .coles: ["www.coles.com.au", "coles.com.au"]
        case .woolworths: ["www.woolworths.com.au", "woolworths.com.au"]
        case .bunnings: ["www.bunnings.com.au", "bunnings.com.au"]
        case .costco: ["www.costco.com.au", "costco.com.au"]
        case .tesco: ["www.tesco.com", "tesco.com"]
        case .walmart: ["www.walmart.com", "walmart.com"]
        case .kmart: ["www.kmart.com.au", "kmart.com.au"]
        case .costcoUS: ["www.costco.com", "costco.com"]
        case .bigW: ["www.bigw.com.au", "bigw.com.au"]
        case .amazon: ["www.amazon.com", "amazon.com"]
        case .kroger: ["www.kroger.com", "kroger.com"]
        case .target: ["www.target.com", "target.com"]
        case .chemistWarehouse: ["www.chemistwarehouse.com.au", "chemistwarehouse.com.au"]
        case .priceline: ["www.priceline.com.au", "priceline.com.au"]
        case .officeworks: ["www.officeworks.com.au", "officeworks.com.au"]
        case .jbHiFi: ["www.jbhifi.com.au", "jbhifi.com.au"]
        case .targetAU: ["www.target.com.au", "target.com.au"]
        case .petbarn: ["www.petbarn.com.au", "petbarn.com.au"]
        case .supercheapAuto: ["www.supercheapauto.com.au", "supercheapauto.com.au"]
        case .bcf: ["www.bcf.com.au", "bcf.com.au"]
        case .bunningsNZ: ["www.bunnings.co.nz", "bunnings.co.nz"]
        case .theWarehouse: ["www.thewarehouse.co.nz", "thewarehouse.co.nz"]
        case .newWorld: ["www.newworld.co.nz", "newworld.co.nz"]
        case .paknsave: ["www.paknsave.co.nz", "paknsave.co.nz"]
        case .sainsburys: ["www.sainsburys.co.uk", "sainsburys.co.uk"]
        case .asda: ["www.asda.com", "asda.com", "groceries.asda.com"]
        case .morrisons: ["groceries.morrisons.com"]
        case .ocado: ["www.ocado.com", "ocado.com"]
        case .waitrose: ["www.waitrose.com", "waitrose.com"]
        case .boots: ["www.boots.com", "boots.com"]
        case .walgreens: ["www.walgreens.com", "walgreens.com"]
        case .cvs: ["www.cvs.com", "cvs.com"]
        case .ikeaAU: ["www.ikea.com", "ikea.com"]
        #if STORE_REGISTRY_PROOF
        case .synthetic: ["www.store.example"]
        #endif
        }
    }
    var dataDomain: String {
        switch self {
        case .coles: "coles.com.au"
        case .woolworths: "woolworths.com.au"
        case .bunnings: "bunnings.com.au"
        case .costco: "costco.com.au"
        case .tesco: "tesco.com"
        case .walmart: "walmart.com"
        case .kmart: "kmart.com.au"
        case .costcoUS: "costco.com"
        case .bigW: "bigw.com.au"
        case .amazon: "amazon.com"
        case .kroger: "kroger.com"
        case .target: "target.com"
        case .chemistWarehouse: "chemistwarehouse.com.au"
        case .priceline: "priceline.com.au"
        case .officeworks: "officeworks.com.au"
        case .jbHiFi: "jbhifi.com.au"
        case .targetAU: "target.com.au"
        case .petbarn: "petbarn.com.au"
        case .supercheapAuto: "supercheapauto.com.au"
        case .bcf: "bcf.com.au"
        case .bunningsNZ: "bunnings.co.nz"
        case .theWarehouse: "thewarehouse.co.nz"
        case .newWorld: "newworld.co.nz"
        case .paknsave: "paknsave.co.nz"
        case .sainsburys: "sainsburys.co.uk"
        case .asda: "asda.com"
        case .morrisons: "morrisons.com"
        case .ocado: "ocado.com"
        case .waitrose: "waitrose.com"
        case .boots: "boots.com"
        case .walgreens: "walgreens.com"
        case .cvs: "cvs.com"
        case .ikeaAU: "ikea.com"
        #if STORE_REGISTRY_PROOF
        case .synthetic: "store.example"
        #endif
        }
    }
    var home: URL {
        if self == .ikeaAU { return URL(string: "https://www.ikea.com/au/en/")! }
        if self == .asda { return URL(string: "https://www.asda.com/groceries")! }
        if self == .morrisons { return URL(string: "https://groceries.morrisons.com")! }
        return URL(string: "https://www.\(dataDomain)")!
    }
    var listID: UUID {
        let value: String
        switch self {
        case .coles: value = "10000000-0000-4000-8000-000000000001"
        case .woolworths: value = "10000000-0000-4000-8000-000000000002"
        case .bunnings: value = "10000000-0000-4000-8000-000000000003"
        case .costco: value = "10000000-0000-4000-8000-000000000004"
        case .tesco: value = "10000000-0000-4000-8000-000000000005"
        case .walmart: value = "10000000-0000-4000-8000-000000000006"
        case .kmart: value = "10000000-0000-4000-8000-000000000007"
        case .costcoUS: value = "10000000-0000-4000-8000-000000000008"
        case .bigW: value = "10000000-0000-4000-8000-000000000009"
        case .amazon: value = "10000000-0000-4000-8000-000000000010"
        case .kroger: value = "10000000-0000-4000-8000-000000000011"
        case .target: value = "10000000-0000-4000-8000-000000000012"
        case .chemistWarehouse: value = "10000000-0000-4000-8000-000000000013"
        case .priceline: value = "10000000-0000-4000-8000-000000000014"
        case .officeworks: value = "10000000-0000-4000-8000-000000000015"
        case .jbHiFi: value = "10000000-0000-4000-8000-000000000016"
        case .targetAU: value = "10000000-0000-4000-8000-000000000017"
        case .petbarn: value = "10000000-0000-4000-8000-000000000018"
        case .supercheapAuto: value = "10000000-0000-4000-8000-000000000019"
        case .bcf: value = "10000000-0000-4000-8000-000000000020"
        case .bunningsNZ: value = "10000000-0000-4000-8000-000000000021"
        case .theWarehouse: value = "10000000-0000-4000-8000-000000000022"
        case .newWorld: value = "10000000-0000-4000-8000-000000000023"
        case .paknsave: value = "10000000-0000-4000-8000-000000000024"
        case .sainsburys: value = "10000000-0000-4000-8000-000000000025"
        case .asda: value = "10000000-0000-4000-8000-000000000026"
        case .morrisons: value = "10000000-0000-4000-8000-000000000027"
        case .ocado: value = "10000000-0000-4000-8000-000000000028"
        case .waitrose: value = "10000000-0000-4000-8000-000000000029"
        case .boots: value = "10000000-0000-4000-8000-000000000030"
        case .walgreens: value = "10000000-0000-4000-8000-000000000031"
        case .cvs: value = "10000000-0000-4000-8000-000000000032"
        case .ikeaAU: value = "10000000-0000-4000-8000-000000000033"
        #if STORE_REGISTRY_PROOF
        case .synthetic: value = "10000000-0000-4000-8000-000000000099"
        #endif
        }
        return UUID(uuidString: value)!
    }
    var websiteDataID: UUID {
        let value: String
        switch self {
        case .coles: value = "20000000-0000-4000-8000-000000000001"
        case .woolworths: value = "20000000-0000-4000-8000-000000000002"
        case .bunnings: value = "20000000-0000-4000-8000-000000000003"
        case .costco: value = "20000000-0000-4000-8000-000000000004"
        case .tesco: value = "20000000-0000-4000-8000-000000000005"
        case .walmart: value = "20000000-0000-4000-8000-000000000006"
        case .kmart: value = "20000000-0000-4000-8000-000000000007"
        case .costcoUS: value = "20000000-0000-4000-8000-000000000008"
        case .bigW: value = "20000000-0000-4000-8000-000000000009"
        case .amazon: value = "20000000-0000-4000-8000-000000000010"
        case .kroger: value = "20000000-0000-4000-8000-000000000011"
        case .target: value = "20000000-0000-4000-8000-000000000012"
        case .chemistWarehouse: value = "20000000-0000-4000-8000-000000000013"
        case .priceline: value = "20000000-0000-4000-8000-000000000014"
        case .officeworks: value = "20000000-0000-4000-8000-000000000015"
        case .jbHiFi: value = "20000000-0000-4000-8000-000000000016"
        case .targetAU: value = "20000000-0000-4000-8000-000000000017"
        case .petbarn: value = "20000000-0000-4000-8000-000000000018"
        case .supercheapAuto: value = "20000000-0000-4000-8000-000000000019"
        case .bcf: value = "20000000-0000-4000-8000-000000000020"
        case .bunningsNZ: value = "20000000-0000-4000-8000-000000000021"
        case .theWarehouse: value = "20000000-0000-4000-8000-000000000022"
        case .newWorld: value = "20000000-0000-4000-8000-000000000023"
        case .paknsave: value = "20000000-0000-4000-8000-000000000024"
        case .sainsburys: value = "20000000-0000-4000-8000-000000000025"
        case .asda: value = "20000000-0000-4000-8000-000000000026"
        case .morrisons: value = "20000000-0000-4000-8000-000000000027"
        case .ocado: value = "20000000-0000-4000-8000-000000000028"
        case .waitrose: value = "20000000-0000-4000-8000-000000000029"
        case .boots: value = "20000000-0000-4000-8000-000000000030"
        case .walgreens: value = "20000000-0000-4000-8000-000000000031"
        case .cvs: value = "20000000-0000-4000-8000-000000000032"
        case .ikeaAU: value = "20000000-0000-4000-8000-000000000033"
        #if STORE_REGISTRY_PROOF
        case .synthetic: value = "20000000-0000-4000-8000-000000000099"
        #endif
        }
        return UUID(uuidString: value)!
    }
    func ownsDataDomain(_ domain: String) -> Bool {
        let value = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if self == .coles && ["colesgroupprofile.com.au", "auth.colesgroupprofile.com.au", "id.colesgroupprofile.com.au"].contains(value) {
            return true
        }
        return value == dataDomain || value.hasSuffix("." + dataDomain)
    }
}

// Pure validation shared by DEBUG-only live-probe call sites. Release browsing
// never consults these environment flags. Tests can validate isolation without
// opening a website or creating a persistent store.
enum StoreProbeIsolation {
    static func persistentIdentifier(for id: StoreID, environment: [String: String]) -> UUID? {
        guard id == .officeworks,
              environment["LISTRUNNER_LIVE_CART_PROBE"] == id.rawValue,
              environment["LISTRUNNER_LIVE_PERSISTENT_PROBE"] == id.rawValue,
              let raw = environment["LISTRUNNER_UI_TEST_SESSION"], let identifier = UUID(uuidString: raw),
              identifier != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
              !StoreID.allCases.contains(where: { $0.websiteDataID == identifier || $0.listID == identifier }) else { return nil }
        return identifier
    }

    static func permitsCartProbe(for id: StoreID, isPersistent: Bool, identifier: UUID?,
                                 environment: [String: String]) -> Bool {
        guard environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil,
              environment["LISTRUNNER_LIVE_CART_PROBE"] == id.rawValue else { return false }
        if !isPersistent { return true }
        guard let expected = persistentIdentifier(for: id, environment: environment) else { return false }
        return identifier == expected
    }
}

enum StoreCategory: String, Codable, CaseIterable, Hashable {
    case grocery
    case groceryHome
    case clothingHome
    case homeFurniture
    // Retained only to decode schema-6 historical category arrays.
    case departmentStore
    case warehouseClub
    case onlineMarketplace
    case hardwareGarden
    case pharmacyBeauty
    case electronics
    case officeSupplies
    case petSupplies
    case automotive
    case outdoorCamping

    static let legacyCases = Set(allCases).subtracting([.groceryHome, .clothingHome, .homeFurniture])
    static let currentCases = Set(allCases).subtracting([.departmentStore, .warehouseClub])

    var displayName: String {
        switch self {
        case .grocery: "Grocery"
        case .groceryHome: "Groceries & Home"
        case .clothingHome: "Clothing & Home"
        case .homeFurniture: "Home & Furniture"
        case .departmentStore: "Department Store"
        case .warehouseClub: "Warehouse Club"
        case .onlineMarketplace: "Online Marketplace"
        case .hardwareGarden: "Hardware & Garden"
        case .pharmacyBeauty: "Pharmacy & Beauty"
        case .electronics: "Electronics"
        case .officeSupplies: "Office Supplies"
        case .petSupplies: "Pet Supplies"
        case .automotive: "Automotive"
        case .outdoorCamping: "Outdoor & Camping"
        }
    }
}

// In-memory provenance for one trusted Add interrupted by the reviewed Tesco
// authentication route. A guest quantity is deliberately NOT carried into the
// account basket, and this receipt never grants retailer-cart Undo permission.
struct StoreLoginReplay {
    let productID: String
    let context: String
    let nonce: String
    let sourceURL: URL
    let deadline: TimeInterval
    private(set) var visitedAuthentication = false

    static func isAuthentication(_ url: URL) -> Bool {
        // Tesco's observed first-party flow crosses both route families before
        // returning to the original search. Do not allow arbitrary /account pages.
        ["/account/auth/en-GB", "/account/login/en-GB"].contains { prefix in
            url.path == prefix || url.path.hasPrefix(prefix + "/")
        }
    }

    init?(store: StoreDefinition, productID: String, context: String, nonce: String,
          sourceURL: URL, now: TimeInterval) {
        guard store.id == .tesco, store.capabilities.cartDetection,
              store.allows(sourceURL), Self.isStorefront(sourceURL),
              store.acceptsProductIdentity(productID), !context.isEmpty, !nonce.isEmpty else { return nil }
        self.productID = productID
        self.context = context
        self.nonce = nonce
        self.sourceURL = sourceURL
        self.deadline = now + 300
    }

    private static func isStorefront(_ url: URL) -> Bool {
        url.path.hasPrefix("/shop/en-GB/") || url.path.hasPrefix("/groceries/en-GB/")
    }

    func isReturn(_ url: URL) -> Bool {
        guard var expected = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              var actual = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        expected.fragment = nil; actual.fragment = nil
        // Tesco's reviewed legacy route redirects to /shop without changing query.
        expected.path = expected.path.replacingOccurrences(of: "/groceries/en-GB/", with: "/shop/en-GB/")
        actual.path = actual.path.replacingOccurrences(of: "/groceries/en-GB/", with: "/shop/en-GB/")
        return expected == actual
    }

    mutating func visit(_ url: URL, store: StoreDefinition, context: String, now: TimeInterval) -> Bool {
        guard context == self.context, now <= deadline, store.id == .tesco,
              store.allows(url), url.host == sourceURL.host else { return false }
        if Self.isAuthentication(url) { visitedAuthentication = true; return true }
        return visitedAuthentication && isReturn(url)
    }

    func accepts(_ object: [String: Any], url: URL, context: String, now: TimeInterval) -> Int? {
        guard context == self.context, now <= deadline, visitedAuthentication, isReturn(url),
              Set(object.keys) == ["nonce", "productID", "successful", "requestedQuantity", "resultingQuantity"],
              object["nonce"] as? String == nonce, object["productID"] as? String == productID,
              let success = object["successful"] as? NSNumber, CFGetTypeID(success) == CFBooleanGetTypeID(), success.boolValue,
              let requested = StoreBridge.integer(object["requestedQuantity"]),
              let resulting = StoreBridge.integer(object["resultingQuantity"]),
              (1...9999).contains(resulting), requested == resulting else { return nil }
        return resulting
    }
}

struct StoreDefinition: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, automationSchemaVersion, id, displayName, serviceArea, homepage, allowedHosts
        case search, addedColor, brandColors, categories, category, capabilities, cart
    }

    struct ServiceArea: Codable {
        let countryCodes: [String]
    }
    struct Capabilities: Codable {
        var search: Bool
        var cartDetection: Bool
        var cartUndo: Bool
    }
    struct Search: Codable {
        enum Strategy: String, Codable { case urlTemplate }
        let strategy: Strategy
        let template: String
        var resultsSelector: String? = nil
        var resultsTopOffset: Double? = nil
    }
    struct Cart: Codable {
        enum Strategy: String, Codable { case trustedTileQuantity, profiled, verifiedCartSnapshot }
        enum IdentityStrategy: String, Codable { case numericURLSuffix, capturedURLComponent }
        struct DetectionProfile: Codable {
            enum Scope: String, Codable { case productCard, productPage }
            enum Identity: String, Codable { case cardLink, pageURL }
            enum Confirmation: String, Codable { case productReceipt, quantityIncrease, productAcknowledgement, cartSnapshot }
            struct Acknowledgement: Codable {
                let selector: String
                let successSelector: String
                let successText: String
                let titleSelector: String
                let failureSelector: String
            }
            struct Receipt: Codable {
                struct ImageIdentity: Codable {
                    let selector: String
                    let allowedHosts: [String]
                    let productURLPattern: String
                }
                let selector: String
                let successText: String
                let quantityPattern: String?
                var productSelector: String? = nil
                var quantitySelector: String? = nil
                var imageIdentity: ImageIdentity? = nil
                var failureSelector: String? = nil
            }
            struct Undo: Codable {
                let decrementSelector: String
                let decrementLabelPattern: String
            }
            struct SetupPrompt: Codable {
                let selector: String
                let textPattern: String
                let maximumWaitMS: Int
            }
            let id: String
            let scope: Scope
            let identity: Identity
            let containerSelector: String
            let titleSelector: String
            let addSelector: String
            let addLabelPatterns: [String]
            let confirmation: Confirmation
            let confirmationWindowMS: Int
            let quantitySelector: String?
            let receipt: Receipt?
            var emptyStatusText: String? = nil
            var undo: Undo? = nil
            var setupPrompt: SetupPrompt? = nil
            var acknowledgement: Acknowledgement? = nil
            var quantityDraftSelector: String? = nil
            // Explicit opt-in for a retailer's read-only, product-scoped basket count.
            // Existing profiles continue to read input values/aria-valuenow only.
            var quantityText: Bool? = nil
        }
        let strategy: Strategy
        let identityStrategy: IdentityStrategy
        let tileSelector: String
        let linkSelector: String
        let productURLPattern: String
        let addSelector: String
        let addLabelPatterns: [String]
        let quantitySelector: String
        let emptyStatusSelector: String
        let emptyStatusText: String
        let decrementLabelPattern: String
        var profiles: [DetectionProfile]? = nil
        struct Snapshot: Codable {
            let path: String
            let rowSelector: String
            let articleSelector: String
            let quantitySelector: String
            let emptySelector: String
            let emptyText: String
            let decrementSelector: String
            let removeSelector: String
        }
        var snapshot: Snapshot? = nil
    }
    struct AddedColor: Codable {
        let red: Int
        let green: Int
        let blue: Int
    }
    struct BrandColors: Codable {
        let primary: AddedColor
        let highlight: AddedColor
    }
    let schemaVersion: Int
    let automationSchemaVersion: Int
    let id: StoreID
    let displayName: String
    let serviceArea: ServiceArea
    let homepage: URL
    let allowedHosts: [String]
    let search: Search
    let addedColor: AddedColor
    var brandColors: BrandColors? = nil
    var categories: [StoreCategory] = []
    var category: StoreCategory? = nil
    var capabilities: Capabilities
    let cart: Cart?

    init(schemaVersion: Int, id: StoreID, displayName: String, serviceArea: ServiceArea,
         homepage: URL, allowedHosts: [String], search: Search, addedColor: AddedColor,
         brandColors: BrandColors? = nil, automationSchemaVersion: Int? = nil,
          categories: [StoreCategory] = [], category: StoreCategory? = nil,
          capabilities: Capabilities, cart: Cart?) {
        self.schemaVersion = schemaVersion
        self.automationSchemaVersion = automationSchemaVersion ?? schemaVersion
        self.id = id
        self.displayName = displayName
        self.serviceArea = serviceArea
        self.homepage = homepage
        self.allowedHosts = allowedHosts
        self.search = search
        self.addedColor = addedColor
        self.brandColors = brandColors
        self.categories = categories
        self.category = category
        self.capabilities = capabilities
        self.cart = cart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let hasCategories = schemaVersion == 6
        let hasCategory = schemaVersion == 7
        let hasAutomationSchemaVersion = schemaVersion >= 6
        guard [2, 3, 4, 5, 6, 7].contains(schemaVersion) else { throw ConfigurationError.invalid }
        var expectedKeys = Set(CodingKeys.allCases.map(\.stringValue))
        if !hasCategories { expectedKeys.remove(CodingKeys.categories.rawValue) }
        if !hasCategory { expectedKeys.remove(CodingKeys.category.rawValue) }
        if !hasAutomationSchemaVersion { expectedKeys.remove(CodingKeys.automationSchemaVersion.rawValue) }
        if !container.contains(.brandColors) { expectedKeys.remove(CodingKeys.brandColors.rawValue) }
        guard Set(container.allKeys.map(\.stringValue)) == expectedKeys else {
            throw ConfigurationError.invalid
        }
        if hasAutomationSchemaVersion {
            automationSchemaVersion = try container.decode(Int.self, forKey: .automationSchemaVersion)
        } else {
            automationSchemaVersion = schemaVersion
        }
        guard !hasAutomationSchemaVersion || [2, 3, 4, 5].contains(automationSchemaVersion) else {
            throw ConfigurationError.invalid
        }
        id = try container.decode(StoreID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        serviceArea = try container.decode(ServiceArea.self, forKey: .serviceArea)
        homepage = try container.decode(URL.self, forKey: .homepage)
        allowedHosts = try container.decode([String].self, forKey: .allowedHosts)
        search = try container.decode(Search.self, forKey: .search)
        addedColor = try container.decode(AddedColor.self, forKey: .addedColor)
        brandColors = try container.decodeIfPresent(BrandColors.self, forKey: .brandColors)
        if hasCategories {
            categories = try container.decode([StoreCategory].self, forKey: .categories)
        } else {
            categories = []
        }
        if hasCategory { category = try container.decode(StoreCategory.self, forKey: .category) }
        guard !hasCategories || (!categories.isEmpty && Set(categories).isSubset(of: StoreCategory.legacyCases)
              && Set(categories).count == categories.count) else { throw ConfigurationError.invalid }
        guard !hasCategory || (category.map(StoreCategory.currentCases.contains) == true && categories.isEmpty) else { throw ConfigurationError.invalid }
        capabilities = try container.decode(Capabilities.self, forKey: .capabilities)
        cart = try container.decodeIfPresent(Cart.self, forKey: .cart)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        if schemaVersion >= 6 {
            try container.encode(automationSchemaVersion, forKey: .automationSchemaVersion)
        }
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(serviceArea, forKey: .serviceArea)
        try container.encode(homepage, forKey: .homepage)
        try container.encode(allowedHosts, forKey: .allowedHosts)
        try container.encode(search, forKey: .search)
        try container.encode(addedColor, forKey: .addedColor)
        try container.encodeIfPresent(brandColors, forKey: .brandColors)
        if schemaVersion == 6 { try container.encode(categories, forKey: .categories) }
        if schemaVersion == 7 { try container.encode(category, forKey: .category) }
        try container.encode(capabilities, forKey: .capabilities)
        // The wire contract requires the cart key even for browsing-only stores.
        try container.encode(cart, forKey: .cart)
    }

    private var supportsSchema4Features: Bool { automationSchemaVersion == 4 }
    private var supportsProfiledCart: Bool { [3, 4].contains(automationSchemaVersion) }

    enum ConfigurationError: Error { case invalid }

    var isConfigurationValid: Bool { (try? validate()) != nil }
    // Keep every destination registered for future work and data recovery, but
    // offer shopping only after its item search has independent verification.
    var isAvailableForShopping: Bool { id.permitsSearch && capabilities.search && isConfigurationValid }

    func validate() throws {
        let countries = serviceArea.countryCodes
        let supportedCountryCodes = Set(Locale.Region.isoRegions.map(\.identifier))
        guard [2, 3, 4, 5, 6, 7].contains(schemaVersion),
              (schemaVersion == 6
                ? (!categories.isEmpty && Set(categories).isSubset(of: StoreCategory.legacyCases)
                    && Set(categories).count == categories.count && [2, 3, 4, 5].contains(automationSchemaVersion))
                : schemaVersion == 7
                    ? (category.map(StoreCategory.currentCases.contains) == true && categories.isEmpty && [2, 3, 4, 5].contains(automationSchemaVersion))
                    : (category == nil && categories.isEmpty && automationSchemaVersion == schemaVersion)),
              displayName == id.displayName,
              !countries.isEmpty, Set(countries).count == countries.count,
              countries.allSatisfy({ $0.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil
                  && supportedCountryCodes.contains($0) }),
              !allowedHosts.isEmpty,
              Set(allowedHosts).count == allowedHosts.count,
              Set(allowedHosts).isSubset(of: id.hosts), allows(homepage),
              search.template.components(separatedBy: "{query}").count == 2,
              !search.template.replacingOccurrences(of: "{query}", with: "").contains("{"),
              !search.template.replacingOccurrences(of: "{query}", with: "").contains("}"),
               let probe = searchURL(for: "validation / & + # ?"), allows(probe),
               (0...255).contains(addedColor.red), (0...255).contains(addedColor.green), (0...255).contains(addedColor.blue),
               brandColors.map({ (0...255).contains($0.primary.red) && (0...255).contains($0.primary.green) && (0...255).contains($0.primary.blue)
                   && (0...255).contains($0.highlight.red) && (0...255).contains($0.highlight.green) && (0...255).contains($0.highlight.blue) }) ?? true,
                !capabilities.search || id.permitsSearch,
                !capabilities.cartDetection || id.permitsCartDetection,
               !capabilities.cartUndo || capabilities.cartDetection,
               !capabilities.cartUndo || id.permitsCartUndo,
              !capabilities.cartDetection || cart != nil else { throw ConfigurationError.invalid }
        if let selector = search.resultsSelector {
            guard !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  selector.utf8.count <= 1_024 else { throw ConfigurationError.invalid }
        }
        if let offset = search.resultsTopOffset {
            guard search.resultsSelector != nil, offset.isFinite, (0...500).contains(offset)
            else { throw ConfigurationError.invalid }
        }
        if let cart {
            // Snapshot verification is a separately reviewed engine, not a way
            // for a data file to upgrade an existing retailer's capabilities.
            if cart.strategy == .verifiedCartSnapshot {
                guard automationSchemaVersion == 5, id == .ikeaAU,
                      cart.identityStrategy == .numericURLSuffix,
                      let snapshot = cart.snapshot,
                      snapshot.path == "/au/en/shoppingcart/",
                      cart.profiles?.isEmpty == false else { throw ConfigurationError.invalid }
                for selector in [snapshot.rowSelector, snapshot.articleSelector, snapshot.quantitySelector,
                                 snapshot.emptySelector, snapshot.decrementSelector, snapshot.removeSelector] {
                    guard !selector.isEmpty, selector.utf8.count <= 1_024 else { throw ConfigurationError.invalid }
                }
                guard !snapshot.emptyText.isEmpty, snapshot.emptyText.utf8.count <= 256 else { throw ConfigurationError.invalid }
            } else {
                guard automationSchemaVersion != 5, cart.snapshot == nil else { throw ConfigurationError.invalid }
            }
            guard (automationSchemaVersion == 2 && cart.strategy == .trustedTileQuantity && cart.profiles == nil)
                || (supportsProfiledCart && cart.strategy == .profiled && cart.profiles?.isEmpty == false)
                || (automationSchemaVersion == 5 && cart.strategy == .verifiedCartSnapshot) else { throw ConfigurationError.invalid }
            guard supportsSchema4Features || cart.identityStrategy == .numericURLSuffix else { throw ConfigurationError.invalid }
            if cart.identityStrategy == .capturedURLComponent {
                guard [.officeworks, .jbHiFi, .petbarn, .sainsburys, .walgreens, .boots, .theWarehouse, .waitrose].contains(id),
                      !capabilities.cartUndo else { throw ConfigurationError.invalid }
            }
            for selector in [cart.tileSelector, cart.linkSelector, cart.addSelector, cart.quantitySelector, cart.emptyStatusSelector] {
                guard !selector.isEmpty, selector.utf8.count <= 1_024 else { throw ConfigurationError.invalid }
            }
            guard !cart.emptyStatusText.isEmpty, !cart.addLabelPatterns.isEmpty else { throw ConfigurationError.invalid }
            for pattern in cart.addLabelPatterns + [cart.productURLPattern, cart.decrementLabelPattern] {
                guard pattern.utf8.count <= 512 else { throw ConfigurationError.invalid }
                _ = try NSRegularExpression(pattern: pattern)
            }
            guard try NSRegularExpression(pattern: cart.productURLPattern).numberOfCaptureGroups == 1 else {
                throw ConfigurationError.invalid
            }
            if let profiles = cart.profiles {
                guard profiles.count <= 8, Set(profiles.map(\.id)).count == profiles.count else { throw ConfigurationError.invalid }
                for profile in profiles {
                    guard profile.id.range(of: "^[a-z][a-zA-Z0-9-]{0,63}$", options: .regularExpression) != nil,
                          (profile.scope == .productCard && profile.identity == .cardLink)
                            || (profile.scope == .productPage && profile.identity == .pageURL),
                          (500...15_000).contains(profile.confirmationWindowMS),
                          !profile.addLabelPatterns.isEmpty else { throw ConfigurationError.invalid }
                    for selector in [profile.containerSelector, profile.titleSelector, profile.addSelector] + [profile.quantitySelector, profile.receipt?.selector, profile.receipt?.productSelector, profile.receipt?.quantitySelector, profile.receipt?.failureSelector,
                        profile.acknowledgement?.selector, profile.acknowledgement?.successSelector, profile.acknowledgement?.titleSelector, profile.acknowledgement?.failureSelector, profile.quantityDraftSelector].compactMap({ $0 }) {
                        guard !selector.isEmpty, selector.utf8.count <= 1_024 else { throw ConfigurationError.invalid }
                    }
                    for pattern in profile.addLabelPatterns {
                        guard pattern.utf8.count <= 512 else { throw ConfigurationError.invalid }
                        _ = try NSRegularExpression(pattern: pattern)
                    }
                    if profile.quantityDraftSelector != nil {
                        guard supportsSchema4Features, profile.confirmation == .quantityIncrease,
                              profile.undo == nil, !capabilities.cartUndo else { throw ConfigurationError.invalid }
                    }
                    if profile.quantityText != nil {
                        guard supportsSchema4Features, profile.quantityText == true,
                              profile.confirmation == .quantityIncrease,
                              profile.quantitySelector != nil else { throw ConfigurationError.invalid }
                    }
                    switch profile.confirmation {
                    case .cartSnapshot:
                        guard automationSchemaVersion == 5, cart.strategy == .verifiedCartSnapshot,
                              profile.quantitySelector == nil, profile.receipt == nil,
                              profile.acknowledgement == nil, profile.undo == nil,
                              profile.emptyStatusText == nil, profile.setupPrompt == nil,
                              profile.quantityDraftSelector == nil, profile.quantityText == nil else { throw ConfigurationError.invalid }
                    case .productReceipt:
                        guard automationSchemaVersion != 5 else { throw ConfigurationError.invalid }
                        guard let receipt = profile.receipt, profile.acknowledgement == nil, profile.quantitySelector == nil, profile.emptyStatusText == nil, profile.undo == nil,
                               !receipt.successText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               receipt.successText.utf8.count <= 256 else { throw ConfigurationError.invalid }
                        if let pattern = receipt.quantityPattern {
                            guard receipt.productSelector == nil, receipt.quantitySelector == nil, receipt.imageIdentity == nil, receipt.failureSelector == nil,
                                  pattern.utf8.count <= 512,
                                  try NSRegularExpression(pattern: pattern).numberOfCaptureGroups == 1 else { throw ConfigurationError.invalid }
                        } else {
                            guard supportsSchema4Features, receipt.productSelector != nil,
                                  receipt.quantitySelector != nil, receipt.failureSelector != nil else { throw ConfigurationError.invalid }
                        }
                        if let image = receipt.imageIdentity {
                            guard supportsSchema4Features, id == .priceline,
                                  image.allowedHosts == ["api.priceline.com.au"],
                                  !image.selector.isEmpty, image.selector.utf8.count <= 1_024,
                                  image.productURLPattern.utf8.count <= 512,
                                  image.productURLPattern.hasPrefix("^"), image.productURLPattern.hasSuffix("$"),
                                  try NSRegularExpression(pattern: image.productURLPattern).numberOfCaptureGroups == 1 else { throw ConfigurationError.invalid }
                        }
                    case .quantityIncrease:
                        guard automationSchemaVersion != 5 else { throw ConfigurationError.invalid }
                        guard profile.quantitySelector != nil, profile.receipt == nil, profile.acknowledgement == nil else { throw ConfigurationError.invalid }
                    case .productAcknowledgement:
                        guard supportsSchema4Features, let acknowledgement = profile.acknowledgement,
                              !acknowledgement.successText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              acknowledgement.successText.utf8.count <= 256,
                              profile.receipt == nil, profile.quantitySelector == nil, profile.emptyStatusText == nil,
                              profile.undo == nil, profile.setupPrompt == nil, !capabilities.cartUndo else { throw ConfigurationError.invalid }
                    }
                    if let empty = profile.emptyStatusText {
                        guard !empty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, empty.utf8.count <= 256 else { throw ConfigurationError.invalid }
                    }
                    if let undo = profile.undo {
                        guard !undo.decrementSelector.isEmpty, undo.decrementSelector.utf8.count <= 1_024,
                              !undo.decrementLabelPattern.isEmpty, undo.decrementLabelPattern.utf8.count <= 512 else { throw ConfigurationError.invalid }
                        _ = try NSRegularExpression(pattern: undo.decrementLabelPattern)
                    }
                    if capabilities.cartUndo && cart.strategy != .verifiedCartSnapshot {
                        guard profile.confirmation == .quantityIncrease, profile.undo != nil, profile.emptyStatusText != nil else { throw ConfigurationError.invalid }
                    }
                    if let setup = profile.setupPrompt {
                        guard profile.confirmation == .quantityIncrease,
                              !setup.selector.isEmpty, setup.selector.utf8.count <= 1_024,
                              !setup.textPattern.isEmpty, setup.textPattern.utf8.count <= 512,
                              (1_000...300_000).contains(setup.maximumWaitMS) else { throw ConfigurationError.invalid }
                        _ = try NSRegularExpression(pattern: setup.textPattern)
                    }
                }
            }
        } else if [3, 4, 5].contains(automationSchemaVersion) {
            throw ConfigurationError.invalid
        }
    }

    func allows(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) && allowedHosts.contains(url.host?.lowercased() ?? "") &&
        (id != .ikeaAU || Self.isAustralianIKEAPath(url))
    }

    private static func isAustralianIKEAPath(_ url: URL) -> Bool {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return path.hasPrefix("/au/en/") && !path.contains("\\") &&
            path.range(of: "%25|%2e|%2f|%5c|(?:^|/)\\.{1,2}(?:/|$)", options: [.regularExpression, .caseInsensitive]) == nil
    }

    // Authentication is browsing-only. Never extend the cart bridge or bundled
    // automation host allowlist to the login origin.
    func allowsNavigation(_ url: URL) -> Bool {
        if allows(url) { return true }
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        let host = url.host?.lowercased() ?? ""
        if id == .coles {
            return ["auth.colesgroupprofile.com.au", "id.colesgroupprofile.com.au"].contains(host)
        }
        if id == .sainsburys { return host == "account.sainsburys.co.uk" }
        if id == .waitrose { return host == "auth.waitrose.com" }
        // Bunnings establishes its website session through a silent authorization
        // frame. This is browsing-only: `allows` and automation hosts stay closed.
        if id == .bunnings { return host == "authorisation.api.bunnings.com.au" }
        return id == .bunningsNZ && host == "authorisation.api.bunnings.co.nz"
    }

    func searchURL(for query: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: search.template.replacingOccurrences(of: "{query}", with: encoded))
    }

    func acceptsProductIdentity(_ value: String) -> Bool {
        if id == .ikeaAU { return value.utf8.count == 8 && value.utf8.allSatisfy { (48...57).contains($0) } }
        if supportsSchema4Features && cart?.identityStrategy == .capturedURLComponent {
            if id == .waitrose {
                let components = value.split(separator: "-", omittingEmptySubsequences: false)
                return components.count == 3 && components.allSatisfy {
                    (1...16).contains($0.utf8.count) && $0.utf8.allSatisfy { (48...57).contains($0) }
                }
            }
            let bytes = Array(value.utf8)
            let isAlphanumeric: (UInt8) -> Bool = { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
            guard (1...256).contains(bytes.count), let first = bytes.first, isAlphanumeric(first) else { return false }
            return bytes.allSatisfy { isAlphanumeric($0) || $0 == 45 || $0 == 95 }
        }
        return !value.isEmpty && value.utf8.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func load(_ id: StoreID, bundle: Bundle = .main) -> StoreDefinition {
        do {
            guard let url = bundle.url(forResource: id.rawValue + "-v2", withExtension: "json")
                    ?? bundle.url(forResource: id.rawValue, withExtension: "json") else { throw ConfigurationError.invalid }
            let value = try decodeConfiguration(from: Data(contentsOf: url))
            guard value.id == id else { throw ConfigurationError.invalid }
            return value
        } catch {
            // Browsing/manual status remain safe even if a bundled configuration is bad.
            return StoreDefinition(schemaVersion: 2, id: id, displayName: id.displayName,
                                    serviceArea: ServiceArea(countryCodes: []),
                                    homepage: id.home, allowedHosts: id.hosts.sorted(),
                                    search: Search(strategy: .urlTemplate,
                                                   template: id == .bunnings
                                                    ? "https://www.bunnings.com.au/search/products?q={query}"
                                                    : id.home.absoluteString + "?q={query}"),
                                    addedColor: {
                                        switch id {
                                        case .coles: AddedColor(red: 224, green: 26, blue: 34)
                                        case .woolworths: AddedColor(red: 0, green: 114, blue: 61)
                                        case .bunnings: AddedColor(red: 218, green: 41, blue: 28)
                                        case .costco: AddedColor(red: 0, green: 93, blue: 170)
                                        case .tesco: AddedColor(red: 0, green: 83, blue: 159)
                                        case .walmart: AddedColor(red: 0, green: 113, blue: 206)
                                        case .kmart: AddedColor(red: 0, green: 91, blue: 172)
                                        case .costcoUS: AddedColor(red: 0, green: 93, blue: 170)
                                        case .bigW: AddedColor(red: 0, green: 107, blue: 182)
                                        case .amazon: AddedColor(red: 35, green: 47, blue: 62)
                                        case .kroger: AddedColor(red: 0, green: 75, blue: 141)
                                        case .target: AddedColor(red: 204, green: 0, blue: 0)
                                        case .ikeaAU: AddedColor(red: 0, green: 88, blue: 163)
                                        case .chemistWarehouse, .priceline, .officeworks, .jbHiFi, .targetAU, .petbarn,
                                             .supercheapAuto, .bcf, .bunningsNZ, .theWarehouse, .newWorld, .paknsave,
                                             .sainsburys, .asda, .morrisons, .ocado, .waitrose, .boots, .walgreens, .cvs:
                                            AddedColor(red: 64, green: 64, blue: 64)
                                        #if STORE_REGISTRY_PROOF
                                        case .synthetic: AddedColor(red: 64, green: 64, blue: 64)
                                        #endif
                                        }
                                    }(),
                                    brandColors: id == .bunnings ? BrandColors(
                                        primary: AddedColor(red: 13, green: 82, blue: 87),
                                        highlight: AddedColor(red: 255, green: 171, blue: 0)
                                    ) : nil,
                                    capabilities: Capabilities(search: false, cartDetection: false, cartUndo: false), cart: nil)
        }
    }

    static func decodeConfiguration(from data: Data) throws -> StoreDefinition {
        guard data.count <= 65_536 else { throw ConfigurationError.invalid }
        try rejectDuplicateKeys(in: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               hasOnlyKeys(root, ["schemaVersion", "automationSchemaVersion", "id", "displayName", "serviceArea", "homepage", "allowedHosts",
                                  "search", "addedColor", "brandColors", "categories", "category", "capabilities", "cart"]),
              hasOnlyKeys(root["serviceArea"] as? [String: Any], ["countryCodes"]),
              hasOnlyKeys(root["search"] as? [String: Any], ["strategy", "template", "resultsSelector", "resultsTopOffset"]),
              hasOnlyKeys(root["addedColor"] as? [String: Any], ["red", "green", "blue"]),
              hasOnlyKeys(root["capabilities"] as? [String: Any], ["search", "cartDetection", "cartUndo"]) else {
            throw ConfigurationError.invalid
        }
        if let colors = root["brandColors"] as? [String: Any],
           (!hasOnlyKeys(colors, ["primary", "highlight"])
            || !hasOnlyKeys(colors["primary"] as? [String: Any], ["red", "green", "blue"])
            || !hasOnlyKeys(colors["highlight"] as? [String: Any], ["red", "green", "blue"])) {
            throw ConfigurationError.invalid
        }
        if let cart = root["cart"] as? [String: Any],
           !hasOnlyKeys(cart, ["strategy", "identityStrategy", "tileSelector", "linkSelector", "productURLPattern",
                               "addSelector", "addLabelPatterns", "quantitySelector", "emptyStatusSelector",
                                 "emptyStatusText", "decrementLabelPattern", "profiles", "snapshot"]) {
            throw ConfigurationError.invalid
        }
        if let cart = root["cart"] as? [String: Any], let snapshot = cart["snapshot"], !(snapshot is NSNull),
           !hasOnlyKeys(snapshot as? [String: Any], ["path", "rowSelector", "articleSelector", "quantitySelector", "emptySelector", "emptyText", "decrementSelector", "removeSelector"]) {
            throw ConfigurationError.invalid
        }
        if let cart = root["cart"] as? [String: Any], let rawProfiles = cart["profiles"] {
            guard let profiles = rawProfiles as? [[String: Any]] else { throw ConfigurationError.invalid }
            for profile in profiles {
                guard hasOnlyKeys(profile, ["id", "scope", "identity", "containerSelector", "titleSelector", "addSelector",
                                           "addLabelPatterns", "confirmation", "confirmationWindowMS", "quantitySelector", "receipt", "emptyStatusText", "undo", "setupPrompt", "acknowledgement", "quantityDraftSelector", "quantityText"]) else {
                    throw ConfigurationError.invalid
                }
                if let receipt = profile["receipt"], !(receipt is NSNull),
                   !hasOnlyKeys(receipt as? [String: Any], ["selector", "successText", "quantityPattern", "productSelector", "quantitySelector", "imageIdentity", "failureSelector"]) { throw ConfigurationError.invalid }
                if let receipt = profile["receipt"] as? [String: Any], let image = receipt["imageIdentity"], !(image is NSNull),
                   !hasOnlyKeys(image as? [String: Any], ["selector", "allowedHosts", "productURLPattern"]) { throw ConfigurationError.invalid }
                if let undo = profile["undo"], !(undo is NSNull),
                   !hasOnlyKeys(undo as? [String: Any], ["decrementSelector", "decrementLabelPattern"]) { throw ConfigurationError.invalid }
                if let setup = profile["setupPrompt"], !(setup is NSNull),
                   !hasOnlyKeys(setup as? [String: Any], ["selector", "textPattern", "maximumWaitMS"]) { throw ConfigurationError.invalid }
                if let acknowledgement = profile["acknowledgement"], !(acknowledgement is NSNull),
                   !hasOnlyKeys(acknowledgement as? [String: Any], ["selector", "successSelector", "successText", "titleSelector", "failureSelector"]) { throw ConfigurationError.invalid }
            }
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    private static func hasOnlyKeys(_ object: [String: Any]?, _ allowed: Set<String>) -> Bool {
        guard let object else { return false }
        return Set(object.keys).isSubset(of: allowed)
    }

    private static func rejectDuplicateKeys(in data: Data) throws {
        // JSONSerialization and JSONDecoder both silently keep one duplicate
        // value. Scan object keys before decoding, including escaped spellings.
        let bytes = Array(data)
        var objects: [Set<String>?] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: objects.append([]) // object
            case 91: objects.append(nil) // array
            case 125, 93:
                guard !objects.isEmpty else { throw ConfigurationError.invalid }
                objects.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count && bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { throw ConfigurationError.invalid }
                var next = index + 1
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] == 58 {
                    guard let last = objects.indices.last, var keys = objects[last] else { throw ConfigurationError.invalid }
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...index]))
                    guard keys.insert(key).inserted else { throw ConfigurationError.invalid }
                    objects[last] = keys
                }
            default: break
            }
            index += 1
        }
    }

    private static func hasOnlyKeys(_ object: [String: Any]?, _ allowed: [String]) -> Bool {
        hasOnlyKeys(object, Set(allowed))
    }
}

enum StoreCatalogue {
    static func indexTitle(for name: String, locale: Locale = .current) -> String {
        let first = String(name.prefix(1)).folding(options: [.diacriticInsensitive], locale: locale).uppercased(with: locale)
        return !first.isEmpty && first.unicodeScalars.allSatisfy(CharacterSet.letters.contains) ? first : "#"
    }

    struct Section {
        let title: String
        let indexTitle: String?
        let stores: [StoreDefinition]
        var beginsOtherStores = false
    }

    static func sections(_ definitions: [StoreDefinition], countryCode: String?, search: String = "",
                         locale: Locale = .current) -> [Section] {
        let candidates = ordered(definitions, countryCode: nil, locale: locale).filter {
            search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
        }
        if !search.isEmpty {
            return candidates.isEmpty ? [] : [Section(title: "Matching stores", indexTitle: nil, stores: candidates)]
        }
        let valid = candidates.filter(\.isConfigurationValid)
        let invalid = candidates.filter { !$0.isConfigurationValid }
        let local = valid.filter { countryCode.map($0.serviceArea.countryCodes.contains) ?? false }
        let others = valid.filter { countryCode.map($0.serviceArea.countryCodes.contains) != true }
        var result: [Section] = []
        if let countryCode, !local.isEmpty {
            result.append(Section(title: "Stores in \(ShoppingCountry.name(countryCode, locale: locale))",
                                  indexTitle: nil, stores: local))
        }
        let groups = Dictionary(grouping: others) { indexTitle(for: $0.displayName, locale: locale) }
        let letters = groups.keys.sorted {
            if $0 == "#" { return false }
            if $1 == "#" { return true }
            return $0.compare($1, locale: locale) == .orderedAscending
        }
        for (index, letter) in letters.enumerated() {
            result.append(Section(title: letter, indexTitle: letter, stores: groups[letter] ?? [],
                                  beginsOtherStores: countryCode != nil && index == 0))
        }
        if !invalid.isEmpty {
            result.append(Section(title: "Setup unavailable", indexTitle: nil, stores: invalid))
        }
        return result
    }

    static func ordered(_ definitions: [StoreDefinition], countryCode: String?, enabledIDs: Set<StoreID>? = nil,
                        locale: Locale = .current) -> [StoreDefinition] {
        let candidates = definitions.filter { $0.isAvailableForShopping && (enabledIDs?.contains($0.id) ?? true) }
        return candidates.sorted { left, right in
            if countryCode != nil && left.isConfigurationValid != right.isConfigurationValid {
                return left.isConfigurationValid
            }
            let leftMatches = countryCode.map { left.serviceArea.countryCodes.contains($0) } ?? false
            let rightMatches = countryCode.map { right.serviceArea.countryCodes.contains($0) } ?? false
            if leftMatches != rightMatches { return leftMatches }
            let comparison = left.displayName.compare(right.displayName, options: [.caseInsensitive, .numeric, .widthInsensitive], locale: locale)
            return comparison == .orderedSame ? left.id.rawValue < right.id.rawValue : comparison == .orderedAscending
        }
    }
}

enum ShoppingCountry {
    static let codes = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.sorted()

    static func validated(_ code: String?) -> String? {
        guard let code = code?.uppercased(), codes.contains(code) else { return nil }
        return code
    }

    static func name(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }
}

struct StoreBrand: Identifiable {
    let id: String
    let name: String
    let regions: [StoreDefinition]

    var isRegional: Bool { regions.count > 1 }
    func matches(_ country: String?) -> Bool {
        regions.contains { definition in
            definition.isConfigurationValid && (country.map(definition.serviceArea.countryCodes.contains) ?? false)
        }
    }

    static func catalogue(_ definitions: [StoreDefinition]) -> [StoreBrand] {
        Dictionary(grouping: definitions, by: { $0.id.brandID }).map { id, regions in
            StoreBrand(id: id, name: regions[0].id.brandName,
                       regions: regions.sorted { $0.id.rawValue < $1.id.rawValue })
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    struct Section {
        let title: String
        let indexTitle: String?
        let brands: [StoreBrand]
        var beginsOtherStores = false
    }

    static func sections(_ definitions: [StoreDefinition], countryCode: String?, search: String,
                         enabledIDs: Set<StoreID> = []) -> [Section] {
        let brands = catalogue(definitions.filter(\.isAvailableForShopping)).filter { brand in
            search.isEmpty || brand.name.localizedCaseInsensitiveContains(search)
                || brand.regions.contains { region in
                    region.displayName.localizedCaseInsensitiveContains(search)
                        || region.serviceArea.countryCodes.contains {
                            ShoppingCountry.name($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search)
                        }
                }
        }
        if !search.isEmpty {
            return brands.isEmpty ? [] : [Section(title: "Matching stores", indexTitle: nil, brands: brands)]
        }
        let enabled = brands.filter { $0.regions.contains { enabledIDs.contains($0.id) } }
        let disabled = brands.filter { brand in !brand.regions.contains { enabledIDs.contains($0.id) } }
        let valid = disabled.filter { $0.regions.contains(where: \.isConfigurationValid) }
        let invalid = disabled.filter { !$0.regions.contains(where: \.isConfigurationValid) }
        let local = valid.filter { $0.matches(countryCode) }
        let other = valid.filter { !$0.matches(countryCode) }
        var result: [Section] = []
        if !enabled.isEmpty {
            result.append(Section(title: "Enabled stores", indexTitle: nil, brands: enabled))
        }
        if let countryCode, !local.isEmpty {
            result.append(Section(title: "Stores in \(ShoppingCountry.name(countryCode))", indexTitle: nil, brands: local))
        }
        let grouped = Dictionary(grouping: other) { StoreCatalogue.indexTitle(for: $0.name) }
        let letters = grouped.keys.sorted {
            if $0 == "#" { return false }; if $1 == "#" { return true }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
        for (index, letter) in letters.enumerated() {
            result.append(Section(title: letter, indexTitle: letter, brands: grouped[letter] ?? [],
                                  beginsOtherStores: countryCode != nil && index == 0))
        }
        if !invalid.isEmpty { result.append(Section(title: "Setup unavailable", indexTitle: nil, brands: invalid)) }
        return result
    }
}

// A snapshot belongs to one immutable, loaded registry. Keep full validation at
// this boundary; visibility toggles only intersect IDs and never recompile every
// retailer's validation expressions during SwiftUI rendering.
struct StoreShoppingAvailability {
    let availableIDs: Set<StoreID>

    init(definitions: [StoreDefinition]) {
        availableIDs = Set(definitions.filter(\.isAvailableForShopping).map(\.id))
    }

    func visibleIDs(in enabledIDs: Set<StoreID>) -> Set<StoreID> {
        availableIDs.intersection(enabledIDs)
    }
}

@MainActor
final class StoreVisibilityPreferences: ObservableObject {
    @Published private(set) var visibleIDs: Set<StoreID>
    @Published private(set) var nonEmptyListIDs: Set<UUID> = []
    @Published private(set) var listItemCounts: [UUID: Int] = [:]
    @Published private(set) var listLookupFailed = false
    var listItemCountsProvider: (() throws -> [UUID: Int])?

    private func canDisable(_ ids: Set<StoreID>) -> Bool {
        listLookupFailed = false
        guard !ids.isEmpty else { return true }
        if let listItemCountsProvider {
            do {
                let counts = try listItemCountsProvider()
                listItemCounts = counts
                nonEmptyListIDs = Set(counts.filter { $0.value > 0 }.map(\.key))
            } catch {
                listLookupFailed = true
                return false
            }
        }
        return ids.allSatisfy { !nonEmptyListIDs.contains($0.listID) }
    }
    // Do not rewrite saved visibility: hidden stores can recover their previous
    // preferences when support improves. UI eligibility is a separate projection.
    func shoppingVisibleIDs(in definitions: [StoreDefinition]) -> Set<StoreID> {
        Set(definitions.filter(\.isAvailableForShopping).map(\.id)).intersection(visibleIDs)
    }
    @Published private(set) var hasCompletedStoreSetup: Bool
    @Published private(set) var shoppingCountryCode: String?
    @Published private(set) var useLocalIngredientNames: Bool
    @Published private(set) var autoScrollToResults: Bool
    // Published as one atomic value so browsers never see a half-updated pair.
    @Published private(set) var ingredientSearchContext: IngredientSearchContext = .unchanged
    @Published private(set) var regionalChoices: [String: String]
    private let defaults: UserDefaults
    private let visibleKey = "visibleStoreIDs.v1"
    private let knownKey = "knownStoreIDs.v1"
    private let countryKey = "shoppingCountry.v1"
    private let countryInitializedKey = "shoppingCountryInitialized.v1"
    private let regionalKey = "storeRegionalChoices.v1"
    private let pendingSelectionKey = "pendingEnabledStoreSelection.v1"
    private let setupCompletedKey = "storeSetupCompleted.v1"

    init(defaults: UserDefaults? = nil, suggestedCountryCode: String? = Locale.current.region?.identifier) {
        if let defaults {
            self.defaults = defaults
        } else if let raw = ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"],
                  let token = UUID(uuidString: raw),
                  let testDefaults = UserDefaults(suiteName: "ListRunnerUITests.\(token.uuidString)") {
            self.defaults = testDefaults
        } else {
            self.defaults = .standard
        }
        let defaults = self.defaults
        let localNames = defaults.object(forKey: "useLocalIngredientNames.v1") as? Bool ?? true
        useLocalIngredientNames = localNames
        autoScrollToResults = defaults.object(forKey: "autoScrollToResults.v1") as? Bool ?? true
        regionalChoices = defaults.dictionary(forKey: regionalKey) as? [String: String] ?? [:]
        var suggestion = suggestedCountryCode
        #if DEBUG
        // Only isolated automatic UI tests can inject a region suggestion.
        if ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil,
           let fixture = ProcessInfo.processInfo.environment["LISTRUNNER_COUNTRY_TEST_REGION"] {
            suggestion = fixture
        }
        #endif
        if defaults.bool(forKey: countryInitializedKey) {
            shoppingCountryCode = ShoppingCountry.validated(defaults.string(forKey: countryKey))
        } else {
            let initialCountry = ShoppingCountry.validated(defaults.string(forKey: countryKey))
                ?? ShoppingCountry.validated(suggestion)
            shoppingCountryCode = initialCountry
            defaults.set(initialCountry, forKey: countryKey)
            defaults.set(true, forKey: countryInitializedKey)
        }
        // Both legacy sort modes migrate identically, without a location request.
        // Their presence identifies an install that predates store visibility;
        // preserve its original default stores while fresh installs start with
        // no stores enabled.
        let hasLegacyStorePreferences = defaults.object(forKey: "storeSortMode.v1") != nil
        defaults.removeObject(forKey: "storeSortMode.v1")
        let current = Set(StoreID.allCases)
        let hasStoredVisibility = defaults.array(forKey: knownKey) != nil
        if defaults.array(forKey: knownKey) != nil {
            let stored = Set((defaults.array(forKey: visibleKey) as? [String] ?? []).compactMap(StoreID.init(rawValue:)))
            visibleIDs = stored.intersection(current)
        } else if hasLegacyStorePreferences {
            // These are the stores present before visibility preferences existed.
            visibleIDs = Set([StoreID.coles, .woolworths, .bunnings]).intersection(current)
        } else {
            visibleIDs = []
        }
        // Existing installs retain the neutral empty state. On new installs the
        // welcome remains until a store is actually enabled, across relaunches.
        hasCompletedStoreSetup = defaults.object(forKey: setupCompletedKey) as? Bool
            ?? (hasStoredVisibility || hasLegacyStorePreferences)
        if !visibleIDs.isEmpty { hasCompletedStoreSetup = true }
        defaults.set(hasCompletedStoreSetup, forKey: setupCompletedKey)
        defaults.set(current.map(\.rawValue).sorted(), forKey: knownKey)
        defaults.set(visibleIDs.map(\.rawValue).sorted(), forKey: visibleKey)
        // Superseded by checking the active store on every return to the list.
        defaults.removeObject(forKey: "selectEnabledStoreAfterEmpty.v1")
        ingredientSearchContext = IngredientSearchContext(countryCode: shoppingCountryCode, enabled: localNames)
    }

    func updateNonEmptyListIDs(_ ids: Set<UUID>) {
        nonEmptyListIDs = ids
    }

    @discardableResult
    func setVisible(_ visible: Bool, for id: StoreID) -> Bool {
        guard visible || canDisable([id]) else { return false }
        var updated = visibleIDs
        if visible { updated.insert(id) } else { updated.remove(id) }
        saveVisibility(updated)
        return true
    }

    private func saveVisibility(_ updated: Set<StoreID>) {
        var pending = (defaults.array(forKey: pendingSelectionKey) as? [String] ?? [])
            .compactMap(StoreID.init(rawValue:)).filter { updated.contains($0) }
        // Record actual disabled→enabled transitions only. A repeated on-value
        // or country/filter change must not steal a later explicit selection.
        for id in updated.subtracting(visibleIDs).sorted(by: { $0.rawValue < $1.rawValue }) {
            pending.removeAll { $0 == id }
            pending.append(id)
        }
        defaults.set(pending.map(\.rawValue), forKey: pendingSelectionKey)
        visibleIDs = updated
        defaults.set(updated.map(\.rawValue).sorted(), forKey: visibleKey)
        if !updated.isEmpty {
            hasCompletedStoreSetup = true
            defaults.set(true, forKey: setupCompletedKey)
        }
    }

    func selectionForList(current: StoreID, definitions: [StoreDefinition]) -> StoreID? {
        // Resolve only when returning to the list, never during management.
        // Reading persisted visibility also repairs an old disabled selection on launch.
        let available = shoppingVisibleIDs(in: definitions)
        let pending = (defaults.array(forKey: pendingSelectionKey) as? [String] ?? [])
            .compactMap(StoreID.init(rawValue:)).last(where: { available.contains($0) })
        // Consume on return, even when already active, so subsequent visits or
        // explicit picker choices are not overridden by an old enable action.
        defaults.removeObject(forKey: pendingSelectionKey)
        if let pending { return pending }
        return available.contains(current) ? current
            : StoreCatalogue.ordered(definitions, countryCode: nil, enabledIDs: available).first?.id
    }

    func setShoppingCountry(_ code: String?) {
        guard code == nil || ShoppingCountry.validated(code) != nil else { return }
        shoppingCountryCode = ShoppingCountry.validated(code)
        defaults.set(shoppingCountryCode, forKey: countryKey)
        defaults.set(true, forKey: countryInitializedKey)
        ingredientSearchContext = IngredientSearchContext(countryCode: shoppingCountryCode, enabled: useLocalIngredientNames)
    }

    func setUseLocalIngredientNames(_ enabled: Bool) {
        useLocalIngredientNames = enabled
        defaults.set(enabled, forKey: "useLocalIngredientNames.v1")
        ingredientSearchContext = IngredientSearchContext(countryCode: shoppingCountryCode, enabled: enabled)
    }

    func setAutoScrollToResults(_ enabled: Bool) {
        defaults.set(enabled, forKey: "autoScrollToResults.v1")
        autoScrollToResults = enabled
    }

    func selectedRegion(for brand: StoreBrand) -> StoreDefinition {
        // A saved choice or enabled destination always wins over Shopping country.
        if let raw = regionalChoices[brand.id], let saved = brand.regions.first(where: { $0.id.rawValue == raw }) { return saved }
        if let enabled = brand.regions.first(where: { visibleIDs.contains($0.id) }) { return enabled }
        return brand.regions.first(where: { $0.isConfigurationValid && (shoppingCountryCode.map($0.serviceArea.countryCodes.contains) ?? false) })
            ?? brand.regions[0]
    }

    @discardableResult
    func setBrandVisible(_ visible: Bool, brand: StoreBrand) -> Bool {
        let selected = selectedRegion(for: brand)
        let siblings = StoreID.allCases.filter { $0.brandID == brand.id }
        var updated = visibleIDs.subtracting(siblings)
        if visible { updated.insert(selected.id) }
        guard canDisable(visibleIDs.subtracting(updated)) else { return false }
        var choices = regionalChoices
        choices[brand.id] = selected.id.rawValue
        regionalChoices = choices
        defaults.set(choices, forKey: regionalKey)
        saveVisibility(updated)
        return true
    }

    @discardableResult
    func chooseRegion(_ id: StoreID, for brand: StoreBrand) -> Bool {
        guard brand.regions.contains(where: { $0.id == id }) else { return false }
        let siblings = StoreID.allCases.filter { $0.brandID == brand.id }
        let enabled = siblings.contains { visibleIDs.contains($0) }
        let replaced = Set(siblings).intersection(visibleIDs).subtracting([id])
        guard !enabled || canDisable(replaced) else { return false }
        var choices = regionalChoices
        choices[brand.id] = id.rawValue
        regionalChoices = choices
        defaults.set(choices, forKey: regionalKey)
        // Called only after explicit confirmation. Hide siblings, never delete their
        // data or change activeStoreID here. The list screen resolves a disabled
        // active destination to an enabled store when management is dismissed.
        var updated = visibleIDs.subtracting(siblings)
        if enabled { updated.insert(id) }
        saveVisibility(updated)
        return true
    }
}

enum StoreBridge {
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let result = value as? Int else { return nil }
        return result
    }

    static func productID(_ value: Any?) -> Bool {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= 32 else { return false }
        return text.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func decode(_ raw: String, store: StoreDefinition) -> [String: Any]? {
        guard raw.utf8.count <= 8_192, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(object["schemaVersion"]) == 1, object["storeID"] as? String == store.id.rawValue,
              let session = object["sessionID"] as? String, !session.isEmpty,
              let interaction = object["interactionID"] as? String, !interaction.isEmpty,
              let item = object["itemID"] as? String, UUID(uuidString: item) != nil,
              let generation = integer(object["documentGeneration"]), generation >= 0,
              let page = object["pageURL"] as? String, let url = URL(string: page), store.allows(url),
              let type = object["type"] as? String else { return nil }
        let common: Set<String> = ["schemaVersion", "storeID", "sessionID", "interactionID", "itemID", "documentGeneration", "pageURL", "type"]
        switch type {
        case "cartInteractionStarted":
            guard Set(object.keys) == common.union(["productID", "beforeQuantity", "intent"]),
                  let product = object["productID"] as? String, store.acceptsProductIdentity(product),
                  let before = integer(object["beforeQuantity"]), (0...9_999).contains(before),
                  object["intent"] as? String == (before == 0 ? "add" : "increment") else { return nil }
        case "addDetected":
            guard Set(object.keys) == common.union(["productID", "beforeQuantity", "resultingQuantity", "confirmationID"]),
                   let product = object["productID"] as? String, store.acceptsProductIdentity(product), productID(object["confirmationID"]),
                  let before = integer(object["beforeQuantity"]), let after = integer(object["resultingQuantity"]),
                   (0...9_999).contains(before), (1...9_999).contains(after), after > before else { return nil }
        case "addAcknowledged":
            guard store.automationSchemaVersion == 4, !store.capabilities.cartUndo,
                  Set(object.keys) == common.union(["productID", "confirmationID", "profileID"]),
                  let product = object["productID"] as? String, store.acceptsProductIdentity(product),
                  productID(object["confirmationID"]),
                  let profileID = object["profileID"] as? String,
                  store.cart?.profiles?.contains(where: { $0.id == profileID && $0.confirmation == .productAcknowledgement }) == true else { return nil }
        case "automationUnavailable":
            guard Set(object.keys) == common.union(["capability", "scope", "reason"]),
                  object["capability"] as? String == "cartDetection", object["scope"] as? String == "interaction",
                   ["productIdUnavailable", "quantityUnavailable", "confirmationTimedOut", "cartPreflightUnavailable"].contains(object["reason"] as? String ?? ""),
                   object["reason"] as? String != "cartPreflightUnavailable" || store.cart?.strategy == .verifiedCartSnapshot else { return nil }
        default: return nil
        }
        return object
    }
}
