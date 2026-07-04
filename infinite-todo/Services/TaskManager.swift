//
//  TaskManager.swift
//  todo
//
//  Centralizes every structural mutation of the task tree so that
//  ordering, re-parenting, and cycle-prevention logic lives in one place
//  rather than being scattered across views.
//

import Foundation
import SwiftData

struct TaskManager {
    let context: ModelContext
    /// The list currently being viewed. Needed only to scope root-level
    /// (`parent == nil`) queries and insertions to this list.
    let list: TaskList?

    init(context: ModelContext, list: TaskList? = nil) {
        self.context = context
        self.list = list
    }

    // MARK: - Creation

    /// Creates a task and appends it to the end of `parent`'s children
    /// (or the root list when `parent` is `nil`).
    @discardableResult
    func addTask(title: String, parent: TodoItem? = nil) -> TodoItem {
        let order = (siblings(of: parent).map(\.sortOrder).max() ?? -1) + 1
        let task = TodoItem(title: title, parent: parent, sortOrder: order)
        if parent == nil { task.list = list }
        context.insert(task)
        if let parent {
            parent.children = (parent.children ?? []) + [task]
            parent.isExpanded = true
        }
        return task
    }

    /// Creates an empty task positioned directly after `item` in the same
    /// sibling group. Used for "press Return to add the next task".
    @discardableResult
    func addSibling(after item: TodoItem) -> TodoItem {
        let parent = item.parent
        let task = TodoItem(title: "", parent: parent)
        if parent == nil { task.list = list }
        context.insert(task)

        var ordered = siblings(of: parent).filter { $0 !== task }
        if let idx = ordered.firstIndex(where: { $0 === item }) {
            ordered.insert(task, at: idx + 1)
        } else {
            ordered.append(task)
        }
        if let parent {
            parent.children = ordered
        }
        renumber(ordered)
        return task
    }

    // MARK: - Simple mutations

    /// Toggles `item`'s completion and applies the same state to its whole
    /// subtree, so finishing a parent finishes everything under it. Then
    /// syncs ancestors so completion also flows upward: checking the last
    /// open subtask completes its parent, and un-checking a subtask
    /// un-completes every ancestor.
    func toggleCompletion(_ item: TodoItem) {
        setCompletion(!item.isCompleted, for: item)
        syncAncestorCompletion(startingAt: item.parent)
    }

    /// Walks up from `parent`, marking each ancestor complete iff all of its
    /// children are complete. Auto-completion applies plain completion (no
    /// recurrence rollover) — rollover stays a direct-tap behavior.
    private func syncAncestorCompletion(startingAt parent: TodoItem?) {
        var node = parent
        while let current = node {
            let kids = current.children ?? []
            let allDone = !kids.isEmpty && kids.allSatisfy(\.isCompleted)
            if allDone != current.isCompleted {
                current.isCompleted = allDone
                if allDone {
                    NotificationManager.cancel(for: current)
                } else {
                    NotificationManager.schedule(for: current)
                }
            }
            node = current.parent
        }
    }

    private func setCompletion(_ completed: Bool, for item: TodoItem) {
        // Completing a recurring task means "done for this occurrence":
        // roll its due date forward and keep it active, like Reminders,
        // instead of checking it off forever and killing the repeat.
        if completed, item.recurrenceRule != .none, item.dueDate != nil {
            rollToNextOccurrence(item)
        } else {
            item.isCompleted = completed
            if completed {
                NotificationManager.cancel(for: item)
            } else {
                NotificationManager.schedule(for: item)
            }
        }
        for child in item.children ?? [] {
            setCompletion(completed, for: child)
        }
    }

    /// Advances a recurring task's due date to its first occurrence after
    /// now and reschedules its reminder.
    private func rollToNextOccurrence(_ item: TodoItem) {
        guard let dueDate = item.dueDate,
              let unit = item.recurrenceRule.calendarComponent else { return }
        let calendar = Calendar.current
        let now = Date()
        var next = dueDate
        while next <= now {
            guard let advanced = calendar.date(byAdding: unit, value: 1, to: next),
                  advanced > next else { break }
            next = advanced
        }
        item.dueDate = next
        item.isCompleted = false
        refreshNotification(for: item)
    }

    /// Sets or clears `item`'s due date and keeps its reminder notification
    /// in sync. Always go through this rather than setting `item.dueDate`
    /// directly. Clearing the date also clears any recurrence, since a
    /// repeat needs a due date to anchor its time of day.
    func setDueDate(_ date: Date?, for item: TodoItem) {
        item.dueDate = date
        if date == nil { item.recurrenceRule = .none }
        refreshNotification(for: item)
    }

    /// Sets how often `item`'s reminder repeats. No-ops usefully if there's
    /// no due date yet — it'll take effect once one is set.
    func setRecurrence(_ rule: RecurrenceRule, for item: TodoItem) {
        item.recurrenceRule = rule
        refreshNotification(for: item)
    }

    /// Cancels and re-adds `item`'s reminder so pending content (like the
    /// title in the notification body) matches the current model. Called
    /// after edits that don't otherwise touch scheduling.
    func refreshNotification(for item: TodoItem) {
        NotificationManager.cancel(for: item)
        NotificationManager.schedule(for: item)
    }

