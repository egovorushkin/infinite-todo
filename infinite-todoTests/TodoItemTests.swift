//
//  TodoItemTests.swift
//  infinite-todoTests
//

import Foundation
import Testing
@testable import infinite_todo

@MainActor
struct TodoItemTests {
    @Test func totalDescendantCountCountsAllLevels() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let child = manager.addTask(title: "Child", parent: root)
        _ = manager.addTask(title: "Child 2", parent: root)
        _ = manager.addTask(title: "Grandchild", parent: child)

        #expect(root.totalDescendantCount == 3)
        #expect(child.totalDescendantCount == 1)
    }

    @Test func completedDescendantCountCountsOnlyCompleted() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let childA = manager.addTask(title: "A", parent: root)
        _ = manager.addTask(title: "B", parent: root)
        childA.isCompleted = true

        #expect(root.completedDescendantCount == 1)
        #expect(root.totalDescendantCount == 2)
    }

    @Test func subtreeCompletionFractionIsZeroWithNoDescendants() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let leaf = manager.addTask(title: "Leaf")

        #expect(leaf.subtreeCompletionFraction == 0)
    }

    @Test func subtreeCompletionFractionReflectsPartialProgress() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let childA = manager.addTask(title: "A", parent: root)
        _ = manager.addTask(title: "B", parent: root)
        childA.isCompleted = true

        #expect(root.subtreeCompletionFraction == 0.5)
    }

    @Test func isDiscardableTrueForBlankLeaf() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let item = manager.addTask(title: "")

        #expect(item.isDiscardable)
    }

    @Test func isDiscardableFalseWhenItHasNotesDueDateOrChildren() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)

        let withNotes = manager.addTask(title: "")
        withNotes.notes = "Remember this"
        #expect(!withNotes.isDiscardable)

        let withDueDate = manager.addTask(title: "")
        withDueDate.dueDate = Date()
        #expect(!withDueDate.isDiscardable)

        let withChild = manager.addTask(title: "")
        _ = manager.addTask(title: "Child", parent: withChild)
        #expect(!withChild.isDiscardable)
    }

    @Test func isDescendantDetectsAncestorAtAnyDepth() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let root = manager.addTask(title: "Root")
        let child = manager.addTask(title: "Child", parent: root)
        let grandchild = manager.addTask(title: "Grandchild", parent: child)

        #expect(grandchild.isDescendant(of: root))
        #expect(grandchild.isDescendant(of: child))
        #expect(!root.isDescendant(of: grandchild))
    }

    @Test func isDescendantFalseForUnrelatedItems() throws {
        let context = try makeTestContext()
        let manager = TaskManager(context: context)
        let a = manager.addTask(title: "A")
        let b = manager.addTask(title: "B")

        #expect(!a.isDescendant(of: b))
    }
}
