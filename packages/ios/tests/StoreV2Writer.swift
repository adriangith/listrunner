import Foundation
import SwiftData

@main struct StoreV2Writer {
    @MainActor static func main() throws {
        let listID = StoreID.coles.listID
        let itemID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
        let configuration = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: Schema(versionedSchema: ShoppingSchemaV2.self), configurations: configuration)
        let list = ShoppingSchemaV2.GroceryList(id: listID, storeID: "coles", selectedItemID: itemID, lastActiveDay: "2026-10-21")
        let item = ShoppingSchemaV2.GroceryItem(id: itemID, name: "2L milk", searchTerm: "2L milk", quantityAmount: 2,
                                                quantityUnit: "l", statusRawValue: "Added", position: 4, listID: listID)
        container.mainContext.insert(list)
        container.mainContext.insert(item)
        try container.mainContext.save()
    }
}
