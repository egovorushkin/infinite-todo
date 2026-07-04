//
//  TaskEditorView.swift
//  todo
//
//  Sheet for editing a task's title and notes. Uses @Bindable, the
//  Observation-era replacement for @ObservedObject bindings.
//

import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Bindable var item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $item.title, axis: .vertical)
                        .focused($titleFocused)
                        .onSubmit { dismiss() }
                }
                Section("Notes") {
                    TextField("Add notes…", text: $item.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }
}
