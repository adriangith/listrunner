import AppIntents
import Combine
import Foundation
import SwiftData

// Siri, Shortcuts and Spotlight support. The intents run inside the app
// process and share its one LocalDataController, so they write through the
// same SwiftData main context the visible list reads.
//
// Public contract: intent type names, ShoppingListEntity ids (ListOwner raw
// values), SiriDefaultList raw values and the App Shortcut phrases are stored
// by the system. Add to them; do not rename or remove shipped ones.

// MARK: - Setting

// Where Siri adds items when the person does not name a list.
enum SiriDefaultList: String, CaseIterable, Identifiable {
    case inbox = "inbox"
    case lastUsed = "lastUsed"
    case ask = "ask"

    static let preferenceKey = "siriDefaultList.v1"
    var id: String { rawValue }

    static func current(in defaults: UserDefaults) -> SiriDefaultList {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .inbox
    }
}

// MARK: - Navigation

// Open List hands its target to the root screen, which uses the same path as
// choosing a list in the app. A cold launch reads it on first appearance.
@MainActor
final class SiriNavigation: ObservableObject {
    static let shared = SiriNavigation()
    @Published var requestedList: ListOwner?
}

// MARK: - Errors

enum SiriListError: Error, CustomLocalizedStringResourceConvertible {
    case noLists
    case listNotFound
    case listUnavailable(String)
    case nothingToAdd
    case storageUnavailable
    case unsavedChanges
    case importInProgress
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noLists: "Turn on a store or Inbox in ListRunner first."
        case .listNotFound: "ListRunner doesn’t have that list."
        case .listUnavailable(let name): "\(name) isn’t turned on in ListRunner. Turn it on in Manage Stores."
        case .nothingToAdd: "I didn’t catch any items to add."
        case .storageUnavailable: "ListRunner can’t open your lists right now. Open the app to fix this."
        case .unsavedChanges: "Finish the change you’re making in ListRunner, then try again."
        case .importInProgress: "ListRunner is importing from Reminders. Try again when it finishes."
        case .saveFailed: "ListRunner couldn’t save the items. Nothing was added."
        }
    }
}

// MARK: - List entity

struct ShoppingListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ShoppingListQuery()

    // ListOwner raw value ("coles", "inbox"): stable across launches and devices.
    let id: String
    @Property(title: "Name") var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ owner: ListOwner) {
        id = owner.rawValue
        name = owner.displayName
    }
}

struct ShoppingListQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShoppingListEntity] {
        identifiers.compactMap(ListOwner.init(rawValue:)).map(ShoppingListEntity.init)
    }

    // Enabled lists only: these feed the Shortcuts picker, Siri's "which
    // list?" question and the spoken list names in App Shortcut phrases.
    func suggestedEntities() async throws -> [ShoppingListEntity] {
        await SiriLists.availableLists().map(ShoppingListEntity.init)
    }

    func entities(matching string: String) async throws -> [ShoppingListEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return await SiriLists.availableLists()
            .filter { $0.displayName.localizedCaseInsensitiveContains(query) || query.localizedCaseInsensitiveContains($0.displayName) }
            .map(ShoppingListEntity.init)
    }
}

// MARK: - Shared list access

@MainActor
enum SiriLists {
    enum Purpose { case add, read }
    enum Destination: Equatable { case list(ListOwner), ask }

    private static let definitions = StoreID.allCases.map { StoreDefinition.load($0) }
    private static var defaults: UserDefaults { LocalDataController.forApp().defaults }
    private static let readLimit = 10

    // Inbox (when on) first, then enabled stores in the app's own order.
    static func availableLists() -> [ListOwner] {
        let preferences = StoreVisibilityPreferences(defaults: defaults)
        let stores = StoreCatalogue.ordered(definitions, countryCode: nil,
                                            enabledIDs: preferences.shoppingVisibleIDs(in: definitions))
        return (preferences.inboxEnabled ? [.inbox] : []) + stores.map { .store($0.id) }
    }

