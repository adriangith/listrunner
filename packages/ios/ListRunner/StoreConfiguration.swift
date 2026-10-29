import Foundation
import CoreFoundation
import Combine

enum StoreID: String, Codable, CaseIterable, Identifiable {
    case coles, woolworths, bunnings, costco, tesco, walmart, kmart, costcoUS, bigW
    #if STORE_REGISTRY_PROOF
    // Only compiled by the standalone extensibility proof, never the app.
    case synthetic
    #endif
    var id: String { rawValue }
    // Reviewed native ceilings: bundled data cannot enable unreviewed store automation.
    var permitsSearch: Bool { ![.tesco, .walmart, .costcoUS, .bigW].contains(self) }
    // Brand grouping is reviewed native identity, never inferred from a name or host.
    var brandID: String { self == .costcoUS ? StoreID.costco.rawValue : rawValue }
    var brandName: String { self == .costcoUS ? "Costco" : displayName }
    var regionalCountryCode: String? {
        switch self {
        case .costco: "AU"
        case .costcoUS: "US"
        default: nil
        }
    }
    var permitsCartUndo: Bool { [.coles, .kmart].contains(self) }
    var permitsCartDetection: Bool { [.coles, .woolworths, .bunnings, .kmart].contains(self) }
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
        #if STORE_REGISTRY_PROOF
        case .synthetic: "Example Hardware"
        #endif
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
        #if STORE_REGISTRY_PROOF
        case .synthetic: "store.example"
        #endif
        }
    }
    var home: URL { URL(string: "https://www.\(dataDomain)")! }
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

