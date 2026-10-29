import Foundation
import SwiftData

// Deliberately compiled in its own process/module with the original top-level,
// unversioned model. This exercises an actual pre-multi-store database migration.
@Model final class GroceryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var searchTerm: String
    var quantityAmount: Double?
    var quantityUnit: String?
    var statusRawValue: String
    var position: Int

    init() {
        id = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
        name = "BBQ Sauce"; searchTerm = "BBQ Sauce"
        quantityAmount = 2; quantityUnit = "bottles"
        statusRawValue = "Added"; position = 7
    }
}

@main struct LegacyStoreWriter {
    @MainActor static func main() throws {
        let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: GroceryItem.self, configurations: config)
        container.mainContext.insert(GroceryItem())
        try container.mainContext.save()
    }
}
