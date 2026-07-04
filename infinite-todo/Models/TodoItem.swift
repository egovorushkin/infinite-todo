//
//  TodoItem.swift
//  todo
//
//  A recursively-nestable todo item. The self-referencing
//  `parent`/`children` relationship is what enables infinite depth.
//

import Foundation
import SwiftData

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

    /// Fraction of direct children that are complete, in `0...1`.
    /// Returns `0` when there are no children.
    var completedChildFraction: Double {
        let kids = children ?? []
        guard !kids.isEmpty else { return 0 }
        let done = kids.filter(\.isCompleted).count
        return Double(done) / Double(kids.count)
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
