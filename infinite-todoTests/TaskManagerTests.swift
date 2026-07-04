//
//  TaskManagerTests.swift
//  infinite-todoTests
//

import Testing
import SwiftData
@testable import infinite_todo

@MainActor
struct TaskManagerTests {
    @Test func addTaskAppendsWithIncrementingSortOrder() throws {
        let context = try makeTestContext()
        let list = ListManager(context: context).addList(name: "List")
        let manager = TaskManager(context: context, list: list)
        let first = manager.addTask(title: "First")
        let second = manager.addTask(title: "Second")

        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
    }

    @Test func addSiblingInsertsDirectlyAfterItemAndRenumbers() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let a = manager.addTask(title: "A")
        let b = manager.addTask(title: "B")
        let inserted = manager.addSibling(after: a)

        let ordered = [a, inserted, b].sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.id) == [a.id, inserted.id, b.id])
    }

    @Test func toggleCompletionCascadesToWholeSubtree() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let child = manager.addTask(title: "Child", parent: root)
        let grandchild = manager.addTask(title: "Grandchild", parent: child)

        manager.toggleCompletion(root)

        #expect(root.isCompleted)
        #expect(child.isCompleted)
        #expect(grandchild.isCompleted)
    }

    @Test func toggleCompletionCompletesParentWhenLastChildFinishes() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let childA = manager.addTask(title: "A", parent: root)
        let childB = manager.addTask(title: "B", parent: root)

        manager.toggleCompletion(childA)
        #expect(!root.isCompleted)

        manager.toggleCompletion(childB)
        #expect(root.isCompleted)
    }

    @Test func toggleCompletionUncompletesAncestorsWhenChildIsUnchecked() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let child = manager.addTask(title: "Child", parent: root)

        manager.toggleCompletion(child) // completes child, then root
        #expect(root.isCompleted)

        manager.toggleCompletion(child) // un-completes child
        #expect(!root.isCompleted)
    }

    @Test func reparentIsNoOpWhenTargetIsOwnDescendant() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let child = manager.addTask(title: "Child", parent: root)

        manager.reparent(root, under: child) // would create a cycle

        #expect(root.parent == nil)
        #expect(child.parent?.id == root.id)
    }

    @Test func reparentMovesTaskAndRenumbersBothSiblingGroups() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let listA = manager.addTask(title: "List A root")
        let listB = manager.addTask(title: "List B root")
        let moving = manager.addTask(title: "Moving", parent: listA)
        _ = manager.addTask(title: "Stays in A", parent: listA)

        manager.reparent(moving, under: listB)

        #expect(moving.parent?.id == listB.id)
        #expect(listA.sortedChildren.map(\.sortOrder) == [0])
        #expect(listB.sortedChildren.map(\.sortOrder) == [0])
    }

    @Test func moveReordersSiblingsToTargetIndex() throws {
        let context = try makeTestContext()
        let list = ListManager(context: context).addList(name: "List")
        let manager = TaskManager(context: context, list: list)
        let a = manager.addTask(title: "A")
        let b = manager.addTask(title: "B")
        let c = manager.addTask(title: "C")

        manager.move(c, toIndex: 0, under: nil)

        let ordered = [a, b, c].sorted { $0.sortOrder < $1.sortOrder }
        #expect(ordered.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func moveToListMovesRootTaskBetweenListsAndRenumbers() throws {
        let context = try makeTestContext()
        let listManager = ListManager(context: context)
        let listA = listManager.addList(name: "A")
        let listB = listManager.addList(name: "B")

        let managerA = TaskManager(context: context, list: listA)
        let task = managerA.addTask(title: "Task")
        _ = managerA.addTask(title: "Stays in A")

        managerA.moveToList(task, to: listB)

        #expect(task.list?.id == listB.id)
        #expect(task.parent == nil)
        #expect(listA.items?.filter { $0.id != task.id }.map(\.sortOrder) == [0])
    }

    @Test func deleteCascadesAndRenormalizesSiblingOrder() throws {
        let context = try makeTestContext()
        let list = ListManager(context: context).addList(name: "List")
        let manager = TaskManager(context: context, list: list)
        let a = manager.addTask(title: "A")
        let b = manager.addTask(title: "B")
        let c = manager.addTask(title: "C")

        manager.delete(b)

        let remaining = [a, c].sorted { $0.sortOrder < $1.sortOrder }
        #expect(remaining.map(\.sortOrder) == [0, 1])
    }

    @Test func purgeDiscardableTasksRemovesBlankLeavesRepeatedly() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let parent = manager.addTask(title: "") // blank, becomes discardable once its child is gone
        _ = manager.addTask(title: "", parent: parent) // blank leaf

        manager.purgeDiscardableTasks()

        let descriptor = FetchDescriptor<TodoItem>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty)
    }
}
