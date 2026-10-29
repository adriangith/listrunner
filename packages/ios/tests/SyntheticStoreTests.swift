import Foundation

// Compiled only with STORE_REGISTRY_PROOF. No network or application data access.
@main
struct SyntheticStoreTests {
    @MainActor
    static func main() throws {
        let data = Data(#"""
        {
          "schemaVersion": 2,
          "id": "synthetic",
          "displayName": "Example Hardware",
          "serviceArea": {"countryCodes": ["AU", "NZ"]},
          "homepage": "https://www.store.example",
          "allowedHosts": ["www.store.example"],
          "search": {"strategy": "urlTemplate", "template": "https://www.store.example/search?q={query}"},
          "addedColor": {"red": 64, "green": 64, "blue": 64},
          "capabilities": {"search": true, "cartDetection": false, "cartUndo": false},
          "cart": null
        }
        """#.utf8)
        let definition = try StoreDefinition.decodeConfiguration(from: data)
        precondition(definition.id == .synthetic && definition.isConfigurationValid)
        precondition(!definition.capabilities.cartUndo && !definition.id.permitsCartUndo)
        precondition(definition.searchURL(for: "tea & coffee")?.query?.contains("%26") == true)
        precondition(Set(StoreID.allCases.map(\.listID)).count == StoreID.allCases.count)
        precondition(Set(StoreID.allCases.map(\.websiteDataID)).count == StoreID.allCases.count)
        precondition(!definition.allows(URL(string: "https://www.coles.com.au")!))
        let existing = try StoreDefinition.decodeConfiguration(from: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("coles.json")))
        precondition(StoreCatalogue.ordered([existing, definition], countryCode: "NZ").first?.id == .synthetic)
        precondition(StoreCatalogue.ordered([definition, existing], countryCode: "AU").map(\.id) == [.coles, .synthetic])

        let suite = "ListRunnerSyntheticProof.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = StoreVisibilityPreferences(defaults: defaults)
        precondition(!preferences.visibleIDs.contains(.synthetic))
        preferences.setVisible(true, for: .synthetic)
        precondition(StoreVisibilityPreferences(defaults: defaults).visibleIDs.contains(.synthetic))
        preferences.setVisible(false, for: .synthetic)
        precondition(!StoreVisibilityPreferences(defaults: defaults).visibleIDs.contains(.synthetic))
        print("PASS: synthetic bundled registration, multi-country ordering, encoded search, trust/identity isolation and hidden-by-default persistence")
    }
}