struct StoreDefinition: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, displayName, serviceArea, homepage, allowedHosts
        case search, addedColor, brandColors, capabilities, cart
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
    }
    struct Cart: Codable {
        enum Strategy: String, Codable { case trustedTileQuantity }
        enum IdentityStrategy: String, Codable { case numericURLSuffix }
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
    let id: StoreID
    let displayName: String
    let serviceArea: ServiceArea
    let homepage: URL
    let allowedHosts: [String]
    let search: Search
    let addedColor: AddedColor
    var brandColors: BrandColors? = nil
    var capabilities: Capabilities
    let cart: Cart?

    init(schemaVersion: Int, id: StoreID, displayName: String, serviceArea: ServiceArea,
         homepage: URL, allowedHosts: [String], search: Search, addedColor: AddedColor,
         brandColors: BrandColors? = nil, capabilities: Capabilities, cart: Cart?) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.serviceArea = serviceArea
        self.homepage = homepage
        self.allowedHosts = allowedHosts
        self.search = search
        self.addedColor = addedColor
        self.brandColors = brandColors
        self.capabilities = capabilities
        self.cart = cart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.stringValue))
                .subtracting(container.contains(.brandColors) ? [] : [CodingKeys.brandColors.rawValue]) else {
            throw ConfigurationError.invalid
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(StoreID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        serviceArea = try container.decode(ServiceArea.self, forKey: .serviceArea)
        homepage = try container.decode(URL.self, forKey: .homepage)
        allowedHosts = try container.decode([String].self, forKey: .allowedHosts)
        search = try container.decode(Search.self, forKey: .search)
        addedColor = try container.decode(AddedColor.self, forKey: .addedColor)
        brandColors = try container.decodeIfPresent(BrandColors.self, forKey: .brandColors)
        capabilities = try container.decode(Capabilities.self, forKey: .capabilities)
        cart = try container.decodeIfPresent(Cart.self, forKey: .cart)
    }

    enum ConfigurationError: Error { case invalid }

    var isConfigurationValid: Bool { (try? validate()) != nil }

    func validate() throws {
        let countries = serviceArea.countryCodes
        let supportedCountryCodes = Set(Locale.Region.isoRegions.map(\.identifier))
        guard schemaVersion == 2, displayName == id.displayName,
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
        if let cart {
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
        }
    }

    func allows(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) && allowedHosts.contains(url.host?.lowercased() ?? "")
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
        // Bunnings establishes its website session through a silent authorization
        // frame. This is browsing-only: `allows` and automation hosts stay closed.
        return id == .bunnings && host == "authorisation.api.bunnings.com.au"
    }

    func searchURL(for query: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: search.template.replacingOccurrences(of: "{query}", with: encoded))
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
              hasOnlyKeys(root, ["schemaVersion", "id", "displayName", "serviceArea", "homepage", "allowedHosts",
                                 "search", "addedColor", "brandColors", "capabilities", "cart"]),
              hasOnlyKeys(root["serviceArea"] as? [String: Any], ["countryCodes"]),
              hasOnlyKeys(root["search"] as? [String: Any], ["strategy", "template"]),
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
                               "emptyStatusText", "decrementLabelPattern"]) {
            throw ConfigurationError.invalid
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
        let candidates = definitions.filter { enabledIDs?.contains($0.id) ?? true }
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
        let brands = catalogue(definitions).filter { brand in
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

@MainActor
final class StoreVisibilityPreferences: ObservableObject {
    @Published private(set) var visibleIDs: Set<StoreID>
    @Published private(set) var shoppingCountryCode: String?
    @Published private(set) var useLocalIngredientNames: Bool
    // Published as one atomic value so browsers never see a half-updated pair.
    @Published private(set) var ingredientSearchContext: IngredientSearchContext = .unchanged
    @Published private(set) var regionalChoices: [String: String]
    private let defaults: UserDefaults
    private let visibleKey = "visibleStoreIDs.v1"
    private let knownKey = "knownStoreIDs.v1"
    private let countryKey = "shoppingCountry.v1"
    private let countryInitializedKey = "shoppingCountryInitialized.v1"
    private let regionalKey = "storeRegionalChoices.v1"

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
        defaults.removeObject(forKey: "storeSortMode.v1")
        let current = Set(StoreID.allCases)
        if defaults.array(forKey: knownKey) != nil {
            let stored = Set((defaults.array(forKey: visibleKey) as? [String] ?? []).compactMap(StoreID.init(rawValue:)))
            visibleIDs = stored.intersection(current)
        } else {
            // These are the stores present before visibility preferences existed.
            visibleIDs = Set([StoreID.coles, .woolworths, .bunnings]).intersection(current)
        }
        defaults.set(current.map(\.rawValue).sorted(), forKey: knownKey)
        defaults.set(visibleIDs.map(\.rawValue).sorted(), forKey: visibleKey)
        // Superseded by checking the active store on every return to the list.
        defaults.removeObject(forKey: "selectEnabledStoreAfterEmpty.v1")
        ingredientSearchContext = IngredientSearchContext(countryCode: shoppingCountryCode, enabled: localNames)
    }

    func setVisible(_ visible: Bool, for id: StoreID) {
        var updated = visibleIDs
        if visible { updated.insert(id) } else { updated.remove(id) }
        saveVisibility(updated)
    }

    private func saveVisibility(_ updated: Set<StoreID>) {
        visibleIDs = updated
        defaults.set(updated.map(\.rawValue).sorted(), forKey: visibleKey)
    }

    func selectionForList(current: StoreID, definitions: [StoreDefinition]) -> StoreID? {
        // Resolve only when returning to the list, never during management.
        // Reading persisted visibility also repairs an old disabled selection on launch.
        visibleIDs.contains(current) ? current
            : StoreCatalogue.ordered(definitions, countryCode: nil, enabledIDs: visibleIDs).first?.id
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

    func selectedRegion(for brand: StoreBrand) -> StoreDefinition {
        // A saved choice or enabled destination always wins over Shopping country.
        if let raw = regionalChoices[brand.id], let saved = brand.regions.first(where: { $0.id.rawValue == raw }) { return saved }
        if let enabled = brand.regions.first(where: { visibleIDs.contains($0.id) }) { return enabled }
        return brand.regions.first(where: { $0.isConfigurationValid && (shoppingCountryCode.map($0.serviceArea.countryCodes.contains) ?? false) })
            ?? brand.regions[0]
    }

    func setBrandVisible(_ visible: Bool, brand: StoreBrand) {
        let selected = selectedRegion(for: brand)
        var choices = regionalChoices
        choices[brand.id] = selected.id.rawValue
        regionalChoices = choices
        defaults.set(choices, forKey: regionalKey)
        var updated = visibleIDs.subtracting(brand.regions.map(\.id))
        if visible { updated.insert(selected.id) }
        saveVisibility(updated)
    }

    func chooseRegion(_ id: StoreID, for brand: StoreBrand) {
        guard brand.regions.contains(where: { $0.id == id }) else { return }
        let enabled = brand.regions.contains { visibleIDs.contains($0.id) }
        var choices = regionalChoices
        choices[brand.id] = id.rawValue
        regionalChoices = choices
        defaults.set(choices, forKey: regionalKey)
        // Called only after explicit confirmation. Hide siblings, never delete their
        // data or change activeStoreID here. The list screen resolves a disabled
        // active destination to an enabled store when management is dismissed.
        var updated = visibleIDs.subtracting(brand.regions.map(\.id))
        if enabled { updated.insert(id) }
        saveVisibility(updated)
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
            guard Set(object.keys) == common.union(["productID", "beforeQuantity", "intent"]), productID(object["productID"]),
                  let before = integer(object["beforeQuantity"]), (0...9_999).contains(before),
                  object["intent"] as? String == (before == 0 ? "add" : "increment") else { return nil }
        case "addDetected":
            guard Set(object.keys) == common.union(["productID", "beforeQuantity", "resultingQuantity", "confirmationID"]),
                  productID(object["productID"]), productID(object["confirmationID"]),
                  let before = integer(object["beforeQuantity"]), let after = integer(object["resultingQuantity"]),
                  (0...9_999).contains(before), (1...9_999).contains(after), after > before else { return nil }
        case "automationUnavailable":
            guard Set(object.keys) == common.union(["capability", "scope", "reason"]),
                  object["capability"] as? String == "cartDetection", object["scope"] as? String == "interaction",
                  ["productIdUnavailable", "quantityUnavailable"].contains(object["reason"] as? String ?? "") else { return nil }
        default: return nil
        }
        return object
    }
}
