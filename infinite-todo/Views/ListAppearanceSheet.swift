//
//  ListAppearanceSheet.swift
//  todo
//
//  Icon and color grids for customizing a list. Both apply live as you tap,
//  so there's no separate save step — Done just dismisses.
//

import SwiftUI

struct ListAppearanceSheet: View {
    let list: TaskList
    let manager: ListManager

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @State private var selectedIcon: TaskListIcon
    @State private var selectedColor: TaskListColor

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    init(list: TaskList, manager: ListManager) {
        self.list = list
        self.manager = manager
        _selectedIcon = State(initialValue: TaskListIcon(rawValue: list.iconName) ?? .list)
        _selectedColor = State(initialValue: TaskListColor(rawValue: list.colorName) ?? .indigo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: selectedIcon.systemImage)
                            .font(.system(size: 30))
                            .foregroundStyle(selectedColor.color)
                            .frame(width: 64, height: 64)
                            .background(selectedColor.color.opacity(0.15), in: Circle())
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(TaskListIcon.allCases, id: \.self) { icon in
                            iconSwatch(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(TaskListColor.allCases, id: \.self) { color in
                            colorSwatch(color)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("List Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedIcon) { _, newValue in manager.setIcon(list, to: newValue) }
            .onChange(of: selectedColor) { _, newValue in manager.setColor(list, to: newValue) }
        }
        // Sheets get their own hosting controller, so the app root's
        // .preferredColorScheme doesn't reliably apply here — set it directly.
        .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme)
    }

    private func iconSwatch(_ icon: TaskListIcon) -> some View {
        let isSelected = selectedIcon == icon
        return Button {
            selectedIcon = icon
        } label: {
            Image(systemName: icon.systemImage)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 40, height: 40)
                .background(isSelected ? selectedColor.color : Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ option: TaskListColor) -> some View {
        let isSelected = selectedColor == option
        return Button {
            selectedColor = option
        } label: {
            Circle()
                .fill(option.color)
                .frame(width: 36, height: 36)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
