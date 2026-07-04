//
//  SettingsView.swift
//  todo
//
//  App-wide preferences. Currently just appearance, but a natural home for
//  future settings without cluttering the Lists screen.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("listsLayout") private var listsLayoutRaw: String = ListsLayout.stack.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appThemeRaw) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Layout", selection: $listsLayoutRaw) {
                        ForEach(ListsLayout.allCases) { layout in
                            Text(layout.label).tag(layout.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Lists")
                } footer: {
                    Text("Stack shows lists as cards you open one by one. Tabs keeps every list one tap away, like Google Tasks.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // A sheet gets its own hosting controller, so the app root's
        // .preferredColorScheme doesn't live-update it — apply it here too
        // so picking a theme repaints this screen immediately.
        .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme)
    }
}
