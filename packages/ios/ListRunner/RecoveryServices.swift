import Combine
import Foundation
import SwiftData
import WebKit

@MainActor
final class LocalDataController: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var opening = false
    private let configuration: ModelConfiguration
    let defaults: UserDefaults
    private let opener: (ModelConfiguration) throws -> ModelContainer
    let diagnostics: DiagnosticStore

    static func forApp() -> LocalDataController {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_SESSION"], let token = UUID(uuidString: raw) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ListRunnerUITests/" + token.uuidString)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let defaults = UserDefaults(suiteName: "ListRunnerUITests." + token.uuidString)!
            let controller = LocalDataController(configuration: ModelConfiguration(url: directory.appendingPathComponent("test.store")),
                                                 diagnostics: DiagnosticStore(fileURL: directory.appendingPathComponent("diagnostics.json")), defaults: defaults)
            if ProcessInfo.processInfo.environment["LISTRUNNER_UI_TEST_EMPTY_LIST"] != "1",
               let context = controller.container?.mainContext,
               (try? context.fetchCount(FetchDescriptor<GroceryItem>())) == 0 {
                context.insert(GroceryItem(name: "Coles fixture item", amount: 2, position: 0, listID: StoreID.coles.listID))
                context.insert(GroceryItem(name: "Woolworths fixture item", amount: 1, position: 0, listID: StoreID.woolworths.listID))
                context.insert(GroceryItem(name: "Bunnings fixture item", amount: 1, position: 0, listID: StoreID.bunnings.listID))
                try? context.save()
            }
            return controller
        }
        #endif
        return LocalDataController()
    }

    init(configuration: ModelConfiguration = ModelConfiguration(schema: ShoppingLists.schema),
         diagnostics: DiagnosticStore = DiagnosticStore(), defaults: UserDefaults = .standard,
         opener: @escaping (ModelConfiguration) throws -> ModelContainer = {
             try ShoppingLists.open(configuration: $0)
         }) {
        self.configuration = configuration
        self.diagnostics = diagnostics
        self.defaults = defaults
        self.opener = opener
        open()
    }

    func open() {
        guard !opening, container == nil else { return }
        opening = true
        defer { opening = false }
        do {
            let value = try opener(configuration)
            value.mainContext.autosaveEnabled = false
            do {
                try ShoppingLists.prepare(value.mainContext, legacySelectedID: defaults.string(forKey: "lastOverlaySelectedItemID").flatMap(UUID.init(uuidString:)))
            } catch {
                value.mainContext.rollback()
                throw error
            }
            container = value
        } catch {
            container = nil
            diagnostics.record(.storage, .localOpen, reason: .storageFailure, outcome: .failed)
        }
    }

    func resetAfterConfirmation() {
        // Offered only when storage cannot open. Never delete an open database,
        // a parent directory, or any WebKit/Reminders storage.
        guard container == nil, !opening else { return }
        do {
            let url = configuration.url
            for path in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            }
            for key in ["lastOverlaySelectedItemID", "lastActiveLocalDate", "activeStoreID",
                        "visibleStoreIDs.v1", "knownStoreIDs.v1", "storeSortMode.v1",
                         "shoppingCountry.v1", "shoppingCountryInitialized.v1", "storeRegionalChoices.v1", "useLocalIngredientNames.v1",
                        "selectEnabledStoreAfterEmpty.v1", "pendingEnabledStoreSelection.v1"] {
                defaults.removeObject(forKey: key)
            }
            try diagnostics.clear()
            open()
        } catch {
            diagnostics.record(.storage, .localReset, reason: .storageFailure, outcome: .failed)
        }
    }
}

enum StoreWebsiteData {
    @MainActor
    static func clear(in store: WKWebsiteDataStore, for storeID: StoreID) async -> Bool {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter { storeID.ownsDataDomain($0.displayName) }
        await store.removeData(ofTypes: types, for: records)
        let cookies = await store.httpCookieStore.allCookies()
        for cookie in cookies where storeID.ownsDataDomain(cookie.domain) {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        let remainingRecords = await store.dataRecords(ofTypes: types).filter { storeID.ownsDataDomain($0.displayName) }
        let remainingCookies = await store.httpCookieStore.allCookies().filter { storeID.ownsDataDomain($0.domain) }
        return remainingRecords.isEmpty && remainingCookies.isEmpty
    }
}