    func delete(_ item: TodoItem) {
        let parent = item.parent
        cancelNotifications(inSubtreeOf: item)
        // Without this, `parent.children` keeps a stale reference to `item`
        // until the next fetch, so a parent left childless by this delete
        // doesn't look discardable yet (see purgeDiscardableTasks).
        parent?.children?.removeAll { $0 === item }
        context.delete(item) // cascade removes the subtree
        normalizeOrders(of: parent)
    }

    /// Deletes every abandoned blank task (no title, subtasks, notes, or
    /// reminder) anywhere in the store. The inline-editing flows discard
    /// these on focus loss, but a few paths escape that — leaving the
    /// screen mid-edit, switching tabs, or the app being killed — so this
    /// runs as a sweep on screen transitions. Repeats because removing a
    /// blank child can make its (also blank) parent discardable.
    func purgeDiscardableTasks() {
        let descriptor = FetchDescriptor<TodoItem>()
        var repeatSweep = true
        while repeatSweep {
            repeatSweep = false
            guard let items = try? context.fetch(descriptor) else { return }
            for item in items where item.isDiscardable {
                delete(item)
                repeatSweep = true
            }
        }
    }

    private func cancelNotifications(inSubtreeOf item: TodoItem) {
        NotificationManager.cancel(for: item)
        for child in item.children ?? [] {
            cancelNotifications(inSubtreeOf: child)
        }
    }

    // MARK: - Drag & drop

    /// Makes `item` a child of `newParent` (dropped *onto* a row).
    /// No-ops when it would create a cycle or is already the parent.
    func reparent(_ item: TodoItem, under newParent: TodoItem) {
        guard item !== newParent else { return }
        guard !newParent.isDescendant(of: item) else { return }
        guard item.parent !== newParent else { return }

        let oldParent = item.parent
        detach(item)
        item.parent = newParent
        item.list = nil
        let order = (siblings(of: newParent).map(\.sortOrder).max() ?? -1) + 1
        item.sortOrder = order
        newParent.children = (newParent.children ?? []) + [item]
        newParent.isExpanded = true
        normalizeOrders(of: oldParent)
        normalizeOrders(of: newParent)
    }

    /// Reorders `item` so it sits at `targetIndex` among the children of
    /// `newParent` (dropped *between* rows). Also handles moving between
    /// levels when the sibling group differs from the item's current one.
    func move(_ item: TodoItem, toIndex targetIndex: Int, under newParent: TodoItem?) {
        guard item !== newParent else { return }
        if let newParent, newParent.isDescendant(of: item) { return }

        let oldParent = item.parent

        // Build the destination sibling list without `item`.
        var ordered = siblings(of: newParent).filter { $0 !== item }
        let clamped = max(0, min(targetIndex, ordered.count))

        detach(item)
        item.parent = newParent
        item.list = newParent == nil ? list : nil
        ordered.insert(item, at: clamped)

        if let newParent {
            newParent.children = ordered
            newParent.isExpanded = true
        }
        renumber(ordered)
        if oldParent !== newParent {
            normalizeOrders(of: oldParent)
        }
    }

    /// Moves `item` (with its whole subtree) into `target`, appended at the
    /// end of that list's root tasks. Used when a task is dropped onto a
    /// list card or tab chip.
    func moveToList(_ item: TodoItem, to target: TaskList) {
        // Already a root task of the target — nothing to do.
        guard !(item.parent == nil && item.list?.id == target.id) else { return }

        let oldParent = item.parent
        let oldList = oldParent == nil ? item.list : nil

        detach(item)
        item.parent = nil
        item.list = target
        let order = (rootTasks(of: target).filter { $0 !== item }.map(\.sortOrder).max() ?? -1) + 1
        item.sortOrder = order

        if let oldParent {
            renumber(oldParent.sortedChildren)
        }
        if let oldList, oldList.id != target.id {
            renumber(rootTasks(of: oldList).filter { $0 !== item })
        }
    }

    /// Root tasks of an arbitrary list (unlike `siblings(of:)`, which is
    /// scoped to this manager's own `list`).
    private func rootTasks(of list: TaskList) -> [TodoItem] {
        let listID = list.id
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.parent == nil && $0.list?.id == listID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Lookup

    /// Resolves the live model for a dragged identifier.
    func find(_ id: UUID) -> TodoItem? {
        var descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Helpers

    /// Direct children of `parent`, or `list`'s root tasks when `parent` is `nil`.
    private func siblings(of parent: TodoItem?) -> [TodoItem] {
        if let parent {
            return parent.sortedChildren
        }
        guard let list else { return [] }
        let listID = list.id
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.parent == nil && $0.list?.id == listID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Removes `item` from its current parent's children array.
    private func detach(_ item: TodoItem) {
        guard let parent = item.parent else { return }
        parent.children?.removeAll { $0 === item }
    }

    /// Rewrites `sortOrder` to a dense 0..<n sequence.
    private func renumber(_ items: [TodoItem]) {
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }

    private func normalizeOrders(of parent: TodoItem?) {
        renumber(siblings(of: parent))
    }
}
