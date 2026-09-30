import AppKit
import EventKit
import SwiftUI

/// 流水线和分段清单都存在「提醒事项」里（iCloud），手机上用自带的提醒事项 app 就能看到和勾选。
/// 配置里用到的列表不存在时会自动建好。
///
/// Pipelines and sections live in Apple Reminders (iCloud), so the stock Reminders app on
/// iPhone sees and checks the same items. Lists the config needs are created automatically.
@MainActor
final class RemindersStore: TodoBackend {
    private let store = EKEventStore()
    private var calendarIDs: [String: String] = [:]
    private var observer: NSObjectProtocol?

    var authorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func start(onChange: @escaping () -> Void) async -> SourceState {
        do {
            guard try await store.requestFullAccessToReminders() else { return .denied }
        } catch {
            return .failed(error.localizedDescription)
        }
        store.refreshSourcesIfNecessary()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { _ in
                MainActor.assumeIsolated { onChange() }
            }
        }
        return .ready
    }

    func ensureLists(_ lists: [(name: String, color: Color)]) {
        for list in lists { _ = calendar(named: list.name, color: list.color) }
    }

    func items(list: String, doneSince: Date) async -> [TodoItem] {
        guard let cal = calendar(named: list) else { return [] }
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [cal])
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: doneSince, ending: nil, calendars: [cal])
        let a = await fetch(open, list: list)
        let b = await fetch(done, list: list)
        return a + b
    }

    func add(_ title: String, list: String) async -> TodoItem? {
        guard let cal = calendar(named: list) else { return nil }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        do { try store.save(r, commit: true) } catch {
            NSLog("NotchPad: save reminder failed \(error)")
            return nil
        }
        return TodoItem(id: r.calendarItemIdentifier, title: title, done: false,
                        created: r.creationDate ?? Date(), completed: nil, list: list)
    }

    func setDone(id: String, _ done: Bool) async {
        guard let r = reminder(id) else { return }
        r.isCompleted = done
        try? store.save(r, commit: true)
    }

    func delete(id: String) async {
        guard let r = reminder(id) else { return }
        try? store.remove(r, commit: true)
    }

    func move(id: String, toList list: String) async {
        guard let r = reminder(id), let cal = calendar(named: list) else { return }
        r.calendar = cal
        try? store.save(r, commit: true)
    }

    // MARK: -

    private func reminder(_ id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    private func fetch(_ predicate: NSPredicate, list: String) async -> [TodoItem] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { r in
                    TodoItem(id: r.calendarItemIdentifier, title: r.title ?? "",
                             done: r.isCompleted, created: r.creationDate ?? .distantPast,
                             completed: r.completionDate, list: list)
                }
                cont.resume(returning: items)
            }
        }
    }

    /// 按名字找列表；没有就在默认账户（通常是 iCloud）里新建一个
    /// Find a list by name; if missing, create it in the default account (usually iCloud)
    private func calendar(named name: String, color: Color? = nil) -> EKCalendar? {
        if let id = calendarIDs[name], let c = store.calendar(withIdentifier: id) { return c }
        if let c = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            calendarIDs[name] = c.calendarIdentifier
            return c
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first(where: { $0.sourceType == .local })
        else { return nil }

        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = name
        c.source = source
        if let color { c.cgColor = NSColor(color).cgColor }
        do { try store.saveCalendar(c, commit: true) } catch {
            NSLog("NotchPad: create list “\(name)” failed \(error)")
            return nil
        }
        calendarIDs[name] = c.calendarIdentifier
        return c
    }
}
