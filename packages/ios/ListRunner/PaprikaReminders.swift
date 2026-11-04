import Combine
import EventKit
import Foundation

struct PaprikaReminderSnapshot: Equatable {
    let id: String
    let title: String
    let creationDate: Date?
}

struct StagedPaprikaItem {
    let reminderID: String?
    let grocery: ParsedGrocery
}

enum PaprikaImportError: Error, Equatable {
    case access
    case permissionDenied
    case listNotFound
    case multipleLists
    case noNewItems
    case noUncheckedItems
    case noReadableItems
    case transaction

    var message: LocalizedStringResource {
        switch self {
        case .access:
            "Could not access Apple Reminders. Try again. Your list is unchanged. You can still type or paste groceries."
        case .permissionDenied:
            "Allow full Reminders access in Settings so ListRunner can read and manage your imported reminders. Your list is unchanged."
        case .listNotFound:
            "We couldn’t find a Reminders list called ‘Paprika’. Export your groceries from Paprika first, using that exact list name. Your list is unchanged."
        case .multipleLists:
            "More than one Apple Reminders list is named ‘Paprika’. Rename the others so only your grocery export list has that name, then try again. Your list is unchanged."
        case .noNewItems:
            "These items are already in your list. Export new groceries from Paprika to Apple Reminders, then import again. Existing items aren’t refreshed."
        case .noUncheckedItems:
            "No unchecked groceries found in the ‘Paprika’ Reminders list. Export your groceries from Paprika first. Checked items aren’t imported."
        case .noReadableItems:
            "No readable new groceries found. Check that your exported Apple reminders have grocery names, then try again. Your list is unchanged."
        case .transaction:
            "Could not save the imported groceries. Your list is unchanged. Try importing again."
        }
    }
}

enum PaprikaImportPlanner {
    static func removalCandidates(reminders: [PaprikaReminderSnapshot], savedIDs: Set<String>, parser: IngredientParser = .application) -> [PaprikaReminderSnapshot] {
        var seen = Set<String>()
        return reminders.filter {
            savedIDs.contains($0.id) && !$0.id.isEmpty && seen.insert($0.id).inserted
                && !parser.parseGroceries($0.title).isEmpty
        }
    }

    /// Used only when staging produced no rows. Do not call a blank title
    /// "already imported" just because it was ignored by the parser.
    static func emptyImportError(reminders: [PaprikaReminderSnapshot], existingIDs: Set<String>, parser: IngredientParser = .application) -> PaprikaImportError {
        if reminders.isEmpty { return .noUncheckedItems }
        let readable = reminders.filter { !$0.id.isEmpty && !parser.parseGroceries($0.title).isEmpty }
        if !readable.isEmpty && readable.allSatisfy({ existingIDs.contains($0.id) }) { return .noNewItems }
        return .noReadableItems
    }

    static func stage(reminders: [PaprikaReminderSnapshot], existingIDs: Set<String>, parser: IngredientParser = .application) -> [StagedPaprikaItem] {
        let ordered = reminders.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.id < rhs.id
            }
        }

        var seen = existingIDs
        var staged: [StagedPaprikaItem] = []
        for reminder in ordered {
            guard !reminder.id.isEmpty, seen.insert(reminder.id).inserted else { continue }
            let parsed = parser.parseGroceries(reminder.title)
            guard !parsed.isEmpty else { continue }
            // Paprika normally exports one grocery per reminder. If a title uses
            // ListRunner's comma syntax, preserve every parsed grocery while
            // linking the source reminder only once to avoid competing writebacks.
            for (index, grocery) in parsed.enumerated() {
                staged.append(StagedPaprikaItem(reminderID: index == 0 ? reminder.id : nil, grocery: grocery))
            }
        }
        return staged
    }
}

struct ReminderWriteback: Equatable {
    let reminderID: String
    let title: String
    let isCompleted: Bool
}

/// Serializes writes per Reminder and coalesces mutations that have not started.
/// The executor is deliberately injectable so queue ordering can be tested without
/// touching a user's Reminders database.
@MainActor
final class ReminderWritebackQueue {
    typealias Executor = @MainActor (ReminderWriteback) async -> Void
    private let execute: Executor
    private var queued: [String: ReminderWriteback] = [:]
    private var running: Set<String> = []

    init(execute: @escaping Executor) { self.execute = execute }

    func enqueue(_ write: ReminderWriteback) {
        queued[write.reminderID] = write
        guard running.insert(write.reminderID).inserted else { return }
        Task { @MainActor [weak self] in await self?.drain(write.reminderID) }
    }

    func cancelQueued(reminderID: String) { queued.removeValue(forKey: reminderID) }

    private func drain(_ reminderID: String) async {
        while let next = queued.removeValue(forKey: reminderID) {
            await execute(next)
        }
        running.remove(reminderID)
        // Close the enqueue-at-drain-boundary race without ever running two
        // writes for this reminder concurrently.
        if queued[reminderID] != nil, running.insert(reminderID).inserted {
            await drain(reminderID)
        }
    }
}

