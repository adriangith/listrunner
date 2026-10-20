import SwiftUI

@main
struct ListRunnerApp: App {
    var body: some Scene {
        WindowGroup {
            GroceryListScreen()
        }
        .modelContainer(for: GroceryItem.self)
    }
}
