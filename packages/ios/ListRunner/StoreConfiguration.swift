import Foundation
import CoreFoundation

enum StoreID: String, Codable, CaseIterable, Identifiable {
    case coles, woolworths, bunnings
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .coles: "Coles"
        case .woolworths: "Woolworths"
        case .bunnings: "Bunnings"
        }
    }
    var hosts: Set<String> {
        switch self {
        case .coles: ["www.coles.com.au", "coles.com.au"]
        case .woolworths: ["www.woolworths.com.au", "woolworths.com.au"]
        case .bunnings: ["www.bunnings.com.au", "bunnings.com.au"]
        }
    }
    var dataDomain: String {
        switch self {
        case .coles: "coles.com.au"
        case .woolworths: "woolworths.com.au"
        case .bunnings: "bunnings.com.au"
        }
    }
    var home: URL { URL(string: "https://www.\(dataDomain)")! }
    var listID: UUID {
        let value: String
        switch self {
        case .coles: value = "10000000-0000-4000-8000-000000000001"
        case .woolworths: value = "10000000-0000-4000-8000-000000000002"
        case .bunnings: value = "10000000-0000-4000-8000-000000000003"
        }
        return UUID(uuidString: value)!
    }
    var websiteDataID: UUID {
        let value: String
        switch self {
        case .coles: value = "20000000-0000-4000-8000-000000000001"
        case .woolworths: value = "20000000-0000-4000-8000-000000000002"
        case .bunnings: value = "20000000-0000-4000-8000-000000000003"
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
    let homepage: URL
    let allowedHosts: [String]
    let search: Search
    let addedColor: AddedColor
    var brandColors: BrandColors? = nil
    var capabilities: Capabilities
    let cart: Cart?

    enum ConfigurationError: Error { case invalid }

    func validate() throws {
        guard schemaVersion == 1, displayName == id.displayName, !allowedHosts.isEmpty,
              Set(allowedHosts).count == allowedHosts.count,
              Set(allowedHosts).isSubset(of: id.hosts), allows(homepage),
              search.template.components(separatedBy: "{query}").count == 2,
              !search.template.replacingOccurrences(of: "{query}", with: "").contains("{"),
              !search.template.replacingOccurrences(of: "{query}", with: "").contains("}"),
               let probe = searchURL(for: "validation / & + # ?"), allows(probe),
               (0...255).contains(addedColor.red), (0...255).contains(addedColor.green), (0...255).contains(addedColor.blue),
               brandColors.map({ (0...255).contains($0.primary.red) && (0...255).contains($0.primary.green) && (0...255).contains($0.primary.blue)
                   && (0...255).contains($0.highlight.red) && (0...255).contains($0.highlight.green) && (0...255).contains($0.highlight.blue) }) ?? true,
              !capabilities.cartUndo || capabilities.cartDetection,
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
        return id == .coles && url.scheme?.lowercased() == "https"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && ["auth.colesgroupprofile.com.au", "id.colesgroupprofile.com.au"].contains(url.host?.lowercased() ?? "")
    }

    func searchURL(for query: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: search.template.replacingOccurrences(of: "{query}", with: encoded))
    }

    static func load(_ id: StoreID, bundle: Bundle = .main) -> StoreDefinition {
        do {
            guard let url = bundle.url(forResource: id.rawValue, withExtension: "json") else { throw ConfigurationError.invalid }
            let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard value.id == id else { throw ConfigurationError.invalid }
            try value.validate()
            return value
        } catch {
            // Browsing/manual status remain safe even if a bundled configuration is bad.
            let bunningsCart: Cart? = id == .bunnings
                ? Cart(strategy: .trustedTileQuantity, identityStrategy: .numericURLSuffix,
                       tileSelector: "main", linkSelector: "a[href]",
                       productURLPattern: "_p(\\d{1,32})(?:[/?#]|$)", addSelector: "button",
                       addLabelPatterns: ["^add to cart$", "^increase quantity$"],
                       quantitySelector: "input[aria-label=\"Quantity\"],input[name=\"quantity\"]",
                       emptyStatusSelector: "[role=\"status\"]", emptyStatusText: "product is not in your cart",
                       decrementLabelPattern: "^decrease quantity$")
                : nil
            return StoreDefinition(schemaVersion: 1, id: id, displayName: id.displayName,
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
                                        }
                                    }(),
                                    capabilities: Capabilities(search: id == .bunnings,
                                                               cartDetection: bunningsCart != nil, cartUndo: false), cart: bunningsCart)
        }
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
