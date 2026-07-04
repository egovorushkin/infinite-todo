//
//  ListManagerTests.swift
//  infinite-todoTests
//

import Testing
import SwiftData
@testable import infinite_todo

@MainActor
struct ListManagerTests {
    @Test func addListCyclesColorPaletteByPosition() throws {
        let context = try makeTestContext()
        let manager = ListManager(context: context)
        let palette = TaskListColor.allCases

        let lists = (0..<(palette.count + 2)).map { manager.addList(name: "List \($0)") }

        for (index, list) in lists.enumerated() {
            #expect(list.colorName == palette[index % palette.count].rawValue)
        }
    }

    @Test func moveReordersListsToTargetIndex() throws {
        let context = try makeTestContext()
        let manager = ListManager(context: context)
        let a = manager.addList(name: "A")
        let b = manager.addList(name: "B")
        let c = manager.addList(name: "C")

        manager.move(c, toIndex: 0)

        let ordered = [a, b, c].sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func deleteCascadesToTasksInList() throws {
        let context = try makeTestContext()
        let listManager = ListManager(context: context)
        let list = listManager.addList(name: "A")
        let taskManager = TaskManager(context: context, list: list)
        let task = taskManager.addTask(title: "Task")

        listManager.delete(list)

        let descriptor = FetchDescriptor<TodoItem>()
        let remainingTasks = try context.fetch(descriptor)
        #expect(remainingTasks.isEmpty)
        #expect(taskManager.find(task.id) == nil)
    }

    @Test func migrateOrphanTasksAssignsToDefaultListReusingExisting() throws {
        let context = try makeTestContext()
        let listManager = ListManager(context: context)

        // A root-level task with no list, as if created before lists existed.
        let orphan = TodoItem(title: "Orphan", sortOrder: 0)
        context.insert(orphan)

        listManager.migrateOrphanTasks()
        #expect(orphan.list?.name == "Tasks")

        let listCountAfterFirstMigration = try context.fetch(FetchDescriptor<TaskList>()).count

        // Running it again with no new orphans must not create a second "Tasks" list.
        listManager.migrateOrphanTasks()
        let listCountAfterSecondMigration = try context.fetch(FetchDescriptor<TaskList>()).count

        #expect(listCountAfterFirstMigration == 1)
        #expect(listCountAfterSecondMigration == 1)
    }
}
