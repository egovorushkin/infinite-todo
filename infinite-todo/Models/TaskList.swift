//
//  TaskList.swift
//  todo
//
//  A named container of root-level tasks (e.g. "Daily Tasks", "Projects").
//  Only root tasks carry a direct `list` reference; nested subtasks are
//  reached by walking `parent`, so they never need one.
//

import Foundation
import SwiftData
import SwiftUI

/// A curated palette so lists are visually distinct without needing to
/// persist arbitrary `Color` values (SwiftData can't store `Color` directly).
enum TaskListColor: String, CaseIterable, Codable {
    case indigo, blue, teal, green, yellow, orange, red, pink

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        }
    }
}

/// A curated set of icons so lists can look distinct at a glance, alongside
/// their color.
enum TaskListIcon: String, CaseIterable {
    case list = "list.bullet"
    case checklist
    case star = "star.fill"
    case flag = "flag.fill"
    case house = "house.fill"
    case briefcase = "briefcase.fill"
    case cart = "cart.fill"
    case heart = "heart.fill"
    case book = "book.fill"
    case airplane
    case gift = "gift.fill"
    case dumbbell = "dumbbell.fill"
    case creditcard = "creditcard.fill"
    case leaf = "leaf.fill"
    case graduationcap = "graduationcap.fill"
    case figureRun = "figure.run"

    var systemImage: String { rawValue }
}

@Model
final class TaskList {
    var id: UUID = UUID()
    var name: String = ""
    /// Position among all lists.
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// Raw `TaskListColor`; stored as a string since SwiftData can't
    /// persist `Color` directly.
    var colorName: String = TaskListColor.indigo.rawValue
    /// SF Symbol name shown on the list row.
    var iconName: String = TaskListIcon.list.rawValue

    /// This list's root-level tasks. Deleting the list cascades to them,
    /// which in turn cascades to their own subtrees.
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.list)
    var items: [TodoItem]?

    init(name: String = "", sortOrder: Int = 0, colorName: String = TaskListColor.indigo.rawValue) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.colorName = colorName
        self.iconName = TaskListIcon.list.rawValue
        self.items = []
    }

    /// This list's tint, used throughout its task tree so each list reads
    /// as visually distinct rather than everything sharing one accent color.
    var color: Color {
        (TaskListColor(rawValue: colorName) ?? .indigo).color
    }
}
