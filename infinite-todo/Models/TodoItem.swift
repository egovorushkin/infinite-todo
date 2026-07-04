//
//  TodoItem.swift
//  todo
//
//  A recursively-nestable todo item. The self-referencing
//  `parent`/`children` relationship is what enables infinite depth.
//

import Foundation
import SwiftData

/// How often a task's reminder repeats. Anchored to `dueDate`'s time of
/// day (and weekday/day-of-month/month, as relevant).
enum RecurrenceRule: String, CaseIterable, Codable, Identifiable {
    case none, hourly, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Never"
        case .hourly: "Hourly"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    /// The calendar unit one occurrence spans, used to roll a completed
    /// recurring task's due date forward to its next occurrence.
    var calendarComponent: Calendar.Component? {
        switch self {
        case .none: nil
        case .hourly: .hour
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

@Model
final class TodoItem {
    /// Stable identifier used as the drag-and-drop payload.
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isCompleted: Bool = false
    /// Whether this item's subtree is expanded in the UI.
    var isExpanded: Bool = true
    /// Position among siblings that share the same parent.
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    /// The containing task, or `nil` for a root-level task.
    var parent: TodoItem?

    /// The list this task belongs to. Only set for root-level tasks
    /// (`parent == nil`); nested subtasks reach their list via `parent`.
    var list: TaskList?

    /// When this task is due. Setting it schedules a reminder notification;
    /// clearing it (or completing/deleting the task) cancels one. See
    /// `TaskManager.setDueDate` — always go through it rather than setting
    /// this directly, so the notification stays in sync.
    var dueDate: Date?

    /// Raw `RecurrenceRule`; stored as a string for the same reason
    /// `TaskList.colorName` is — SwiftData persists this more simply than
    /// an enum with associated behavior. Go through `TaskManager.setRecurrence`.
    var recurrenceRuleRaw: String = RecurrenceRule.none.rawValue

    var recurrenceRule: RecurrenceRule {
        get { RecurrenceRule(rawValue: recurrenceRuleRaw) ?? .none }
        set { recurrenceRuleRaw = newValue.rawValue }
    }

    /// Sub-tasks. Deleting a task cascades to its whole subtree.
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.parent)
    var children: [TodoItem]?

    init(
        title: String = "",
        parent: TodoItem? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.parent = parent
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.children = []
    }

    // MARK: - Derived values

    /// Children ordered for display.
    var sortedChildren: [TodoItem] {
        (children ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var hasChildren: Bool {
        !(children ?? []).isEmpty
    }

    /// Every task anywhere beneath this one, at any depth (not including
    /// itself). Backs the "3/7 done" progress shown on parent rows.
    var totalDescendantCount: Int {
        let kids = children ?? []
        return kids.count + kids.reduce(0) { $0 + $1.totalDescendantCount }
    }

    /// Completed tasks anywhere beneath this one, at any depth.
    var completedDescendantCount: Int {
        let kids = children ?? []
        return kids.filter(\.isCompleted).count + kids.reduce(0) { $0 + $1.completedDescendantCount }
    }

    /// Fraction of the subtree that's complete, in `0...1`. `0` when there
    /// are no descendants, so an empty parent doesn't render a full ring.
    var subtreeCompletionFraction: Double {
        let total = totalDescendantCount
        guard total > 0 else { return 0 }
        return Double(completedDescendantCount) / Double(total)
    }

    /// True when auto-discarding this task loses nothing the user typed:
    /// blank title, no subtasks, no notes, no reminder. The inline-editing
    /// flows delete abandoned rows only when this holds.
    var isDiscardable: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
            && !hasChildren
            && notes.isEmpty
            && dueDate == nil
    }

    /// True if `self` is `ancestor`, or appears anywhere beneath it.
    /// Used to prevent creating a cycle when re-parenting.
    func isDescendant(of ancestor: TodoItem) -> Bool {
        var node: TodoItem? = self
        while let current = node {
            if current === ancestor { return true }
            node = current.parent
        }
        return false
    }
}
