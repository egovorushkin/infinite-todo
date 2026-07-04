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
    // Kept small (rather than 0) so a row and its expanded children read as
    // visually distinct blocks instead of merging into one solid stack.
    static let rowSpacing: CGFloat = 2
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
    @Environment(\.currentList) private var currentList
    @State private var isNestTargeted = false
    @State private var showingDetails = false
    @State private var confirmingDelete = false

    private var manager: TaskManager { TaskManager(context: context, list: currentList) }
    /// Tints this row with its list's color instead of one global accent,
    /// so each list reads as visually distinct.
    private var accent: Color { currentList?.color ?? .accentColor }

    /// Tapers title weight/size by depth so hierarchy reads at a glance
    /// without relying on indentation alone.
    private var titleFont: Font {
        switch depth {
        case 0: .body.weight(.semibold)
        case 1: .body
        default: .subheadline
        }
    }

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
        .confirmationDialog(
            "Delete \"\(item.title.isEmpty ? "New Task" : item.title)\" and its \(item.totalDescendantCount) subtasks?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                withAnimation(.snappy) { manager.delete(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All nested subtasks will be deleted too. This can't be undone.")
        }
    }

    // MARK: Row card

    private var rowCard: some View {
        HStack(spacing: 2) {
            rowContent
            dragHandle
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .padding(.leading, CGFloat(depth) * Layout.indentStep)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(.rect)
        .dropDestination(for: TodoDragPayload.self) { payloads, _ in
            handleNestDrop(payloads)
        } isTargeted: { isNestTargeted = $0 }
        .sensoryFeedback(.success, trigger: item.isCompleted)
        .animation(.snappy, value: item.isCompleted)
        .animation(.snappy, value: item.isExpanded)
    }

    /// Everything but the drag handle. `.contextMenu` is scoped to just this
    /// so its long-press recognizer never overlaps the handle's hit area —
    /// otherwise it races the handle's drag interaction and briefly flashes
    /// the menu before the drag wins.
    private var rowContent: some View {
        HStack(spacing: 10) {
            // Only present when there are children — leaf rows don't reserve
            // blank chevron space, letting the checkbox and title sit left.
            if item.hasChildren {
                disclosure
            }
            checkbox

            VStack(alignment: .leading, spacing: 2) {
                // Vertical axis lets long titles wrap (max 3 lines) instead
                // of clipping. A wrapping TextField turns Return into a
                // newline rather than a submit, so the onChange below strips
                // the newline and runs the submit flow instead.
                TextField("New Task", text: $item.title, axis: .vertical)
                    .lineLimit(1...3)
                    .font(titleFont)
                    .focused(focus, equals: item.id)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .submitLabel(.next)
                    .onSubmit(handleSubmit)
                    .onChange(of: item.title) { _, newValue in
                        if newValue.contains("\n") {
                            item.title = newValue.replacingOccurrences(of: "\n", with: "")
                            handleSubmit()
                        }
                    }

                if !item.notes.isEmpty {
                    // Up to 3 lines so short notes read fully in place; the
                    // preview itself is the tap target for the full editor,
                    // since tapping elsewhere on the row edits the title.
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .contentShape(.rect)
                        .onTapGesture { showingDetails = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Shows the full note and task details")
                }

                if let dueDate = item.dueDate {
                    HStack(spacing: 3) {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        if item.recurrenceRule != .none {
                            Image(systemName: "repeat")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(isOverdue(dueDate) ? .red : .secondary)
                }
            }

            Spacer(minLength: 0)

            // Tighter spacing within the trailing cluster than between the
            // main row elements, so icons don't eat into title width.
            HStack(spacing: 2) {
                if item.hasChildren {
                    subtreeProgress
                }
                detailsButton
            }
        }
        .contentShape(.rect)
        .contextMenu { contextMenu }
    }

    /// Always-visible route to Notes & Details, so the editor isn't gated
    /// behind the context menu or the (gesture-contended) notes tap.
    private var detailsButton: some View {
        Button {
            showingDetails = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Details")
        .accessibilityHint("Shows notes, due date, and repeat settings")
    }

    /// Small ring + count, more glanceable than a bare fraction. "Add
    /// Subtask" lives in the context menu instead of a persistent button
    /// here, keeping the row's trailing edge to just this and the handle.
    private var subtreeProgress: some View {
        HStack(spacing: 4) {
            ProgressRing(progress: item.subtreeCompletionFraction, tint: accent)
                .frame(width: 14, height: 14)
            Text("\(item.completedDescendantCount)/\(item.totalDescendantCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isNestTargeted
                    ? accent.opacity(0.18)
                    : item.isCompleted
                        ? Color.green.opacity(0.08)
                        : Color(.secondarySystemGroupedBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent, lineWidth: isNestTargeted ? 2 : 0)
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
        .accessibilityLabel(item.isExpanded ? "Collapse subtasks" : "Expand subtasks")
    }

    private var checkbox: some View {
        Button {
            withAnimation(.snappy) { manager.toggleCompletion(item) }
        } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isCompleted ? accent : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete")
        .accessibilityValue(item.isCompleted ? "Completed" : "Not completed")
    }

    /// Dedicated grab handle for reordering. Drag has to start here rather
    /// than anywhere on the row because the row also has a `.contextMenu`,
    /// and long-press-to-show-menu wins the gesture over long-press-to-drag
    /// when both are attached to the same view. The padding exists to grow
    /// the touch target toward Apple's 44pt minimum without changing the
    /// icon's visual size.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            // Wider than the icon so the grab target approaches Apple's 44pt
            // guidance; height stays near the row's natural height so the
            // tightened row spacing is preserved.
            .frame(width: 40, height: 30)
            .contentShape(.rect)
            .draggable(TodoDragPayload.task(item.id)) {
                dragPreview
            }
            .accessibilityLabel("Reorder")
            .accessibilityHint("Drag to move this task")
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
            // A subtree delete is confirmed first; a leaf task deletes
            // immediately since only one row is at stake.
            if item.hasChildren {
                confirmingDelete = true
            } else {
                withAnimation(.snappy) { manager.delete(item) }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// A recurring task's `dueDate` is just the anchor time of day, so its
    /// staying in the past doesn't mean an occurrence was missed.
    private func isOverdue(_ dueDate: Date) -> Bool {
        !item.isCompleted && item.recurrenceRule == .none && dueDate < Date()
    }

    // MARK: Actions

    /// Return key: commit this task and open a fresh sibling to keep typing.
    /// A blank task is discarded on submit — but only when it carries no
    /// other data (notes, reminder, subtasks), so clearing a title can't
    /// destroy real content.
    private func handleSubmit() {
        if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
            if item.isDiscardable {
                manager.delete(item)
            }
            focus.wrappedValue = nil
        } else {
            let sibling = manager.addSibling(after: item)
            focus.wrappedValue = sibling.id
        }
    }

    private func handleNestDrop(_ payloads: [TodoDragPayload]) -> Bool {
        guard let payload = payloads.first, payload.kind == .task,
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
    @Environment(\.currentList) private var currentList
    @State private var isTargeted = false

    private var manager: TaskManager { TaskManager(context: context, list: currentList) }
    private var accent: Color { currentList?.color ?? .accentColor }

    var body: some View {
        Capsule()
            .fill(isTargeted ? accent : Color.clear)
            // Idle height is intentionally tiny (not 0) so rows sit close
            // together while this still keeps a real drop target between them.
            .frame(height: isTargeted ? 4 : 1)
            .padding(.leading, CGFloat(depth) * Layout.indentStep + Layout.baseInset)
            .padding(.trailing, Layout.baseInset)
            .contentShape(.rect)
            .dropDestination(for: TodoDragPayload.self) { payloads, _ in
                handleDrop(payloads)
            } isTargeted: { isTargeted = $0 }
            .animation(.snappy, value: isTargeted)
    }

    private func handleDrop(_ payloads: [TodoDragPayload]) -> Bool {
        guard let payload = payloads.first, payload.kind == .task,
              let dragged = manager.find(payload.id) else { return false }
        withAnimation(.snappy) {
            manager.move(dragged, toIndex: index, under: parent)
        }
        return true
    }
}