@MainActor
final class PaprikaReminders: ObservableObject {
    @Published private(set) var importing = false
    private let eventStore: EKEventStore
    private let writeQueue: ReminderWritebackQueue

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.writeQueue = ReminderWritebackQueue { [weak eventStore] write in
            guard let eventStore,
                  let reminder = eventStore.calendarItem(withIdentifier: write.reminderID) as? EKReminder else { return }
            reminder.title = write.title
            reminder.isCompleted = write.isCompleted
            reminder.completionDate = write.isCompleted ? Date() : nil
            do { try eventStore.save(reminder, commit: true) }
            catch {
                // Best effort by design. A later local mutation may issue a new write.
            }
        }
    }

    func fetchPaprikaSnapshot() async throws -> [PaprikaReminderSnapshot] {
        guard !importing else { throw PaprikaImportError.access }
        importing = true

        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] {
            switch fixture {
            case "missing": throw PaprikaImportError.listNotFound
            case "multiple": throw PaprikaImportError.multipleLists
            case "accessDenied": throw PaprikaImportError.permissionDenied
            case "accessError": throw PaprikaImportError.access
            case "empty": return []
            case "blank": return [PaprikaReminderSnapshot(id: "blank", title: " • ", creationDate: nil)]
            default: break
            }
            var reminders = [
                PaprikaReminderSnapshot(id: "test-milk-reminder", title: "2L milk", creationDate: Date(timeIntervalSince1970: 1)),
                PaprikaReminderSnapshot(id: "test-bread-reminder", title: "bread", creationDate: Date(timeIntervalSince1970: 2)),
                PaprikaReminderSnapshot(id: "test-blank-reminder", title: " •  ", creationDate: Date(timeIntervalSince1970: 3))
            ]
            if fixture == "additional" {
                reminders.append(PaprikaReminderSnapshot(id: "test-apples-reminder", title: "apples", creationDate: Date(timeIntervalSince1970: 4)))
            }
            return reminders
        }
        #endif

        try await requestAccessIfNeeded()
        let matches = eventStore.calendars(for: .reminder).filter { $0.title == "Paprika" }
        guard !matches.isEmpty else { throw PaprikaImportError.listNotFound }
        guard matches.count == 1, let calendar = matches.first else { throw PaprikaImportError.multipleLists }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let fetched: [EKReminder]? = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }
        guard let reminders = fetched else { throw PaprikaImportError.access }
        return reminders.compactMap { reminder in
            guard !reminder.isCompleted,
                  !reminder.calendarItemIdentifier.isEmpty,
                  let title = reminder.title else { return nil }
            return PaprikaReminderSnapshot(id: reminder.calendarItemIdentifier, title: title, creationDate: reminder.creationDate)
        }
    }

    func desiredWriteback(for item: GroceryItem) -> ReminderWriteback? {
        guard let reminderID = item.paprikaReminderID else { return nil }
        var parts: [String] = []
        if let amount = item.quantityAmount { parts.append(String(amount)) }
        if let unit = item.quantityUnit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty { parts.append(unit) }
        parts.append(item.name)
        return ReminderWriteback(reminderID: reminderID, title: parts.joined(separator: " "), isCompleted: item.status == .added)
    }

    /// Called only after the corresponding local groceries are durably saved.
    /// Revalidate source identity/content before each destructive operation.
    /// Return failures without rolling back already saved groceries.
    func removeImportedReminders(_ snapshot: [PaprikaReminderSnapshot]) -> Int {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LISTRUNNER_PAPRIKA_TEST_FIXTURE"] != nil {
            return 0 // Fixtures must never remove real reminders.
        }
        #endif
        let calendars = eventStore.calendars(for: .reminder).filter { $0.title == "Paprika" }
        guard calendars.count == 1, let calendar = calendars.first else { return snapshot.count }
        var failed = 0
        for source in snapshot {
            guard let reminder = eventStore.calendarItem(withIdentifier: source.id) as? EKReminder else { continue }
            guard reminder.calendar.calendarIdentifier == calendar.calendarIdentifier,
                  !reminder.isCompleted, reminder.title == source.title else {
                failed += 1
                continue
            }
            writeQueue.cancelQueued(reminderID: source.id)
            do { try eventStore.remove(reminder, commit: true) }
            catch { failed += 1 }
        }
        return failed
    }

    func queueWriteback(_ write: ReminderWriteback) {
        writeQueue.enqueue(write)
    }

    func cancelQueuedWriteback(for item: GroceryItem) {
        guard let reminderID = item.paprikaReminderID else { return }
        writeQueue.cancelQueued(reminderID: reminderID)
    }

    func finishImport() { importing = false }

    private func requestAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await eventStore.requestFullAccessToReminders()
            } catch {
                throw PaprikaImportError.access
            }
            guard granted else { throw PaprikaImportError.permissionDenied }
        case .writeOnly, .denied:
            throw PaprikaImportError.permissionDenied
        case .restricted:
            throw PaprikaImportError.access
        @unknown default:
            throw PaprikaImportError.access
        }
    }
}
