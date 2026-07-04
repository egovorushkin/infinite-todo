//
//  NotificationManager.swift
//  todo
//
//  Schedules/cancels the local "task due soon" reminder. One pending
//  notification per task, keyed by the task's own UUID so it's trivial to
//  cancel without tracking identifiers anywhere else.
//

import Foundation
import SwiftData
import UserNotifications

enum NotificationManager {
    /// How long before the due date the reminder fires.
    static let leadTime: TimeInterval = 60 * 60 // 1 hour

    /// iOS silently keeps only the 64 soonest pending local notifications;
    /// we stay under that so *we* choose what gets dropped (the furthest-out
    /// reminders), not the system.
    private static let pendingLimit = 60

    /// Requests permission if it's never been asked before. If the user
    /// grants it, `onGranted` runs so already-dated tasks (e.g. restored
    /// from iCloud before permission existed) get their reminders scheduled
    /// right away rather than waiting for the next launch's `refreshAll`.
    static func requestAuthorizationIfNeeded(onGranted: @escaping () -> Void = {}) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async(execute: onGranted)
            }
        }
    }

    /// Rebuilds all pending reminders from the store. Run at launch so
    /// notification content tracks model edits made since the last schedule
    /// (e.g. renamed tasks), and so the nearest reminders win when there are
    /// more dated tasks than iOS's pending-notification cap allows.
    static func refreshAll(context: ModelContext) {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.dueDate != nil && !$0.isCompleted }
        )
        guard let items = try? context.fetch(descriptor) else { return }

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Recurring reminders first (they fire indefinitely), then one-offs
        // soonest-first, capped below the system limit.
        let prioritized = items.sorted { a, b in
            let aRepeats = a.recurrenceRule != .none
            let bRepeats = b.recurrenceRule != .none
            if aRepeats != bRepeats { return aRepeats }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
        for item in prioritized.prefix(pendingLimit) {
            schedule(for: item)
        }
    }

    /// Schedules `item`'s reminder. No-ops if it has no due date, is already
    /// completed, or (for a one-off task) the reminder time has already
    /// passed. Recurring tasks reuse `dueDate` only as the anchor for time
    /// of day / weekday / day-of-month / month — the trigger itself repeats
    /// indefinitely until cancelled.
    static func schedule(for item: TodoItem) {
        guard let dueDate = item.dueDate, !item.isCompleted else { return }
        let repeats = item.recurrenceRule != .none
        var fireDate = dueDate.addingTimeInterval(-leadTime)
        var title = String(localized: "Task due soon")

        // When the deadline is less than the lead time away, the "1 hour
        // before" moment has already passed — fall back to firing at the
        // due time itself rather than silently scheduling nothing.
        if !repeats && fireDate <= Date() {
            guard dueDate > Date() else { return }
            fireDate = dueDate
            title = String(localized: "Task due")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = item.title.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "A task is due soon")
            : item.title
        content.sound = .default

        // Which components the trigger matches on determines how often it
        // fires: e.g. matching only `.minute` recurs every hour, matching
        // `.hour` + `.minute` recurs every day at that time.
        let relevantComponents: Set<Calendar.Component>
        switch item.recurrenceRule {
        case .none: relevantComponents = [.year, .month, .day, .hour, .minute, .second]
        case .hourly: relevantComponents = [.minute]
        case .daily: relevantComponents = [.hour, .minute]
        case .weekly: relevantComponents = [.weekday, .hour, .minute]
        case .monthly: relevantComponents = [.day, .hour, .minute]
        case .yearly: relevantComponents = [.month, .day, .hour, .minute]
        }

        let components = Calendar.current.dateComponents(relevantComponents, from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(for item: TodoItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }
}
