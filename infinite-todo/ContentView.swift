//
//  ContentView.swift
//  todo
//
//  Root screen: shows the top-level tasks and lets the tree grow infinitely
//  beneath them via the recursive TaskRowView. Tasks are created inline —
//  either from the bottom composer or by pressing Return on a row.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    /// Root-level tasks (those without a parent), ordered for display.
    @Query(
        filter: #Predicate<TodoItem> { $0.parent == nil },
        sort: \TodoItem.sortOrder
    )
    private var rootItems: [TodoItem]

    /// Focus is keyed by task id so a freshly created task becomes editable
    /// right away, with no separate window or popup.
    @FocusState private var focusedID: UUID?
    @FocusState private var composerFocused: Bool
    @State private var newTaskText = ""

    private var manager: TaskManager { TaskManager(context: context) }

    var body: some View {
        NavigationStack {
            Group {
                if rootItems.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { composer }
            .onChange(of: focusedID) { previous, _ in
                discardEmptyTask(previous)
            }
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SiblingList(parent: nil, items: rootItems, depth: 0, focus: $focusedID)
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Tasks", systemImage: "checklist")
        } description: {
            Text("Type below to add a task. Press + on any task to add a subtask, or drag tasks onto each other to nest them.")
        }
    }

    // MARK: - Inline composer

    private var composer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            TextField("Add a task", text: $newTaskText)
                .focused($composerFocused)
                .submitLabel(.done)
                .onSubmit(addRootTask)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func addRootTask() {
        let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        manager.addTask(title: trimmed)
        newTaskText = ""
        composerFocused = true // stay focused for rapid entry
    }

    /// Removes a task that was left blank when focus moves away, so aborted
    /// inline edits don't leave empty rows behind.
    private func discardEmptyTask(_ id: UUID?) {
        guard let id, let task = manager.find(id) else { return }
        if task.title.trimmingCharacters(in: .whitespaces).isEmpty && !task.hasChildren {
            manager.delete(task)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}
