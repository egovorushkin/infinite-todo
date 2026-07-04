//
//  TaskEditorView.swift
//  todo
//
//  Sheet for editing a task's title, notes, due date, and repeat. Uses
//  @Bindable, the Observation-era replacement for @ObservedObject bindings.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct TaskEditorView: View {
    private enum Field {
        case title, notes
    }

    @Bindable var item: TodoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var focusedField: Field?
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var recurrence: RecurrenceRule
    @State private var notificationsDenied = false

    private var manager: TaskManager { TaskManager(context: context) }

    init(item: TodoItem) {
        self.item = item
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date().addingTimeInterval(3600))
        _recurrence = State(initialValue: item.recurrenceRule)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $item.title, axis: .vertical)
                        .focused($focusedField, equals: .title)
                        .onSubmit { dismiss() }
                }
                Section("Notes") {
                    TextField("Add notes…", text: $item.notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .lineLimit(3...8)
                }
                Section("Due Date") {
                    Toggle("Remind Me", isOn: $hasDueDate)
                    if hasDueDate {
                        if notificationsDenied {
                            notificationsDeniedWarning
                        }
                        DatePicker("Due", selection: $dueDate)
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(RecurrenceRule.allCases) { rule in
                                Text(rule.label).tag(rule)
                            }
                        }
                        Text(reminderCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            // Interactive scroll-dismiss hides the keyboard at the UIKit
            // level without updating @FocusState — SwiftUI then believes the
            // field is still focused and ignores the next tap. Syncing on
            // keyboardDidHide keeps tap-to-edit working after any dismissal.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                focusedField = nil
            }
            .task { await checkNotificationAuthorization() }
            .onChange(of: hasDueDate) { _, _ in applyDueDate() }
            .onChange(of: dueDate) { _, _ in if hasDueDate { applyDueDate() } }
            .onChange(of: recurrence) { _, newValue in manager.setRecurrence(newValue, for: item) }
            // Re-sync the pending notification on close so its body reflects
            // any title change made in this editor.
            .onDisappear {
                if item.dueDate != nil {
                    manager.refreshNotification(for: item)
                }
            }
        }
        // Sheets get their own hosting controller, so the app root's
        // .preferredColorScheme doesn't reliably apply here — set it directly.
        .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme)
    }

    /// Shown when "Remind Me" is on but the user has notifications turned
    /// off — otherwise the toggle looks functional while reminders silently
    /// never arrive.
    private var notificationsDeniedWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are turned off, so this reminder won't be delivered.")
                    .font(.caption)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var reminderCaption: String {
        if recurrence != .none {
            return "You'll get a reminder 1 hour before, repeating \(recurrence.label.lowercased())."
        }
        // Mirrors NotificationManager's fallback: when the deadline is less
        // than an hour out, the reminder fires at the due time instead.
        if dueDate.timeIntervalSinceNow < NotificationManager.leadTime {
            return "You'll get a reminder at the due time."
        }
        return "You'll get a reminder 1 hour before."
    }

    private func applyDueDate() {
        manager.setDueDate(hasDueDate ? dueDate : nil, for: item)
    }

    private func checkNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }
}
