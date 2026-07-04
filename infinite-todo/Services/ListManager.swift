//
//  ListManager.swift
//  todo
//
//  Centralizes mutations of the list of lists, mirroring TaskManager's role
//  for tasks within a list.
//

import Foundation
import SwiftData

struct ListManager {
    let context: ModelContext

    @discardableResult
    func addList(name: String) -> TaskList {
        let order = (allLists().map(\.sortOrder).max() ?? -1) + 1
        // Cycle through the palette by position so consecutive lists don't
        // default to the same color.
        let palette = TaskListColor.allCases
        let colorName = palette[order % palette.count].rawValue
        let list = TaskList(name: name, sortOrder: order, colorName: colorName)
        context.insert(list)
        return list
    }

    func rename(_ list: TaskList, to name: String) {
        list.name = name
    }

    func setColor(_ list: TaskList, to color: TaskListColor) {
        list.colorName = color.rawValue
    }

    func setIcon(_ list: TaskList, to icon: TaskListIcon) {
        list.iconName = icon.rawValue
    }

    /// Repositions `list` at `targetIndex` among all lists and rewrites
    /// `sortOrder` densely, mirroring TaskManager.move for tasks.
    func move(_ list: TaskList, toIndex targetIndex: Int) {
        var ordered = allLists().filter { $0 !== list }
        let clamped = max(0, min(targetIndex, ordered.count))
        ordered.insert(list, at: clamped)
        for (index, item) in ordered.enumerated() {
            item.sortOrder = index
        }
    }

    /// Resolves the live model for a dragged list identifier.
    func find(_ id: UUID) -> TaskList? {
        var descriptor = FetchDescriptor<TaskList>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func delete(_ list: TaskList) {
        // Cancel reminders for every task in the list before the cascade
        // delete, or users keep getting notifications for tasks that no
        // longer exist.
        for root in list.items ?? [] {
            cancelNotifications(inSubtreeOf: root)
        }
        context.delete(list) // cascades to the list's tasks and their subtrees
    }

    private func cancelNotifications(inSubtreeOf item: TodoItem) {
        NotificationManager.cancel(for: item)
        for child in item.children ?? [] {
            cancelNotifications(inSubtreeOf: child)
        }
    }

    /// Assigns any root-level task with no list (left over from before lists
    /// existed) to a default "Tasks" list, so nothing is lost. Reuses an
    /// existing list with that name rather than piling up duplicates, since
    /// this runs on every launch.
    func migrateOrphanTasks() {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.parent == nil && $0.list == nil }
        )
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        let defaultName = String(localized: "Tasks")
        let defaultList = allLists().first { $0.name == defaultName } ?? addList(name: defaultName)
        for task in orphans {
            task.list = defaultList
        }
    }

    private func allLists() -> [TaskList] {
        let descriptor = FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
