import SwiftUI

@main
struct ListRunnerApp: App {
    @StateObject private var storage = LocalDataController.forApp()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = storage.container {
                    ShoppingRootScreen(diagnostics: storage.diagnostics)
                        .modelContainer(container)
                } else {
                    LocalDataRecoveryScreen(storage: storage)
                }
            }
            .modifier(AppAppearance(defaults: storage.defaults))
            .defaultAppStorage(storage.defaults)
        }
    }
}

private struct AppAppearance: ViewModifier {
    @AppStorage private var appearance: String

    init(defaults: UserDefaults) {
        _appearance = AppStorage(wrappedValue: "system", "appearance.v1", store: defaults)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    func body(content: Content) -> some View {
        content.preferredColorScheme(colorScheme)
    }
}
