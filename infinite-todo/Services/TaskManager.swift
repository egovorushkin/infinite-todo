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

    // MARK: - Creation

    /// Creates a task and appends it to the end of `parent`'s children
    /// (or the root list when `parent` is `nil`).
    @discardableResult
    func addTask(title: String, parent: TodoItem? = nil) -> TodoItem {
        let order = (siblings(of: parent).map(\.sortOrder).max() ?? -1) + 1
        let task = TodoItem(title: title, parent: parent, sortOrder: order)
        context.insert(task)
        if let parent {
            parent.children = (parent.children ?? []) + [task]
            parent.isExpanded = true
        }
        return task
    }

    // MARK: - Simple mutations

    func toggleCompletion(_ item: TodoItem) {
        item.isCompleted.toggle()
    }

    func delete(_ item: TodoItem) {
        let parent = item.parent
        context.delete(item) // cascade removes the subtree
        normalizeOrders(of: parent)
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

    /// Direct children of `parent`, or root tasks when `parent` is `nil`.
    private func siblings(of parent: TodoItem?) -> [TodoItem] {
        if let parent {
            return parent.sortedChildren
        }
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.parent == nil },
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
