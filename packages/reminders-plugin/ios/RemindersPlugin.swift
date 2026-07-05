import Foundation
import Capacitor
import EventKit

@objc(RemindersPlugin)
public class RemindersPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RemindersPlugin"
    public let jsName = "Reminders"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getPaprikaItems", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "completeReminder", returnType: CAPPluginReturnPromise)
    ]

    private let eventStore = EKEventStore()

    @objc func getPaprikaItems(_ call: CAPPluginCall) {
        requestAccess { [weak self] granted in
            guard let self else {
                call.reject("Plugin deallocated")
                return
            }
            guard granted else {
                call.reject("Reminders permission denied")
                return
            }
            self.fetchPaprikaItems(call)
        }
    }

    @objc func completeReminder(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("Invalid id")
            return
        }

        requestAccess { [weak self] granted in
            guard let self else {
                call.reject("Plugin deallocated")
                return
            }
            guard granted else {
                call.reject("Reminders permission denied")
                return
            }
            self.completeReminderById(id, call)
        }
    }

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        eventStore.requestAccess(to: .reminder) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func fetchPaprikaItems(_ call: CAPPluginCall) {
        let calendars = eventStore.calendars(for: .reminder)
        guard let paprikaCalendar = calendars.first(where: { $0.title == "Paprika" }) else {
            call.reject("No Paprika list found")
            return
        }

        let predicate = eventStore.predicateForReminders(in: [paprikaCalendar])
        eventStore.fetchReminders(matching: predicate) { reminders in
            guard let reminders else {
                call.reject("Failed to fetch reminders")
                return
            }

            let incomplete = reminders.filter { !$0.isCompleted }

            let items: [[String: Any]] = incomplete.map { r in
                [
                    "id": r.calendarItemIdentifier,
                    "title": r.title ?? "",
                ]
            }

            call.resolve(["items": items])
        }
    }

    private func completeReminderById(_ id: String, _ call: CAPPluginCall) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            call.reject("Reminder not found")
            return
        }

        reminder.isCompleted = true
        do {
            try eventStore.save(reminder, commit: true)
            call.resolve()
        } catch {
            call.reject("Failed to complete reminder: \(error.localizedDescription)")
        }
    }
}