    // Validates a named list, or applies the Siri setting when none was named.
    // `.ask` means the intent should ask the person to choose.
    static func destination(named id: String?, for purpose: Purpose) throws -> Destination {
        let available = availableLists()
        if let id {
            guard let owner = ListOwner(rawValue: id) else { throw SiriListError.listNotFound }
            // Adding to Inbox turns it on; reading any saved list is harmless.
            if available.contains(owner) || owner == .inbox || purpose == .read { return .list(owner) }
            throw SiriListError.listUnavailable(owner.displayName)
        }
        switch SiriDefaultList.current(in: defaults) {
        case .inbox:
            if purpose == .add || available.contains(.inbox) { return .list(.inbox) }
        case .lastUsed:
            let last = ListOwner(rawValue: defaults.string(forKey: "activeStoreID") ?? StoreID.coles.rawValue)
            if let last, available.contains(last) { return .list(last) }
        case .ask:
            break
        }
        guard let first = available.first else { throw SiriListError.noLists }
        return available.count == 1 ? .list(first) : .ask
    }

    // The same staging, merge and save path as typing in a list, plus the
    // All items recency and Reminders write-back an in-app add records.
    static func add(_ text: String, to owner: ListOwner) throws -> [String] {
        let entries = ParsedGrocery.spokenEntries(in: text)
        guard !entries.isEmpty else { throw SiriListError.nothingToAdd }
        guard let context = LocalDataController.forApp().container?.mainContext else {
            throw SiriListError.storageUnavailable
        }
        let reminders = PaprikaReminders.shared
        guard !reminders.importing else { throw SiriListError.importInProgress }
        // Never save someone's half-finished in-app edit on their behalf.
        guard !context.hasChanges else { throw SiriListError.unsavedChanges }
        let defaults = self.defaults
        let allItems: [GroceryItem]
        do { allItems = try context.fetch(FetchDescriptor<GroceryItem>()) }
        catch { throw SiriListError.storageUnavailable }
        let existingIDs = Set(ShoppingLists.orderedItems(in: owner.listID, from: allItems).map(\.id))
        let snapshot = ShoppingLists.AdditionSnapshot(items: allItems, owner: owner)
        let promoted = ShoppingLists.stageAdd(entries, to: owner, allItems: allItems, context: context)
        let removeReminders = defaults.object(forKey: GroceryImportSource.removeRemindersKey) as? Bool ?? true
        let writes = removeReminders ? [] : promoted.filter { existingIDs.contains($0.id) }
            .compactMap { reminders.desiredWriteback(for: $0) }
        do {
            try context.save()
        } catch {
            context.rollback()
            snapshot.restoreAfterRollback()
            throw SiriListError.saveFailed
        }
        for write in writes { reminders.queueWriteback(write) }
        if owner == .inbox, !defaults.bool(forKey: StoreVisibilityPreferences.inboxEnabledKey) {
            StoreVisibilityPreferences.enableInbox(in: defaults)
        }
        let storeOrderKey = "allItemsRecentStoreOrder.v1", itemOrderKey = "allItemsRecentItemOrder.v1"
        defaults.set(ItemPromotionOrder.promotingList(owner, in: defaults.string(forKey: storeOrderKey) ?? ""),
                     forKey: storeOrderKey)
        defaults.set(ItemPromotionOrder.promoting(promoted.map(\.id), in: defaults.string(forKey: itemOrderKey) ?? "",
                                                  existing: Set(allItems.map(\.id)).union(promoted.map(\.id))),
                     forKey: itemOrderKey)
        return promoted.map(\.name)
    }

    // Pending items in the list's own order, with any recorded quantity.
    static func pendingItems(in owner: ListOwner) throws -> [String] {
        guard let context = LocalDataController.forApp().container?.mainContext else {
            throw SiriListError.storageUnavailable
        }
        let allItems: [GroceryItem]
        do { allItems = try context.fetch(FetchDescriptor<GroceryItem>()) }
        catch { throw SiriListError.storageUnavailable }
        return ShoppingLists.orderedItems(in: owner.listID, from: allItems)
            .filter { $0.status == .pending }
            .map { $0.quantityAmount == nil ? $0.name : "\($0.displayQuantity) \($0.name)" }
    }

    static func open(_ id: String) throws {
        guard let owner = ListOwner(rawValue: id) else { throw SiriListError.listNotFound }
        guard availableLists().contains(owner) else { throw SiriListError.listUnavailable(owner.displayName) }
        SiriNavigation.shared.requestedList = owner
    }

