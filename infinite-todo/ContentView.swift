//
//  ContentView.swift
//  todo
//
//  Root screen. Two layouts, chosen in Settings:
//  - Stack: lists as cards you navigate into (the original design).
//  - Tabs: Google Tasks-style — a horizontal chip bar of lists with the
//    selected list's tasks shown inline beneath it.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]

    @AppStorage("listsLayout") private var listsLayoutRaw: String = ListsLayout.stack.rawValue
    /// Which list's tab is active in tabs layout, persisted across launches.
    @AppStorage("selectedListID") private var selectedListIDRaw: String = ""

    @FocusState private var composerFocused: Bool
    @State private var newListName = ""
    @State private var renamingList: TaskList?
    @State private var renameText = ""
    @State private var appearanceList: TaskList?
    @State private var deletingList: TaskList?
    @State private var showingSettings = false
    @State private var showingNewListAlert = false
    /// The list card/chip currently hovered by a list drag, for highlight.
    @State private var listDropTargetID: UUID?

    private var manager: ListManager { ListManager(context: context) }

    private var layout: ListsLayout {
        ListsLayout(rawValue: listsLayoutRaw) ?? .stack
    }

    /// The tab-selected list, falling back to the first list when the saved
    /// selection no longer exists (e.g. it was deleted).
    private var selectedList: TaskList? {
        lists.first { $0.id.uuidString == selectedListIDRaw } ?? lists.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if layout == .tabs {
                    tabsLayout
                } else {
                    stackLayout
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                manager.migrateOrphanTasks()
                // Clear blank tasks left behind by a force-quit mid-entry.
                TaskManager(context: context).purgeDiscardableTasks()
                NotificationManager.refreshAll(context: context)
                NotificationManager.requestAuthorizationIfNeeded {
                    NotificationManager.refreshAll(context: context)
                }
            }
            .toolbar {
                // In tabs mode the chips are drag-reorderable and can't host
                // a context menu, so the selected list's actions live here.
                if layout == .tabs, let selected = selectedList {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            listContextMenu(selected)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("List actions")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .alert("Rename List", isPresented: renamingBinding) {
                TextField("List name", text: $renameText)
                Button("Save", action: commitRename)
                Button("Cancel", role: .cancel) {}
            }
            .alert("New List", isPresented: $showingNewListAlert) {
                TextField("List name", text: $newListName)
                Button("Create", action: addListFromAlert)
                Button("Cancel", role: .cancel) { newListName = "" }
            }
            .sheet(item: $appearanceList) { list in
                ListAppearanceSheet(list: list, manager: manager)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .confirmationDialog(
                "Delete \"\(deletingList?.name ?? "")\"?",
                isPresented: deleteConfirmBinding,
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    if let list = deletingList {
                        manager.delete(list)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All \(deletingList?.items?.count ?? 0) tasks in this list, including their subtasks, will be deleted. This can't be undone.")
            }
        }
    }

    // MARK: - Stack layout (original)

    private var stackLayout: some View {
        Group {
            if lists.isEmpty {
                emptyState
            } else {
                listOfLists
            }
        }
        .navigationTitle("Lists")
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var listOfLists: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    ListReorderDropZone(index: index, manager: manager)
                    NavigationLink {
                        TaskListDetailView(list: list)
                    } label: {
                        listRow(list, index: index)
                    }
                    .buttonStyle(.plain)
                }
                ListReorderDropZone(index: lists.count, manager: manager)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func listRow(_ list: TaskList, index: Int) -> some View {
        HStack(spacing: 12) {
            // Context menu is scoped to this leading section so its
            // long-press never races the drag handle's lift gesture —
            // same pattern as task rows.
            HStack(spacing: 12) {
                Image(systemName: list.iconName)
                    .foregroundStyle(list.color)
                Text(list.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .contextMenu { listContextMenu(list) }

            Image(systemName: "line.3.horizontal")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 30)
                .contentShape(.rect)
                .draggable(TodoDragPayload.list(list.id)) {
                    Label(list.name, systemImage: list.iconName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
                .accessibilityLabel("Reorder")
                .accessibilityHint("Drag to move this list")
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    listDropTargetID == list.id
                        ? Color.accentColor.opacity(0.18)
                        : Color(.secondarySystemGroupedBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: listDropTargetID == list.id ? 2 : 0)
                }
        )
        .contentShape(.rect)
        // One drop target per card, routing by payload kind: a dragged list
        // takes this card's position; a dragged task moves into this list.
        // (Two stacked dropDestinations would fight — the inner one rejects
        // foreign payloads with the ⊘ badge instead of falling through.)
        .dropDestination(for: TodoDragPayload.self) { payloads, _ in
            handleDropOnList(payloads, cardIndex: index, list: list)
        } isTargeted: { targeted in
            listDropTargetID = targeted ? list.id : (listDropTargetID == list.id ? nil : listDropTargetID)
        }
        .animation(.snappy, value: listDropTargetID)
    }

    /// Shared routing for drops on a list card or tab chip.
    private func handleDropOnList(_ payloads: [TodoDragPayload], cardIndex: Int, list: TaskList) -> Bool {
        guard let payload = payloads.first else { return false }
        switch payload.kind {
        case .list:
            guard let dragged = manager.find(payload.id), dragged.id != list.id else { return false }
            withAnimation(.snappy) {
                manager.move(dragged, toIndex: cardIndex)
            }
            return true
        case .task:
            let taskManager = TaskManager(context: context)
            guard let dragged = taskManager.find(payload.id) else { return false }
            withAnimation(.snappy) {
                taskManager.moveToList(dragged, to: list)
            }
            return true
        }
    }

    // MARK: - Tabs layout (Google Tasks style)

    private var tabsLayout: some View {
        VStack(spacing: 0) {
            if lists.isEmpty {
                emptyTabsState
            } else {
                tabBar
                if let selected = selectedList {
                    // .id resets scroll/focus state when switching tabs, so
                    // each list's tree behaves like its own screen.
                    TaskListDetailView(list: selected)
                        .id(selected.id)
                }
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lists) { list in
                    tabChip(list)
                }
                newListChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func tabChip(_ list: TaskList) -> some View {
        let isSelected = list.id == selectedList?.id
        return Button {
            selectedListIDRaw = list.id.uuidString
        } label: {
            HStack(spacing: 6) {
                Image(systemName: list.iconName)
                    .font(.caption)
                Text(list.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? list.color : Color(.secondarySystemGroupedBackground))
            )
            .overlay {
                Capsule().strokeBorder(Color.accentColor, lineWidth: listDropTargetID == list.id ? 2 : 0)
            }
            .scaleEffect(listDropTargetID == list.id ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        // Chips are draggable for reordering, so they can't also carry a
        // context menu (long-press-for-menu wins over long-press-to-drag);
        // list actions live in the toolbar "…" menu in tabs mode instead.
        .draggable(TodoDragPayload.list(list.id)) {
            Label(list.name, systemImage: list.iconName)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
        // One destination for both payload kinds: dragged lists reorder to
        // this chip's position, dragged tasks move into this list.
        .dropDestination(for: TodoDragPayload.self) { payloads, _ in
            guard let targetIndex = lists.firstIndex(where: { $0.id == list.id }) else { return false }
            return handleDropOnList(payloads, cardIndex: targetIndex, list: list)
        } isTargeted: { targeted in
            listDropTargetID = targeted ? list.id : (listDropTargetID == list.id ? nil : listDropTargetID)
        }
        .animation(.snappy, value: listDropTargetID)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var newListChip: some View {
        Button {
            showingNewListAlert = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New list")
    }

    private var emptyTabsState: some View {
        ContentUnavailableView {
            Label("No Lists", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Create your first list, like Daily Tasks or Projects.")
        } actions: {
            Button("New List") { showingNewListAlert = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func listContextMenu(_ list: TaskList) -> some View {
        Button {
            renameText = list.name
            renamingList = list
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            appearanceList = list
        } label: {
            Label("Icon & Color", systemImage: "paintpalette")
        }
        Button(role: .destructive) {
            deletingList = list
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lists", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Type below to create your first list, like Daily Tasks or Projects.")
        }
    }

    // MARK: - Inline composer (stack layout)

    private var composer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            TextField("Add a list", text: $newListName)
                .focused($composerFocused)
                .submitLabel(.done)
                .onSubmit(addList)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func addList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        manager.addList(name: trimmed)
        newListName = ""
        composerFocused = true // stay focused for rapid entry
    }

    private func addListFromAlert() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        newListName = ""
        guard !trimmed.isEmpty else { return }
        let list = manager.addList(name: trimmed)
        selectedListIDRaw = list.id.uuidString // jump to the new tab
    }

    private func commitRename() {
        guard let list = renamingList else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        manager.rename(list, to: trimmed)
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingList != nil },
            set: { if !$0 { renamingList = nil } }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deletingList != nil },
            set: { if !$0 { deletingList = nil } }
        )
    }
}

/// A slim drop target between list cards in stack layout. Dropping a
/// dragged list here moves it to that position — the list-level twin of
/// the task tree's ReorderDropZone.
private struct ListReorderDropZone: View {
    let index: Int
    let manager: ListManager

    @State private var isTargeted = false

    var body: some View {
        Capsule()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            // Taller idle hit area than the visible line, so the gap between
            // cards is easy to target mid-drag.
            .frame(height: isTargeted ? 5 : 8)
            .contentShape(.rect)
            .dropDestination(for: TodoDragPayload.self) { payloads, _ in
                guard let payload = payloads.first, payload.kind == .list,
                      let dragged = manager.find(payload.id) else { return false }
                withAnimation(.snappy) {
                    manager.move(dragged, toIndex: index)
                }
                return true
            } isTargeted: { isTargeted = $0 }
            .animation(.snappy, value: isTargeted)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TodoItem.self, TaskList.self], inMemory: true)
}
