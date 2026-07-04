//
//  TaskRowView.swift
//  todo
//
//  The recursive building block of the task tree. A row renders itself and,
//  when expanded, renders its children by calling back into `SiblingList` —
//  which is what produces the infinite nesting depth.
//

import SwiftUI
import SwiftData

private enum Layout {
    static let indentStep: CGFloat = 22
    static let baseInset: CGFloat = 16
    static let rowSpacing: CGFloat = 6
}

// MARK: - Sibling list

/// Renders a group of sibling tasks with reorder drop-zones interleaved
/// between them. Shared by the root list and every nested level.
struct SiblingList: View {
    /// The parent whose children are shown, or `nil` for the root level.
    let parent: TodoItem?
    let items: [TodoItem]
    let depth: Int
    /// Shared focus, keyed by task id, so newly created tasks can be edited
    /// immediately without any popup.
    var focus: FocusState<UUID?>.Binding

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            ReorderDropZone(parent: parent, index: index, depth: depth)
            TaskRowView(item: item, depth: depth, focus: focus)
        }
        ReorderDropZone(parent: parent, index: items.count, depth: depth)
    }
}

// MARK: - Row

struct TaskRowView: View {
    @Bindable var item: TodoItem
    let depth: Int
    var focus: FocusState<UUID?>.Binding

    @Environment(\.modelContext) private var context
    @State private var isNestTargeted = false
    @State private var showingDetails = false

    private var manager: TaskManager { TaskManager(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            rowCard

            if item.isExpanded && item.hasChildren {
                SiblingList(parent: item, items: item.sortedChildren, depth: depth + 1, focus: focus)
            }
        }
        .sheet(isPresented: $showingDetails) {
            TaskEditorView(item: item)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Row card

    private var rowCard: some View {
        HStack(spacing: 10) {
            disclosure
            checkbox

            VStack(alignment: .leading, spacing: 2) {
                TextField("New Task", text: $item.title)
                    .focused(focus, equals: item.id)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .submitLabel(.next)
                    .onSubmit(handleSubmit)

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if item.hasChildren {
                Text("\(item.sortedChildren.filter(\.isCompleted).count)/\(item.sortedChildren.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            addSubtaskButton
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .padding(.leading, CGFloat(depth) * Layout.indentStep)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(.rect)
        .draggable(TaskTransferID(id: item.id)) {
            dragPreview
        }
        .dropDestination(for: TaskTransferID.self) { payloads, _ in
            handleNestDrop(payloads)
        } isTargeted: { isNestTargeted = $0 }
        .contextMenu { contextMenu }
        .sensoryFeedback(.success, trigger: item.isCompleted)
        .animation(.snappy, value: item.isCompleted)
        .animation(.snappy, value: item.isExpanded)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isNestTargeted ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isNestTargeted ? 2 : 0)
            }
    }

    private var disclosure: some View {
        Button {
            withAnimation(.snappy) { item.isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .opacity(item.hasChildren ? 1 : 0)
        .disabled(!item.hasChildren)
    }

    private var checkbox: some View {
        Button {
            withAnimation(.snappy) { manager.toggleCompletion(item) }
        } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    /// Adds a child task at any depth and focuses it for immediate typing —
    /// this is what makes subtask nesting effectively infinite.
    private var addSubtaskButton: some View {
        Button {
            let child = manager.addTask(title: "", parent: item)
            focus.wrappedValue = child.id
        } label: {
            Image(systemName: "plus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private var dragPreview: some View {
        Label(item.title.isEmpty ? "New Task" : item.title, systemImage: "checklist")
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            let child = manager.addTask(title: "", parent: item)
            focus.wrappedValue = child.id
        } label: {
            Label("Add Subtask", systemImage: "plus.circle")
        }
        Button {
            showingDetails = true
        } label: {
            Label("Notes & Details", systemImage: "text.alignleft")
        }
        Button(role: .destructive) {
            withAnimation(.snappy) { manager.delete(item) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: Actions

    /// Return key: commit this task and open a fresh sibling to keep typing.
    /// An empty task on submit is discarded.
    private func handleSubmit() {
        if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            manager.delete(item)
            focus.wrappedValue = nil
        } else {
            let sibling = manager.addSibling(after: item)
            focus.wrappedValue = sibling.id
        }
    }

    private func handleNestDrop(_ payloads: [TaskTransferID]) -> Bool {
        guard let payload = payloads.first,
              let dragged = manager.find(payload.id) else { return false }
        withAnimation(.snappy) { manager.reparent(dragged, under: item) }
        return true
    }
}

// MARK: - Reorder drop zone

/// A slim target rendered between rows. Dropping here reorders the dragged
/// task to that position within `parent`'s children (sibling reorder).
struct ReorderDropZone: View {
    let parent: TodoItem?
    let index: Int
    let depth: Int

    @Environment(\.modelContext) private var context
    @State private var isTargeted = false

    private var manager: TaskManager { TaskManager(context: context) }

    var body: some View {
        Capsule()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            .frame(height: isTargeted ? 4 : 8)
            .padding(.leading, CGFloat(depth) * Layout.indentStep + Layout.baseInset)
            .padding(.trailing, Layout.baseInset)
            .contentShape(.rect)
            .dropDestination(for: TaskTransferID.self) { payloads, _ in
                handleDrop(payloads)
            } isTargeted: { isTargeted = $0 }
            .animation(.snappy, value: isTargeted)
    }

    private func handleDrop(_ payloads: [TaskTransferID]) -> Bool {
        guard let payload = payloads.first,
              let dragged = manager.find(payload.id) else { return false }
        withAnimation(.snappy) {
            manager.move(dragged, toIndex: index, under: parent)
        }
        return true
    }
}
