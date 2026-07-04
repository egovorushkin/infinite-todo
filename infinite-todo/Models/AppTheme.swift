//
//  AppTheme.swift
//  todo
//
//  User's appearance preference, persisted via @AppStorage so it applies
//  immediately and survives relaunch without needing SwiftData.
//

import SwiftUI

/// How the home screen organizes lists: a vertical stack of cards you
/// navigate into, or Google Tasks-style tabs with the selected list's
/// tasks shown inline.
enum ListsLayout: String, CaseIterable, Identifiable {
    case stack, tabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stack: "Stack"
        case .tabs: "Tabs"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` defers to the system setting, matching `.preferredColorScheme`'s
    /// own convention for "don't override".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
