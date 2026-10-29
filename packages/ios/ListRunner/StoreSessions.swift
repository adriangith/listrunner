import Combine
import Foundation
import WebKit

@MainActor
final class StoreSessions: ObservableObject {
    let diagnostics: DiagnosticStore
    let definitions: [StoreDefinition]
    private var browsers: [StoreID: StoreBrowser] = [:]
    private var searchContext: IngredientSearchContext = .unchanged
    private var preferenceSubscription: AnyCancellable?

    init(diagnostics: DiagnosticStore, preferences: StoreVisibilityPreferences? = nil) {
        self.diagnostics = diagnostics
        definitions = StoreID.allCases.map { StoreDefinition.load($0) }
        if let preferences {
            searchContext = preferences.ingredientSearchContext
            preferenceSubscription = preferences.$ingredientSearchContext.removeDuplicates().sink { [weak self] context in
                guard let self else { return }
                self.searchContext = context
                for browser in self.browsers.values { browser.updateIngredientSearchContext(context) }
            }
        }
    }

    func browser(for id: StoreID) -> StoreBrowser {
        if let existing = browsers[id] { return existing }
        let definition = definitions.first { $0.id == id }!
        // Preserve the existing Coles login in the default persistent store. All
        // new retailers get a distinct named persistent store (iOS 17+).
        let dataStore: WKWebsiteDataStore
        #if DEBUG
        if ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"].flatMap(UUID.init(uuidString:)) != nil {
            dataStore = .nonPersistent()
        } else {
            dataStore = id == .coles ? .default() : WKWebsiteDataStore(forIdentifier: id.websiteDataID)
        }
        #else
        dataStore = id == .coles ? .default() : WKWebsiteDataStore(forIdentifier: id.websiteDataID)
        #endif
        let browser = StoreBrowser(store: definition, websiteDataStore: dataStore, diagnostics: diagnostics)
        browser.updateIngredientSearchContext(searchContext)
        browsers[id] = browser
        return browser
    }

    func endAllInteractions() {
        for browser in browsers.values { browser.endInteraction() }
    }
}
