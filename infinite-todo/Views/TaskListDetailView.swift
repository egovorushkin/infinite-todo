//
//  TaskListDetailView.swift
//  todo
//
//  Shows one TaskList's root-level tasks and lets the tree grow infinitely
//  beneath them via the recursive TaskRowView. Tasks are created inline —
//  either from the bottom composer or by pressing Return on a row.
//

import SwiftUI
import SwiftData
import UIKit

/// The list a task tree belongs to, read by TaskRowView/SiblingList/
/// ReorderDropZone so they can scope root-level drops to the right list
/// without threading it through every initializer.
private struct CurrentListKey: EnvironmentKey {
    static let defaultValue: TaskList? = nil
}

extension EnvironmentValues {
    var currentList: TaskList? {
        get { self[CurrentListKey.self] }
        set { self[CurrentListKey.self] = newValue }
    }
}

struct TaskListDetailView: View {
    let list: TaskList

    @Environment(\.modelContext) private var context

    /// Root-level tasks belonging to `list`, ordered for display.
    @Query private var rootItems: [TodoItem]

    /// Focus is keyed by task id so a freshly created task becomes editable
    /// right away, with no separate window or popup.
    @FocusState private var focusedID: UUID?
    @FocusState private var composerFocused: Bool
    @State private var newTaskText = ""

    private var manager: TaskManager { TaskManager(context: context, list: list) }

    init(list: TaskList) {
        self.list = list
        let listID = list.id
        _rootItems = Query(
            filter: #Predicate<TodoItem> { $0.parent == nil && $0.list?.id == listID },
            sort: \TodoItem.sortOrder
        )
    }

    var body: some View {
        Group {
            if rootItems.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { composer }
        .environment(\.currentList, list)
        // Scrolling drags the keyboard down with the gesture.
        .scrollDismissesKeyboard(.interactively)
        // Interactive dismiss hides the keyboard without updating
        // @FocusState, leaving SwiftUI convinced a field is still focused —
        // which blocks the next tap-to-edit. Re-sync when the keyboard is
        // actually gone.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            focusedID = nil
            composerFocused = false
        }
        .onChange(of: focusedID) { previous, _ in
            discardEmptyTask(previous)
        }
        // Leaving this screen (back navigation, tab switch) abandons any
        // in-progress blank task without a focus change — sweep them here.
        .onDisappear {
            manager.purgeDiscardableTasks()
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SiblingList(parent: nil, items: rootItems, depth: 0, focus: $focusedID)
            }
            .padding(.vertical, 8)
        }
        // Tapping anywhere that isn't an interactive control (empty space
        // below the rows, row backgrounds) drops focus and hides the
        // keyboard. Controls inside rows still receive their own taps first.
        .contentShape(.rect)
        .onTapGesture {
            focusedID = nil
            composerFocused = false
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
                .foregroundStyle(list.color)

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
    /// inline edits don't leave empty rows behind. Only discards when the
    /// task carries nothing else (no notes, reminder, or subtasks) — a
    /// cleared title alone must never destroy real data.
    private func discardEmptyTask(_ id: UUID?) {
        guard let id, let task = manager.find(id) else { return }
        if task.isDiscardable {
            manager.delete(task)
        } else if task.dueDate != nil {
            // Focus leaving a row is the end of an inline title edit — re-sync
            // the pending notification so its body shows the new title.
            manager.refreshNotification(for: task)
        }
    }
}

#Preview {
    NavigationStack {
        TaskListDetailView(list: TaskList(name: "Daily Tasks"))
    }
    .modelContainer(for: [TodoItem.self, TaskList.self], inMemory: true)
}