    // "your Coles list", "your Inbox": read aloud, so phrased for speech.
    static func spokenName(_ owner: ListOwner) -> String {
        owner == .inbox ? String(localized: "your Inbox") : String(localized: "your \(owner.displayName) list")
    }

    static func spokenItems(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }

    static func readAloud(_ names: [String], in owner: ListOwner) -> String {
        let list = spokenName(owner)
        guard !names.isEmpty else { return String(localized: "There’s nothing left to get on \(list).") }
        let spoken = names.count > readLimit
            ? Array(names.prefix(readLimit)) + [String(localized: "\(names.count - readLimit) more")]
            : names
        let count = names.count == 1 ? String(localized: "1 item") : String(localized: "\(names.count) items")
        let subject = list.prefix(1).uppercased() + String(list.dropFirst())
        return String(localized: "\(subject) has \(count) left: \(spokenItems(spoken)).")
    }

    static func addedMessage(_ names: [String], to owner: ListOwner) -> String {
        let items = names.count > 5 ? String(localized: "\(names.count) items") : spokenItems(names)
        return String(localized: "Added \(items) to \(spokenName(owner)).")
    }
}

// MARK: - Intents

struct AddItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Items"
    static var description = IntentDescription("Adds items to a ListRunner list. Separate items with commas or “and”.")

    @Parameter(title: "Items", requestValueDialog: "What would you like to add?")
    var items: String

    @Parameter(title: "List", requestValueDialog: "Which list should I add to?")
    var list: ShoppingListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$items) to \(\.$list)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        // Resolve every value first: requestValue is the last chance to stop
        // before the save, which is the only side effect.
        var destination = try await SiriLists.destination(named: list?.id, for: .add)
        if destination == .ask {
            let chosen: ShoppingListEntity? = try await $list.requestValue("Which list should I add to?")
            guard let chosen else { throw SiriListError.noLists }
            destination = try await SiriLists.destination(named: chosen.id, for: .add)
        }
        guard case .list(let owner) = destination else { throw SiriListError.noLists }
        let added = try await SiriLists.add(items, to: owner)
        let message = await SiriLists.addedMessage(added, to: owner)
        return .result(value: added, dialog: "\(message)")
    }
}

struct ReadListIntent: AppIntent {
    static let title: LocalizedStringResource = "Read List"
    static var description = IntentDescription("Reads the items still to get on a ListRunner list.")

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var list: ShoppingListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Read \(\.$list)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        var destination = try await SiriLists.destination(named: list?.id, for: .read)
        if destination == .ask {
            let chosen: ShoppingListEntity? = try await $list.requestValue("Which list?")
            guard let chosen else { throw SiriListError.noLists }
            destination = try await SiriLists.destination(named: chosen.id, for: .read)
        }
        guard case .list(let owner) = destination else { throw SiriListError.noLists }
        let names = try await SiriLists.pendingItems(in: owner)
        let message = await SiriLists.readAloud(names, in: owner)
        return .result(value: names, dialog: "\(message)")
    }
}

struct OpenListIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open List"
    static var description = IntentDescription("Opens a list in ListRunner.")

    @Parameter(title: "List", requestValueDialog: "Which list?")
    var target: ShoppingListEntity

    func perform() async throws -> some IntentResult {
        try await SiriLists.open(target.id)
        return .result()
    }
}

// MARK: - App Shortcuts

// Free-form item text cannot appear in a phrase, so Siri asks for the items
// after "Add items in ListRunner". List names can: they expand from the
// enabled lists, refreshed when those change.
struct ListRunnerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemsIntent(),
            phrases: [
                "Add items in \(.applicationName)",
                "Add to my \(.applicationName) list",
                "Add to \(\.$list) in \(.applicationName)",
                "Add to my \(\.$list) list in \(.applicationName)"
            ],
            shortTitle: "Add Items",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ReadListIntent(),
            phrases: [
                "What’s on my \(.applicationName) list",
                "What’s on my \(\.$list) list in \(.applicationName)",
                "Read my \(\.$list) list in \(.applicationName)"
            ],
            shortTitle: "Read List",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: OpenListIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Shop at \(\.$target) with \(.applicationName)"
            ],
            shortTitle: "Open List",
            systemImageName: "cart"
        )
    }
}
