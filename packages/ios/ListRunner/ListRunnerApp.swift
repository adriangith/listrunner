import SwiftUI

@main
struct ListRunnerApp: App {
    @StateObject private var storage = LocalDataController.forApp()

    var body: some Scene {
        WindowGroup {
            if let container = storage.container {
                ShoppingRootScreen(diagnostics: storage.diagnostics)
                    .modelContainer(container)
                    .defaultAppStorage(storage.defaults)
            } else {
                LocalDataRecoveryScreen(storage: storage)
            }
        }
    }
}
